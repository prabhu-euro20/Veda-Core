.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of SSC (Stack-Spill Capability):
    # SSC_STACK_SPILL_CAPABILITY_DESIGN.md's own third Special
    # Capability Register -- OSpecialRW's scr_sel=2 (VEDA_SCR_SSC),
    # mirroring Sail's own already-verified vc_ssc_roundtrip.S exactly.
    # Proves: (a) SSC starts genuinely untagged; (b) SSC round-trips a
    # real capability's Base field correctly; (c) SSC, TSC, and ODA are
    # three genuinely independent registers.
    #
    # Object_ID=300: a real authority object, Perms=0x0080
    # (Permit_Access_System_Registers).
    # ─────────────────────────────────────────────────────────────
    li   x1, 300
    li   x2, 0x8002100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 300
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1

    .insn r 0x5b, 0x1, 0x13, x2, x1, x2  # ospecialrw c2, ssc, c1  -- c2 = SSC's OLD value (expect Tag=0); SSC := c1
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag x10, c2  -- expect 0

    .insn r 0x5b, 0x1, 0x13, x3, x1, x2  # ospecialrw c3, ssc, c1  -- c3 = SSC's OLD value (now c1); SSC := c1 again
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag  x11, c3  -- expect 1
    .insn r 0x5b, 0x0, 0x00, x12, x3, x0  # cgetbase x12, c3  -- expect 0x80021000

    .insn r 0x5b, 0x1, 0x13, x4, x1, x0  # ospecialrw c4, oda, c1  -- c4 = ODA's OLD value (expect Tag=0)
    .insn r 0x5b, 0x0, 0x03, x13, x4, x0  # cgettag x13, c4  -- expect 0

    .insn r 0x5b, 0x1, 0x13, x6, x1, x1  # ospecialrw c6, tsc, c1  -- c6 = TSC's OLD value (expect Tag=0)
    .insn r 0x5b, 0x0, 0x03, x14, x6, x0  # cgettag x14, c6  -- expect 0
1:
    j 1b
