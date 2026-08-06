.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of minimal OS kernel Milestone A
    # (MINIMAL_OS_KERNEL_DESIGN.md): the TSC (Trusted Stack Capability)
    # -- OSpecialRW's new SCR-selector operand (`scr_sel`, previously
    # hardcoded to ODA-only, `x0`), read from the FULL 5-bit rs2
    # register-field position -- exercised here with `scr_sel = 1`
    # (VEDA_SCR_TSC), mirroring Sail's own already-verified
    # vc_switcher_tsc_roundtrip.S exactly. Proves: (a) TSC starts
    # genuinely untagged; (b) TSC round-trips a real capability's Base
    # field correctly; (c) TSC and ODA are genuinely independent state --
    # reading ODA (scr_sel=0, the pre-existing, backward-compatible
    # encoding) after only ever writing TSC still shows ODA untagged,
    # proving this is a real second register, not an aliased read/write
    # of the same one.
    #
    # Object_ID=50: a real authority object, Perms=0x0080
    # (Permit_Access_System_Registers).
    # ─────────────────────────────────────────────────────────────
    li   x1, 50
    li   x2, 0x8002100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 50
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- the TSC-bound capability, unsealed

    .insn r 0x5b, 0x1, 0x13, x2, x1, x1  # ospecialrw c2, tsc, c1  -- c2 = TSC's OLD value (expect Tag=0); TSC := c1
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag x10, c2  -- expect 0

    .insn r 0x5b, 0x1, 0x13, x3, x1, x1  # ospecialrw c3, tsc, c1  -- c3 = TSC's OLD value (now c1); TSC := c1 again
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag  x11, c3  -- expect 1
    .insn r 0x5b, 0x0, 0x00, x12, x3, x0  # cgetbase x12, c3  -- expect 0x80021000

    .insn r 0x5b, 0x1, 0x13, x4, x1, x0  # ospecialrw c4, oda, c1  -- c4 = ODA's OLD value (expect Tag=0, ODA never written this test)
    .insn r 0x5b, 0x0, 0x03, x13, x4, x0  # cgettag x13, c4  -- expect 0
1:
    j 1b
