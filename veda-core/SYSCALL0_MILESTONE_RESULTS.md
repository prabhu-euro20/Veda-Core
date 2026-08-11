# Syscall-0 Milestone: Results

## Context

The clean-room, Linux-ABI-*numbered* (not binary-compatible) OS work approved this session, per
the earlier Linux-port-feasibility research's own unanimous recommendation and the project's own
hardware-first philosophy: build a Veda-Core-native OS whose syscall *numbers* and calling
convention echo real Linux, but whose actual argument shapes and enforcement are entirely
object-centric -- no raw pointers anywhere, ever. "Syscall-0" is the first concrete milestone: a
minimal `write()`/`exit()` pair, real end to end, proving the kernel can independently validate an
untrusted, user-supplied Object_ID via hardware before trusting it.

Four steps, each built and empirically verified in sequence (no step trusted without running it
under `sail_riscv_sim` and checking the real trace):

| Step | Task | What | Regression at completion |
|---|---|---|---|
| 0 | #296 | Pre-flight spike: does a syscall-shaped `ecall` compose with M21's PCC auto-restore-on-`mret`? | `sail_tests` 64/64 |
| 1 | #297 | Real KERNEL ecall dispatch: `sys_write`(64)/`sys_exit`(93), hardware-validated Object_ID | `sail_tests` 65/65 |
| 2 | #298 | `hello_world.c`: a real, compiled C program through the unmodified toolchain | 4 suites, all green (below) |
| 3 | #299 | Forged-Object_ID negative test: the real security proof | Positive + negative both green |

## Step 0: pre-flight spike (`sail_tests/vc_syscall0_step0_spike.S`)

**Real bug found and fixed**, not assumed safe by analogy to the already-proven
`vc_pcc_auto_restore_on_mret.S`: `compartment_u`'s own `Length` (`0x40`, 64 bytes) was too small to
cover its *own* post-`ecall` canary/CSR-readback check code, not just its pre-`ecall` body. The
deliberate boundary-escape trap this test uses to prove real enforcement (not just CSR readback)
fired one instruction early -- inside the check code itself, at the `la t4, compartment_u` straddling
offset 64, confirmed via `objdump` byte-counting, not guessed. Fixed by widening `Length` to `0x54`
(84 bytes, the exact count through the last legitimate instruction). Mutation-tested (a corrupted
expected round-trip value correctly flips SUCCESS->FAILURE).

## Step 1: KERNEL ecall dispatch (`sail_tests/vc_syscall0_kernel.S`)

Real Linux syscall numbers (`__NR_write=64`, `__NR_exit=93`), a deliberate ABI divergence from real
Linux (this ISA has no raw pointers): `a0`=fd, `a1`=Object_ID, `a2`=offset, `a3`=count, `a7`=syscall
number for `sys_write`; `a0`=status, `a7`=93 for `sys_exit` (unchanged from real Linux, no pointer
argument to adapt). `sys_write` binds the caller-supplied Object_ID via **trapping** `veda.bind`
(confirmed via direct Sail source read: no privilege check at all, legal at any privilege level,
hard-traps on a bad Object_ID with `VEDA_CAUSE_OBJECT_NOT_FOUND`/`VEDA_CAUSE_OWNER_VIOLATION`) --
hardware validation, zero software checking. Full GPR save/restore around the handler body, the
M25/M26 idiom scoped down (no thread-resume-jump machinery, since this handler always returns to the
same interrupted context).

**Real bug found and fixed**: the full-GPR-restore sweep unconditionally restored `x10`/`a0` to its
pre-`ecall` value, clobbering the syscall's own return value (`mv a0, a3`, set immediately before the
restore) -- a real, fundamental correctness bug (every real syscall ABI treats `a0` as the one
register a call is *expected* to change). Fixed by excluding `a0` from the restore sweep. Two
mutation tests (corrupted expected byte pattern; unrecognized syscall number) both correctly flip to
FAILURE. `sail_tests` 65/65.

## Step 2: `hello_world.c` (`compiler/veda_syscall0_hello_world.c` + `veda_syscall0_kernel_entry.S` +
`veda_syscall0_shim.S`)

A real, compiled C program, built through the **unmodified** Veda-Core toolchain (same
`-fpass-plugin` two-stage pipeline every other `compiler/` demo already uses).

**Three real bugs found via direct trace debugging, none assumed away:**

1. **Missing `__attribute__((veda_compartment))`** on `hello_world_thread`. Compiles fine, crashes at
   runtime: the default (unattributed) prologue does an ordinary `sd ra, ...(sp)`, which a live
   OCInvoke-narrowed compartment's purecap enforcement correctly hard-traps on
   (`VEDA_CAUSE_PURECAP_VIOLATION`, `cause=0x07`). Fixed by adding the attribute, matching every other
   OCInvoke-entered demo in this repo.
2. **`CODE`'s own `Base` pointed directly at `hello_world_thread`, not `landing_pad`.** `OCInvoke`
   jumped straight past the entry point's own SSC-establishment code -- `c15` never got bound to the
   real `STACK_REGION` object, silently keeping whatever `OCInvoke`'s own IDC side effect had installed
   instead (an Invoke-only placeholder object), so the function's real `ocs.d c15, ...` prologue
   hard-trapped with `VEDA_CAUSE_PERM_STORE_VIOLATION` (`cause=0x13`). Fixed by pointing `CODE`'s
   `Base` at `landing_pad`, matching `veda_alloca_protect_entry.S`'s own established pattern exactly.
3. **A genuine structural incompatibility, found (not assumed) by direct source reads of two
   independent things:**
   - `VedaShadowPropagation.cpp:507` (`if (F.isDeclaration() ...) continue;`): the pass only rewrites
     -- and only knows how to call-site-fix-up -- functions **defined with a body** in a
     pass-processed translation unit. A hand-written `.S` function is permanently "just a
     declaration" from the pass's own point of view; there is no real mechanism for it to ever
     receive an auto-appended shadow Object_ID parameter, regardless of how its C prototype is
     written. This closes off the pointer-parameter shim design the milestone's own earlier framing
     assumed would work.
   - `veda_compiler_rt.c`/`runtime/veda_rt.c` are compiled **without** `-fpass-plugin` in every
     established build script in this repo (confirmed by grep) -- their own internal bookkeeping
     (`g_in_use[]`/etc.) is always ordinary, un-instrumented C. Calling `veda_malloc_raw` from *inside*
     `hello_world_thread` (post-`OCInvoke`) hit a real `PURECAP_VIOLATION` on `veda_rt_init`'s own
     ordinary `sb` bookkeeping write, confirmed via `--trace-instr` before either fix.

   **Real fix, not a workaround**: `hello_world_thread`'s own C signature takes **one scalar
   parameter** (`unsigned int msg_oid`) -- no pointer parameter at all, so `rewriteSignatures` never
   touches this function's signature, sidestepping problem 3a entirely. The entry point
   (`veda_syscall0_kernel_entry.S`) calls `veda_rt_init`/`veda_malloc_raw` and writes the real message
   bytes itself, **before** `OCInvoke` narrows PCC -- mirroring `veda_global_protect_entry.S`'s own
   already-established pre-`OCInvoke` `veda_rt_init_globals()` call, for the identical real reason
   ("purecap enforcement is not yet active at that point").

Two mutation tests (corrupted expected byte pattern in the kernel's own self-check; corrupted
expected return value inside `hello_world.c` itself) both correctly flip to FAILURE. Zero regressions
across four independent suites: `run_veda_demo_tests.sh` 8/8, `run_veda_alloca_protect_test.sh`
PASS, `run_veda_global_protect_test.sh` PASS, `sail_tests` 65/65.

## Step 3: forged-Object_ID negative test (`run_veda_syscall0_forged_oid_test.sh`)

The real security property this whole milestone exists to prove. Reuses `hello_world.c` **unchanged**
against a variant entry point (`veda_syscall0_kernel_entry_forged.S`) that hands `hello_world_thread`
a deliberately forged, never-populated Object_ID (`99999`) instead of the real one `veda_malloc_raw`
returned.

**Result, traced and confirmed to the exact cause, not just "did it fail"**: `mcause=0x18`,
`mtval=0x65` -- `cap_idx=3` (the KERNEL's own `c3`, `do_sys_write`'s trapping-bind target),
`cause=0x05` (`VEDA_CAUSE_OBJECT_NOT_FOUND`). The kernel's own `veda.bind c3, a1` rejected the forged
Object_ID in hardware, before any data movement, with **zero software-side validation anywhere in the
syscall path** -- exactly the property `veda.bind`'s trapping semantics are designed to provide.

## Summary: what this milestone proves

A real, compiled C program, using the unmodified Veda-Core toolchain, can obtain a real Object_ID
(`veda_malloc_raw`'s own `out_oid`), pass it across a hand-written asm boundary (the syscall shim) to
a kernel that independently validates it via hardware (`veda.bind`, trapping) before trusting it --
and a forged Object_ID is provably, exactly, rejected in hardware. This is the load-bearing security
property the whole clean-room-OS direction depends on.

## RTL mirror

The KERNEL ecall dispatcher (Step 1 / Task #297) has now been mirrored into RTL
(`rtl/sim/veda_smoke_syscall0_kernel.S`, Object_IDs 130-134). Two real prerequisite gaps, found by
directly auditing `rtl/veda_core.tlv` before writing the port (not assumed present because the Sail
side had them), had to be closed first: RTL had neither M21's automatic PCC restore-on-`mret` nor
M27's `mtvec`-write compartment-escape gate. Both were mirrored, each with its own new smoke test and
mutation tests, and Phase 3 of the restore-on-`mret` test surfaced two genuinely new nested-trap bugs
never previously found or tested on either the Sail or RTL side. Full detail:
`rtl/MILESTONE_21_27_RESTORE_MTVEC_GATE_RTL_RESULTS.md`.

The RTL port of the dispatcher itself reused the Sail source's exact structure (dispatch on `a7`,
trapping `veda.bind` on the caller-supplied Object_ID, dword-copy loop, full-GPR-save/restore via the
already RTL-proven M25/M26 `mscratch`+`OCS.D`/`OCL.D` idiom), adapted only for this project's own
RTL testbench convention (GPR-readback sentinels + fixed cycle budget, no `tohost`/HTIF) rather than
`RVMODEL_HALT_PASS/FAIL`. Passed on the first real clocked-simulation run; mutation-tested (a
corrupted expected destination byte flips PASS to FAIL, confirming the test is non-vacuous). Full RTL
smoke-test regression: **52/52 passed**. ACT4 RV64I conformance: **51/51 passed**. Zero regressions.

The forged-Object_ID negative case (Task #299's own RTL parity) remains a natural, closely-following
next step, not yet started.

## What remains genuinely, honestly out of scope (not started, not hidden)

Named explicitly, matching this project's own standing "no silent scope creep" discipline:

- **Real console I/O device.** `KERNEL_CONSOLE_BUF` is a kernel-private scratch object, not a real
  device -- `sys_write`'s data-movement mechanism is proven, the destination is a deliberate stand-in.
- **General syscall dispatch table.** Only a flat, 2-arm branch chain (`a7==64`/`a7==93`) exists; a
  third syscall would need real dispatch-table work, not a copy-paste extension.
- **Real per-process exit semantics.** `sys_exit` halts the whole simulator (`RVMODEL_HALT_PASS/FAIL`)
  -- there is no process concept, no `-ENOSYS`, no fd cleanup.
- **Fault-recovery path.** A trap anywhere in this milestone's own code halts the simulator; there is
  no "recover and keep running" mechanism.
- **`task_struct`/fd-table/VFS layer, a POSIX-shaped libc surface, multi-hart/SMP, `clone`/`fork`, a
  real filesystem.** None started.
- **`memcpy`/struct-copy type-aware shadow propagation** (a real, pre-existing, unrelated gap named in
  `TOOLCHAIN_MILESTONE_20_KERNEL_GAPS_RESULTS.md`) is why `hello_world.c` writes its message one byte
  at a time rather than via a string-literal initializer -- a real, already-documented scope limit
  this program deliberately stays inside rather than tripping, not new to this milestone.
- **RTL mirror.** ~~Every fix in this milestone is Sail/LLVM-pass/hand-written-asm only... No RTL
  work attempted or needed yet~~ -- **now done**, see "RTL mirror" section below. Every fix
  *described above* remains Sail/LLVM-pass/hand-written-asm only (`vc_syscall0_kernel.S` itself was
  never touched by the RTL pass); the RTL mirror is a separate, new `rtl/sim/*.S` port, not a change
  to any file listed here.

## Files

- `sail_tests/vc_syscall0_step0_spike.S` (Step 0, fixed)
- `sail_tests/vc_syscall0_kernel.S` (Step 1, new)
- `compiler/veda_syscall0_hello_world.c`, `veda_syscall0_shim.S`, `veda_syscall0_kernel_entry.S`,
  `run_veda_syscall0_hello_world_test.sh` (Step 2, new)
- `compiler/veda_syscall0_kernel_entry_forged.S`, `run_veda_syscall0_forged_oid_test.sh` (Step 3, new)
- No `.sail`/`.tlv` changes anywhere in Steps 0-3 above -- every fix there exercises already-existing,
  already-verified real instructions and mechanisms (`veda.bind`, `OCL.D`/`OCS.D`, `ODT-Populate`,
  `OCInvoke`, `CSeal`, `OSpecialRW`, M21-restore, the M25/M26 full-GPR-save idiom).
- **RTL mirror** (new, separate pass): `rtl/veda_core.tlv` (M21-restore + M27-mtvec-gate mirrors),
  `rtl/sim/veda_smoke_pcc_restore_on_mret.S`, `rtl/sim/veda_smoke_mtvec_escape_neg.S`,
  `rtl/sim/veda_smoke_syscall0_kernel.S` (+ matching testbenches), 4 pre-existing RTL negative tests
  updated for the new auto-restore behavior (see `rtl/MILESTONE_21_27_RESTORE_MTVEC_GATE_RTL_RESULTS.md`
  for the full list and reasoning) -- all registered in `rtl/run_veda_smoke_test.sh`.
