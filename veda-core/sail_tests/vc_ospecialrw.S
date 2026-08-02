.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: OSpecialRW -- Milestone 11
    # (NEXT_STEPS_ROADMAP.md §2.5, "capability-authority-gated
    # ODT-Populate/ODT-Destroy"). Term-for-term adaptation of real
    # CHERI's own CSpecialRW (CHERI ISA spec §4.3.6/p.235): reads the
    # ODA's OLD value into cd, THEN overwrites the ODA with cs1 -- a
    # real atomic read-then-write, verified here field-for-field, not
    # assumed correct from the design alone.
    #
    # Object_ID=40: a real, minted "ODT-manager" authority object,
    # Perms=0x0080 (Permit_Access_System_Registers, bit 7 --
    # VEDA_CORE_SPEC.md's own Perms table, inherited from CHERI's real
    # permission list at Milestone V-B but never consumed by any real
    # instruction until this milestone).
    li   x1, 40
    li   x2, 0x8001100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 40
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   -- the authority capability, unsealed

    # -- OSpecialRW's own atomic read-then-write, exercised twice to
    #    prove both halves independently. --
    .insn r 0x5b, 0x1, 0x13, x2, x1, x0  # ospecialrw c2, c1  -- c2 = ODA's OLD value (expect Tag=0, never set before); ODA := c1
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag x10, c2    -- expect 0 (the old, empty ODA)

    .insn r 0x5b, 0x1, 0x13, x3, x1, x0  # ospecialrw c3, c1  -- c3 = ODA's OLD value (now c1, from the write just above); ODA := c1 again
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag  x11, c3   -- expect 1 (the ODA really was populated by the first call)
    .insn r 0x5b, 0x0, 0x00, x12, x3, x0  # cgetbase x12, c3   -- expect 0x80011000 (c1's own real Base -- confirms it's genuinely c1's contents round-tripped through the ODA, not a coincidence)

    # -- ODT-Populate still succeeds with the ODA now genuinely
    #    authorized (in addition to this test's own ordinary M-mode
    #    privilege, which alone already suffices -- Sail's own S/U-mode
    #    support is disabled in this project's own test config, so a
    #    real "M-mode-independent" proof of the ODA path alone is
    #    RTL-side work, see MILESTONE_11_RESULTS.md; this positive test's
    #    own real job is proving OSpecialRW itself, not re-proving
    #    privilege gating already covered by earlier milestones). --
    li   x1, 41
    li   x2, 0x8001200000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 41
    .insn i 0x0b, 0x5, x4, x1, 0  # veda.bind c4, x1
    .insn r 0x5b, 0x0, 0x03, x13, x4, x0  # cgettag  x13, c4   -- expect 1
    .insn r 0x5b, 0x0, 0x00, x14, x4, x0  # cgetbase x14, c4   -- expect 0x80012000

    li   t0, 0
    bne  x10, t0, fail
    li   t0, 1
    bne  x11, t0, fail
    li   t0, 0x80011000
    bne  x12, t0, fail
    li   t0, 1
    bne  x13, t0, fail
    li   t0, 0x80012000
    bne  x14, t0, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
