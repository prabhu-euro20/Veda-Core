# Veda-Core RTL — Milestone 6 Results

**Date:** 2026-07-23
**Scope:** `CSeal`/`CUnseal` — real, working RTL for the first time (no
decode, ALU logic, or write-back existed for these before this milestone,
unlike Milestone 5's already-built-but-untested gap). The first RTL
instructions with a *second capability-register* operand (`cs2`, the
type-authority), a genuinely new operand pattern not used by any earlier
instruction in this file. Also the first real test that can ever create a
sealed capability — which activates `$veda_sealed`'s own enforcement in
`OCL`/`OCS`/`NMC_ADD`/Veda-Atomic (wired into every one of their violation
checks since Milestone 1, but structurally dead code until now, since
`otype` could never be anything but `0xFFFF` before `CSeal` existed).

## Ground truth used, not re-derived

Implemented by re-reading `veda_cap_insts.sail`'s own `VEDA_CSEAL`/
`VEDA_CUNSEAL` (already real, working, verified Sail) directly before
writing any RTL, not re-derived from the CHERI spec summary in
`VEDA_CORE_SPEC.md`. Confirmed exact bit positions from `veda_types.sail`:
`PERM_SEAL = 8`, `PERM_UNSEAL = 9` (consistent with this RTL's own already-
established `Perms[2]`=Load/`Perms[3]`=Store/`Perms[12]`=NMC_Compute
convention). `VEDA_CORE_SPEC.md` Section 1's own encoding decision (Custom-2,
`funct7=0010000`/`0010001`, `funct3=001`, a direct field-for-field match to
CHERI-RISC-V's real `CSeal`/`CUnseal` shape) was already settled — used
as-is.

## What was built

1. **Decode**: `$is_veda_cseal`/`$is_veda_cunseal` (`funct7=0010000`/
   `0010001`, same Custom-2/`funct3=001` "dest is a Capability Register"
   convention as `OCA`/`CSetBounds`). `$veda_cseal_cunseal_rs2_cap[3:0] =
   $instr[23:20]` — the new capability-typed `rs2` field.
2. **Authorization checks**, mirroring Sail exactly:
   - `CSeal`: `cs2.Tag && !sealed(cs2) && cs2.Perms[8] && (cs2.Offset <
     cs2.Length) && (cs2.Offset != 0xFFFF)`, further gated on `cs1.Tag &&
     !sealed(cs1)`.
   - `CUnseal`: `cs2.Tag && !sealed(cs2) && cs2.Perms[9] && sealed(cs1) &&
     (cs2.Offset == cs1.otype) && (cs2.Offset < cs2.Length)`, further gated
     on `cs1.Tag`.
3. **`/vreg` write-back**: a 4th/5th independent write source
   (`$cseal_wr_en`/`$cunseal_wr_en`), reusing the exact "copy every field
   from `cs1`, override one field" skeleton already proven correct for
   `OCA` (Milestone 2, after its own real field-copy bug) and `CSetBounds`
   (Milestone 3) — here the one overridden field is `otype` (`cs2.Offset`
   for `CSeal`, `0xFFFF` for `CUnseal`); everything else (`Object_ID`,
   `Base`, `Length`, `Offset`, `Perms`, `Reserved`) copies from `cs1`
   unchanged, exactly matching `veda_cap_insts.sail`'s own struct literal.
4. **No new sealed-capability enforcement RTL was needed** — `$veda_sealed
   = (otype != 0xFFFF)` and its use in `$veda_ocl_violation`/
   `$veda_ocs_violation`/`$veda_nmc_add_*_violation`/`$veda_atomic_violation`
   already existed, unmodified since Milestone 1. This milestone is the
   first time that code path can actually be exercised with a real, live
   sealed capability.

## Result: PASS — clean first-pass build, no bugs found

Like Milestone 4 (and unlike Milestones 2/3/5), the first real simulation
run of the complete positive+negative test passed outright. The design
surface was smaller than it might first appear: both new instructions
reuse an already-verified write skeleton, and the "use" side of sealed-
capability enforcement was already real, tested-elsewhere logic
(`$veda_sealed`) — only its *trigger condition* was new.

### Test (`sim/veda_smoke_m6.S`, `tb_veda_smoke_m6.sv`)

Ties together Milestone 4's `ODT-Populate` to mint a real type-authority
capability: neither reset-seeded object (`Object_ID=1`/`2`) carries
`Permit_Seal`/`Permit_Unseal`, so a fresh `Object_ID=10` is populated with
`Perms=0x0300` (both bits) via the already-verified `ODT-Populate` — real,
previously-verified RTL used to build this test's own fixture, not a
shortcut around it.

Full lifecycle, all values matched exactly on the first run:
1. `c0` = `Bind(Object_ID=1)` — the "data" capability to be sealed
   (`Perms=0x100C`, deliberately *without* `Permit_Seal`/`Unseal`).
2. `c2` = `Bind(Object_ID=10)` — the type-authority (`Perms=0x0300`,
   `Offset=0` by bind default — `0` is a valid `otype` value).
3. `cseal c1, c0, c2` → `c1.Tag=1`, `c1.otype=0` (`= c2.Offset`),
   `c1.Base=0x80010000`/`c1.Perms=0x100C` (confirmed via the query family —
   a full field copy from `c0`, not just the overridden `otype`).
4. **Sealed-use blocked**: `ocl.d c1, ...` into a register pre-loaded with
   sentinel `0xDEAD` — the register stays `0xDEAD`, confirming
   `$veda_sealed`'s pre-existing check genuinely fires for the first time.
5. `cunseal c3, c1, c2` (same authority, `c2.Offset(0) == c1.otype(0)`) →
   `c3.Tag=1`.
6. **Unsealed-use works again**: a real `OCS.D`/`OCL.D` round trip through
   `c3` — `0xABCD1234ABCD5678` written and read back exactly, closing the
   full seal → blocked → unseal → usable-again lifecycle end to end.
7. **Negative 1** (missing `Permit_Seal`): `cseal c5, c0, c0` (using `c0`,
   which lacks bit 8, as its own bogus type-authority) → `c5.Tag=0`.
8. **Negative 2** (mismatched type-authority): a second binding of
   `Object_ID=10` (`c4`) repositioned via `OCA` to `Offset=5` (`!=
   c1.otype=0`, but still `< Length=0x40`, isolating the type-mismatch
   condition from a bounds condition) — `cunseal c6, c1, c4` → `c6.Tag=0`.

### Full regression: zero impact

All of Milestones 1–5's own tests (10 positive/negative programs) and the
base RV64I core's own unmodified 81-instruction smoke test were re-run
against the final build — **12 real test programs through one script**
(`run_veda_smoke_test.sh`), zero regressions.

## Design notes worth recording

- **`cs1` is read-only in both instructions** — `CSeal`/`CUnseal` write only
  `cd`, never `cs1`. The test exploits this directly: `c1` (sealed via step
  3) is reused unmodified for negative test 2, five instructions after it
  was first produced, since nothing in between could have altered it.
- **A genuinely new operand-decode pattern, but a zero-cost one for the
  write-back path**: `cs2` needed its own fresh `/vreg` read (no existing
  signal could be reused, unlike `cs1` which reuses the same
  `$veda_ocl_ocs_rs1_cap`-derived `$veda_rs1cap_*` signals every other
  Custom-2 instruction already shares) — but once read, `cs2`'s fields feed
  only the authorization booleans and the one `otype` override, so the
  `/vreg` write mux itself needed no structural change beyond two more
  ternary arms per field, the same shape as adding `OCA`/`CSetBounds` before
  it.
- **This closes `VEDA_CORE_SPEC.md`'s own item 4** ("Sealing/Unsealing")
  for the RTL layer specifically — Sail already had this since Milestone
  V-B; RTL now has real parity.

## Not yet built

Real trap/exception infrastructure (sealed-`rs1`-on-a-"use"-instruction
still soft-fails/suppresses-write here, not the hard trap `cause=0x03`
Sail's own model implements — the same honest, stated floor as every other
RTL milestone), `Rebind` (Object-Bind's own seal-check for `Rebind`
targeting an already-sealed register is Sail-only, since RTL doesn't
implement `Rebind` mode at all yet), and any privilege-raising or
`CInvoke`-equivalent domain-transition mechanism (explicitly out of scope
per `VEDA_CORE_SPEC.md` Section 6 item 7). With `CSeal`/`CUnseal` now real
in RTL, every Milestone V-B Sail instruction family has RTL parity except
`Rebind`/`Bind-NoTrap` (Object-Bind mode variants) and real trap delivery.
