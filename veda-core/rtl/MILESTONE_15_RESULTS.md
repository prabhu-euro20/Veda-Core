# Veda-Core RTL Milestone 15: ODT Full-Object_ID Verification (Real Bug Fix)

**Date:** 2026-07-27

## The real bug, found via empirical reproduction, not code review alone

The RTL's 256-entry ODT indexes on only the low 8 bits of the real 23-bit
`Object_ID` field — a real, previously-documented scope boundary
(`veda_core.tlv`'s own header comment, unchanged since Milestone 1). Its
security consequence had never been analyzed or tested anywhere in this
project until this milestone: any two Object_IDs that share a low byte
alias onto the same physical ODT slot and **silently overwrite each
other's metadata**, with no trap, no error, no signal to either party.

Reproduced directly: populated `Object_ID=100` (object A) and bound `c0`
to it (correctly read `0xAAAA...`). Then populated `Object_ID=356`
(`100+256`, same low byte) as an unrelated object B. A **fresh** `Bind`
for `Object_ID=100`, issued after this, silently resolved to object B's
data instead — proof the vulnerability is real, not theoretical
(`ARCHITECTURE_IMPROVEMENT_FINDINGS.md` Finding 1).

## The fix

Bytes `+11`/`+12` of the 16-byte ODT entry were real, allocated-but-
unused space (`veda_core.tlv`'s own header comment: "88 bits used of
128 available"). `ODT-Populate` now records the real Object_ID's upper 15
bits there; every lookup — both `Object-Bind`'s own ODT read and the
independent dereference-time generation re-check `OCL`/`OCS` use — now
requires this stored value to match the requested/cached Object_ID. A
mismatch folds into the existing `$veda_odt_valid`/`$veda_check_odt_valid`
signals, so every downstream consumer (`owner_ok`, `bind_notfound
_violation`, `rebind_ok`, `gen_stale`) inherits the fix with no other
change needed. A low-byte collision with a genuinely different Object_ID
now reads as "not found" (plain `Bind` hard-traps, `cause=0x05`) instead
of silently returning the wrong object's metadata.

## Verification

- **Negative test** (`veda_smoke_m15_neg.S`): reproduces the exact
  Object_ID=32/288 aliasing scenario; confirms the fix delivers a real
  hard trap (`mcause=0x18`, `mtval=0x25` — cause `0x05` object-not-found,
  `cap_idx=1` for the `c1` destination) instead of the old silent
  wrong-object read. **PASSED.**
- **Positive test** (`veda_smoke_m15.S`): confirms the fix rejects only
  real aliasing collisions, nothing else — two different, non-aliasing
  Object_IDs (30, 31) resolve independently and correctly, and a
  legitimate same-ID re-populate (30, new backing memory) is still
  honored. **PASSED.**
- **Full existing Veda-Core RTL milestone suite** (all 23 positive/
  negative smoke tests, Milestones 1-14): re-run against the fixed core.
  **23/23 passed, zero regressions.**
- **Full ACT4 RV64I conformance suite**: re-run against the fixed core.
  **51/51 passed, zero regressions.**

## What this does not fix — stated plainly

This closes Finding 1 only. Finding 2 (`ARCHITECTURE_IMPROVEMENT_
FINDINGS.md` — the 8-bit generation counter's own real ABA-problem
wraparound, independently reproduced and confirmed this same research
pass) is a **different, still-open** vulnerability: it involves the
*same* Object_ID being destroyed and re-populated many times, not two
different IDs colliding, so this milestone's full-Object_ID check does
not and cannot address it. **Correction, checked directly against the
real Sail source rather than assumed**: Finding 1 is RTL-only and always
was — `toolchain/sail-riscv`'s own `veda_regs.sail` declares `veda_odt :
vector(8388608, odt_entry)` and `odt_lookup` indexes it with the *full*
23-bit `object_id`, no truncation, ever. Sail's formal model never had
this bug; there is nothing to mirror for Finding 1. (An earlier draft of
this document incorrectly implied otherwise — corrected here, not left
stale.)
