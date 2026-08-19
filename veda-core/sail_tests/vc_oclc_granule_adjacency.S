.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Length/Offset widening (NEXT_STEPS_ROADMAP.md, "a thorough
    # pre-implementation audit"): the dedicated adversarial test that
    # audit named -- "a real, poisoned-data-adjacent-to-a-capability
    # -store test to confirm no spurious tag-sharing." A 17-byte
    # capability store now always spans 2 of mem_metadata.sail's own
    # real, unchanged 16-byte tag-store granules (its 17th byte spills
    # into the second one). This test proves BOTH directions of the
    # real, coarse-granule design's own honest contract: (a) an ordinary
    # plain write to memory OUTSIDE either of the 2 granules the
    # capability's own footprint occupies must NOT spuriously invalidate
    # its tag (no false-positive aliasing beyond the real 2-granule
    # span); (b) an ordinary plain write INSIDE the second granule --
    # even at a byte the capability's own real 17 bytes never actually
    # used -- correctly DOES invalidate the tag (the granule, not the
    # individual byte, is the real unit of protection, an intentional,
    # already-decided design property, not a bug).
    la   t0, trap_handler
    csrw mtvec, t0

    # Object_ID=464 (target, Load|Store): Base=0x80020000 -- deliberately
    # 32-byte aligned (0x20000 mod 32 == 0), so the OCS.C/OCL.C accesses
    # below satisfy the new alignment gate and this test isolates the
    # tag-granule property alone. Length=0x0040 (64 bytes).
    li   x1, 464
    li   x2, 0x800200000040000C   # Base=0x80020000, Length=0x0040, Perms=0x000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2

    li   x1, 464
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1  -- target/address capability

    # Object_ID=1 (veda_test_seed_odt's own permanent seed): a real,
    # tagged capability to store -- this test's own focus is whether the
    # tag survives, not which capability's value is used.
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0   # veda.bind c1, x1  -- value capability, tagged

    # Store c1 through c0 at offset 0 -- occupies physical bytes
    # [0x80020000, 0x80020011), spanning granule G (byte 0-15) and
    # granule G+1 (the 17th byte, byte 16, lands at G+1's own byte 0).
    li   x5, 0
    .insn r 0x0b, 0x4, 0x01, x1, x0, x5   # ocs.c c0, x5(=0), c1

    # Sanity: an immediate, undisturbed round trip must still read tagged.
    .insn r 0x0b, 0x4, 0x00, x2, x0, x5   # ocl.c c0, x5(=0), c2
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag x10, c2  -- expect 1
    beq  x10, x0, fail

    # (a) Plain writes OUTSIDE the real 2-granule span (G-1 and G+2) --
    #     must NOT invalidate the tag.
    li   t1, 0x8001FFF8    # Base-8, inside granule G-1 ([Base-16, Base))
    sd   x0, 0(t1)
    li   t1, 0x80020020    # Base+32, the START of granule G+2 ([Base+32, Base+48))
    sd   x0, 0(t1)

    .insn r 0x0b, 0x4, 0x00, x3, x0, x5   # ocl.c c0, x5(=0), c3
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag x11, c3  -- expect STILL 1
    beq  x11, x0, fail

    # (b) A plain write INSIDE granule G+1 (Base+17 -- one byte past the
    #     capability's own real 17-byte footprint, but the same real
    #     granule its own 17th byte occupies) -- MUST invalidate the tag.
    li   t1, 0x80020011    # Base+17
    sd   x0, 0(t1)

    .insn r 0x0b, 0x4, 0x00, x4, x0, x5   # ocl.c c0, x5(=0), c4
    .insn r 0x5b, 0x0, 0x03, x12, x4, x0  # cgettag x12, c4  -- expect 0 now
    bne  x12, x0, fail

    li   x20, 0x600D
    j    done

trap_handler:
    # Any trap here is a real failure -- every access in this file is
    # deliberately in-bounds, tagged, and 32-byte aligned.
    li   x20, 0xDEAD

done:
    li   t2, 0x600D
    bne  x20, t2, real_fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
real_fail:
    RVMODEL_HALT_FAIL
