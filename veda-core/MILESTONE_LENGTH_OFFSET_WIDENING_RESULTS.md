# Length/Offset Widening: 16 -> 20 bits (Sail)

**Date:** 2026-08-19
**Scope:** implements the Length/Offset field widening decided the same day in `NEXT_STEPS_ROADMAP.md`'s two "DECIDED, 2026-08-19" entries -- the capability's `Length`/`Offset` fields grow from 16 to 20 bits each (max object size 64 KiB -> 1 MiB), the packed capability grows from 128 to 136 bits (16 to 17 bytes), and every real touch point that decision's own audit named. This pass is Sail-side only, matching this project's established Sail-first-then-RTL sequencing -- the RTL mirror is explicitly **not** attempted here (see "Not yet built").

## Why

The prior day's decision (`NEXT_STEPS_ROADMAP.md`) found the original 16-bit Length/Offset fields cap a single object at 65,535 bytes -- tight enough that a moderate embedded data structure (a frame buffer, a packet-reassembly buffer, a firmware image slice) could not be represented as one bounded object at all, forcing either multiple smaller capabilities (defeating the point of a single bounds-checked handle) or falling back to `veda_purecap`-unchecked raw pointers for anything larger. Real embedded-MCU SRAM/Flash datasheet research (Nordic nRF52840, ST STM32H7, Microchip SAM D51) found on-chip SRAM tops out around 1 MiB even on the highest-end Cortex-M7-class parts, so 20 bits (1 MiB) was chosen over the originally-floated 24 bits (16 MiB) as proportionate to this line's own "modest, data-structure-sized objects" philosophy rather than the project's internal 512 KiB simulation constant.

## What changed, file by file

**`model/extensions/Veda/veda_types.sail`** -- `capability.Length`/`.Offset` and `odt_entry.Length`: `bits(16)` -> `bits(20)`. `veda_cap_pack`/`veda_cap_unpack`: `bits(128)` -> `bits(136)`, every bit-slice re-derived (Object_ID `[135..113]`, Base `[112..81]`, Length `[80..61]`, Offset `[60..41]`, Perms `[40..25]`, otype `[24..9]`, Reserved `[8..1]`, pad `[0]`) -- same field order, same "pad as LSB" convention, just wider.

**`model/extensions/Veda/veda_regs.sail`** -- `VEDA_PCC_UNBOUNDED`: `0xFFFF`(16-bit) -> `0xFFFFF`(20-bit); `veda_pcc_length`/`veda_mepcc_length`: `bits(16)` -> `bits(20)`; `veda_attr` CSR (0x7C4, Milestone 18's populate-fast template register): `bits(32)` -> `bits(36)`, Length moves from `[31..16]` to `[35..16]` (16->20 bits), **Perms keeps its original `[15..0]` position unchanged** -- a deliberate "extend upward, don't reshuffle" choice that turned out to matter: it means `vc_odt_populate_fast.S`, an existing test that packs `veda_attr` via a plain 32-bit literal, kept working with zero changes, because its own Length value's upper 4 new bits are implicitly zero. `read_CSR`/`write_CSR(0x7C4)` gained an `if xlen == 64` guard (see "A real Sail-only type error" below) and `is_CSR_accessible(0x7C4,...)` was gated the same way, matching `core/sys_regs.sail`'s own real `mstatush`-at-`xlen==32` precedent.

**`model/extensions/Veda/veda_cap_insts.sail`** -- `VEDA_OCA`'s offset-add and `VEDA_CSETBOUNDS`'s new-Length slice: `[15..0]` -> `[19..0]`. **CSeal/CUnseal/OCJALR's otype-width mismatch** (the real finding of this pass's own audit, below).

**`model/extensions/Veda/veda_ocl_insts.sail`** -- OCL.C/OCS.C's byte-width literal: `16` -> `17` everywhere (`bits(128)`->`bits(136)`, `read_ram`/`write_ram` width argument). Plain `VEDA_ODT_POPULATE`'s own 64-bit GPR descriptor stays **unchanged** by design (`NEXT_STEPS_ROADMAP.md`'s own "Break 3": Length packs into the descriptor's `[31..16]`, still 16 bits, `zero_extend`ed into the new 20-bit field on assignment) -- this instruction is now explicitly capped at 64 KiB objects; `VEDA_ODT_POPULATE_FAST` is the only path that can produce a >64 KiB object, since its Length comes from the widened `veda_attr` CSR. **New: OCL.C/OCS.C now hard-require the real physical store address to be 32-byte aligned** (see "A second real finding" below).

**`model/extensions/Veda/veda_bind_insts.sail`** -- **zero changes needed** to the Bind/Rebind Length/Offset field copies (`Length = e.Length`, `Offset = cur.Offset`/`zeros()`) -- these are same-width struct-to-struct copies that pick up the new field widths automatically from the struct definition. New cause code added: `VEDA_CAUSE_ALIGNMENT_VIOLATION = 0x08`.

**`model/extensions/Veda/veda_atomic_insts.sail`** -- **zero changes needed**: `zero_extend(C(capidx).Offset)` is width-agnostic.

**`model/core/mem_metadata.sail`** -- **a real, honest gap found and fixed while implementing this pass**, not part of the original touch-point map (see "A third real finding" below).

**`c_emulator/riscv_model_impl.h`/`.cpp`, `gdbstub.cpp`** -- `pack_veda_capability_reg`'s buffer: `uint8_t[16]` -> `uint8_t[17]`; GDB's own `g`-packet capability-register loop and target-description XML (`org.veda-core.capabilities` feature): `bitsize="128"`/`vector count="16"` -> `bitsize="136"`/`count="17"`. The register-count loops (`for i in 0..16`, 16 capability registers, 16 tag pseudo-registers) are unrelated to byte width and correctly stayed `16`.

## Three real findings beyond the mechanical bit-slice work

The original touch-point map (from the prior day's audit) named CSeal/CUnseal's Offset<->otype coupling, but two more issues surfaced only while actually implementing and testing this pass -- named here explicitly, not glossed over, matching this project's own "re-derive from source, don't trust a prior document's claim" discipline.

**1. CSeal/CUnseal/OCJALR's otype-width mismatch.** `otype` (veda_types.sail) deliberately did **not** widen -- it stays 16 bits, matching real CHERI's own otype width, which is a function of the sealing/compartment address space, not the object-bounds address space Length/Offset share. CSeal's own `otype = cs2.Offset` assignment is therefore a real, narrowing truncation now (20 bits -> 16), not a same-width copy. Silently truncating (`cs2.Offset[15..0]`, no gate) would let two distinct Offset values differing only in bits `[19..16]` (e.g. `0x00005` and `0x10005`) alias to the identical otype -- a genuine type-confusion risk: CUnseal presented with either forged Offset would appear to authorize the same sealed capability. Fixed with two different, individually-correct techniques depending on whether the site *mints* or merely *compares*:
   - **CSeal (the one real mint site):** added `cs2.Offset[19..16] == 0b0000` as an explicit new conjunct of `authorized`, folded into the existing soft-fail (tag-clear) path CSeal's authorization failures already use -- not a new mechanism.
   - **CUnseal and OCJALR (compare-only sites):** compare the full 20-bit `cs2.Offset` against `zero_extend(cs1.otype)` rather than truncating `cs2.Offset`. This is mathematically equivalent to CSeal's own explicit gate (equality can only hold if `cs2.Offset`'s upper 4 bits are already zero, since a zero-extended 16-bit value never has them set) and is the simpler, more idiomatic Sail expression at a read site.

**2. OCL.C/OCS.C's new 32-byte alignment requirement.** Real Sail/RTL parity, not something the tag mechanism itself strictly requires in Sail (see finding 3): the project's own already-decided RTL tag-store design (`NEXT_STEPS_ROADMAP.md`'s prior-day audit) fixes the tag-store write to exactly 2 statically-known-adjacent granules for real hardware-simplicity/area reasons (Yosys-verified: 540 vs 75 cells, 7.2x cheaper than a dynamically-addressed alternative) -- which only stays a valid, cheap hardware design if every real capability-store address is 32-byte aligned. Gating this in Sail now, ahead of the RTL mirror, means Sail's own reference behavior already matches what RTL will enforce, avoiding the exact kind of Sail/RTL behavioral divergence this project's sequencing discipline exists to prevent. Real precedent: CHERI-RISC-V's own `[C]LC`/`[C]SC` also require capability-aligned addresses and trap on a misaligned one. New cause `VEDA_CAUSE_ALIGNMENT_VIOLATION` (0x08), hard trap, checked after `veda_check_access`'s own tag/seal/perm/bounds checks succeed (so a misaligned-and-otherwise-invalid access still reports its *first* real violation, not alignment).

**3. `mem_metadata.sail`'s own single-granule tag model.** Found by actually reading this file's real logic while implementing the widening (the prior day's audit had verified the coarse-granule decision only against real Yosys synthesis of the *RTL's* own `tag_mem` write logic -- a synthetic Verilog mockup, not this file -- so Sail's independent tag-store implementation was never separately checked). Before this fix, `__WriteRAM_Meta`/`__ReadRAM_Meta` computed a *single* granule index from the access's start address alone and completely ignored `width`. This was harmless by coincidence for the original 16-byte capability only if every real capability-store happened to already be 16-byte-aligned (never actually enforced anywhere) -- and is now genuinely broken for the 17-byte capability: a 17-byte OCS.C store's own 17th byte *always* spills into a second granule this single-index model never touched, meaning that byte's real data reached RAM (the underlying byte-level write is unconditional) but was never protected by the tag mechanism -- an unrelated plain write landing on that spillover byte could silently corrupt part of a "still tagged" capability's own field bits, undetected. Fixed by computing the real index of the access's own last byte too (`addr + width - 1`) and touching/reading both granules identically (write: both set to the same value; read: AND of both, so a capability is valid only if *every* granule its own footprint spans is still tagged) -- correct for any access up to 2 granules, which covers this project's own real widths (8 bytes for OCL.D/OCS.D, 17 for OCL.C/OCS.C) with no loop needed.

## A real Sail-only type error (not RTL-relevant)

`veda_attr`'s widening to `bits(36)` broke `zero_extend(veda_attr)` in `read_CSR(0x7C4)`: Sail's build system compiles **both** rv32 and rv64 model configs (`model/CMakeLists.txt`'s own `foreach (xlen IN ITEMS 32 64)`), even though only rv64 is ever actually exercised by this project's own tests, so the type-checker must prove `zero_extend` correct for a hypothetical `xlen==32` too -- impossible for a 36-bit source into a 32-bit target. The original `bits(32)` `veda_attr` never hit this because RISC-V's own `xlen >= 32` axiom always covers a 32-bit source. Fixed by gating `veda_attr`'s `is_CSR_accessible`/`read_CSR`/`write_CSR` clauses with `if xlen == 64`, mirroring `core/sys_regs.sail`'s own real `mstatush` (0x310, valid only at `xlen==32`) precedent for exactly this kind of xlen-conditional CSR existence.

## New tests (5)

- **`vc_widened_bounds.S`** (positive): builds a 0x50000-byte (327,680-byte, >4x the old 16-bit ceiling) object via `VEDA_ODT_POPULATE_FAST`+`veda_attr` (impossible via plain `VEDA_ODT_POPULATE`), round-trips a dword right at the object's own real upper edge (`offset = Length-8`, reaching exactly to `Length`), and checks `CGetLen` reads back the full `0x50000` -- not a truncated value.
- **`vc_widened_bounds_neg.S`** (negative): the same object, an access reaching 4 bytes *past* `Length` must hard-trap `VEDA_CAUSE_BOUNDS_VIOLATION` -- proves the bounds check compares against the real 20-bit Length, not some aliased/overflowed value.
- **`vc_cseal_offset_hibits_neg.S`** (negative): an authority capability with `Offset=0x10005` (upper bits genuinely nonzero, comfortably in-bounds) must soft-fail CSeal (`CGetTag` of the result reads 0) -- proves the new precondition fires rather than silently truncating to a colliding `otype=0x0005`.
- **`vc_oclc_alignment_neg.S`** (negative): an object deliberately based at a non-32-byte-aligned (but still 4-byte-aligned) address, accessed via OCS.C at offset 0, must hard-trap with `mcause=0x18`/`mtval` cause `0x08` -- confirms the new alignment gate fires with the *right* cause, not some other check.
- **`vc_oclc_granule_adjacency.S`** (adversarial, both directions): stores a tagged capability, then proves (a) ordinary plain writes *outside* the real 2-granule span (one granule before, one two granules after) do **not** spuriously invalidate its tag, and (b) an ordinary plain write *inside* the second granule -- at a byte the capability's own real 17 bytes never used -- **does** correctly invalidate it. This is the real, dedicated adversarial test the prior day's audit named as still owed.

## An existing test that needed fixing, not just widening

**`sail_tests/vc_ocsc_bind_spill_restore_roundtrip.S`** -- its own SPILL object was sized `Length=0x0010` (16 bytes) to match the old capability width exactly; OCL.C/OCS.C now move 17 bytes, so this object was legitimately 1 byte too small and correctly `BOUNDS_VIOLATION`-trapped (real, intended behavior, not a bug to work around). Fixed by widening the object's own declared Length to `0x0011` and its backing `.data` reservation to 3 dwords (24 bytes, comfortably >=17).

## ~20 existing tests broke on the *old* 16-bit sentinel literal, not the widening's own logic

The first full-suite run after the mechanical widening surfaced a real, separate class of regression: `VEDA_PCC_UNBOUNDED` changed value (`0xFFFF` -> `0xFFFFF`), but ~20 hand-written `sail_tests/*.S` files hardcode the literal `0xFFFF` at sites that mean "the real unbounded sentinel," not "the otype `UNSEALED_OTYPE` constant" (which correctly stayed 16-bit `0xFFFF` and needed **no** change -- distinguishing the two per-occurrence, by reading context, was itself real work). One of these (`vc_syscall0_step0_spike.S`, an explicit `csrw 0x7c3, t3` "abandon this compartment" idiom) produced a genuine multi-minute simulator hang -- `PASS` became a false "the mepcc restore mechanism composes correctly" was actually "PCC got silently re-narrowed to a bogus 16-bit-sentinel-shaped value on the *next* `mret`, causing a real fetch-fault-retrap loop with no forward progress." Two categories of fix:

1. **Pure CSR-value comparisons/writes** (most of the ~20): mechanical `0xFFFF` -> `0xFFFFF`.
2. **Object descriptors deliberately packing `Length=0xFFFF` to coincide with the old sentinel** (~8 files, all "return to an unbounded caller/switcher context" idioms): plain `VEDA_ODT_POPULATE`'s own 16-bit-capped Length field can *never* produce the new 20-bit sentinel value at all -- this specific idiom is now structurally impossible via the old encoding. Converted each to `VEDA_ODT_POPULATE_FAST` + `veda_attr` (the only path with a real 20-bit Length), preserving the exact original security property (genuine, bit-for-bit return to the true architectural "unbounded" state) rather than weakening it to "returns to some large-but-finite region."

Also added a 20-second `timeout` wrapper around the sim invocation in `run_veda_selfcheck_tests.sh` -- a real, durable robustness improvement independent of this specific bug (a hang previously blocked the entire regression run with no diagnostic signal; it now becomes a fast, clear `FAIL (exit=124)`).

## Verification

**Full regression**, `run_veda_selfcheck_tests.sh`: **70/70 passed** (65 pre-existing, after the sentinel-literal fixes above, + 5 new).

```
=== Veda-Core Milestone V-C self-check results ===
[... 68 PASS lines ...]
---
70/70 passed
```

**Mutation testing** (3 mechanisms, each: break, rebuild, confirm the specific new test flips to `FAILURE`, revert, rebuild, confirm back to 70/70):

1. **CSeal precondition** (`cs2.Offset[19..16] == 0b0000` removed from `authorized`): `vc_cseal_offset_hibits_neg` flipped to `FAILURE 1` (the seal now silently succeeds with the colliding otype).
2. **OCS.C alignment gate** (`if paddr_bits[4..0] != 0b00000 ...` replaced with `if false ...`): `vc_oclc_alignment_neg` flipped to `FAILURE 1` (the misaligned store now silently succeeds).
3. **Multi-granule tag write** (`__WriteRAM_Meta`'s second-granule write disabled): `vc_oclc_granule_adjacency` flipped to `FAILURE 1` (the capability's own tag no longer survives the initial round trip at all, since its second granule is never set -- confirming the fix is load-bearing, not merely aesthetic).

All three reverted cleanly; final full regression re-confirmed at **70/70**.

## Files changed

`toolchain/sail-riscv` (Sail fork): `model/core/mem_metadata.sail`, `model/extensions/Veda/veda_types.sail`, `veda_regs.sail`, `veda_cap_insts.sail`, `veda_ocl_insts.sail`, `veda_bind_insts.sail`; `c_emulator/riscv_model_impl.h`, `riscv_model_impl.cpp`, `gdbstub.cpp`. `veda-core`: 5 new `sail_tests/vc_*.S`, `sail_tests/vc_ocsc_bind_spill_restore_roundtrip.S` (fixed), ~20 existing `sail_tests/vc_*.S` (sentinel-literal fix), `sail_tests/run_veda_selfcheck_tests.sh` (+timeout), this results doc.

## Not yet built

**RTL mirror** -- deliberately not attempted this pass, matching this project's established Sail-first sequencing. `rtl/veda_core.tlv` still has the old 128-bit/16-byte capability format throughout: CRF field declarations, `$veda_ocsc_packed`'s own pack/unpack, OCL.C/OCS.C's byte-move logic, `tag_mem`/`tcm_scratch_tag` array sizing, the ODT entry format, every zero-extension literal-width site, and the `16'hFFFF` sentinel family (~15 sites, per the prior day's audit) -- none of this pass's changes have been mirrored there yet. The RTL milestone also owes its own **fresh Yosys synthesis check at the real 20-bit width** (the prior day's 540-vs-75-cell numbers were measured on synthetic mockups at the *pre-this-pass* field widths, for comparing tag-granule strategies in the abstract, not the real widened RTL) and a **re-verification of `REALTIME_SAFETY_CRITICAL_AUDIT_RESULTS.md`'s "exactly one hold mechanism" claim** against the actual changed RTL, per that same audit's own explicit caveat -- not assumed to still hold.

**Toolchain layer** -- `VedaShadowPropagation.cpp`'s `kVedaCapTableSlotBytes = 16`
constant, plus 3 more real, related toolchain-layer regressions this doc's own
scope did not originally anticipate (a stale `0xFFFF`-vs-`0xFFFFF` PCC-unbounded
sentinel across 6 hand-written `.S` files, a second hand-mirrored copy of the
`kVedaCapTableSlotBytes` constant in `runtime/veda_rt.c`, and two hand-sized
scheduler-object Length constants) -- all found by a full regression sweep and
**closed in TOOLCHAIN_MILESTONE_22_WIDENING_PARITY_RESULTS.md**, see that doc for
the full detail. `veda_rt.h`'s `veda_rt_init(uint16_t length, uint16_t perms)`
signature remains unaudited/not yet revisited. The 9 hand-written `.S` bootstrap
files using `slli ..., 16` to pack plain-`VEDA_ODT_POPULATE` descriptors are
confirmed to need **zero** changes (plain POPULATE's own encoding stays unchanged
by design).

**Not committed or pushed yet**, matching this session's established pattern.
