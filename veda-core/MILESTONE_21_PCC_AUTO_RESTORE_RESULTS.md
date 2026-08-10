# Automatic PCC Restore-on-mret/sret Results

**Date:** 2026-08-10
**Scope:** closes the "restore-and-resume-inside-compartment pattern" `MILESTONE_21_RESULTS.md` itself named as "a real, usable extension this fix enables but does not itself build or test" -- `veda_pcc_save_and_reset()` already captured the interrupted compartment's bounds into `veda_mepcc_base`/`veda_mepcc_length` (CSRs 0x7C2/0x7C3) on every trap; this milestone adds automatic restoration of those bounds on `mret`/`sret`, matching real CHERI-RISC-V's own `mepcc`-unseal-on-`mret` precedent, so a preemptive interrupt handler no longer needs bespoke code to resume the compartment it interrupted.

## Design decision and why (Plan Mode, approved before implementation)

Two real mechanisms were researched and compared for where to hook the restore:

- Changing `xret_callback`'s declared-`pure` effect signature so its body could write registers -- rejected: all 10 callbacks in `core/callbacks.sail` share the identical `pure {cpp:...}` shape, tied to external C++ RVFI/instrumentation symbols; this project's own prior Coq/Lem export work never touched the purity/effect question, so the cross-backend blast radius was genuinely unverified.
- A direct conditional call inside `execute MRET()`/`execute SRET()` (`extensions/I/base_insts.sail`) -- **adopted**, matching a real, already-shipped precedent at the exact same call site: `if hartSupports(Ext_Zicfilp) then zicfilp_restore_elp_on_xret(mRET, cur_privilege);` immediately before the existing `xret_callback(...)` call, for both MRET (line 579-580) and SRET (line 623-624).

Real CHERI's own `mepcc`-unseal-on-`mret` is unconditional on cause (CHERI-RISC-V spec §12.2.19/§4.7.7: "MRET unseals mepcc and writes the result into pcc", no qualifier), because real CHERI's PCC is never in an "unbounded/inactive" state -- its reset value is the Infinite/root capability, always legitimate to install. Veda-Core's own restore is gated on `veda_mepcc_length != VEDA_PCC_UNBOUNDED`, since Veda-Core's model has a genuine unbounded/no-compartment state real CHERI's doesn't.

## Implementation

- `veda-core/rtl` unaffected -- this is Sail-only, matching this project's own Sail-first sequencing.
- **`toolchain/sail-riscv/model/extensions/Veda/veda_regs.sail`**: new `veda_pcc_restore_on_xret()`, sibling to `veda_pcc_save_and_reset()`:
  ```sail
  function veda_pcc_restore_on_xret() -> unit = {
    if veda_mepcc_length != VEDA_PCC_UNBOUNDED then {
      veda_pcc_base = veda_mepcc_base;
      veda_pcc_length = veda_mepcc_length;
      veda_mepcc_base = zeros();
      veda_mepcc_length = VEDA_PCC_UNBOUNDED;
    }
  }
  ```
  Self-consuming by design: a saved value is never applied to more than one `mret`/`sret`.
- **`toolchain/sail-riscv/model/exceptions/sys_exceptions.sail`**: a forward `val veda_pcc_restore_on_xret : unit -> unit`, discovered necessary during implementation (not anticipated in the approved plan, but the identical module-ordering fix `handle_trap_extension` itself already uses right above it) -- `base_insts.sail` (module `I`) does not itself require the `Veda` module, so a plain call to a `veda_regs.sail`-defined function fails to type-check without a forward declaration visible in a module `I` does require (`exceptions`).
- **`toolchain/sail-riscv/model/extensions/I/base_insts.sail`**: one `if hartSupports(Ext_Veda) then veda_pcc_restore_on_xret();` added in each of `execute MRET()` and `execute SRET()`, immediately before their existing `xret_callback(...)` calls.

## Real regressions found and fixed (the plan's own "zero behavioral diff" prediction was wrong for one real class of test)

The approved plan predicted zero behavioral difference for any test that "never narrows a compartment." Running the full regression after the implementation found **3 real regressions**: `vc_pcc_bounds_neg`, `vc_pcc_generic_trap_reset`, `vc_timer_intr_pcc_reset` -- all three narrow a compartment, trap, and their own handlers relied on the *old* default (no auto-restore, stay unbounded) without explicitly saying so. The new default silently resumed them back inside the compartment they meant to leave.

Root cause, traced precisely in `vc_pcc_bounds_neg.S`: its own recovery code already wrote directly to the *live* registers (`veda_pcc_base`/`veda_pcc_length`, 0x7C0/0x7C1) to re-widen PCC -- the correct, already-established idiom before this milestone -- but never touched the *shadow* registers (`veda_mepcc_base`/`veda_mepcc_length`, 0x7C2/0x7C3), which still held the abandoned compartment's real bounds from the fault. The new auto-restore then silently overwrote the handler's own explicit recovery on `mret`.

**Fix**: all three tests updated to also `csrw 0x7c3, <VEDA_PCC_UNBOUNDED>` before their own `mret`, explicitly cancelling the pending restore -- a real, necessary migration for any handler that wants to deliberately abandon a compartment, not a workaround. Each fix is commented with the real reasoning, not silently patched. Full regression: **61/61** (60 pre-existing incl. the 3 fixes + 1 new), zero remaining regressions.

## New test: `sail_tests/vc_pcc_auto_restore_on_mret.S`

Three phases, one compartment each (distinct Object_IDs, distinct `Length` values, so no phase can pass by reusing another's leftover state):

1. **Positive automatic restore + self-consuming + real enforcement.** Compartment narrows (`Length=0x40`), traps, handler does *not* touch `veda_mepcc_*`, `mret`s. Confirms `veda_pcc_length`/`veda_pcc_base` read back the original bounds (not unbounded) with zero handler code, confirms `veda_mepcc_length` already reads back `VEDA_PCC_UNBOUNDED` (self-consumed), then proves real enforcement: the resumed code's own remaining checks run right up against the real 0x40-byte window, and the fetch that finally exceeds it genuinely PCC-bounds-faults (`cause=0x18`, `mtval=0x201`) -- the identical real mechanism `vc_pcc_bounds_neg.S` already proves, reached here empirically rather than via a deliberately staged CSR-write block (the originally-planned mechanism; see design-history note below).
2. **Explicit override still honored.** A second, independent compartment traps; its handler explicitly clears `veda_mepcc_length` before `mret`. Confirms PCC stays unbounded -- software's deliberate choice is not silently overridden.
3. **Repeatability.** A third, independent compartment (fresh Object_IDs, `Length=0x30`, deliberately different from phase 1's `0x40`) proves the mechanism genuinely re-arms for a fresh save/restore cycle, not a one-shot artifact of phase 1's own specific state.

**Design-history note, recorded honestly rather than silently revised:** the approved plan's own third property was "a nested trap incorrectly restoring a stale, unrelated saved value." Tracing that scenario precisely while writing this test found it does not test what was intended -- an inner trap's own `mret` restoring a value saved by an outer, still-in-progress handler is real, CHERI-consistent behavior (real CHERI's own `mepcc`-unseal is unconditional on every `mret`, nesting included; managing that is standard OS/software responsibility, the same discipline `mepc` itself already requires for any re-entrant handler), not a bug this milestone's self-consuming reset does or should prevent. Phase 3 above tests the real, well-defined property the self-consuming reset actually guarantees instead. General nested/re-entrant trap handling remains a real, separate, explicitly out-of-scope gap -- named here, not silently assumed solved.

## Mutation testing (this project's standing discipline) -- one honest non-finding, one confirmed finding

**Mutation 1 -- remove the `veda_mepcc_length != VEDA_PCC_UNBOUNDED` guard entirely.** Rebuilt, ran the full regression: **61/61 still passed, zero observable difference.** A dedicated follow-up test (`vc_pcc_restore_guard_neg.S`) was written specifically to construct a scenario where the guard's presence should matter (a direct, non-`OCInvoke` CSR write establishing bounded live PCC, with no prior save). Tracing it against a real execution trace found the scenario is not reachable as designed: **all three of this project's own pre-existing save call sites** (`veda_trap()`, `ext_handle_fetch_check_error`, `ext_handle_data_check_error` -- Milestone 14, not this milestone's own `handle_trap_extension` hook) already save unconditionally whenever *any* trap is taken from a bounded context, regardless of how that context became bounded. By the time `veda_pcc_restore_on_xret()` is ever reached with something to restore, a real save has just happened for *that* trap -- there is no currently-reachable path where the guard's absence would apply a stale, unrelated value. The dedicated test was deleted rather than forced to "pass" artificially, and `veda_pcc_restore_on_xret()`'s own comment was rewritten to state this honestly: the guard matches this project's stated design principle and costs nothing, but no reachable scenario currently depends on it -- a real, mutation-tested finding, not an assumption.

**Mutation 2 -- remove the self-consuming reset** (`veda_mepcc_base = zeros(); veda_mepcc_length = VEDA_PCC_UNBOUNDED;`). Rebuilt, ran the full regression: **`vc_pcc_auto_restore_on_mret` flips to a real `FAILURE`** (phase 1's own inline assertion, `veda_mepcc_length` must read back `VEDA_PCC_UNBOUNDED` immediately after the restore, correctly catches it) -- confirmed non-vacuous. Reverted; full regression back to **61/61**.

## Final state

`toolchain/sail-riscv` diff: 3 files, 59 insertions, matching (plus one necessary forward-declaration file the approved plan didn't anticipate) exactly the approved plan's scope. `veda-core` diff: 1 new test file, 3 pre-existing test files updated with the real, necessary migration, this results doc, and `MILESTONE_21_RESULTS.md`'s own "Not yet built" section updated to point here. Not committed or pushed yet, matching this session's established pattern.
