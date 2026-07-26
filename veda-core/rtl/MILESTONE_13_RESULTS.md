# Veda-Core Milestone 13 Results — Plain Bind's Own Object-Not-Found Hard-Trap (RTL) + a New Sail Test

**Date:** 2026-07-26
**Scope:** `MILESTONE_9_RESULTS.md`'s own explicitly named, deliberately deferred gap: *"plain `Bind`'s own ODT-miss hard-trap (`VEDA_CAUSE_OBJECT_NOT_FOUND`, `0x05`) is real in Sail but was not wired into RTL this pass... a real, separate, correctly-named follow-on."* Sail has implemented this correctly since early in the project (`veda_bind_insts.sail`'s `VEDA_BINDINST` catch-all else-branch); this milestone closes the RTL-side gap and adds the dedicated Sail-side test that, it turns out, never existed either.

## Why now, and why this was chosen over the other remaining gaps

After Milestone 12, four named gaps remained: plain `Bind`'s own ODT-miss trap (this milestone), `OSpecialRW`'s privilege-only gating (blocked on a real `PCC` register — a large, dedicated design effort), `ODT-Destroy`'s own owner-hart gating (a real design question, not a mechanical extension — Destroy's authorization is arguably orthogonal to Bind-time ownership, not obviously the same lever), and real multi-hart RTL (very large, new module architecture). This one was chosen because it is the smallest, most mechanical, best-understood closure — Sail's own behavior for this exact case has existed and been trusted for many milestones, RTL already has every piece of trap infrastructure this needs (built in Milestones 9 and 12), and Milestone 12 already made moot the one reason Milestone 9 gave for deferring it (see below).

## A real risk found by research before writing any RTL, not discovered by a broken test after the fact

Milestone 9's own deferral reasoning was: *"doing so would, for the first time, make RTL's plain `Bind` and `Bind-NoTrap` behaviorally different... a real, separate follow-on."* That specific reason is now moot — Milestone 12's own owner-violation trap already created that exact divergence. But before writing any RTL, a full grep of every `veda_smoke_*.S` file's own plain-`Bind` usage (not `Bind-NoTrap`, not `Rebind`) against its target `Object_ID`'s actual validity turned up **five real, load-bearing collisions** — pre-existing, currently-passing tests that rely on plain `Bind`'s *current* soft-fail behavior against a never-populated or just-destroyed `Object_ID`, without any trap handler that expects this specific new trap:

1. `veda_smoke_neg.S` (Milestone 1's own negative control) — binds `Object_ID=50` (never populated) then a subsequent `OCS.D` is the instruction meant to trap; a Bind-time trap would fire first, with the wrong `mtval`.
2. `veda_smoke_m4.S` (Milestone 4's own positive test) — re-binds `Object_ID=3` *after* destroying it, expecting `Tag=0`.
3. `veda_smoke_m4_neg.S` — binds `Object_ID=5` (never populated) with **no trap handler installed at all**; an unhandled trap would jump to address 0.
4. `veda_smoke_m9.S` (Milestone 9's own positive test) — binds `Object_ID=99` (never populated) specifically *to* set up its own real subject, `OCS.D`'s Tag-check trap; same "wrong instruction traps first" problem as #1.
5. `veda_smoke_m11_neg.S` — binds `Object_ID=6` (never populated) with no trap handler installed; same address-0 risk as #3.

This is the exact same failure class Milestone 9 itself hit and fixed once already (*"enabling real hard traps breaking three unrelated, already-passing tests that embedded a soft-fail assumption from an earlier milestone"*) — found here by research and grep *before* touching any RTL, not by a broken regression after the fact, though the full regression run below (deliberately performed *before* fixing the five tests) confirmed the prediction exactly: 5 failures, 17 passes, matching the five files identified.

## The fix: use the architecturally correct instruction, not a workaround

Each of the five collisions was fixed the same way: the specific plain-`Bind` instruction that needs a soft-fail (`Tag=0`, no trap) was changed to **`Bind-NoTrap`** — the instruction that has existed precisely for this purpose since Milestone 8 (*"produce a result without disrupting control flow"*). This is not a patch or a workaround; it is the same category of fix as Milestone 12's own principle: the test's *real* subject (an unrelated instruction's own trap, or an unrelated privilege check) is unaffected, and Bind's own new trap semantics are simply not exercised by an instruction that was never actually testing them. No test's own assertions, sentinels, or pass/fail logic needed to change — only the one `.word` encoding at the specific point each test needed a non-disruptive `Tag=0`.

## Design decisions, reasoned and stated, not invented

- **Cause code `0x05`** is not new — `VEDA_CORE_SPEC.md` Section 3 already reserved and named it (`VEDA_CAUSE_OBJECT_NOT_FOUND`) since early in the project; this milestone is the first RTL consumer, not the definition.
- **`cap_idx = rd`**, identical to Milestone 12's own owner-violation — both of plain `Bind`'s hard-trap reasons share the same `veda_trap(rd, ...)` call shape in Sail, so RTL's own `$veda_trap_cap_idx` mux needed no new per-family case, only a combined umbrella.
- **A single combined `$veda_bind_trap` signal** (`$veda_bind_owner_violation || $veda_bind_notfound_violation`), mutually exclusive by construction (one requires `$veda_odt_valid`, the other requires `!$veda_odt_valid`) — mirrors `veda_bind_insts.sail`'s own catch-all else-chain exactly (owner check, then object-not-found, as two mutually exclusive outcomes of the same `e.valid` test), and lets `$bind_wr_en`'s own trap-exclusion term stay a single clause instead of growing per new trap reason.
- **The destination register is left completely untouched on this trap too**, not just Tag-cleared — same reasoning and same `!$veda_bind_trap` exclusion mechanism already established for the owner-violation case.

## Implementation

**RTL** (`veda_core.tlv`): `$veda_bind_notfound_violation = $is_veda_bind_plain && !$veda_odt_valid`; `$veda_bind_trap`/`$veda_bind_cause` combine it with the existing owner-violation signal; `$bind_wr_en`'s exclusion term changed from `!$veda_bind_owner_violation` to `!$veda_bind_trap`; the outer `$veda_trap_taken`/`$veda_trap_cause`/`$veda_trap_cap_idx` mux's three owner-violation-only arms became `$veda_bind_trap`-gated instead. No Sail changes — Sail already implements this correctly.

**Tests**: five pre-existing RTL tests migrated from plain `Bind` to `Bind-NoTrap` at the one specific instruction each needed it (see above); one new RTL test (`veda_smoke_m13_neg.S`/`tb_veda_smoke_m13_neg.sv`) proving the new trap fires correctly (`cause=0x05`, `cap_idx=rd`, correct `mepc`/`MRET` resume, destination register completely untouched); one new Sail test (`vc_bind_notfound_neg.S`) closing a real, previously-unnoticed **test-coverage** gap — Sail's own object-not-found trap has existed for many milestones but had never been directly, explicitly asserted by any self-check test until now.

## Result

All five migrated tests pass with their original assertions completely unchanged (only the one Bind→Bind-NoTrap encoding swap per file). The new RTL negative test and the new Sail negative test both passed on their first real simulation run — no design or implementation bugs found this milestone; the only real issue was a comment-syntax mistake in the new Sail test file (`//` instead of `#`), corrected before it ever reached the simulator.

## Full regression: zero net impact after the five predicted, understood, and fixed migrations

**RTL**: `run_veda_smoke_test.sh` — **23/23 passed** (22 prior tests + `veda_smoke_m13_neg`), zero regressions, including the base RV64I core's own unmodified 81-instruction smoke test. (An intermediate run with the RTL logic change applied but the five tests not yet migrated showed exactly the five predicted failures — 17/22 — confirming the risk analysis before the fix, not after.)

**Sail**: `run_veda_selfcheck_tests.sh` — **22/22 passed** (21 prior tests + `vc_bind_notfound_neg`), zero regressions.

## Not yet built

`OSpecialRW`'s own privilege-only gating, `ODT-Destroy`'s own owner-hart gating, real physical multi-hart RTL, and a real `PCC` register with fetch-time capability enforcement all remain exactly as named in `MILESTONE_12_RESULTS.md`'s own "Not yet built" section — none of them were touched or affected by this milestone.
