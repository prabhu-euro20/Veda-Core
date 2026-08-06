# Veda-Core Toolchain Milestone 10 Results — a C-Callable Cooperative Scheduler API

**Date:** 2026-08-06
**Scope:** connect two previously-separate parts of this project for the first time — the
LLVM-based toolchain (Milestones 1-9, culminating in a real compiled linked-list demo) and the
minimal-OS-kernel cooperative scheduler (Milestones A/B/C, both Sail and RTL). Build a real,
C-callable API around the already-proven switcher/scheduler mechanism, so an ordinary compiled C
`main()` can drive it — not a new or simplified mechanism, the identical one `sail_tests/
vc_scheduler_cooperative_yield.S` (53/53) and `rtl/sim/veda_smoke_m23_scheduler.S` (41/41) already
proved.

## Grounding research

A parallel research pass read all nine `TOOLCHAIN_MILESTONE_*_RESULTS.md` docs, the real `veda_rt`
runtime (`runtime/veda_rt.c/.h/veda_rt_asm.S/veda_rt.ld/crt0.S`), the real M9 build pipeline
(`compiler/run_veda_demo_tests.sh`), and CHERIoT RTOS's own real, fetched C-level thread API
(github.com/CHERIoT-Platform/cheriot-rtos) — the real precedent this whole switcher/scheduler
design has been modeled on throughout. **Key finding, changing the original design**: CHERIoT
RTOS's real thread creation is static and build-time, not a dynamic `thread_create()` call —
threads are declared in a compile-time table with plain C functions as entry points, and there is
no function literally named `yield()` (they use zero-timeout `thread_sleep`/`futex_wait`
instead). This directly informed the final API shape below: a caller-supplied static array of
thread descriptors, not runtime thread creation.

An independent Plan-agent verification pass, reading the real LLVM tablegen source directly
(`RISCVInstrInfoXVeda.td`), found two real gaps in the initial design before any code was
written: `csealentry`/`ocreturn` have **no** LLVM MC-layer mnemonic support at all, and the named
`ospecialrw` mnemonic hardwires the ODA-only selector (`rs2=0`) — the TSC-selector form the
scheduler depends on has none either. Both are closed the same way the already-proven `.S` tests
close them: raw `.insn` encoding, applied uniformly (not mixed with named mnemonics) for
consistency with the two files this is a direct port of.

## A major, previously-undiscovered architectural finding (empirical, not assumed)

While building the demo, direct `clang -S` inspection (the exact "verify real codegen before
depending on it" discipline `TOOLCHAIN_MILESTONE_9_RESULTS.md` already learned once with a
struct-return ABI surprise) revealed: **ordinary compiler-generated C functions cannot run inside
a narrowly OCInvoke/OCRETURN-bound compartment at all.** Standard RV64 ABI requires a function to
save any callee-saved register it touches in its own prologue — an ordinary `sd`/`ld` store/load,
which Milestone 19's purecap rule hard-traps unconditionally inside any live, narrowly bound
compartment (confirmed independent of the `veda_purecap` bit). Three attempts were tried and
empirically rejected before landing on the real fix:
1. A `static` counter — touches memory every loop iteration. Rejected.
2. A function-local `register unsigned long counter asm("x20")` — still spilled in the function's
   own prologue (`sd s4, 8(sp)` observed at `-O1`, an ABI-mandated callee-saved-register save).
   Rejected.
3. A file-scope "global register variable" (`register ... asm("x20");` at file scope) — crashes
   this LLVM build's RISC-V backend outright (`Trying to obtain non-reserved register "x20"`).
   Rejected as unstable.

**Real fix**: thread bodies must be hand-written assembly containing zero ordinary memory
traffic, using dedicated GPRs for persistent state (x20/x21) — exactly
`vc_scheduler_cooperative_yield.S`'s own established convention. This works because the register
**file** itself survives every `OCInvoke`/`OCRETURN` compartment switch (only PCC narrows, GPRs
are never cleared) — no explicit save/restore was ever needed for persistence; the real
limitation is specifically about what a *compiler's own ABI conventions* emit, not about state
survival. The **orchestration mechanism** (init/run/yield) is genuinely C-callable; the innermost
thread bodies are not, and this is stated plainly in `runtime/veda_sched.h`'s own doc comment
rather than glossed over.

## Design

**Four new files**, following `veda_rt`'s own established three-way split:
- `runtime/veda_sched.h` — public API (`veda_thread_t{entry, code_length}`, `veda_scheduler_start`,
  `veda_yield` as plain clang inline `ecall`, safe because `ecall` is a standard base-ISA
  instruction unaffected by the real, documented clang-driver `xveda` arch-string rejection).
- `runtime/veda_sched_asm.S` — every Veda-Core-mnemonic step (mirrors
  `vc_scheduler_cooperative_yield.S` directly, unified so a thread's first-ever entry and every
  later resume both go through the identical atomic `OCA`+`CSealEntry`+`OCRETURN` path — a real
  simplification found during implementation: `OCRETURN`'s own violation check only needs a
  sealed-as-sentry, Execute-permitted capability, no DATA capability or type-authority at all,
  cutting each thread's own setup from 3 Object_IDs to 1; only `SCHEDULER`, entered via real
  `OCInvoke`, still needs a true sealed CODE+DATA pair).
- `runtime/veda_sched.c` — thin glue (Object_ID population, thread binding).
- `compiler/veda_sched_demo_threads.S` + `compiler/veda_sched_demo.c` — the real demo: two
  hand-written, zero-memory-traffic thread bodies (x20/x21 counters) driven by a real, compiled
  `main()`, which reads the final counter values back via `mv`-based inline asm once the
  scheduler has genuinely returned (unbounded context by then, ordinary reads are fine).

Object_IDs 160-168 (9 total, not the originally-planned 13 — the DATA/type-authority
simplification above), personally grepped fresh against every existing `sail_tests/*.S` and
`rtl/sim/*.S` file before picking.

## Three real bugs found and fixed (all in the new assembly, none in existing hardware/model logic)

All found via direct `sail_riscv_sim --trace-instr --trace-exception --trace-csr` tracing —
this project's standing empirical debugging discipline.

1. **`ra` (x1) clobbered.** The original hand-assembled test used `x1` as a free scratch register
   to carry Object_ID values into `veda.odt.populate`/`veda.bind` — safe there since it's a
   standalone `_start` program with no `ret`. Ported directly into a real C-callable function,
   this silently clobbered the real return address; `veda_sched_init_asm`'s own `ret` jumped to
   address `0xA8` — exactly `168`, the last Object_ID literal loaded into `x1` before it. Fixed by
   moving all such uses to `a0` (dead/reusable after its own argument value is copied elsewhere).
2. **The `OSpecialRW` TSC-selector broke when the `x1`→`a0` fix above was applied too broadly.**
   `x1`'s own register *index* (not its value) is what selects TSC (`rs2=1`); blanket-replacing it
   with `a0` (index 10) produced a genuinely unrecognized selector, hard-trapping as `illegal
   0x26a3175b`. Fixed by reverting those three specific occurrences back to `x1` — safe there
   because the instruction never reads the register's *value*, only its *index*.
3. **`sp` (x2) clobbered.** The original test used `x2` as a free scratch register to hold a
   packed Object_ID descriptor before `veda.odt.populate`'s third operand — again safe in a
   `_start` program with no C-style stack. Ported directly, this silently overwrote the real stack
   pointer with a descriptor value (`Base<<32|Length<<16|Perms`). The corruption stayed invisible
   through `veda_sched_init_asm` (which never touches `sp`) and the entire scheduler run (thread
   bodies and the switcher never touch `sp` either), only surfacing as a real hardware
   `load-access-fault` (`mcause=5`, `mtval=0x800004ECFFFF002A` — a literal descriptor value, not
   an address) the moment `veda_scheduler_start`'s own epilogue finally did `ld ra, 0x28(sp)`.
   Fixed by using `t0`/`t1` (already holding the same descriptor value) directly, eliminating the
   `sp`-clobbering copy entirely.

**General lesson, worth stating plainly**: every register convention a standalone `_start`
assembly test can safely use (any GPR is fair game — no ABI, no caller, no stack) becomes a real
correctness hazard the moment the identical code is ported into a function real C code calls.
`x1`/`ra` and `x2`/`sp` are the two GPRs where this bites hardest, since they carry meaning even
when never explicitly "used" by the ported code's own logic.

## Verification

```
$ bash compiler/run_veda_sched_demo_test.sh
...
SUCCESS
*** TEST PASSED *** (real compiled C main() drives the real switcher/scheduler mechanism --
OCInvoke/OCRETURN/OSpecialRW-TSC-swap/CSealEntry the whole way, hand-written zero-memory-traffic
thread bodies, both threads' counters reach 2 after 4 real yields)
```

Full regression, zero regressions: `sail_tests/run_veda_selfcheck_tests.sh` 53/53,
`compiler/run_veda_demo_tests.sh` 2/2, `runtime/run_veda_rt_tests.sh` 2/2.

## Not yet built

RTL mirror of this C API (Sail-first sequencing, matching every prior milestone); more than 2
threads / true N-way round-robin generalization; dynamic/runtime thread creation (deliberately
not built, following CHERIoT RTOS's own real static precedent instead); full GPR context save;
preemption; priorities; any IPC (message queues/futexes) — all already named as deferred by the
existing scheduler design itself, unchanged here. Most importantly: **arbitrary compiled C thread
bodies remain impossible** without either a custom LLVM calling-convention/codegen mode that never
spills across a compartment boundary, or a real RTL/Sail design change relaxing the purecap rule
for compartment-internal stack accesses specifically — both genuinely separate, large pieces of
future work, not attempted here.
