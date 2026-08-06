.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone B: OCRETURN negative -- an untagged
    # capability operand must TAG_VIOLATION-trap, the same real check
    # OCJALR's own cs1-side already performs (cause/mtval encoding
    # verified against vc_ocjalr_neg.S's own already-proven convention).
    la   t0, trap_handler
    csrw mtvec, t0

neg_fault:
    .insn r 0x5b, 0x1, 0x16, x0, x5, x0  # ocreturn c5  -- c5 was never bound, untagged -- must TRAP
    RVMODEL_HALT_PASS

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0xA2                     # TAG_VIOLATION(0x02), cap_idx=5 (c5) -> (5<<5)|0x02=0xA2
    bne  t3, t4, fail
    csrr t5, mepc
    la   t6, neg_fault
    bne  t5, t6, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

fail:
    RVMODEL_HALT_FAIL
