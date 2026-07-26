# Veda-Core RTL — Milestone 7 Results

**Date:** 2026-07-25
**Scope:** `OCL.C`/`OCS.C` — real, working RTL for the first time,
capability-width (128-bit), Tag-preserving memory access. This is the
Tier 1 item `NEXT_STEPS_ROADMAP.md` identified as the highest-leverage
next milestone: until now, a Veda-Core capability could not be stored to
memory and loaded back with its Tag intact, meaning no capability could
be placed in a data structure, passed through memory, or built into a
capability-based heap — the property that makes this a real capability
*system*, not a register-only demonstration.

## Ground truth used, not re-derived

Implemented in both Sail and RTL, in that order, using each layer's own
real, established precedent — not invented fresh in either:

- **Sail**: `core/mem_metadata.sail`'s own `mem_meta` hook, already
  identified as the real extension point in `FORMAL_VERIFICATION_PLAN.md`
  §2.2 (*"specifically for an extension to override with real
  per-location metadata"*) but never actually used until this milestone.
  Redefined from `unit` to `bool` (the Tag bit), with a real, bounded tag
  store (`veda_tag_store`, one bit per 16-byte granule, scoped to the same
  real ELF-loadable RAM region every other Veda-Core mechanism already
  uses) — mirroring real CHERI hardware's own physically-separate
  tagged-memory mechanism, not a per-address dictionary (Sail has no
  native sparse-map primitive, and no real hardware implements one
  unbounded either).
- **RTL**: a new `tag_mem[]` array, structurally identical to the
  already-proven `odt_mem[]`/`elfmem[]` pattern, and a new capability-typed
  `rd` operand for `OCL.C`/`OCS.C` — decided by direct, verified analogy
  to real CHERI's own `[C]LC`/`[C]SC` (already cited elsewhere in
  `VEDA_CORE_SPEC.md`), which target a capability register, not a GPR, for
  the same reason: a 128-bit capability plus Tag has no meaningful GPR
  representation.

## A genuine spec gap found and closed before writing any code

The OCL/OCS width table has named `funct3=100` "128-bit (capability
load/store)" since the very first draft, but no prior pass ever specified
what `rd` means for that width — every other width treats it as an
ordinary GPR. Closed this pass in `VEDA_CORE_SPEC.md`'s new "OCL.C/OCS.C
semantics" section: `rd` is reinterpreted, for this one width only, as a
4-bit Capability Register index — the same "one shared field position,
reinterpreted per encoding" idiom already used throughout this ISA, not a
new one invented for this case.

## Result: two real bugs found and fixed — one in the test, one in the RTL, kept honestly distinct

### Sail: clean first-pass build, no bugs found

The Sail implementation (`mem_metadata.sail`'s tag store, `veda_types.sail`'s
`veda_cap_pack`/`veda_cap_unpack`, `veda_ocl_insts.sail`'s `VEDA_OCL_C`/
`VEDA_OCS_C`) needed three real, mechanical Sail type-system fixes during
development — none were correctness bugs in the design:
1. Integer division (`byte_off / 16`) couldn't be statically proven
   non-negative by Sail's dependent-type checker — fixed using a bitvector
   right-shift (`>> 4`) instead, the same real technique real hardware
   would use for a fixed power-of-two granule size.
2. A vector-index bounds proof (`veda_tag_store[idx]`) didn't survive
   across an `Option` match arm — fixed with an explicit `assert` at the
   point of use.
3. A `Kind-Int` type-level constant (`veda_tagstore_granules`) isn't
   directly usable in value position — fixed using this codebase's own
   already-established `sizeof()` idiom (`core/xlen.sail`'s `let xlen =
   sizeof(xlen)`).

The real test (`sail_tests/vc_ocl_ocs_c.S`) passed on its first real run:
a capability stored via `OCS.C` and loaded back via `OCL.C` matched
exactly (Tag, `otype`, `Base`, `Length`, `Perms` all round-tripped), and a
subsequent plain `OCS.D` overwrite of the same bytes correctly produced a
Tag of `0` on the next `OCL.C` — confirmed the real security property
(*"a capability loaded from memory is only as trustworthy as what was
genuinely stored there"*) on the first attempt. **14/15 → 15/15**, zero
regressions.

### RTL: one real test-design bug, then one real, genuine RTL gap — diagnosed via an actual debug trace, not assumed

**Bug 1 (test, not RTL)**: the positive test's own `Object-Bind` for `c1`
used the wrong `rs1` register index in its hand-computed encoding (`bind`'s
own Python signature takes a *register index*, not the *value* that
register holds — the same real class of confusion, register-index-vs-value,
already documented once before this project, in Milestone 5's own results).
Diagnosed via a real per-cycle debug trace showing `c1` itself never
actually became tagged/bound (not a downstream OCL.C/OCS.C problem at
all) — fixed by correcting the encoding to reference the actual register
holding the intended `Object_ID`, not the `Object_ID` value used as if it
were a register index.

**Bug 2 (real, genuine RTL gap, found by the test's own negative path
after Bug 1 was fixed)**: once the positive path passed, the negative
control — an ordinary `OCS.D` overwriting a previously-tagged granule,
expecting the tag to read back `0` — failed: the tag stayed `1`. Diagnosed,
not assumed: `OCL.C`/`OCS.C` were the *only* instructions in the entire
file that ever touched `tag_mem[]` — every other write path (base ISA
stores, `OCS.D`, `NMC_ADD.{W,D}`, Veda-Atomic) left an already-set tag bit
untouched forever, meaning a plain, non-capability write could silently
corrupt a capability's raw bytes while `tag_mem[]` kept reporting it as
still genuinely valid. This is a real, load-bearing property of actual
CHERI hardware — **byte-granular tag invalidation**: any plain write
touching a tagged granule must clear that granule's tag, because the
bytes there may no longer form an intact capability. **Fixed by adding a
tag-clearing side effect to every existing write block in the file** (base
ISA store, `OCS.D`, `NMC_ADD.{W,D}`, Veda-Atomic), each gated on a real,
bounds-checked granule computation for that instruction's own real write
address. This is exactly the kind of subtle, security-critical property
this project's own "verify before deciding" discipline exists to catch —
found by the test doing its job, not by inspection of the design alone.

### Full regression: zero impact

All of Milestones 1–6's own tests (10 positive/negative programs) and the
base RV64I core's own unmodified 81-instruction smoke test were re-run
against the final build — **13 real test programs through one script**
(`run_veda_smoke_test.sh`), zero regressions, including after the
byte-granular tag-invalidation fix touched five separate, previously-
stable write blocks.

## Design notes worth recording

- **The negative test earned its keep twice in one milestone** — first by
  exposing a bug in the test itself (Bug 1), then, once that was fixed, by
  exposing a real, previously-invisible RTL gap (Bug 2) that the positive
  test alone could never have caught (byte-granular tag invalidation only
  matters once a *second*, plain write happens after a real `OCS.C`).
- **`Sail` and `RTL` now agree on one real memory layout, not two silently
  different ones**: both implementations pack a capability's 128 bits in
  the identical field order (`Object_ID @ Base @ Length @ Offset @ Perms @
  otype @ Reserved @ 1-bit pad`), a deliberate, stated choice rather than
  an accident of two independent implementations.
- **The tag store's own scope boundary is real and bounded, by design,
  not by oversight** — 32,768 granules (matching `ELFMEM_SIZE/16` in RTL,
  the identical real region every other Veda-Core mechanism is already
  scoped to), not an unbounded per-address structure. The same "real,
  bounded, honestly-scoped" discipline already used for the ODT (256 real
  RTL entries, not Sail's 8.4M).

## Not yet built

`Rebind`/`Bind-NoTrap` in RTL (Sail-only since Milestone V-A/B), real trap
infrastructure (violations still suppress writes, not Sail's own hard
trap), `CInvoke`-equivalent domain transition, and capability-authority-
gated `ODT-Populate`/`ODT-Destroy` (still ordinary-privilege-gated) — all
real, previously-named, still-deferred items, unaffected by this
milestone. With `OCL.C`/`OCS.C` now real in both layers, Veda-Core
capabilities can, for the first time, genuinely live in a data structure
in memory, not just in the 16-entry register file.
