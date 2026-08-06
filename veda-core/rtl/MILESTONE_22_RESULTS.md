# Veda-Core RTL Milestone 22 Results — OCJALR Compartment-Boundary Scope, RTL Parity with Sail

**Date:** 2026-08-05
**Scope:** the last remaining item named in `veda-core/MILESTONE_22_RESULTS.md`'s
own "Not yet built" section ("RTL mirrors for Milestones 19-22" — 19/20/21
already closed this same audit pass; this closes 22, the final gap). Real
RTL parity for a real, empirically-confirmed Sail finding — not a redesign.

## The question this closes

Sail's own Milestone 22 (`veda-core/MILESTONE_22_RESULTS.md`) found and
empirically confirmed a real scope boundary: `OCJALR` (Milestone 17's
sentry-style return-capability jump) does not touch `veda_pcc_base`/
`veda_pcc_length` at all — unlike `OCInvoke`, which narrows PCC as a
deliberate part of its own real compartment-entry semantics. A genuinely
valid, correctly-authorized sealed return-capability targeting an address
outside a live `OCInvoke` compartment still hard-traps at the target's own
first fetch, because the compartment's narrowed bounds are still active —
not a security escape (Milestone 14's own fetch-check remains the real
backstop), a real, intentional scope boundary instead: `OCJALR` alone
cannot cross a compartment boundary; the correct, already-established
primitive for that remains a second `OCInvoke`. This RTL pass verifies the
identical property holds in real RTL, not just in the Sail formal model.

## Real RTL implementation status, verified before writing any test

Grepped `veda_core.tlv` directly before assuming anything: `OCJALR`
(`$is_veda_ocjalr`, Milestone 17) and PCC bounding (`$veda_pcc_violation`,
`$veda_pcc_base`/`$veda_pcc_length`, Milestone 14) are both already real,
independently-implemented RTL features — this milestone needed zero new
hardware, only a test proving their *combination* behaves identically to
Sail's own already-verified finding, the exact same kind of gap Sail's own
Milestone 22 closed for the formal model (a combination two earlier,
individually-correct milestones had never actually been tested together).

## Test design

`veda_smoke_m22.S`/`tb_veda_smoke_m22.sv`, built on the exact same real
`veda.odt.populate`/`veda.bind`/`cseal`/`ocinvoke`/`ocjalr` sequence
`veda_smoke_m14_neg.S` and `veda_smoke_m17.S` each already independently
prove work — combined here for the first time in RTL:

1. A sealed **RETURN capability** (Object_ID=93, `Permit_Execute` only,
   pointing at `return_landing`, genuinely far outside the compartment)
   and its type-authority (Object_ID=94) are built and sealed *before*
   entering the compartment — capability registers are not cleared by
   `OCInvoke`, only PCC narrows, so this survives into the compartment as
   the real, legitimate "call-site-prepared return capability" pattern.
2. A minimal compartment (Object_ID=90/91/92, CODE `Length=0x0004` — one
   instruction only, matching `veda_smoke_m14_neg.S`'s own established
   minimal-compartment convention) is entered via a real `OCInvoke`.
3. The compartment's one live instruction is `ocjalr c7, c6` — the sealed
   return-capability, jumping toward `return_landing`.
4. The trap handler asserts **four** real conditions, not just
   mcause/mtval: `mcause=0x18`, `mtval=0x201` (`cap_idx=16`, the real PCC
   sentinel; `cause=0x01`, `VEDA_CAUSE_BOUNDS_VIOLATION` reused), **`mepc`
   equal to `return_landing`'s own real address** (the load-bearing
   addition beyond Sail's own test — proves `OCJALR`'s `jump_to()` really
   resolved and redirected PC there *before* the fetch-check caught it,
   distinguishing a genuine jump-then-block from a coincidental
   fall-through fault at `landing_pad+4`, which sits at the same
   compartment boundary and would otherwise be indistinguishable by
   `mcause`/`mtval` alone), and `veda_pcc_length` correctly restored to
   `0xFFFF` (Milestone 21's own generic-trap-reset fix, proven again).

## Result

```
==> Milestone 22: Compiling (OCJALR compartment-boundary scope, RTL parity with Sail)
==> Simulating (Milestone 22)
*** TEST PASSED ***
```

Full regression: **35/35 RTL smoke tests passed** (34 pre-existing + this
one, zero regressions) via `run_veda_smoke_test.sh`; **51/51 ACT4 RV64I
conformance tests passed** via `run_act4_tests.sh`. First real run, no
debugging iterations needed — both underlying mechanisms (`OCJALR`,
Milestone 14 PCC-bounding) were already independently correct in RTL; this
milestone only needed to prove their combination, which it did cleanly.

## Design-decision note, carried forward explicitly

This test confirms — deliberately, not by oversight — that Veda-Core's RTL
compartment-exit remains **symmetric**: `OCJALR` is correctly scope-limited
to intra-compartment jumps only, and the only real way out of a
compartment is a second `OCInvoke`, matching Sail's own already-reasoned
Milestone 22 decision (`OCJALR`'s narrow scope was deliberately not widened
to also handle compartment-exit, to avoid re-blurring the exact scope that
closed a real, earlier vulnerability). Real CHERI's own compartment exit is
**asymmetric** (a heavy, two-capability `CInvoke` on entry; a light,
single-capability, `cra`-register-sourced, type-checked sentry jump on
exit) — genuinely different from Veda-Core's current symmetric design, and
a real, deliberate direction for the future minimal OS-kernel work, not
this milestone's own scope. Closing this RTL-parity gap now, on the
existing symmetric design, does not foreclose that future direction — it
simply proves the current design is *safe*, which it is.

## Not yet built

The asymmetric, CHERI-style lightweight exit-sentry mechanism itself
(a dedicated, `cra`-analogous register and a cheap, single-capability,
type-checked exit primitive) — explicitly deferred to the minimal
OS-kernel design phase, where real compartment-switching frequency and
performance will make the tradeoff concrete rather than theoretical.
