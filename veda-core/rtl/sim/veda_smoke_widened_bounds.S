.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Length/Offset widening RTL mirror (MILESTONE_LENGTH_OFFSET_
    # WIDENING_RESULTS.md, Sail-side): mirrors vc_widened_bounds.S's
    # own scenario exactly (same encodings, identical bit layout in
    # both layers). Real, positive proof that an object's Length can
    # now genuinely exceed 65535 bytes -- impossible under the old
    # 16-bit field, and still impossible via plain VEDA_ODT_POPULATE,
    # whose own descriptor stays 16-bit-capped by design. Uses
    # VEDA_ODT_POPULATE_FAST + veda_attr (the only path that carries
    # the real 20-bit Length) to build a 0x50000-byte (327,680-byte,
    # >4x the old 16-bit ceiling) object, then proves OCL.D/OCS.D
    # genuinely enforces this real width -- a round trip right at the
    # object's own real upper edge (offset = Length-8, width=8, so
    # [offset, offset+8) reaches exactly to Length), not just
    # "somewhere comfortably inside a huge object," which could pass
    # even with a silently-truncated Length.
    #
    # Object_ID=500, a fresh block (grep-audited against every
    # existing rtl/sim/*.S file's own `li x1, <N>` literals -- highest
    # prior use found was 330).
    # ─────────────────────────────────────────────────────────────
    li   t1, 0x50000000C   # veda_attr: Length=0x50000 (20-bit), Perms=0x000C (Load|Store)
    csrw 0x7c4, t1
    li   x1, 500
    li   x2, 0x80010000    # Base -- Base+Length = 0x80060000, well inside elfmem[]'s own 512KB region
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast x5, x1, x2

    li   x1, 500
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1

    # Round trip at offset 0 (sanity: the object's own Base is genuinely usable).
    li   x6, 0
    li   x7, 0x11112222
    .insn r 0x0b, 0x3, 0x01, x7, x0, x6   # ocs.d c0, x6(=0), x7
    .insn r 0x0b, 0x3, 0x00, x8, x0, x6   # ocl.d x8, x6(=0), c0

    # The load-bearing assertion: round trip right at the real, widened
    # upper edge -- offset = Length-8 (0x4FFF8), width=8, so this access
    # spans [0x4FFF8, 0x50000), the last valid dword, reaching exactly
    # to the object's own real Length (0x50000) without exceeding it. A
    # silently-truncated Length (e.g. if only the low 16 bits of the
    # widened field were actually wired through) would make this trap.
    li   x9, 0x4FFF8
    li   x10, 0x33334444
    .insn r 0x0b, 0x3, 0x01, x10, x0, x9  # ocs.d c0, x9, x10
    .insn r 0x0b, 0x3, 0x00, x11, x0, x9  # ocl.d x11, x9, c0

    # cgetlen must read back the real, full 20-bit value -- not
    # truncated, not sign-extended incorrectly.
    .insn r 0x5b, 0x0, 0x01, x12, x0, x0  # cgetlen x12, c0

1:
    j 1b
