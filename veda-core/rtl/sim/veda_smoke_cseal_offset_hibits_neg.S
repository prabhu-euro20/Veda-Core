.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Length/Offset widening RTL mirror (mirrors vc_cseal_offset_
    # hibits_neg.S's own Sail scenario exactly): CSeal's own
    # `otype = cs2.Offset[15:0]` assignment is a real, narrowing
    # truncation now (Offset is 20 bits, otype stays 16) -- this test
    # proves the new explicit precondition ($veda_cs2_offset[19:16]
    # == 4'b0000 in $veda_cseal_authorized) actually fires and
    # soft-fails, rather than silently truncating cs2.Offset=0x10005
    # down to otype=0x0005. A silent-truncation bug would make this
    # test's own CSeal SUCCEED (wrongly) instead of soft-failing.
    #
    # Object_ID=504, a fresh block. Authority object: Base=0x80010000,
    # Length=0x10010 (65552 bytes, >0xFFFF -- only reachable via
    # VEDA_ODT_POPULATE_FAST, matching every other widened-Length
    # object in this pass), Perms=Permit_Seal|Permit_Unseal (0x0300)
    # -- large enough that Offset=0x10005 stays genuinely within
    # [0, Length), so the ONLY reason this CSeal can fail is the new
    # precondition, not an incidental bounds violation.
    # ─────────────────────────────────────────────────────────────
    li   t1, 0x100100300   # veda_attr: Length=0x10010, Perms=0x0300
    csrw 0x7c4, t1
    li   x1, 504
    li   x2, 0x80010000
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast x5, x1, x2

    li   x1, 504
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1  -- authority, unsealed

    # Move c0's own Offset to 0x10005 (bits[19:16] = 0x1, genuinely
    # nonzero) via OCA -- 0x10005 is comfortably inside [0, 0x10010),
    # so OCA itself succeeds (this is not a bounds-violation setup).
    li   x2, 0x10005
    .insn r 0x5b, 0x1, 0x0a, x1, x0, x2   # oca c1, c0, x2  -- c1.Offset := 0x10005
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0  # cgettag x10, c1  -- expect 1 (in-range, sanity)

    # Object_ID=1 (this RTL's own reset-seeded fixture): a real,
    # ordinary unsealed capability to attempt sealing -- this test's
    # own focus is the AUTHORITY side (c1), not cs1.
    li   x1, 1
    .insn i 0x0b, 0x5, x2, x1, 0   # veda.bind c2, x1  -- cs1, unsealed

    .insn r 0x5b, 0x1, 0x10, x3, x2, x1   # cseal c3, c2, c1  -- c1.Offset=0x10005: must SOFT-FAIL
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag x11, c3  -- expect 0 (soft-fail confirmed, no trap)

1:
    j 1b
