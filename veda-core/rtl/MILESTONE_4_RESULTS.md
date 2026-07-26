# Veda-Core RTL — Milestone 4 Results

**Date:** 2026-07-23
**Scope:** the minimal, real privilege gate decided in `MILESTONE_PLAN.md`'s
Milestone 4 addendum (a 1-bit `$priv` register, reset to `1`, cleared
one-way by a new Custom-3 instruction `veda.droppriv`), and
`ODT-Populate`/`ODT-Destroy` gated on it — the two instructions this
project's own research (seL4/CHERI/Plessey precedent, CHERI's monotonicity
principle) established were the real, specific reason Milestones 1–3 could
safely defer all privilege architecture but this milestone could not.

## Why this milestone exists (not re-derived here, see the real record)

`MILESTONE_PLAN.md`'s Milestone 4 addendum has the full reasoning, written
*before* this code was built, in direct response to the user's own
architectural challenge ("why don't we still build privilege
infrastructure..."). Not reproduced here in full; this document covers only
what was actually built and how it was verified.

## What was built

1. **`$priv`** (`rtl/veda_core.tlv`, `|cpu @0`): `$priv = $reset ? 1'b1 :
   (>>1$is_veda_droppriv ? 1'b0 : >>1$priv);` — the identical simple
   stateful-signal idiom already used for `$cyc_cnt`, not a new one.
2. **`veda.droppriv`**: Custom-3 (`opcode=1111011`, explicitly "Reserved,
   unallocated" in this project's own ISA summary table since the first
   draft), `funct7=0000000`. Decoded as `$op_is_custom3 &&
   ($funct7==7'b0000000)` — deliberately ignoring `rs1`/`rs2`/`rd`/`funct3`
   entirely, since the instruction carries no operands (a pure state
   transition, mirroring the real "drop-privilege-and-never-return"
   pattern used in secure-boot flows).
3. **`ODT-Populate`/`ODT-Destroy`** (`VEDA_CORE_SPEC.md` §5.1's
   already-decided encoding: Custom-0, `funct7=0000011`, `funct3=000`/`001`)
   — real, working RTL for the first time. `rs1` = a GPR holding
   `Object_ID`; reuses the *exact same* address computation Object-Bind's
   own ODT lookup already performs (`$veda_odt_addr`/`$veda_odt_valid`/
   `$veda_odt_gen`/`$veda_odt_base`/`$veda_odt_length`/`$veda_odt_perms`),
   since both read `rs1` as `Object_ID` through the identical 8-bit-indexed
   256-entry scheme — not recomputed, reused directly. `rs2` (Populate
   only) = a packed descriptor (`Base[31:0]` in bits `[63:32]`,
   `Length[15:0]` in bits `[31:16]`, `Perms[15:0]` in bits `[15:0]`, per
   spec). Generation-bump logic mirrors Sail's own
   `VEDA_ODT_POPULATE`/`VEDA_ODT_DESTROY` field-for-field (a slot
   repopulated while still `valid` bumps generation too, not just
   Destroy — the ODT's real security property must hold regardless of
   *how* a slot's identity changed). `rd` = `0` on success.
4. **Gating**: `$veda_odt_populate_violation = $is_veda_odt_populate &&
   !$priv` / `$veda_odt_destroy_violation = $is_veda_odt_destroy && !$priv`
   — the identical violation-suppresses-write convention already used for
   every soft-fail in this file (`OCL`/`OCS`/`NMC_ADD`/Veda-Atomic), now
   closing the one real gap monotonicity alone couldn't cover: minting new
   capability-granting authority from raw values. A dropped-privilege
   attempt simply never writes `odt_mem[]` — the honest floor available
   without trap infrastructure, same real constraint documented for every
   earlier milestone.
5. **`odt_mem[]` write** — a new, real trailing `\SV always_ff` block
   (the array itself already existed since Milestone 1, read-only until
   now), following the identical pattern already proven for `elfmem[]`'s
   own OCS/NMC_ADD/Atomic write blocks.

## Result: PASS — clean first-pass build, no bugs found

Unlike Milestones 2 (`OCA`'s partial-field-copy bug) and 3 (the testbench
cycle-timing issue), this milestone's first real simulation run passed both
the positive and negative test outright — an honest result, not
undersold: this milestone's design surface was smaller and more thoroughly
reasoned through in `MILESTONE_PLAN.md` *before* any code was written
(a direct consequence of the user's own explicit request for "proper
thorough validation and verification" before deciding), and it reused two
already-verified mechanisms (the ODT address computation, the
violation-suppresses-write convention) rather than introducing new ones.

### Positive test (`sim/veda_smoke_m4.S`, `tb_veda_smoke_m4.sv`)

Full privileged lifecycle against a fresh `Object_ID=3` (never seeded at
reset — a real, first mint, not a pre-populated test fixture):

1. `veda.odt.populate` writes `Base=0x80010200`/`Length=0x40`/
   `Perms=0x100C` for `Object_ID=3`.
2. `veda.bind c0, x1` — `c0.Tag=1`, fields match the just-populated values
   exactly (confirmed via `cgetbase x7, c0` reading back `0x80010200`, not
   a stale/seeded value).
3. `ocs.d c0, x3, x4` then `ocl.d c0, x3, x6` — a real 64-bit value
   (`0x1234567890ABCDEF`) round-trips through the freshly-minted object.
4. `veda.odt.destroy x9, x1` — invalidates `Object_ID=3`, bumps generation.
5. `veda.bind c1, x1` against the same, now-destroyed `Object_ID` —
   `cgettag x10, c1` reads `0` (the ODT entry is genuinely gone, not just
   logically ignored).
6. `ocl.d c0, x3, x11` — `c0` was bound *before* the destroy, so its cached
   generation (`0`) no longer matches the ODT's bumped generation (`1`).
   The generation re-check (built into RTL since Milestone 1, only
   independently testable from this milestone on, exactly as
   `MILESTONE_PLAN.md` item 3 predicted) correctly rejects it — `x11`'s
   `0xDEAD` sentinel survives untouched.

All six checks passed on the first real run: `x6=0x1234567890ABCDEF`,
`x7=0x80010200`, `x10=0`, `x11=0xDEAD` (verified via register readback).
`odt_mem[Object_ID=3]`'s own final state, read directly from the real
simulation log (not asserted from memory): `base=0x80010200 valid=0
gen=1` — `valid=0` is the Destroy's own effect, correctly persisted (the
testbench's diagnostic `$display` samples final state, i.e. *after* both
the Populate and the later Destroy have run), and `gen=1` is exactly one
bump, from the one real Destroy that ran.

### Negative test (`sim/veda_smoke_m4_neg.S`, `tb_veda_smoke_m4_neg.sv`)

`veda.droppriv` first (`$priv: 1 -> 0`), then `veda.odt.populate` against a
never-before-seeded `Object_ID=5`. Verified two independent ways:

- **Directly**: `odt_mem[Object_ID=5][9][0]` (the `valid` byte) reads `0`
  — the write genuinely never happened, not merely that some downstream
  check also happened to fail.
- **Through the ISA itself** (Milestone 3's own established discipline —
  verify via a real subsequent instruction, not only internal signal
  introspection): `veda.bind c0, x1` against that same `Object_ID=5`
  correctly reads back `Tag=0` via `cgettag`, since no real ODT entry was
  ever created for it to bind against.

Per-cycle trace confirms the mechanism directly: `pop_viol=1` fires exactly
the one cycle `is_odt_pop=1` decodes, with `priv=0` throughout (droppriv's
own effect from cycle 1 onward).

### Full regression: zero impact

All of Milestones 1–3's own tests (5 positive/negative programs) and the
base RV64I core's own unmodified 81-instruction smoke test were re-run
against the final Milestone 4 build — **11 real test programs through one
script** (`run_veda_smoke_test.sh`), zero regressions.

## Design notes worth recording

- **Reuse, not duplication**: `ODT-Populate`/`ODT-Destroy`'s own ODT
  lookup needed no new address-computation signals at all — `rs1` as
  `Object_ID`, 8-bit-indexed into the same 256-entry `odt_mem[]`, is
  *exactly* what Object-Bind's own lookup already computes every cycle.
  The only genuinely new combinational logic this milestone needed was the
  generation-bump rule and the packed-descriptor field extraction.
- **`$priv` promoted to a top-level signal with zero extra work** — unlike
  `/vreg`'s `$offset` field in Milestone 1 (which needed a real *consumer*
  before SandPiper would hoist it), `$priv` is a plain `|cpu @0` scalar
  signal, the same class as `$pc`/`$instr`/`$cyc_cnt`, and was
  `CPU_priv_a0`-addressable in the testbench with no extra step.
- **Sail parity, stated honestly**: Sail's own `VEDA_ODT_POPULATE`/
  `VEDA_ODT_DESTROY` genuinely trap (`Illegal_Instruction()`) on
  `cur_privilege != Machine`, because Sail has real M/S/U privilege
  architecture. This RTL's `$priv` is a much smaller, honest floor — one
  bit, one direction, no trap — deliberately not presented as equivalent
  to Sail's mechanism, only as closing the same *specific* security gap
  (unauthorized minting) that mechanism closes, per `MILESTONE_PLAN.md`'s
  own explicit scope decision.

## Not yet built

`CSeal`/`CUnseal` and sealed-capability enforcement in RTL (deferred since
Milestone 3, independent of the privilege question — authorized by a
capability's own `Permit_Seal`/`Unseal` bit, not by `$priv`), `NMC_ADD.W`,
the remaining 8 Veda-Atomic ops, real trap/exception infrastructure, and
any privilege-*raising* mechanism (deliberately out of scope per the
Milestone 4 addendum's own "one-way, matching secure-boot's
drop-and-never-return pattern" decision). All real, deferred, later work.
