.section .text
.global _start
_start:
    li   x1, 2          # x1 = Object_ID = 2 (test-seeded: Load+Store only, NO Permit_NMC_Compute)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x4, 0x23       # value operand (irrelevant, should never be used)
    .word 0x0440328b    # nmc_add.d x5, c0, x4 -- c0 lacks Permit_NMC_Compute, must trap (cause 0x1f)
1:
    j 1b
