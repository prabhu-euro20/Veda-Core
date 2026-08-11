# RTL Milestones 21/27 Mirror: Automatic PCC Restore-on-MRET + mtvec Escape Gate

## Problem

Task #297 (Sail-side, `SYSCALL0_MILESTONE_RESULTS.md`) built a real KERNEL ecall dispatcher whose
whole design leans on Milestone 21's **automatic** PCC restore-on-`mret`
(`veda_pcc_restore_on_xret()`, Sail-only per `MILESTONE_21_PCC_AUTO_RESTORE_RESULTS.md`) — the
handler never explicitly writes `veda_pcc_base`/`_length` back before `mret`; hardware does it.

Before mirroring that KERNEL dispatcher into RTL, a direct audit of `rtl/veda_core.tlv` found the
mechanism entirely absent: `$veda_pcc_base`/`$veda_pcc_length`'s own update logic had no `$is_mret`
arm — RTL still required explicit software `csrw` before `mret`, the pre-M21-restore Sail behavior.
Milestone 27's `mtvec`-write compartment-escape gate was *also* missing from RTL, honestly pre-named
in `MILESTONE_27_MTVEC_CSR_GATE_RESULTS.md`'s own "Not yet built" section as "a combined future RTL
pass." Both gaps were real, necessary prerequisites for the KERNEL-dispatcher mirror (Part C, RTL
Milestone syscall0-kernel), not scope creep.

## Part A: automatic PCC restore-on-mret

**A second real bug, found while designing the mirror, not copied blindly from Sail**: RTL's
pre-existing trap-time capture of `$veda_mepcc_base`/`_length` was **unconditional** — it captured on
every trap, even when PCC was already unbounded. Harmless while nothing auto-consumed `mepcc`, but
once `mret` starts consuming it automatically, a second, nested trap between a first trap's save and
its own later `mret` would silently overwrite the first trap's real saved bounds with
`{don't-care, UNBOUNDED}`. Fixed by gating the capture on `>>1$veda_pcc_length != 16'hFFFF`, matching
the Sail side's own already-adversarially-reviewed conditional-capture design.

Three changes to `rtl/veda_core.tlv`:
1. `$veda_mepcc_base`/`_length`'s trap-time capture arm gains the conditional-capture guard above.
2. `$veda_pcc_base`/`_length` gain a new, highest-priority-after-trap arm: `(>>1$is_mret &&
   (>>1$veda_mepcc_length != 16'hFFFF)) ? >>1$veda_mepcc_base/_length : ...`.
3. `$veda_mepcc_base`/`_length` gain a self-consuming reset arm on the same condition, resetting to
   `{0, UNBOUNDED}` so a stale value can never be restored twice.

## Part B: mtvec escape gate

Two changes to `rtl/veda_core.tlv`:
1. `$veda_csr_escape_violation`'s OR-list gains `|| $csr_is_mtvec` — reuses 100% of the already-wired
   `mcause=0x02`/`mtval=raw-instr`/`veda_trap_taken` machinery for free.
2. `$mtvec`'s own CSR-write update arm gains `&& !(>>1$veda_csr_escape_violation)` — `mtvec` has no
   PCC-family "any trap resets me" branch of its own to piggyback on, unlike the PCC-family CSRs, so
   it needs this explicit guard, matching `$veda_mode`'s own already-established pattern.

## New smoke tests

- **`rtl/sim/veda_smoke_pcc_restore_on_mret.S`** (+ testbench): three phases, mirroring the Sail
  side's own `vc_pcc_auto_restore_on_mret.S` exactly.
  - Phase 1 (positive restore + real enforcement): a handler touching neither `pcc_*` nor `mepcc_*`
    still resumes with the original narrow bounds correctly restored, and a deliberate post-check
    fetch past the real boundary still hard-traps — proving genuine restored bounds, not just
    correct CSR readback.
  - Phase 2 (explicit override honored): the handler clears `veda_mepcc_length` before `mret`;
    execution resumes unbounded, not re-narrowed.
  - Phase 3 (nested-trap staleness + repeatability): a second, unrelated trap fires inside the first
    handler before its own `mret`. Two distinct real bugs were found and fixed during debugging of
    this phase (see below), neither present in — nor previously tested by — the Sail-side design.
  - Both phases' own boundary-tuning followed this project's established discipline: `objdump` on the
    real assembled ELF, never a hand-counted `Length`.
- **`rtl/sim/veda_smoke_mtvec_escape_neg.S`** (+ testbench): from inside a live compartment, `csrw
  mtvec` must hard-trap (`mcause=0x02`), and `mtvec` itself reads back the real, originally-installed
  handler address afterward — never hijacked, not even partially.

## Two real bugs found only during Phase 3 debugging (not by design or the Sail port)

1. **`mepcc` cross-context ambiguity**: `mepcc` is a single, global pair — it cannot by itself
   distinguish "the OUTER handler's own real, restore-triggering `mret`" from "an INNER/nested
   handler's own `mret`, which should NOT trigger restore" (both see the identical
   `mepcc_length != UNBOUNDED` condition). Fixed via explicit software shepherding: the inner handler
   saves `mepcc_base`/`_length` into callee-saved GPRs and clears `mepcc_length` before its own
   `mret`; the outer handler's own continuation restores `mepcc` from those GPRs before its own,
   later, real `mret` — genuine, necessary software cooperation for nested-trap safety, matching real
   OS kernel practice, not a workaround.
2. **`mepc` unconditional-capture corruption**: unlike the now-fixed `mepcc`, `mepc` has no
   conditional-capture guard at all — any trap unconditionally overwrites it, including a nested one.
   The outer handler's own resume-address computation must save `mepc` into a GPR *before* triggering
   any nested trap, and use that saved value — never a later re-read of the CSR.

A third, more mundane issue surfaced once all three sentinels correctly read `0x600D`: Phase 3's own
exit path (a raw `j all_done`) was itself an out-of-bounds fetch relative to `phase3_entry`'s own
narrow `Length` — the identical "resume-check-code doesn't fit its own narrow compartment" class of
bug already seen for Phase 1. Fixed the same way Phase 1's own deliberate escape is handled: an
explicit, real ecall-mediated exit (a new `h_phase3_exit` handler, matching `h_phase1_escape`'s
already-proven pattern) rather than a raw jump, with `phase3_entry`'s `Length` widened
(`objdump`-confirmed) to comfortably cover the exit `ecall` itself.

## Mutation tests

- **Part A, capture guard**: temporarily dropped `&& (>>1$veda_pcc_length != 16'hFFFF)` from the
  `mepcc` capture arms — Phase 3 correctly flipped to FAILED (`x26=0x0`, `x22=0xDEAD`). Reverted,
  confirmed PASSED again.
- **Part A, self-consuming reset**: temporarily dropped the `is_mret`-triggered reset arm on
  `mepcc_base`/`_length` — Phase 3 correctly flipped to FAILED (`x26=0x0`, `x22=0xDEAD`, the
  self-consumption check itself catching it). Reverted, confirmed PASSED again.
- **Part B, escape gate**: temporarily dropped `|| $csr_is_mtvec` from `$veda_csr_escape_violation` —
  the malicious `csrw mtvec` silently succeeded, and the test flipped to FAILED in the strongest
  possible way: a *subsequent*, unrelated fetch-bounds trap was serviced by the now attacker-redirected
  `bogus_handler` (`x22=0xBAD2`), directly demonstrating control-flow hijack rather than merely
  failing to detect the escape. Reverted, confirmed PASSED again.

## Verification

- **`veda_smoke_pcc_restore_on_mret`**: PASSED — all three phase sentinels (`x21`/`x25`/`x26`)
  `0x600D`, fail sentinel `x22` stayed `0x0`.
- **`veda_smoke_mtvec_escape_neg`**: PASSED — `x21=0x600D`, `x22=0x900D`.
- **Full RTL smoke-test regression**: `rtl/run_veda_smoke_test.sh`, **51/51 passed**, zero
  regressions elsewhere in the corpus (both new tests registered).
- **ACT4 RV64I conformance suite**: `rtl/run_act4_tests.sh`, **51/51 passed**, zero regressions.

## Scope

RTL now has full Sail/RTL parity for both mechanisms, closing the two prerequisite gaps identified
before Part C (`rtl/sim/veda_smoke_syscall0_kernel.S`, the actual Task #297 mirror) could begin. The
forged-Object_ID negative case (Task #299's own RTL parity) remains a natural, closely-following next
step, not required to close this pass.
