.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone B: OCRETURN negative -- a capability
    # sealed via ordinary CSeal with an arbitrary, non-sentry otype must
    # SEAL_VIOLATION-trap (there is no second operand for OCRETURN to
    # "mismatch" against, unlike OCJALR's own TYPE_VIOLATION -- "not a
    # valid sentry" is a seal-validity failure, the design doc's own
    # explicit, documented choice).
    la   t0, trap_handler
    csrw mtvec, t0

    # Object_ID=52 (ordinary target), Perms=Execute=0x0002.
    li   x1, 52
    li   x2, 0x8005200000400002
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # Object_ID=53 (ordinary type authority), Perms=Seal|Unseal=0x0300.
    li   x1, 53
    li   x2, 0x8005300000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 52
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1
    li   x1, 53
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1

    .insn r 0x5b, 0x1, 0x10, x5, x5, x6  # cseal c5, c5, c6  -- ordinary seal, otype=c6.Offset=0 (NOT the sentry)

neg_fault:
    .insn r 0x5b, 0x1, 0x16, x0, x5, x0  # ocreturn c5  -- sealed, but not a sentry -- must TRAP
    RVMODEL_HALT_PASS

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0xA3                     # SEAL_VIOLATION(0x03), cap_idx=5 (c5) -> (5<<5)|0x03=0xA3
    bne  t3, t4, fail
    csrr t5, mepc
    la   t6, neg_fault
    bne  t5, t6, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

fail:
    RVMODEL_HALT_FAIL
