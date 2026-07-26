.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x1, 2          # Object_ID = 2 (Load+Store only, NO Permit_NMC_Compute)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x4, 0x23
    .word 0x0440328b    # nmc_add.d x5, c0, x4 -- must trap, cause 0x1f
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x1F
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
