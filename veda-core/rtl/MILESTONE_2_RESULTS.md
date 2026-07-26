# Veda-Core RTL — Milestone 2 Results

**Date:** 2026-07-23
**Scope:** `OCA` (Custom-2), `NMC_ADD.D` (Custom-0), and Veda-Atomic
(Custom-1, real RISC-V-Zaamo-encoded 9-op ALU) — real, working TL-Verilog
RTL added to `veda_core.tlv` on top of Milestone 1's Capability Register
File/Object-Bind/`OCL.D`/`OCS.D`. Build order was deliberate, not
arbitrary: `OCA` had to come first, since Milestone 1's `Object-Bind`
always resets a capability's `Offset` to 0, and `NMC_ADD`/Veda-Atomic both
operate on the capability's own *persistent* `Offset` — the identical
dependency already stated in `VEDA_CORE_SPEC.md` Section 1 and already
respected once before when this same subset was built in Sail.

## Result: PASS — real bug found and fixed, then both positive and
negative paths verified empirically

### A real bug, caught by the first real test run, not assumed correct

The first `OCA` implementation only wrote `Tag` and `Offset` to the
destination capability register, silently assuming its other fields
(`Base`/`Length`/`Perms`/`otype`) were already correct from some earlier
`Bind`. **They aren't, in general** — `OCA`'s real semantics (matching
CHERI's own, and this project's own already-verified Sail
implementation) are "`rd` = a full copy of `rs1`'s fields, with `Offset`
replaced," not a partial update. The very first Milestone 2 test run
caught this immediately: `c1` (never independently bound) showed
`base=0x0`/`perms=0x0` after `OCA`, and the whole downstream chain read
zeros. Fixed by making `OCA`'s `/vreg` write copy every field from the
already-read `$veda_rs1cap_*` signals (the same capability lookup already
used for the checks), not just `Tag`/`Offset` — exactly mirroring `Bind`'s
own structure but sourced from `rs1` instead of the ODT. Re-verified
clean afterward. This is precisely why the "build a minimal slice, then
actually run it" discipline matters — the bug was invisible in the source
and only surfaced under real simulation.

### Positive path (`sim/veda_smoke_m2.S`)

`OCA` repositions `c1`'s `Offset` to `0x10` (copied from `c0`, which was
bound to the Milestone 1 seeded object), then `NMC_ADD.D` and Veda-Atomic
(`AMOXOR.D`) both operate through `c1` in sequence:

```
cyc=5   OCA lands -> c1: tag=1 base=0x80010000 perms=0x100c   (full copy, fixed bug confirmed)
cyc=8   x5 = 0x100   (NMC_ADD's old value, matching the stored 0x100)
cyc=11  x7 = 0x123   (Atomic's old value, matching NMC_ADD's own new value: 0x100+0x23)
cyc=13  x8 = 0x12C   (final OCL.D readback: 0x123 XOR 0x0F = 0x12C)
*** TEST PASSED ***
```

Every value in the chain is exact, confirming the real read-modify-write
against `elfmem` at the capability-resolved (not GPR-fresh-offset)
address works correctly for both instruction families.

### Negative controls — two distinct failure modes, both verified

1. **Missing `Permit_NMC_Compute`** (`sim/veda_smoke_m2_neg.S`): a second
   seeded object (`Object_ID=2`, `Perms=0x000C`, no `NMC_Compute` bit —
   added to the RTL test scaffold this pass, mirroring the same real
   negative-control entry already used in the Sail tests). `NMC_ADD.D`
   through it shows `viol=1`, and `x5` never receives a writeback,
   retaining its `0x5555` sentinel — proving the register write, not just
   a signal, is actually suppressed.
2. **`OCA`'s own out-of-bounds soft-fail** (`sim/veda_smoke_oca_neg.S`): a
   delta pushing `Offset` past `Length` clears `c1.Tag` (no trap, matching
   the soft-fail convention), and the *downstream* `NMC_ADD.D` through the
   now-untagged `c1` correctly shows `viol=1` with `x5` unchanged — a
   distinct failure mode from missing permission, both real and both
   caught.

### Full regression: zero impact on everything already verified

All of Milestone 1's own tests (positive round trip, negative control)
and the base RV64I core's own unmodified 81-instruction smoke test were
re-run against the final Milestone 2 build and produced identical results
to their prior runs — six real test programs, one script
(`run_veda_smoke_test.sh`), zero regressions.

## Design notes worth recording

- **Shared signal reuse across instruction families**: `OCA`, `NMC_ADD`,
  and Veda-Atomic all reuse the *same* `$veda_ocl_ocs_rs1_cap`/`$rs2`/`$rd`
  decode signals Milestone 1 already extracted for `OCL`/`OCS` — a direct,
  real payoff of `VEDA_CORE_SPEC.md`'s own stated design principle
  ("every instruction family... keeps register-operand fields at
  consistent bit positions... decode logic built for one instruction
  family transfers almost unchanged to the others").
- **`NMC_ADD` and Veda-Atomic share their real-address/old-value read**
  (`$veda_cap_real_addr`/`$veda_cap_old_d`) since both operate on the
  capability's persistent `Offset` at D-width — computed once, consumed
  by both, rather than duplicated.
- **Permission split preserved from Sail**: `NMC_ADD` gated on its own
  dedicated `Permit_NMC_Compute` bit; Veda-Atomic gated on
  `Permit_Load`+`Permit_Store` (a general RMW, not the dedicated
  compute-at-memory dispatch `NMC_ADD` is) — the identical reasoning
  already worked through once in Sail, applied unchanged here.
- Op-select encoding for Veda-Atomic reuses real RISC-V Zaamo's own
  values verbatim (not invented), matching the same real-precedent-reuse
  decision already made once in Sail Milestone V-B.

## Not yet built

The remaining 8 of 9 Veda-Atomic ops beyond `AMOXOR` share the identical,
now-proven ALU-mux skeleton (not independently tested this pass — the
same real, stated scope choice already made for the Sail work).
`NMC_ADD.W`, the query family, `CSetBounds`/`CSeal`/`CUnseal`,
`ODT-Populate`/`ODT-Destroy`, and real trap/exception infrastructure all
remain real, deferred, later RTL milestones.
