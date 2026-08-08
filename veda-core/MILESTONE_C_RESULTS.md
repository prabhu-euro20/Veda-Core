# Veda-Core Minimal OS Kernel Milestone C Results — a Real Cooperative Scheduler

**Date:** 2026-08-06
**Scope:** proving Milestones A (`veda_tsc` + `OSpecialRW` selector, `MINIMAL_OS_KERNEL_DESIGN.md`)
and B (reserved-otype sentry mechanism — `CSealEntry`/`OCRETURN`, `MILESTONE_B_RESULTS.md`)
**compose** into the real, working pattern this whole initiative is named for: a genuine
two-thread cooperative round-robin scheduler, built the way the real CHERIoT RTOS builds one.
**Zero changes to the Sail model** — every instruction this milestone needs (`OCInvoke`,
`OCRETURN`, `CSealEntry`, `OSpecialRW`, ordinary `ecall`/`csrr`/`csrw`) already existed and was
already proven correct in isolation; this is a pure software-integration test.

## Grounding: complete re-read of CHERIoT RTOS's `architecture.md`

The scheduler/thread architecture had not been the focus of the earlier reads that grounded
Milestones A and B, so the full 109-line document was re-read fresh for this milestone. Real
citations that shaped the design:

- Four core components: loader, switcher, scheduler, allocator. **The switcher** "is responsible
  for all cross-compartment and cross-thread transitions... runs with the access-system-registers
  permission. It uses this permission to store a capability to the current thread's trusted stack
  and register-save area in the `mtdc` capability special register" — the real register Veda-Core's
  own `veda_tsc` is modeled on.
- **The scheduler** "is just a compartment... not more privileged than the threads that it
  schedules." "The second entry point is invoked by the switcher."
- "Yielding is implemented with the `mcall` instruction, which enters the switcher and then
  invokes the scheduler's interrupt entry point." Veda-Core has no `mcall`; ordinary `ecall` is
  used instead, already proven (Milestone 21) to correctly reach a handler outside a live
  compartment via the universal trap-time PCC reset.

A Plan agent independently re-verified every cited Sail source (`OSpecialRW`/`OCInvoke`/
`OCRETURN`/`CSealEntry` execute clauses, `handle_trap_extension`, the Milestone 20 CSR gate, both
cited existing test files) before the design was finalized, and surfaced one real correctness
gap — the `mcause==11` guard, closed in the design below — before any code was written.

## Design

One Sail test program, four labeled compartments, matching every prior milestone's own
single-ELF convention: `sail_tests/vc_scheduler_cooperative_yield.S`.

**THREAD_A (Object_ID 100/101/102) / THREAD_B (110/111/112)**: independent `OCInvoke`-entered
compartments, each running `li xN,0` once, then a loop of `addi xN,xN,1; ecall`. Deliberately
discriminating by construction: if the scheduler ever resumed a thread at its fixed entry point
instead of its true last-yielded PC, `xN` would reset to `0` every cycle and the final count
would read `1` regardless of how many yields occurred.

**SWITCHER**: `mtvec`'s own target, runs fully unbounded by construction (never itself
`OCInvoke`-entered — Milestone 20's own CSR gate requires `veda_pcc_length==UNBOUNDED` before
`veda_pcc_base`/`_length`/`veda_mepcc_*` can be written at all). On each `ecall`: guards
`mcause==11`; reads the yielding thread's saved PC/PCC-bounds (already captured into
`veda_mepcc_base`/`_length` by Milestone 21's universal reset) and stores them into that thread's
own save-area block; swaps `veda_tsc` (via `OSpecialRW`) to the next thread's own save-area
capability — the real "swap `mtdc`" step, TSC's first genuine, non-synthetic use in this project;
invokes SCHEDULER via `OCInvoke` with a freshly `CSealEntry`-minted return sentry; on return,
resumes the chosen thread via the OCRETURN-based restore below.

**SCHEDULER (Object_ID 120/121/122)**: minimal round-robin — toggle a persistent thread-index,
return via `OCRETURN` through the switcher-minted sentry, mirroring
`vc_switcher_register_clear_fast_return.S`'s already-proven pattern, given a real job here.

**Verification**: 4 yields (2 full A↔B round-trips — the minimum to distinguish genuine
independent per-thread restoration from a coincidental single-pass success). Final assertions:
`x20==2`/`x21==2` (each thread's own counter incremented exactly twice); `x22==1`/`x26==1`
(each thread's own live `veda_pcc_base`/`veda_pcc_length`, read back on its second visit, still
equal its own CODE capability's Base/Length — proves the switcher restored the right *bounds*,
not just a PC that happens to still fetch); `tsc_ok==1` (every `OSpecialRW` swap's returned
old-TSC capability matched the expected previously-running thread's own save-area address, every
cycle).

## Two real bugs found and fixed during this milestone (neither previously exercised in this codebase)

Both found by direct `sail_riscv_sim --trace-instr --trace-exception --trace-csr` tracing — this
project's standing empirical-debugging discipline, not assumption.

**Bug 1 — ordinary `lw`/`sw` inside a live `OCInvoke` compartment is unconditionally blocked.**
The scheduler's first draft used plain `lw`/`sw` on `thread_index` and hit a false
`PURECAP_VIOLATION` (`mtval=0x227`). Root-caused by reading `ext_data_get_addr`
(`postlude/step_ext.sail`) directly: it blocks *any* ordinary load/store while
`veda_pcc_length != VEDA_PCC_UNBOUNDED`, completely independent of the `veda_purecap` CSR bit (this
test never sets it) — a real, deliberate Milestone 19 security property ("compartmentalized code
could still issue an ordinary LOAD/STORE to read/write memory anywhere," closing that gap), simply
not something any earlier test had exercised from *inside* a live compartment reading *shared*
memory. Fixed: added a `thread_index` capability (Object_ID 150, Load\|Store) and rewrote the
scheduler to use Veda's own `OCL.D`/`OCS.D` (which bypass `vmem_read`/`vmem_write` entirely via
`read_ram`/`write_ram`) instead of `lw`/`sw`. The SWITCHER, which runs unbounded, is exempt and
keeps using ordinary loads/stores freely.

**Bug 2 — `csrw veda_pcc_base/_length` immediately followed by a separate `mret` is unsafe.**
The first restore implementation narrowed PCC via ordinary `csrw` (the established Milestone
14/20/21 convention) and then executed `mret` as a separate instruction. This hard-faulted
(`cause=0x01`, `cap_idx=16`, fetch violation) *on the `mret` instruction itself* — traced via
`--trace-csr` to discover the trap's own saved `mepc` pointed at the `mret` instruction, proving
the CPU narrowed PCC to the target thread's bounds *before* fetching `mret`, which lives in the
switcher's own code, now outside those just-narrowed bounds. Re-reading
`vc_pcc_generic_trap_reset.S` confirmed this exact "narrow-then-separate-`mret`" pattern had never
actually been exercised end-to-end anywhere in this codebase before this milestone — that test's
own `mret` runs while PCC is still unbounded. **Fixed** by replacing the two-step
`csrw`+`mret` with an atomic `OCA`+`CSealEntry`+`OCRETURN` sequence: freshly re-bind the chosen
thread's own CODE Object_ID (Offset=0), `OCA` its Offset to `delta = saved_pc − saved_base`,
`CSealEntry` it into a sentry in place, `OCRETURN` through it — narrowing PCC and jumping in the
*same* instruction, exactly matching how `OCInvoke`/`OCRETURN` already work everywhere else in
this project.

**Bug 3 — `mepc` saved and restored verbatim, without advancing past the `ecall` itself.**
After fixing Bug 2, the switch/resume mechanism worked (confirmed: execution genuinely resumed
inside the target thread's own compartment, at the right PCC bounds) but the final assertion
`x20==2` still failed. Full-trace inspection (`grep`-ing every control-flow instruction across the
whole run) showed each thread's own `addi xN,xN,1` executed exactly **once** in the entire
4-yield run, and every resume landed back at the exact same `ecall` instruction address as the
prior yield. Root cause: ordinary RISC-V `ecall` never auto-advances `mepc` past itself (unlike a
handled instruction fault), so the switcher's `csrr x28, mepc` captured the `ecall`'s own address;
saving and restoring that verbatim meant every resume re-executed the same `ecall` forever,
never reaching the `j thread_*_loop` that would trigger a second increment. **Fixed** with a
single `addi x28, x28, 4` immediately after `csrr x28, mepc` in `switcher_entry`, before the
value is stored into the yielding thread's save area — a classic ecall-handler correction, real
in this codebase because no earlier test had ever resumed *past* an `ecall` rather than just
verifying the trap fired.

## Verification

```
$ bash run_veda_selfcheck_tests.sh
...
PASS      vc_scheduler_cooperative_yield
...
53/53 passed
```

53/53 (52 pre-existing + this new test), zero regressions.

## Not yet built

Per the plan's own explicit scope: RTL mirror (needs no new instructions, so if ever done it is
purely re-running this identical pattern against `veda_core.tlv`'s already-complete instruction
set — not started this pass, matching the project's own Sail-then-RTL sequencing). Real fault
recovery for the `unexpected_trap`/guard path (currently a clean fail-halt, not a recovery).
~~Full GPR context save~~ **Resolved** — see `MILESTONE_C_GPR_CONTEXT_SAVE_RESULTS.md`: all of
x1-x31 now survive a yield, not just each thread's own counter register plus `mepc`/PCC-bounds.
Preemptive (timer/interrupt-driven)
scheduling — cooperative-`ecall`-yield only, per this initiative's own original scheduling
decision. More than 2 threads, priorities, message queues, event channels, futexes, or the
allocator — all real CHERIoT scheduler/allocator features, explicitly out of scope for this
first, minimal, 2-thread round-robin proof.
