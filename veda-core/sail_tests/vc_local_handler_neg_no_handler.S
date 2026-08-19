.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # LOCAL_FAULT_RECOVERY_DESIGN.md: a compartment that never registers a
    # local handler must see EXACTLY the pre-existing global-fallback
    # behavior -- ordinary cause, PCC reset to unbounded, control lands at
    # mtvec -- zero regression from this session's own new mechanism. No
    # VEDA_SET_LOCAL_HANDLER is ever executed in this test at all.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x22, 0

    # -- Object_ID=630 (CODE): Length=0x0004, Permit_Execute|Permit_Invoke
    #    -- the identical established fault-inducing shape used throughout
    #    this project's own prior trap-quarantine tests. --
    la   t0, comp_entry
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 630
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=631 (DATA): Permit_Invoke only. --
    li   x1, 631
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=632 (TYPE authority). --
    li   x1, 632
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 630
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 631
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 632
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4 -- must trap (no handler registered)
    j    fail_unexpected_no_trap

comp_entry:
    nop                              # the ONE instruction Length=0x0004 permits
    j    fail_unexpected_no_trap

.balign 4
trap_handler:
    # -- the ordinary, pre-existing global fallback. Confirm cause/cap_idx
    #    are exactly the plain bounds violation (0x01/16, unchanged), and
    #    PCC is genuinely unbounded (not any kind of redirect). --
    csrr t4, 0x343
    andi t5, t4, 0x1f
    li   t6, 0x01
    bne  t5, t6, fail_cause_mismatch
    srli t5, t4, 5
    li   t6, 16
    bne  t5, t6, fail_cause_mismatch
    csrr t4, 0x7c1                        # veda_pcc_length
    li   t6, 0xFFFFF
    bne  t4, t6, fail_not_unbounded
    csrr t4, 0x7c0                        # veda_pcc_base
    bne  t4, x0, fail_not_unbounded
    RVMODEL_HALT_PASS

fail_cause_mismatch:
    li   x22, 0xDEAD
    j    real_fail
fail_not_unbounded:
    li   x22, 0xBAD4
    j    real_fail
fail_unexpected_no_trap:
    li   x22, 0xBAD1
    j    real_fail
real_fail:
    RVMODEL_HALT_FAIL
