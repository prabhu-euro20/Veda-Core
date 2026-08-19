.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Adversarial-review Finding #1 (HIGH): no existing test round-
    # trips a genuinely WIDENED (>0xFFFF) Length/Offset capability
    # through OCS.C/OCL.C's own 136-bit pack/unpack -- the single
    # most-named touch point in
    # MILESTONE_LENGTH_OFFSET_WIDENING_RTL_RESULTS.md's own "17-byte
    # OCL.C/OCS.C" section ("first and most prominently"). This test:
    #  1. Binds a source object with Length=0x50000 (>4x the old
    #     16-bit ceiling) via VEDA_ODT_POPULATE_FAST + veda_attr.
    #  2. Moves its Offset via OCA to 0x10005 -- bits[19:16]=0x1,
    #     genuinely nonzero, comfortably inside [0, 0x50000).
    #  3. Stores that capability (Tag, Base, Length=0x50000,
    #     Offset=0x10005 all real, non-truncated 20-bit values) into
    #     a SEPARATE, ordinary target object via OCS.C.
    #  4. Reloads it via OCL.C into a fresh capability register.
    #  5. Confirms Tag/Base/Length/Offset all survived the real
    #     pack -> memory -> unpack round trip bit-for-bit against the
    #     exact values set -- not just "nonzero".
    # The final CGetOffset call below also directly closes Finding #6
    # (CGetOffset never queried at a widened value).
    #
    # Object_ID=506 (source, widened), 507 (target, ordinary). Fresh
    # block -- 500-505 already used by this pass's other new tests.
    # ─────────────────────────────────────────────────────────────
    li   t1, 0x50000000C   # veda_attr: Length=0x50000 (20-bit), Perms=0x000C (Load|Store)
    csrw 0x7c4, t1
    li   x1, 506
    li   x2, 0x80010000    # Base -- Base+Length = 0x80060000, inside elfmem[]'s own 512KB region
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast x5, x1, x2

    li   x1, 506
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1  -- source object, Offset=0 initially

    # Move c0's own Offset to 0x10005 (bits[19:16]=0x1, genuinely
    # nonzero) via OCA -- comfortably inside [0, 0x50000).
    li   x2, 0x10005
    .insn r 0x5b, 0x1, 0x0a, x1, x0, x2   # oca c1, c0, x2  -- c1.Offset := 0x10005
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0  # cgettag x10, c1  -- expect 1 (in-range, sanity)

    # Target object: Object_ID=507, ordinary 16-bit-Length descriptor
    # (plain VEDA_ODT_POPULATE suffices), Base=0x80070000 -- past the
    # source object's own [0x80010000, 0x80060000) range (no overlap),
    # 32-byte aligned, Length=0x0040 (64 bytes, generous headroom over
    # the 17-byte OCS.C access), Perms=0x000C (Load|Store).
    li   x1, 507
    li   x2, 0x800700000040000C   # Base=0x80070000, Length=0x0040, Perms=0x000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2

    li   x1, 507
    .insn i 0x0b, 0x5, x2, x1, 0   # veda.bind c2, x1  -- target/address capability

    # Store c1 (the widened, Offset-moved capability) into c2+0 via
    # OCS.C, then reload it via OCL.C into a fresh capability register
    # (c3) -- the real pack -> memory -> unpack round trip.
    li   x6, 0
    .insn r 0x0b, 0x4, 0x01, x1, x2, x6   # ocs.c c2, x6(=0), c1
    .insn r 0x0b, 0x4, 0x00, x3, x2, x6   # ocl.c c2, x6(=0), c3

    # The load-bearing assertions: every field of c3 must match c1's
    # own real values exactly, not just "look nonzero".
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag    x11, c3  -- expect 1
    .insn r 0x5b, 0x0, 0x00, x12, x3, x0  # cgetbase   x12, c3  -- expect 0x80010000
    .insn r 0x5b, 0x0, 0x01, x13, x3, x0  # cgetlen    x13, c3  -- expect 0x50000
    .insn r 0x5b, 0x0, 0x06, x14, x3, x0  # cgetoffset x14, c3  -- expect 0x10005 (widened value, closes Finding #6)

1:
    j 1b
