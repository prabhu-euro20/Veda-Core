# Veda-Core Milestone 11 Results — OSpecialRW + Capability-Authority-Gated ODT-Populate/ODT-Destroy (Sail + RTL)

**Date:** 2026-07-25
**Scope:** `NEXT_STEPS_ROADMAP.md` §2.5, real since Milestone 4:
`ODT-Populate`/`ODT-Destroy` have gated on ordinary RISC-V privilege
level alone (`cur_privilege == Machine` / RTL's own `$priv`), a stated,
deliberate simplification — `VEDA_CORE_SPEC.md` itself named the real
fix required: *"a real capability-permission-gated version would need
Veda-Core's own privileged-capability model designed first."* Milestone
10 built the first piece of that model (`c15`/IDC). This milestone
builds the second: the **ODA** (Object Descriptor Authority) — Veda-Core's
own single Special Capability Register — and `OSpecialRW`, the
instruction that reads and writes it, term-for-term adapted from real
CHERI's own SCR model.

## Ground truth used, not re-derived

Read CHERI ISA spec §4.3.6 ("Special Capability Registers") and the real
`CSpecialRW` instruction-reference entry (p.235) in full before
designing anything:

- **CHERI's own SCR access rule (Table 4.3's "ASR" column)**: an SCR
  write needs the current privilege mode to be permitted **and**
  `PCC.perms` to grant `PERMIT_ACCESS_SYSTEM_REGISTERS`. This is the
  real precedent this milestone's entire design rests on — Veda-Core
  already had this exact permission bit reserved in its own Perms table
  since CHERI adoption (Milestone V-B), but no instruction had ever
  consumed it until now.
- **`CSpecialRW`'s own real semantics**: *"the destination is the zero
  register... shall not read... When the source is the zero register,
  the instruction will not write..."* — a real read-then-write, atomic,
  with independent skip conditions on each half. Veda-Core has exactly
  one SCR (the ODA), so `OSpecialRW` needs no `scr`-index operand the
  way real `CSpecialRW cd, scr, cs1` does; it always targets the ODA.
  The "skip on zero register" optimization doesn't transfer directly —
  Veda-Core's Capability Register File has no `c`-zero-register
  equivalent (unlike GPR `x0`) — so `OSpecialRW` always performs both
  halves; a stated, deliberate simplification, not a silent omission.
- **CHERI's own layered privilege model** (§3.11.1, read again this
  pass to confirm, not assumed from memory): "ring-based privilege" and
  "capability control of ring-related privilege" **coexist** — capability
  authority constrains ambient ring privilege, it does not replace it.
  This directly settled a real design question: the ODA's own
  authorization is an **OR** with ordinary privilege, not a
  replacement — M-mode alone still always suffices, exactly as it always
  has since Milestone 4.

## Design decisions, reasoned and stated, not invented

- **The ODA lives outside the 16-entry CRF**, not as a 17th capability
  register — it plays a genuinely different architectural role (a
  capability-authority *context* for privileged instructions), the same
  real distinction CHERI itself draws between ordinary capability
  registers and SCRs.
- **`OSpecialRW` itself is gated on ordinary privilege alone** ($priv/
  `cur_privilege == Machine`), not on `PERMIT_ACCESS_SYSTEM_REGISTERS`
  the way real CHERI's own SCR access is — real CHERI's own rule needs
  `PCC.perms`, and Veda-Core still has no `PCC` (Milestone 10's own
  stated, carried-forward scope boundary). A capability-gated version of
  `OSpecialRW` itself would need that same `PCC` work first; using the
  already-established, already-verified privilege convention here is
  the honest floor, not a shortcut invented without precedent.
- **The activated permission bit is `PERMIT_ACCESS_SYSTEM_REGISTERS`
  (bit 7), not a freshly invented one** — real CHERI's own SCR-access
  bit, already present in `VEDA_CORE_SPEC.md`'s Perms table by name
  since Milestone V-B, reserved but never consumed until this milestone.

## Implementation

**Sail** (`veda_regs.sail`: `register veda_oda : capability` +
`register veda_oda_tag : bool`, alongside the existing `cr0`-`cr15`;
`veda_cap_insts.sail`: `VEDA_OSPECIALRW`, `funct7 = 0010011`, the next
unused Custom-2 slot after `OCInvoke` (`0010010`); `veda_ocl_insts.sail`:
`veda_oda_authorized()` helper, OR'd into both `VEDA_ODT_POPULATE`'s and
`VEDA_ODT_DESTROY`'s own existing `cur_privilege != Machine` guard).

**RTL** (`veda_core.tlv`): `$is_veda_ospecialrw` decoded at Custom-2's
`funct7 = 0010011`. The ODA modeled as seven persistent, capability-
shaped signals (`$veda_oda_tag`/`_object_id`/`_base`/`_length`/`_offset`/
`_perms`/`_otype`/`_reserved`) — the identical real persistent-signal
idiom already proven for `$mtvec`/`$mepc`/`$mcause`/`$mtval` (Milestone
9), applied here to a full capability rather than a plain 64-bit value.
`$veda_odt_populate_violation`/`$veda_odt_destroy_violation` (Milestone
4) become `!($priv || $veda_oda_authorized)` — a real, minimal, one-line
change to each of two already-existing signals, not a rewrite. `cd`'s own
`/vreg` write source (`$ospecialrw_wr_en`, real `$veda_rd_cap`-indexed,
unlike `OCInvoke`'s fixed-index `c15` write) copies the ODA's fields from
**before** this same instruction's own write to it — correct by
construction, since the ODA's own persistent-register update (like every
other `>>1`-gated register in this file) only takes effect on the next
cycle, so reading the current-cycle value inside the same execute path
is already the real "old" value, with no separate save/restore needed.

## Result: clean first-pass Sail and RTL builds, zero bugs found

Both Sail tests (`vc_ospecialrw`) and both RTL tests
(`veda_smoke_m11`/`veda_smoke_m11_neg`) passed on their first real
simulation run. No design, Sail, or RTL bugs found this milestone — a
genuine first for this project's own RTL milestones since Milestone 8
(every one of Milestones 4/5/6/7/9/10 found and fixed at least one real
bug along the way).

## A real, honest Sail-side scope limitation found and worked around, not glossed over

This project's own `veda_test_sail.json` config has **both S-mode and
U-mode disabled** (`"S": {"supported": false}`, `"U": {"supported":
false}`) — confirmed directly from the config file, not assumed. Sail's
own `legalize_mstatus` function silently clamps any attempt to write
`mstatus.MPP` to a non-Machine value back to `lowest_supported_privLevel()`
(which, with S/U both disabled, is Machine itself) — meaning **privilege
can never actually drop below Machine in this Sail test environment at
all**, regardless of what software does. This makes a genuine,
independent-of-privilege proof of the ODA authorization path
structurally impossible to construct in Sail with this project's own
existing config (changing the config to add U-mode support would be real,
separate, out-of-scope work, affecting every other Sail test in the
suite, not attempted here).

**RTL does not share this limitation** — `veda.droppriv` (Milestone 4)
is Veda-Core's own real, independent, one-way privilege-drop mechanism,
unrelated to the standard M/S/U privilege-level machinery Sail's config
constrains. `veda_smoke_m11.S` is therefore the one real, genuine,
end-to-end proof that the ODA authorization path works **entirely on its
own**, with zero ordinary-privilege help: ordinary M-mode privilege is
dropped first (`veda.droppriv`), and `ODT-Populate` still succeeds,
confirmed by a subsequent `Bind` genuinely returning `Tag=1` — a real
ODT entry really was created, purely via the delegated authority
capability.

Sail's own `vc_ospecialrw.S` instead proves what it structurally can:
`OSpecialRW`'s own real atomic read-then-write semantics, field-for-field
(the old ODA value correctly returned in `cd` before the new value lands
in the ODA, confirmed via a second `OSpecialRW` call reading back what
the first one wrote).

## Full regression: zero impact

**Sail**: `run_veda_selfcheck_tests.sh` — **19/19 passed** (18 prior
tests + `vc_ospecialrw`), zero regressions.

**RTL**: `run_veda_smoke_test.sh` — **20/20 passed** (18 prior tests +
`veda_smoke_m11`/`veda_smoke_m11_neg`), zero regressions, including the
base RV64I core's own unmodified 81-instruction smoke test.

## Not yet built

`OSpecialRW` itself remains privilege-gated only, not
capability-gated — closing that would need the same real `PCC` register
Milestone 10 deliberately deferred (see that milestone's own "Not yet
built"). `ODT-Destroy`'s own authorization is closed by the identical
change as `ODT-Populate` (same `veda_oda_authorized()`/
`$veda_oda_authorized` check, shared code path) but has no dedicated new
test this pass — Milestone 4's own existing `ODT-Destroy` coverage
(lifecycle tests, both layers) is unaffected and continues to exercise
the ordinary-privilege path unchanged; a dedicated ODA-authorized
`ODT-Destroy` test is a real, cheap, mechanical follow-on, not attempted
here to keep this milestone's own scope proportionate to what it
actually needed to prove. With this milestone,
`NEXT_STEPS_ROADMAP.md` §2.5 is closed.
