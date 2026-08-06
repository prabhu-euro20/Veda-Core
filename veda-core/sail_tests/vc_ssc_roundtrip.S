.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # SSC (Stack-Spill Capability) -- Veda-Core's third Special Capability
    # Register, added to give ordinary compiled C's ABI-mandated stack
    # spills a real, dedicated capability to route through (see
    # veda_regs.sail's own doc comment for the full rationale). Mirrors
    # vc_switcher_tsc_roundtrip.S's own already-proven pattern exactly,
    # but with `x2` in the rs2/scr_sel position (VEDA_SCR_SSC = 0b00010,
    # x2's own real RISC-V register-index encoding). Proves: (a) SSC
    # starts genuinely untagged (Sail's own default-zero init, the same
    # established precedent veda_oda/veda_tsc already rely on), (b) SSC
    # round-trips a real capability's Base field correctly, (c) SSC, TSC,
    # and ODA are three genuinely independent registers -- writing SSC
    # never disturbs the separately-tracked ODA or TSC.

    # Object_ID=200: a real authority object for the SSC write,
    # Perms=0x0080 (Permit_Access_System_Registers) -- the same real
    # permission every prior OSpecialRW test already established as
    # meaningful here.
    li   x1, 200
    li   x2, 0x8002100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 200
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- the SSC-bound capability, unsealed

    # -- SSC read-then-write, exercised twice --
    .insn r 0x5b, 0x1, 0x13, x2, x1, x2  # ospecialrw c2, ssc, c1  -- c2 = SSC's OLD value (expect Tag=0, never set before); SSC := c1
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag x10, c2  -- expect 0 (the old, empty SSC)

    .insn r 0x5b, 0x1, 0x13, x3, x1, x2  # ospecialrw c3, ssc, c1  -- c3 = SSC's OLD value (now c1, from the write just above); SSC := c1 again
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag  x11, c3  -- expect 1 (SSC really was populated by the first call)
    .insn r 0x5b, 0x0, 0x00, x12, x3, x0  # cgetbase x12, c3  -- expect 0x80021000 (c1's own real Base -- confirms genuine round-trip)

    # -- Independence check: ODA and TSC (scr_sel = x0/x1) must both still
    #    read back completely untagged -- proves the SSC writes above
    #    never touched their separate state. --
    .insn r 0x5b, 0x1, 0x13, x4, x1, x0  # ospecialrw c4, oda, c1  -- c4 = ODA's OLD value (expect Tag=0)
    .insn r 0x5b, 0x0, 0x03, x13, x4, x0  # cgettag x13, c4  -- expect 0

    .insn r 0x5b, 0x1, 0x13, x6, x1, x1  # ospecialrw c6, tsc, c1  -- c6 = TSC's OLD value (expect Tag=0)
    .insn r 0x5b, 0x0, 0x03, x14, x6, x0  # cgettag x14, c6  -- expect 0

    li   t0, 0
    bne  x10, t0, fail
    li   t0, 1
    bne  x11, t0, fail
    li   t0, 0x80021000
    bne  x12, t0, fail
    li   t0, 0
    bne  x13, t0, fail
    li   t0, 0
    bne  x14, t0, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
