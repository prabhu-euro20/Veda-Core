.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone A: TSC (Trusted Stack Capability) --
    # OSpecialRW's new SCR-selector operand (`scr_sel`, previously
    # hardcoded `00000`/ODA-only) is exercised here with `scr_sel =
    # 0b00001` (VEDA_SCR_TSC) -- encoded via `x1` in the `.insn` rs2
    # position (x1's own real RISC-V register-index encoding is
    # `0b00001`, confirmed directly against the real R-type layout:
    # `scr_sel` occupies exactly the bit range an ordinary rs2 GPR field
    # would). Mirrors `vc_ospecialrw.S`'s own already-proven
    # read-then-write pattern exactly, for the new SCR. Proves: (a) TSC
    # starts genuinely untagged (Sail's own default-zero init, the same
    # established precedent `veda_oda` already relies on), (b) TSC
    # round-trips a real capability's Base field correctly, (c) TSC and
    # ODA are genuinely independent state -- writing TSC never disturbs
    # a separately-tracked ODA, proving this is a real second register,
    # not an aliased read/write of the same one.

    # Object_ID=50: a real authority object for the TSC write,
    # Perms=0x0080 (Permit_Access_System_Registers) -- the same real
    # permission vc_ospecialrw.S already established as meaningful here.
    li   x1, 50
    li   x2, 0x8002100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 50
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- the TSC-bound capability, unsealed

    # -- TSC read-then-write, exercised twice, mirroring
    #    vc_ospecialrw.S's own proven pattern exactly, but with `x1` in
    #    the rs2/scr_sel position selecting VEDA_SCR_TSC instead of the
    #    default VEDA_SCR_ODA (`x0`). --
    .insn r 0x5b, 0x1, 0x13, x2, x1, x1  # ospecialrw c2, tsc, c1  -- c2 = TSC's OLD value (expect Tag=0, never set before); TSC := c1
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag x10, c2  -- expect 0 (the old, empty TSC)

    .insn r 0x5b, 0x1, 0x13, x3, x1, x1  # ospecialrw c3, tsc, c1  -- c3 = TSC's OLD value (now c1, from the write just above); TSC := c1 again
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag  x11, c3  -- expect 1 (the TSC really was populated by the first call)
    .insn r 0x5b, 0x0, 0x00, x12, x3, x0  # cgetbase x12, c3  -- expect 0x80021000 (c1's own real Base -- confirms genuine round-trip, not a coincidence)

    # -- Independence check: ODA (scr_sel = VEDA_SCR_ODA, `x0` in the
    #    rs2/scr_sel position) must still read back completely untagged
    #    -- proves the TSC writes above never touched the ODA's own
    #    separate state (a real, distinct capability register, not the
    #    same storage under a different selector value by accident). --
    .insn r 0x5b, 0x1, 0x13, x4, x1, x0  # ospecialrw c4, oda, c1  -- c4 = ODA's OLD value (expect Tag=0, ODA never written this test)
    .insn r 0x5b, 0x0, 0x03, x13, x4, x0  # cgettag x13, c4  -- expect 0

    li   t0, 0
    bne  x10, t0, fail
    li   t0, 1
    bne  x11, t0, fail
    li   t0, 0x80021000
    bne  x12, t0, fail
    li   t0, 0
    bne  x13, t0, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
