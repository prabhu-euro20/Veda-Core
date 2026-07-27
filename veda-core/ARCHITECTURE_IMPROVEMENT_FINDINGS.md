# Real Architecture Improvement Findings — Empirically Verified, Not Theoretical

**Date:** 2026-07-27
**Scope:** genuine "problem solver" pass over Veda-Core's own real RTL,
looking for improvement opportunities not already named in this project's
own planning docs. Every finding below was built as a real test program
and run against the actual, unmodified, committed `veda_core.tlv` — two
of the four items found are real, previously-undocumented security bugs,
not just optimization ideas.

## Finding 1 (real bug, CONFIRMED, **now FIXED — RTL Milestone 15**): ODT index aliasing silently corrupts unrelated objects

The RTL's 256-entry ODT indexes on only the low 8 bits of the real 23-bit
`Object_ID` field — documented as a "stated scope boundary," but its
**security consequence was never analyzed anywhere in this project**.

**Empirical proof**: populated `Object_ID=100` (object A) and bound `c0`
to it (correctly reads `0xAAAA...`). Then populated `Object_ID=356`
(`100 + 256`, same low byte) as an entirely different object B, at a
different real memory location. A **fresh** `Bind` for `Object_ID=100`
issued *after* this — which should still resolve to object A — instead
silently resolved to object B (`c1` read back `0xBBBB...`, not
`0xAAAA...`). Two logically distinct, differently-owned objects alias to
one physical slot and **silently overwrite each other's metadata**, with
no trap, no error, no signal to either party.

**Real-world consequence**: any two unrelated Object_IDs that share the
same low 8 bits (1-in-256 chance for any given pair, guaranteed for
enough concurrent objects) can silently corrupt each other's bounds,
permissions, and owner — a real, exploitable-in-principle confused
-deputy/corruption primitive, not just a capacity limit.

**Fixed — RTL Milestone 15** (`MILESTONE_15_RESULTS.md`): the cheaper
interim fix was implemented and verified, not just proposed. Bytes
`+11`/`+12` of the 16-byte ODT entry (real, allocated-but-unused space)
now store the real Object_ID's upper 15 bits, compared on every lookup;
a mismatch reads as "not found" instead of silently proceeding. Verified
via a real negative reproduction (now hard-traps, `cause=0x05`), a real
positive control (non-aliasing IDs and legitimate same-ID re-populates
still work), the full 23-test Veda-Core milestone suite (23/23, zero
regressions), and the full ACT4 suite (51/51, zero regressions). Widening
`ODT_ENTRIES` itself toward the spec's own 23-bit design point remains a
real, larger, unstarted hardware-cost tradeoff, not needed to close this
specific finding.

## Finding 2 (real bug, CONFIRMED, **now FIXED — RTL Milestone 16**): 8-bit generation counter wraps into a real use-after-free false negative

**Empirical proof**: bound `c0` to a fresh object (generation=0 at bind
time, cached in `c0`'s own `Reserved` field). Then issued `ODT-Destroy`
on the same `Object_ID` **256 times in a loop** (each call unconditionally
bumps generation by 1, verified against the real RTL write equation) —
wrapping the 8-bit counter exactly back to 0 — then re-populated the same
slot with an entirely different object B. The stale `c0`, never re-bound
since the very first bind, was used directly: **the staleness check
incorrectly passed** (generation matched post-wrap, and the slot was
valid again), and `c0` successfully read the original object A's memory
(`0xAAAA...`) through a capability that should have been invalid since
the very first `Destroy`, 256 identity-changes ago.

**Real-world consequence**: this is a textbook ABA-problem use-after-free
false negative — a real, well-known vulnerability class in any
generation/tag-counter safety scheme with a narrow field, now
concretely demonstrated on this architecture's own real RTL, not just
asserted as a theoretical risk from the field width alone.

**Fixed — RTL Milestone 16** (`MILESTONE_16_RESULTS.md`): the "cannot
re-populate" direction was implemented and verified, not just proposed.
Saturating the counter at `0xFF` alone was reasoned through and found
insufficient (it would make every future incarnation of the slot
permanently indistinguishable, not just periodically); the real fix
permanently retires a slot once its generation would wrap, using 1 more
bit of the same real, allocated-but-unused ODT-entry space. Verified via
a real negative reproduction (the exact 256-destroy scenario now
hard-traps instead of silently succeeding), a real positive control (five
real destroy/re-populate cycles, far under the 255-reuse threshold, still
work normally), the full 27-test Veda-Core milestone suite (27/27, zero
regressions), and the full ACT4 suite (51/51, zero regressions). Honest
real cost: any single `Object_ID` can now only be destroyed-and
-repopulated 255 times before permanent retirement — widening the
generation field itself (a larger change, since `Reserved` is also part
of the capability register struct, not just the ODT entry) would remove
this limit but was not attempted.

**Also mirrored into the Sail formal model** (`MILESTONE_16_RESULTS.md`'s
own update): a deliberate divergence from real CHERI-D precedent
(arXiv 2606.19055), reasoned through explicitly rather than silently
copied — CHERI-D accepts wraparound as a statistically-rare risk,
Veda-Core's own security-first priority plus a real demonstrated exploit
justified closing it instead. 26/26 Sail self-check tests pass (24
pre-existing + 2 new: `vc_gen_retire_neg.S`, `vc_gen_retire.S`).

## Finding 3 (real, measured, modest): `OCL.C`/`OCS.C` capability spill/restore is cheaper than a fresh `Bind`, but only modestly on the current core

Hypothesis from combining Milestone 7 (`OCL.C`/`OCS.C`, already built)
with this session's own register-pressure study: could spilling/restoring
a capability via capability-width memory access beat a fresh `Bind`'s ODT
walk under register pressure? Measured directly: a real permission gap
was found first (`OCS.C`/`OCL.C` require the *ordinary* `PERM_STORE`
/`PERM_LOAD` bits *in addition to* the capability-specific ones — found
via a real `PERM_STORE_VIOLATION` trap, cause `0x13`, not assumed).
Once corrected, 20 `OCL.C` restores cost **3 instructions/iteration**
versus 20 fresh `Bind`s at **4 instructions/iteration** — a real, but
modest, ~25% saving, entirely because `OCL.C` doesn't need a separate
`Object_ID` reload instruction.

**Honest limit**: on the *current* RTL, the ODT walk itself costs zero
extra simulated cycles (no DRAM latency modeled, per
`DRAM_TCM_LATENCY_STUDY.md`), so this saving is purely instruction-count,
not latency-avoidance. **The real payoff would be much larger once
combined with that same DRAM-latency model** — `OCL.C` restore would
skip the ODT walk (and its `E`-cycle DRAM-tier cost) entirely, while a
fresh `Bind` would still pay it every time. This is a concrete, testable
follow-up, not yet done.

## Items identified but not completed this pass — honest status

- **Fused `veda.odt.populate`+`veda.bind` — investigated, and the real
  finding changes the recommendation**: before designing new hardware,
  checked whether the "wasted" instruction was even a hardware problem.
  It wasn't, for one of the two: `VEDA_ODT_POPULATE` only ever *reads*
  `rs1`(Object_ID)/`rs2`(descriptor) and *writes* `rd` (zeroed) — it never
  touches `rs1` as a destination. Every test program this entire session
  reloaded `x1` with the same Object_ID a second time before `Bind`
  anyway, out of habit, not necessity. Skipping that reload and reusing
  the still-live register was tested directly on the real, unmodified
  core: **93 cycles instead of 94 at N=16, 18 instead of 19 at N=1** — a
  real, verified, zero-hardware-risk 1-cycle saving, updating the earlier
  benchmark's own formula from `veda_cycles = 14+5N` to `13+5N`.
  **Decision on the remaining, genuinely-fused hardware approach**: not
  pursued further. The two real instructions left after this fix
  (`Populate`, `Bind`) are not accidental redundancy — they are
  conceptually separate operations (create vs. claim) this project's own
  `Rebind`/`Bind-NoTrap` mode split and owner-hart tracking already
  depend on staying distinct. A true single-cycle fusion would need to
  merge two independent, already-complex, security-critical write paths
  (the ODT write-mux and the 16-register capability-file write-mux) into
  one — real, meaningfully higher risk for a saving of exactly one more
  instruction, and moot in practice until a real compiler exists to
  target either form automatically. The zero-risk register-reuse fix is
  the real, immediately-usable win from this line of inquiry.
- **Energy/toggle proxy — now done** (`ENERGY_TOGGLE_ACTIVITY_STUDY.md`):
  real VCD-based toggle-activity comparison (Yosys itself has no real
  power-estimation flow without a PDK, so a real RTL-simulation toggle
  count was used instead — a real, standard, if coarse, dynamic-power
  proxy). Real result: Veda-Core's per-cycle activity is ~20% higher
  than traditional's, explained by real, structurally-unconditional
  checks (Milestone 14's own `$veda_pcc_violation`) — but per-signal,
  per-cycle toggle *rate* is comparable once extra hardware and extra
  cycles are both normalized out, meaning the extra circuitry isn't
  unusually hyperactive, it's just real, additional hardware that exists.
- **Real 2-hart RTL**: the owner-hart security mechanism (Milestone 12)
  has only ever been validated via direct ODT-state injection standing in
  for a second hart — never a real one. A real minimal 2-hart testbed is
  a large, genuine undertaking, not attempted this pass.
- **Sail formal-verification export — now done** (`SAIL_COQ_EXPORT_RESULTS.md`):
  a real, already-installed OPAM Sail toolchain was found in this
  project's own `toolchain/opam-root/` (missed by the first search).
  Used it to run Sail's own official Coq/Rocq export target, producing
  real `.v` files (118,761 lines total) with the exact Milestone 15/16
  fix logic verified present and correctly translated, not just "the
  build didn't error." Honest limit: this proves the model translates to
  valid Coq syntax, not that anything is formally proven — `coqc` itself
  is not installed, a further, larger, not-yet-made decision.

## Reproducing this

`/tmp/claude-.../scratchpad/improvements/` (session-scoped, not
committed): `odt_alias.S`, `gen_wraparound.S`, `spill_restore.S`,
`fresh_bind_repeat.S`, `build_and_run.sh` (builds the real, unmodified
`veda_core.tlv` once, runs any named program against it).
