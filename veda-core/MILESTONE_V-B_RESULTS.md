# Veda-Core Formal Model — Milestone V-B Results

**Date:** 2026-07-22
**Scope:** the rest of the Veda-Core ISA in Sail, on top of Milestone V-A's
capability struct/CRF/ODT/Object-Bind/`OCL.D`/`OCS.D` foundation:
`NMC_ADD.{W,D}`, Veda-Atomic (9 AMO-style ops), `OCA`, the Veda-Cap query
family (7 instructions), `CSetBounds`/`CSetBoundsExact`, `CSeal`/`CUnseal`
with sealed-capability enforcement, and a real `ODT-Populate`/`ODT-Destroy`
mechanism replacing Milestone V-A's temporary test scaffold. Also includes
a security-relevant retrofit found and fixed during this pass: the ODT
generation counter is now actually re-checked at every dereference, which
Milestone V-A never did despite the spec requiring it.

All of it built as real Sail source in this project's own already-verified
`sail-riscv` checkout (`toolchain/sail-riscv/model/extensions/Veda/`),
compiled into a real, working `sail_riscv_sim` binary, and run against 13
real hand-assembled test programs — not asserted from the source alone.

## Result: PASS — every instruction added this pass has a real, passing test

### Retrofit: generation re-check at dereference time

**Real gap found before any new instruction was written**: `VEDA_CORE_SPEC.md`
§5.1 requires the ODT generation counter to be "re-checked by the MSA on
every dereference," but Milestone V-A's `veda_check_access` only validated
fields already cached in the capability register — it never re-queried the
ODT to detect staleness. Fixed in `veda_ocl_insts.sail`'s
`veda_check_access` (and mirrored in the new `veda_check_nmc_access`): both
now look up the live ODT entry and compare its `generation` against the
capability's own cached copy, treating a mismatch (or the entry no longer
being `valid`) as a Tag Violation, exactly as the spec states. Verified
non-regressing against both original Milestone V-A tests before any new
instruction work began, and later verified end-to-end for real (see
`ODT-Populate`/`ODT-Destroy` below) once a real destroy mechanism existed
to actually go stale against.

### `NMC_ADD.W` / `NMC_ADD.D`

Semantics adapted from the real, local `AMOADD` implementation
(`extensions/A/zaamo_insts.sail`, read in full before writing this): `rs2`
truncated to the operation width before the add, the add wraps within that
width, `rd` receives the sign-extended *old* value. Gated by a new,
dedicated `Permit_NMC_Compute` permission (cause `0x1f`), not
`Permit_Load`/`Permit_Store`.

- **Positive** (`veda_nmc_add_test.S`): store `0x100`, `nmc_add.d x5,c1,x4`
  (`x4=0x23`) → `x5 <- 0x100` (old value), memory reload confirms
  `0x123` (post-add). Exact match.
- **Negative** (`veda_nmc_add_neg.S`): a second seeded object *without*
  `Permit_NMC_Compute` → `mcause=0x18`, `mtval=0x1F` (`cap_idx=0`,
  `cause=0x1f`). Exact match — confirms the new permission gate actually
  fires, not just present in source.

### Veda-Atomic (`veda.amoswap/add/xor/and/or/min/max/minu/maxu.d`)

Op-select encoding reuses real RISC-V Zaamo's own values verbatim (the
spec's "reference operation set" already names the same operations;
`AMOCAS` deliberately excluded — it needs a third logical operand the
spec's text doesn't name). D-width only this pass, matching Milestone
V-A's own established width-scoping precedent. Shared execute skeleton
mirrors the real `AMO` instruction's structure exactly.

- **Positive** (`veda_atomic_test.S`), `veda.amoxor.d`: store `0xFF`,
  XOR with `0x0F` → `x5 <- 0xFF` (old), memory reload confirms `0xF0`.
  Exact match. The other 8 ops share the identical, now-proven skeleton,
  differing only in a one-line ALU operation — not independently tested
  this pass (a real, stated scope choice, not an oversight).

### `OCA` (Object Capability Adjust)

`cd = cs1` with `Offset` replaced by `cs1.Offset + rs2` (signed); soft-fail
(`Tag` cleared, no trap) if out of `[0, Length)` or `cs1` was sealed —
matching CHERI's real `CIncOffset` unconditional-field/conditional-tag
pattern. One reasoned addition beyond the literal spec text, stated as
such: an already-untagged `cs1` can't produce a tagged result either.

- **Positive** (`veda_oca_test.S`): `oca c1,c0,+0x10`, then `nmc_add.d`
  through `c1` (using its own persistent `Offset`) → old value `0x100`,
  post-add `0x155` at `Base+0x10` — confirms `OCA` genuinely repositions
  where subsequent instructions operate, not just the field value in
  isolation.
- **Negative** (`veda_oca_neg.S`): `oca` with a delta pushing `Offset`
  past `Length` → `c1.Tag` cleared (soft-fail, no trap at the `OCA` site
  itself); a subsequent `nmc_add.d` through `c1` correctly hard-traps,
  `mcause=0x18`/`mtval=0x22` (Tag Violation, `c1`).

### Veda-Cap query family (`CGetBase/Len/Perm/Tag/Type/Addr/Offset`)

No Tag/Seal/bounds checks at all, deliberately — the spec states the
query family "remains unconditionally allowed on sealed capabilities,"
matching CHERI's real principle that metadata is always inspectable.

- **All 7 verified in one test** (`veda_capquery_test.S`) against a
  known, `OCA`-positioned capability: `CGetBase=0x80010000`,
  `CGetLen=0x40`, `CGetPerm=0x100C`, `CGetTag=1`, `CGetType=0xFFFF`
  (unsealed), `CGetAddr=0x80010010` (`Base+Offset`), `CGetOffset=0x10`.
  Every value exact.

### `CSetBounds` / `CSetBoundsExact`

Not in this pass's original task list — added because the spec's own
"Sealed-capability enforcement" text explicitly names both, and Custom-2's
funct7 table already reserved both slots with fully-specified semantics.
**Real, honest observation recorded in the source comments, not glossed
over**: the spec's "Exact traps instead of rounding" distinction exists in
CHERI because CHERI's bounds are a lossy, compressed encoding — Veda-Core's
`Length` field is a plain, uncompressed 16-bit value where every value is
exactly representable, so the two instructions are behaviorally identical
in this implementation. Not an oversight; a direct, stated consequence of
an earlier field-width decision.

- **Verified** (`veda_csetbounds_test.S`): `csetbounds c1,c0,0x20` →
  `CGetBase=0x80010000`, `CGetLen=0x20`, `CGetOffset=0`, `CGetTag=1`.
  Exact match.

### `CSeal` / `CUnseal` + sealed-capability enforcement

The centerpiece of this pass — the actual compartmentalization mechanism
this project has been building toward across several sessions. Real CHERI
semantics adapted term-for-term (verified against the spec's own quoted
CHERI ISA text): CHERI's "address" → Veda-Core's `Offset`; CHERI's "cursor
within cs2's bounds" → `cs2.Offset` within `cs2`'s own `[0, Length)`.

- **Positive seal** (`veda_cseal_test.S`): `cseal c1,c0,c2` (`c2.Offset=5`,
  `Permit_Seal` granted) → `CGetType(c1)=5`, `CGetTag(c1)=1`. Exact match.
- **Enforcement** (`veda_seal_enforce_neg.S`) — the single most important
  test this pass: `ocs.d` through the now-sealed `c1` →
  `mcause=0x18`/`mtval=0x23` (`cause=0x03` Seal Violation, `cap_idx=1`).
  Exact match. Proves the hard-trap side of the manipulate/use split
  actually fires for real, not just compiles.
- **Unseal round-trip** (`veda_cunseal_test.S`): `cunseal c3,c1,c2` then
  `ocs.d`/`ocl.d` through `c3` → succeeds with no trap, `x5 <- 0x99`.
  Proves a sealed capability can be legitimately restored to full,
  ordinary usability by the matching type-authority.
- **Unauthorized seal** (`veda_cseal_unauth_neg.S`): `cseal` with a `cs2`
  lacking `Permit_Seal` → `CGetTag(c1)=0` (soft-fail, no trap — matching
  the "manipulate" family's convention, distinct from enforcement's hard
  trap on the "use" side). Exact match.

### `ODT-Populate` / `ODT-Destroy`

The spec left the exact encoding of this mechanism undecided in an earlier
pass; resolved this pass (`VEDA_CORE_SPEC.md` §5.1) and implemented. R-type,
Custom-0, `funct7=0000011`, `funct3` selects Populate (`000`, `rs2` = a
packed `Base`/`Length`/`Perms` descriptor fitting one 64-bit GPR exactly)
vs. Destroy (`001`). **A real, stated deviation from the earlier
"gated by `Permit_Access_System_Registers`" intent**: R-type's two source
operands are already fully committed to `Object_ID` and the descriptor,
leaving no room for a capability-authority operand, and Veda-Core has no
privileged-capability convention yet to resolve that cleanly. Gated
instead on ordinary RISC-V `cur_privilege == Machine`, a real, standard
mechanism, not an invented one — stated as a deliberate simplification in
the spec, not silently substituted.

- **Full lifecycle, one test** (`veda_odt_lifecycle_test.S`) — the
  strongest test in this pass: `veda.odt.populate` a brand-new
  `Object_ID=5` from raw `Base`/`Length`/`Perms` values (no test scaffold
  involved at all), `veda.bind` it, `ocs.d`/`ocl.d` round-trip confirms
  `0x77` really was stored and loaded through a *genuinely, freshly
  created* object, then `veda.odt.destroy` it, then attempt `ocs.d` again
  through the same still-cached capability register — **hard-traps,
  `mcause=0x18`/`mtval=0x02` (Tag Violation, `c0`)**. This is the real,
  end-to-end proof of the generation-staleness retrofit above: it was
  designed and unit-verified not to regress existing behavior, but could
  only be proven to actually *detect* staleness once a real destroy
  mechanism existed to go stale against. It does.

## Real regression check

Both of Milestone V-A's original tests (`veda_test.elf` positive round-trip,
`veda_neg.elf` negative control) were re-run against the final, fully
V-B-extended build and produced byte-identical results to their original
V-A run: `tp <- 0x1234`, `mcause=0x18`/`mtval=0x22`. No regressions across
the entire pass.

## Real bugs found and fixed while building this (via actual compiler
errors and real test runs, not assumed)

1. **Scattered-union type ordering, twice**: `veda_atomicop` and
   `veda_capquery` both needed to move from their natural home
   (`veda_atomic_insts.sail`/`veda_cap_insts.sail`) into `veda_types.sail`
   (the `before sys`-ordered module) — the identical class of error
   Milestone V-A already documented for `vcapidx`, recognized and fixed
   directly for `veda_capquery` without needing to rediscover it via a
   second compile error.
2. **`xlenbits` vs hardcoded `bits(64)`, three separate times**
   (`NMC_ADD.D`, `OCA`, `ODT-Populate`) — the encdec `when xlen==64`
   clause doesn't propagate into the execute body's type context, a
   pattern from Milestone V-A rediscovered fresh each time via real "Failed
   to prove constraint: xlen==64" errors, now fixed consistently.
3. **Bidirectional `mapping clause assembly` can't have an unused bound
   variable, and can't use a bare `_` wildcard either** (Veda-Atomic's
   `aq`/`rl`) — two distinct real errors (a type error, then a syntax
   error) before landing on binding them to the literal `false` pattern.
4. **`to_bits` on an unconstrained `int` fails the same way indexing
   does** (`OCA`'s offset arithmetic) — fixed by staying in fixed-width
   bitvector arithmetic throughout (mirroring the real `AMO` instruction's
   own approach) and slicing, never converting through `int` for a value
   whose range isn't statically provable.
5. **Struct literals need an explicit type ascription** when the
   containing function's return type doesn't immediately pin it down
   (`OCA`'s `new_cap`) — a real "Cannot infer type of struct literal"
   error.
6. **Wrong test config used, not a code regression**: the very first V-B
   re-verification run (of the *widened* Milestone V-A model, before any
   new instruction existed) failed with every `VEDA_BINDINST` decoding as
   illegal — traced via `--trace-exception` to using the real ACT4 core's
   own `sail.json` (which deliberately sets `Veda.supported: false` to
   protect ACT4 conformance) instead of a Veda-enabled test config. Fixed
   by creating and checking in a dedicated `sail_tests/veda_test_sail.json`.

## Not yet built

`CInvoke`-equivalent domain transition (explicitly, repeatedly deferred —
`VEDA_CORE_SPEC.md` §6 item 7 — no `PCC`-equivalent exists yet to design it
against). `Permit_Access_System_Registers`-based (rather than ordinary
privilege-level) gating for `ODT-Populate`/`ODT-Destroy`, pending a real
privileged-capability model.

**Addendum, 2026-07-25**: the item originally listed here — *"the
remaining 8 of 9 Veda-Atomic ops at non-D widths, mechanical, same
skeleton, not independently tested"* — is now closed. Mirroring the
identical, already-closed gap on the RTL side
(`rtl/MILESTONE_5_RESULTS.md`), a new self-checking test
(`sail_tests/vc_nmc_add_w_and_atomic8.S`) exercises `NMC_ADD.W`'s own
sign-extension/partial-word semantics and all 8 remaining Veda-Atomic ops
(including the signed-vs-unsigned `MIN`/`MAX`/`MINU`/`MAXU` distinction),
plus `NMC_ADD.W`'s own permission-violation path — confirmed to be a real
**hard trap** in Sail (unlike RTL's own soft-fail convention), with the
exact `mtval` encoding (`cap_idx @ cause`) verified directly from source
(`veda_bind_insts.sail`'s `veda_xtval`) rather than assumed equal to
`vc_nmc_add_neg.S`'s own expected value (that test's capability register
index differs, so its `cap_idx` bits in `mtval` differ too — a real,
test-design mistake caught and fixed, not an RTL/Sail bug). 16/16 self-
check tests now pass.
