# Veda-Core Milestone 22 Results — Auditing Against CHERI's Own Real Pillars (Spatial/Temporal Memory Safety, Compartmentalization)

**Date:** 2026-08-01
**Scope:** a directed, systematic audit of Veda-Core against the specific properties Simon Moore's own CHERI correspondence named, requested explicitly before continuing to a broader subsystem-by-subsystem review or any future OS/runtime work. Real, official CHERI framing verified before auditing against it — not assumed from memory (see below). Two of the three areas audited hold up under direct, adversarial re-reading of every real memory-touching instruction; the third (compartmentalization) surfaced one real, new scope-boundary gap, found, confirmed empirically, and closed with documentation and a permanent test in this same pass.

## Real CHERI pillars, verified before auditing against them

A WebSearch of CHERI's own official sources (Cambridge CTSRD's real `cl.cam.ac.uk` pages, including its own FAQ) corrected an assumption before any audit work began: **CHERI's real, stated architectural goals are memory safety (spatial + referential/provenance) and scalable software compartmentalization — CHERI's own FAQ explicitly states it does *not* provide temporal safety, "and there are no current plans to incorporate temporal safety into CHERI."** Temporal safety is addressed by CHERI-adjacent research built on top of CHERI (e.g. the real CHERI-D paper, `arXiv:2606.19055`, whose generation-counter width Veda-Core's own ODT design already deliberately borrowed — see `VEDA_CORE_SPEC.md` Section 5.1/`SCALING_BARRIERS_RESEARCH.md`), not a guarantee of CHERI's own core ISA.

Veda-Core, unlike core CHERI, does make its own real, explicit temporal-safety claim (the generation-counter mechanism) — so this audit covers all three properties (spatial safety, Veda-Core's own temporal-safety claim, and compartmentalization) on their own merits, regardless of which are or aren't official "CHERI pillars" by name.

## Spatial memory safety — audited, no new gap found

Every real memory-touching Veda-Core instruction was re-read in full and checked for a correct, real bounds check:

| Instruction(s) | Check function | Bounds check |
|---|---|---|
| `OCL.D`/`OCS.D` | `veda_check_access` | `unsigned(offset) + width > unsigned(cap.Length)` |
| `OCL.C`/`OCS.C` (128-bit) | `veda_check_access` (width=16) | same, reused unchanged |
| `NMC_ADD.W`/`.D` | `veda_check_nmc_access` | same pattern, separate function, `cap.Offset`-based |
| All 9 Veda-Atomic ops | `veda_check_access` | same, `cap.Offset`-based |

All four converge on the identical real bounds-check shape. Verified this cannot integer-overflow: `unsigned(...)` in Sail produces an unbounded-precision mathematical integer, not fixed-width arithmetic, so the addition and comparison have no wraparound risk regardless of `offset`/`width` magnitude — confirmed from Sail's own type semantics, not assumed.

Checked whether `OCA`/`CSetBounds` could be misused to smuggle an out-of-range `Offset` past a later dereference's own check: `OCA` clears the resulting capability's Tag if the new offset would fall outside `[0, Length)` (`out_of_range` check in its own execute clause), and every dereferencing instruction checks `CTag` first — so an out-of-range `Offset` can never reach a real memory access with a live tag. `CSetBounds`/`CSetBoundsExact` enforce real monotonic narrowing (`cap.Offset + new_length <= cap.Length`), matching CHERI's own real non-widening principle. No gap found.

## Temporal memory safety (Veda-Core's own claim, not a core-CHERI one) — audited, no new gap found

Traced the generation counter end-to-end: `odt_lookup(cap.Object_ID)` is a fresh, live table read at every check (never a cached value); `entry.generation != cap.Reserved` (present in both `veda_check_access` and `veda_check_nmc_access`) correctly detects a capability whose cached generation no longer matches the object's current one. Re-verified `Object-Bind`/`Bind-NoTrap`/`Rebind` (`veda_bind_insts.sail`) all copy `e.generation` — the ODT's live, just-looked-up value — into the capability's `Reserved` field on every successful bind, so a freshly bound capability is always correct by construction; staleness can only arise the intended way (destroy-then-repopulate after a capability was already bound elsewhere). Re-verified `ODT-Populate`/`ODT-Destroy`/`ODT-Populate-Fast`'s own generation-bump and freeze-at-`0xFF`/`retired` logic (the wraparound fix from earlier project history) is still internally consistent: `Destroy` always bumps; `Populate` bumps only when overwriting a still-`valid` slot (not a no-op double-bump on an already-destroyed one, since `Destroy` already advanced it); a `retired` slot can never be repopulated at all. No gap found.

## Compartmentalization — one real, new scope-boundary gap found, confirmed, and closed this pass

Building on Milestones 14/19/20/21's own already-extensive compartmentalization hardening, this pass specifically checked `OCJALR` (the sentry-style return-capability jump, `rtl/MILESTONE_17_RESULTS.md`/`STACK_FRAME_CALL_RETURN_ANALYSIS.md`) in combination with a live `OCInvoke` compartment — a combination neither `vc_ocjalr.S` nor `vc_ocjalr_neg.S` had ever exercised.

**Real, empirically-confirmed finding**: `OCJALR`'s own execute clause is a plain `jump_to()` with zero PCC interaction — unlike `OCInvoke`, it never touches `veda_pcc_base`/`_length`. A genuinely valid, correctly-authorized sealed return-capability (every real check satisfied) targeting an address outside a live compartment's own bounds still hard-traps at the target's own first fetch, because the compartment's narrowed bounds are still active. Confirmed with a real PoC under `sail_riscv_sim` before concluding anything, following this project's own established empirical-first discipline.

**Not a security escape** (Milestone 14's fetch-check remains the real backstop, exactly as designed) — a real scope boundary instead: `OCJALR` cannot cross a compartment boundary on its own. The already-established, already-tested correct primitive is a second `OCInvoke` (the exact pattern `vc_pcc_bounds.S`/`vc_ocinvoke.S` already prove works). Because of Milestone 21's own generic-trap PCC-reset fix, a stray cross-boundary `OCJALR` now fails *safely and recoverably* (reaches a real trap handler) rather than hanging — but it still fails, by design, not by oversight, which is exactly the kind of thing that would have bitten a future OS/runtime implementer hard if left undocumented.

Closed by documentation + permanent test, not by changing `OCJALR`'s own carefully-scoped, already-verified semantics (deliberately narrower than real CHERI's own general-purpose `CJALR`, per its own original design doc — widening it now to also handle compartment-exit would re-blur exactly the narrow, auditable scope that closed its own original vulnerability):

- `STACK_FRAME_CALL_RETURN_ANALYSIS.md` — new section stating the finding, the "not a security escape" reasoning, and the practical guidance for future OS work (internal compartment subroutine calls may use `OCJALR`-protected returns; a compartment's own exit to its invoker must use a second `OCInvoke`).
- `sail_tests/vc_ocjalr_compartment_boundary_neg.S` — the permanent regression test: a real compartment, a real valid return-capability targeting outside it, asserts the real hard-trap (`mcause=0x18`, `mtval=0x201`, the same real PCC-fetch-violation cause/sentinel Milestone 14 already established) and that `veda_pcc_length` is correctly restored to `VEDA_PCC_UNBOUNDED` by the time the handler runs (Milestone 21's own fix, proven, not just argued).

## Result

`run_veda_selfcheck_tests.sh` — **42/42 passed** (41 pre-existing + 1 new), zero regressions.

## Not yet built

Broader subsystem-by-subsystem review (Veda-Atomic's own `aq`/`rl` semantics under real concurrency, `OSpecialRW`'s privilege-only gating, RTL mirrors for Milestones 19-22) explicitly deferred to a later pass, per the user's own stated sequencing: audit the named CHERI-pillar properties first, broaden afterward, with extra caution before any future OS/runtime work begins on top of this project.
