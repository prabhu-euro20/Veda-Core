# Timer-Interrupt Verification: Closing MILESTONE_21's Own Flagged Gap

**Date:** 2026-08-09
**Scope:** verifies, with a real, firing machine-timer interrupt, that `handle_trap_extension` (Milestone 21's universal PCC-reset-on-any-trap hook) fires correctly for an asynchronous interrupt landing inside a live `OCInvoke` compartment -- the exact case `MILESTONE_21_RESULTS.md`'s own "Not yet built" section named and flagged as unverified ("no real interrupt source is currently active"). No new Veda-side hardware was needed to reach this milestone -- the entire timer/interrupt mechanism already existed, complete and spec-correct, in the base Sail model Veda-Core forked from.

## Why this milestone's scope is smaller than originally planned

An earlier plan (produced before reading the base model's own machinery) assumed `mtime`/`mtimecmp`/`mie`/`mip`/`mstatus` and the between-instruction interrupt-dispatch control flow all needed to be built from scratch in Sail, as new work. A full, primary-source audit -- reading the ratified RISC-V Privileged Architecture spec (`riscv/riscv-isa-manual`, `src/priv/machine.adoc`) in complete section form, and reading the base Sail model's own interrupt/CLINT machinery end to end -- found this assumption wrong:

- `mstatus.MIE`=bit3, `MPIE`=bit7, `MPP`=bits[12:11] are real, already-implemented fields (`model/core/sys_regs.sail:167-203`), matching the spec's own `mstatusreg.edn` bit layout exactly.
- `mie`/`mip` share the `Minterrupts` bitfield with `MTI`=bit7, `MSI`=bit3, `MEI`=bit11 (`model/core/interrupt_regs.sail:13-27`), again matching the spec's own bit positions exactly, with real legalize functions, not stubs.
- The `mtime >= mtimecmp` comparator is real: `clint_dispatch()` (`model/sys/platform.sail:141-152`) computes `mip[MTI] = bool_to_bit(mtimecmp <=_u mtime)` -- a byte-for-byte implementation of the spec's own quoted rule.
- Between-instruction interrupt dispatch is real and already wired to the shared trap handler: `run_hart_active()` calls `dispatchInterrupt(cur_privilege)` as its first action, strictly before `fetch()` (`model/postlude/step.sail:98-102`), implementing the exact `MEI > MSI > MTI > SEI > SSI > STI > LCOFI` priority order the spec mandates (`model/sys/sys_control.sail:84-96,107-128`). A pending interrupt routes through `handle_interrupt()` -> the identical `trap_handler()` function synchronous exceptions use (`sys_control.sail:307-308` vs `:259-264`), differentiated only by an `is_interrupt` flag.
- `veda_test_sail.json` already has `clint.supported: true` (base `0x02000000`) -- this project's own test config, not something that needed enabling.

This project's own established pattern across Milestones 1-22 -- extend or hook base-model chokepoints rather than reimplement RISC-V privileged mechanics -- was, for a moment, forgotten when scoping the interrupt-readiness plan. This document is the record of catching that before any Sail/RTL code was written, per this project's own standing discipline of reading complete primary sources before deciding scope. The RTL side is genuinely unaffected: `veda_core.tlv` was never forked from the official Sail model's machinery and has no CLINT, no `mtime`/`mtimecmp` comparator, no timer bits in `mip`/`mie`, and no between-instruction interrupt-dispatch logic -- that remains a full, from-scratch RTL undertaking, unreduced by anything found here.

## What was verified, and how

Two independent, real questions were resolved by source-tracing before any test was written, then confirmed empirically:

1. **Is CLINT MMIO a capability-enforcement bypass?** No. `ext_data_get_addr` (`postlude/step_ext.sail:136-144`) is the mandatory front gate for every `vmem_read`/`vmem_write` call, including a store to `mtimecmp`, and runs before the address is even converted to a `virtaddr`. An ordinary `sd` to CLINT from purecap mode or a live compartment traps `VEDA_CAUSE_PURECAP_VIOLATION` exactly like any other memory access -- a real design constraint (arm the timer from unconstrained context, or hold a valid capability over the CLINT region), not a broken boundary.
2. **Is `handle_trap_extension` source-agnostic, or does it only work for synchronous causes?** Source-agnostic by construction. `handle_interrupt()` calls `trap_handler(del_priv, Interrupt(i), PC, None(), None())` -- the identical function, same `ext=None()` shape, same call position relative to `prepare_trap_vector`, as the exception path. The hook's own body (`step_ext.sail:231-233`) reads only `veda_pcc_length`, with zero dependency on `is_interrupt` or cause value.

## The test: `sail_tests/vc_timer_intr_pcc_reset.S`

Structured as a deterministic (non-racy) variant of `vc_pcc_generic_trap_reset.S`'s own pattern:

1. From unconstrained (pre-compartment) context: set `mtvec` to a realistic handler living outside the compartment; write CLINT `mtimecmp = 0` (address `0x02004000` = `plat_clint_base` + `MTIMECMP_BASE`, per `platform.sail:79`) via an ordinary `sd` -- since `mtime >= 0` always, `mip.MTI` latches pending immediately and stays pending; enable `mie.MTIE` (bit 7) but deliberately leave `mstatus.MIE` (bit 3) off, so no trap is taken yet.
2. Run the same `ODT-Populate` x3 / `veda.bind` x3 / `CSeal` x2 / `OCInvoke` ceremony `vc_pcc_generic_trap_reset.S` uses, narrowing PCC to a small landing-pad region.
3. Inside the compartment: flip `mstatus.MIE` via `csrs mstatus, t0`. Because `mip.MTI` and `mie.MTIE` are already both set, the RISC-V privileged spec's own trap-taken rule means the interrupt is taken at the very next instruction boundary, deterministically -- no polling loop, no timing race, and the trap fires with PCC genuinely still narrowed.
4. `real_handler` (outside the compartment) checks `mcause == 0x8000000000000007` (`Interrupt=1`, code 7 = Machine Timer, per the spec's own Interrupt Codes table) and `veda_pcc_length == 0xFFFF` (`VEDA_PCC_UNBOUNDED`) before returning via `mret` -- with the explicit, real design note that an interrupt's `mepc` (unlike `ecall`'s) already points at the not-yet-executed next instruction and must not be incremented before `mret`, the inverse of the ecall-handler idiom `vc_pcc_generic_trap_reset.S` uses.

## Results

**`vc_timer_intr_pcc_reset` passes on the first attempt** -- no debugging cycle was needed, matching the source-level reasoning above precisely. Full regression: **60/60 passed** (`sail_tests/run_veda_selfcheck_tests.sh`), 59 pre-existing tests plus this one, zero regressions.

**Mutation test (non-vacuity, this project's standing discipline):** `sys_control.sail`'s Machine-mode trap-entry call site was temporarily changed to `if not(is_interrupt) then handle_trap_extension(del_priv, pc, ext);` (skipping the hook specifically for interrupts), `sail_riscv_sim` rebuilt, and the new test re-run in isolation: it flips to a real `FAILURE` (exit code 1) -- the interrupted fetch of `real_handler` fails because PCC was never reset, exactly the fetch-fault failure mode `MILESTONE_21_RESULTS.md` itself documents for the analogous ecall case. The mutation was then reverted (confirmed via `git diff --stat` showing zero remaining diff) and `sail_riscv_sim` rebuilt again; the full suite was re-run and confirmed back at 60/60.

## Honest scope note

This closes exactly the gap named: does the existing, already-built PCC-reset mechanism work correctly for a real asynchronous interrupt. It does not build:

- **RTL mirror** -- explicitly out of scope; RTL has no interrupt/timer machinery at all today, a full from-scratch undertaking.
- **A real timer-interrupt-driven preemptive scheduler** -- this milestone proves the trap-entry mechanism is sound; it does not build the async-safe, arbitrary-entry-point GPR/CRF save discipline a real preemptive scheduler needs (a separate, larger, already-scoped design question -- the current cooperative scheduler's own fixed-sequence save at a single known `ecall` site does not generalize to an interrupt landing at an arbitrary PC).
- **`mie`/`mip` CSR gating review for the compartment/purecap model** -- `mie`/`mstatus` are ordinary, non-Veda CSRs outside the `0x7C0-0x7C3`/`0x7C5` range Milestone 20 gates; this test relies on that fact but did not re-audit whether that gating boundary should ever be extended to standard privileged CSRs, a separate, deliberately-unopened question.
