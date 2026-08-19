.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Length/Offset widening (NEXT_STEPS_ROADMAP.md, 2026-08-19): the real,
    # positive proof that an object's Length can now genuinely exceed
    # 65535 bytes (impossible under the old 16-bit field, and impossible
    # even now via plain VEDA_ODT_POPULATE, whose own descriptor stays
    # 16-bit-capped by design -- NEXT_STEPS_ROADMAP.md "Break 3"). Uses
    # VEDA_ODT_POPULATE_FAST + veda_attr (the only path that carries the
    # real 20-bit Length) to build a 0x50000-byte (327,680 bytes, >4x the
    # old 16-bit ceiling) object, then proves OCL.D/OCS.D genuinely
    # enforces this real width -- a round trip right at the object's own
    # real upper edge (offset = Length-4, width=8, so [offset,offset+8)
    # reaches exactly to Length), not just "somewhere comfortably inside
    # a huge object," which could pass even with a silently-truncated
    # Length.
    #
    # Object_ID=460, a fresh block (grep-audited against every existing
    # sail_tests/*.S `li x1, <N>` literal before picking -- highest prior
    # use found was 454).
    li   t1, 0x50000000C   # veda_attr: Length=0x50000 (20-bit), Perms=0x000C (Load|Store)
    csrw 0x7c4, t1
    li   x1, 460
    li   x2, 0x80010000    # Base -- Base+Length = 0x80060000, well inside the modeled 512KB RAM region
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast x5, x1, x2

    li   x1, 460
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1

    # Round trip at offset 0 (sanity: the object's own Base is genuinely usable).
    li   x6, 0
    li   x7, 0x11112222
    .insn r 0x0b, 0x3, 0x01, x7, x0, x6   # ocs.d c0, x6(=0), x7
    .insn r 0x0b, 0x3, 0x00, x8, x0, x6   # ocl.d x8, x6(=0), c0
    li   t0, 0x11112222
    bne  x8, t0, fail

    # The load-bearing assertion: round trip right at the real, widened
    # upper edge -- offset = Length-8 (0x4FFF8), width=8, so this access
    # spans [0x4FFF8, 0x50000), the last valid dword, reaching exactly to
    # the object's own real Length (0x50000) without exceeding it. A
    # silently-truncated Length (e.g. if only the low 16 bits of the
    # widened field were actually wired through) would make this trap;
    # it must NOT.
    li   x9, 0x4FFF8
    li   x10, 0x33334444
    .insn r 0x0b, 0x3, 0x01, x10, x0, x9  # ocs.d c0, x9, x10
    .insn r 0x0b, 0x3, 0x00, x11, x0, x9  # ocl.d x11, x9, c0
    li   t0, 0x33334444
    bne  x11, t0, fail

    # cgetlen must read back the real, full 20-bit value -- not
    # truncated, not sign-extended incorrectly.
    .insn r 0x5b, 0x0, 0x01, x12, x0, x0  # cgetlen x12, c0
    li   t0, 0x50000
    bne  x12, t0, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
