.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # SSC Milestone: confirms SSC gets the identical, real spatial bounds
    # check every other Veda-Core capability register already gets --
    # not a weaker, special-cased mechanism. Bind a real, bounded
    # (Length=0x40) object into SSC, then attempt an OCL.D one byte past
    # the end (offset=0x40) -- must hard-trap with a real Bounds
    # Violation, matching STACK_FRAME_CALL_RETURN_ANALYSIS.md's own
    # already-established real-hardware-bound-check precedent.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 230
    li   x2, 0x800510000040000C  # Base=0x80051000, Length=0x0040, Perms=0x000C (Load|Store)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 230
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1
    .insn r 0x5b, 0x1, 0x13, x9, x5, x2  # ospecialrw c9(discard), ssc, c5  -- SSC := c5

    li   x6, 0x40  # offset == Length -- one 8-byte word past the real, valid [0,0x40) range
    .insn r 0x0b, 0x3, 0x00, x22, x5, x6  # ocl.d x22, c5, x6(=0x40)  -- MUST hard-trap

    RVMODEL_HALT_FAIL  # unreachable if the trap above fired correctly

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0xA1        # (cap_idx=5<<5)|cause=0x01 -- c5 held the SSC-derived capability;
                          # cause 0x01 = Bounds (Length) Violation, confirming this is a real
                          # spatial bounds trap, not some other, unrelated cause
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
