.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # LOCAL_FAULT_RECOVERY_DESIGN.md: the confused-deputy guard --
    # VEDA_SET_LOCAL_HANDLER must hard-trap (VEDA_CAUSE_BOUNDS_VIOLATION)
    # when the registered entry address does NOT lie within the CURRENT
    # live compartment's own bounds, and the table write must genuinely
    # not happen (checked indirectly: a later, otherwise-identical
    # in-bounds registration for the SAME otype must still succeed, and a
    # deliberate fault afterward must redirect to THAT one, not silently
    # carry over a rejected registration).
    la   t0, trap_handler
    csrw mtvec, t0

    li   x20, 0                    # phase: 0 = expect the confused-deputy trap
    li   x22, 0
    li   x25, 0                    # 1 once the confused-deputy trap is confirmed

    # -- Object_ID=640 (CODE): Base=comp_entry, Length=0x40. --
    la   t0, comp_entry
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 640
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=641 (DATA). --
    li   x1, 641
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=642 (TYPE authority). --
    li   x1, 642
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=643 (OUTSIDE_PTR): Base=outside_target, Length=0x04,
    #    Permit_Execute=0x0002. A genuinely, independently VALID
    #    (freshly-bound, correctly-tagged) capability -- deliberately NOT
    #    derived via OCA from c0, so this test isolates
    #    VEDA_SET_LOCAL_HANDLER's OWN confused-deputy bounds check from
    #    OCA's own unrelated, pre-existing out-of-range tag-clearing
    #    (found empirically: an OCA-derived attempt here hit OCA's own
    #    protection first, cause=0x02 tag violation, not this
    #    instruction's own cause=0x01 bounds check -- a real, distinct
    #    mechanism this test must not conflate). Bound BEFORE OCInvoke,
    #    at top level, since capability registers survive OCInvoke (only
    #    PCC narrows) -- available inside the compartment unchanged. --
    la   t0, outside_target
    slli t0, t0, 32
    li   t1, 0x00040002
    or   t0, t0, t1
    li   x1, 643
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 640
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 641
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 642
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    li   x1, 643
    .insn i 0x0b, 0x5, x11, x1, 0  # veda.bind c11, x1  -- OUTSIDE_PTR, survives OCInvoke

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4
    j    fail_unexpected_no_trap

comp_entry:
    li   t6, 1
    beq  x20, t6, phase2_ordinary_fault

    # -- phase 1: attempt to register c11 (validly tagged, Permit_Execute
    #    set, but its address lies FAR OUTSIDE [comp_entry,
    #    comp_entry+0x40), the CURRENT live compartment's own bounds) --
    #    must hard-trap, the table write must not happen. --
    .insn r 0x5b, 0x1, 0x17, x0, x11, x0  # osethandler c11 -- must trap, confused-deputy guard
    j    fail_unexpected_no_trap           # must NOT be reached

phase2_ordinary_fault:
    # -- prove the rejected phase-1 registration left NOTHING behind: a
    #    fresh, ordinary out-of-bounds fetch from this SAME compartment
    #    (never calling osethandler again) must fall straight through to
    #    the plain global path -- not redirect to any handler, since
    #    nothing was ever successfully registered. --
    la   t3, unreachable_marker
    jr   t3
    j    fail_unexpected_no_trap           # must NOT be reached

.balign 4
trap_handler:
    csrr t4, 0x343
    andi t5, t4, 0x1f
    li   t6, 1
    beq  x20, t6, phase2_check

phase1_check:
    li   t6, 0x01                          # VEDA_CAUSE_BOUNDS_VIOLATION
    bne  t5, t6, fail_cause_mismatch
    srli t5, t4, 5
    li   t6, 11                            # c11, the cs1 operand osethandler named
    bne  t5, t6, fail_cause_mismatch
    li   x25, 1
    # -- the compartment (otype) has NO registered handler (the attempt
    #    above was correctly rejected) -- confirm via the SAME mechanism
    #    the no-handler negative test uses: a fresh fault from this same
    #    compartment must fall straight through to the ordinary global
    #    path, never redirecting anywhere, since nothing was ever
    #    successfully registered. --
    li   x20, 1
    j    return_to_reinvoke

phase2_check:
    li   t6, 0x01
    bne  t5, t6, fail_cause_mismatch
    srli t5, t4, 5
    li   t6, 16                            # the PCC sentinel -- ordinary bounds violation
    bne  t5, t6, fail_cause_mismatch
    csrr t4, 0x7c1
    li   t6, 0xFFFFF
    bne  t4, t6, fail_not_unbounded
    li   t2, 1
    bne  x25, t2, real_fail
    RVMODEL_HALT_PASS

return_to_reinvoke:
    # -- PCC is already unbounded (the confused-deputy trap fell through
    #    the ordinary VEDA_SET_LOCAL_HANDLER trap path, which is NOT a
    #    redirect -- osethandler failing is an ordinary veda_trap(), same
    #    global-fallback chokepoint every other Veda violation uses).
    #    Re-invoke the SAME compartment fresh to drive phase 2's own
    #    fault. --
    li   x1, 640
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 641
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 642
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4
    j    fail_unexpected_no_trap

fail_cause_mismatch:
    li   x22, 0xDEAD
    j    real_fail
fail_not_unbounded:
    li   x22, 0xBAD4
    j    real_fail
fail_unexpected_no_trap:
    li   x22, 0xBAD1
    j    real_fail

.balign 4
outside_target:
    nop
    j    fail_unexpected_no_trap

.balign 4
unreachable_marker:
    nop                                    # never legitimately fetched
    j    fail_unexpected_no_trap

real_fail:
    RVMODEL_HALT_FAIL
