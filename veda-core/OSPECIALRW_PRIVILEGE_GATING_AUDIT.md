# OSpecialRW Privilege-Only Gating — Audited, No Gap Found

**Date:** 2026-08-02
**Scope:** closes the "`OSpecialRW`'s privilege-only gating" item named
in `MILESTONE_22_RESULTS.md`'s own "Not yet built" section, as part of
the same subsystem-by-subsystem security audit that section deferred.

## The question

`OSpecialRW` (Milestone 11, both Sail and RTL) reads/writes the ODA
(Object Descriptor Authority) — a single Special Capability Register
that lets software delegate a real capability-authority context, which
then authorizes `ODT-Populate`/`ODT-Destroy` as an OR alongside
ordinary M-mode privilege (`veda_oda_authorized() | cur_privilege ==
Machine`). `OSpecialRW` itself, though, is gated purely on
`cur_privilege == Machine` — no capability-based alternative. Is this
an overlooked gap, or a deliberate boundary?

## Real evidence, read directly, not recalled from a summary

`OSpecialRW`'s own real execute clause
(`toolchain/sail-riscv/model/extensions/Veda/veda_cap_insts.sail`):

```sail
function clause execute VEDA_OSPECIALRW(rs1, rd) = {
  if cur_privilege != Machine then Illegal_Instruction()
  else { ... }
}
```

Exactly and only `cur_privilege != Machine`. `ODT-Populate`/`ODT-Destroy`,
by contrast, already use the real OR-gate:

```sail
if not(cur_privilege == Machine | veda_oda_authorized()) then Illegal_Instruction()
```

`veda_oda_authorized()` itself (`veda_ocl_insts.sail`) requires the
ODA to hold a live, unsealed capability carrying
`PERMIT_ACCESS_SYSTEM_REGISTERS` — this is real, working, and already
independently verified since Milestone 11.

**The design rationale was already documented at the time, not
retrofitted for this audit** (`rtl/MILESTONE_11_RESULTS.md`):

> `OSpecialRW` itself is gated on ordinary privilege alone
> (`cur_privilege == Machine`), not on `PERMIT_ACCESS_SYSTEM_REGISTERS`
> the way real CHERI's own SCR access is — real CHERI's own rule needs
> `PCC.perms`, and Veda-Core still has no `PCC` (Milestone 10's own
> stated, carried-forward scope boundary). A capability-gated version
> of `OSpecialRW` itself would need that same `PCC` work first; using
> the already-established, already-verified privilege convention here
> is the honest floor, not a shortcut invented without precedent.

And the architectural principle it follows, also already documented:

> CHERI's own layered privilege model... "ring-based privilege" and
> "capability control of ring-related privilege" *coexist* — capability
> authority constrains ambient ring privilege, it does not replace it.

RTL's own implementation (`rtl/veda_core.tlv`) mirrors this exactly:
`OSpecialRW` gated on `$priv` alone, `ODT-Populate`/`ODT-Destroy` gated
on `$priv || $veda_oda_authorized` — the identical asymmetry, for the
identical, already-stated reason.

## Why this is sound, not just old

The dependency is real and still unresolved today: capability-gating
`OSpecialRW` itself would require checking the invoking code's own
`PCC.perms` (real CHERI's actual rule, CHERI ISA spec §4.3.6) — and
Veda-Core still has no full `PCC` struct (`Object_ID`/`Perms`/`otype`
are not tracked for the active compartment, only `Base`/`Length`,
per Milestone 14's own stated, still-current scope boundary). Building
capability-gating for `OSpecialRW` without that prerequisite would mean
inventing an ad hoc, non-CHERI-grounded rule just to have *something*
— worse than the current, honestly-scoped floor.

The asymmetry itself is also architecturally correct, not an
inconsistency: `OSpecialRW` is the instruction that *mints* delegated
authority into the ODA in the first place — a genuine root-of-trust
operation. Letting a capability *already in* the ODA authorize
*writing a new value into* the ODA would be circular (the authority to
delegate authority would have to come from somewhere). M-mode-only
gating here is the correct anchor point, matching every real capability
system's own need for *some* privileged root that capability-delegation
chains bottom out at.

## Conclusion

**Audited, no gap found.** This is a deliberate, already-reasoned,
already-documented design boundary (Milestone 11), not an oversight
surfaced fresh by this audit. It remains correctly named as real,
open future work — conditioned on a full `PCC` struct (`Perms`
specifically) ever being built, itself gated on a real consumer
existing for it, per Milestone 10's own original scope decision.
Closing this item of the subsystem audit with no code change, matching
`MILESTONE_22_RESULTS.md`'s own precedent for the spatial/temporal
-safety properties it audited and found sound.
