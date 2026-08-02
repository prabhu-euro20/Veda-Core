.section .text
.global _start
_start:
    li   x1, 2          # x1 = Object_ID = 2 (test-seeded: Load+Store only, NO Permit_NMC_Compute)
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x4, 0x23       # value operand (irrelevant, should never be used)
    .insn r 0x0b, 0x3, 0x02, x5, x0, x4  # nmc_add.d x5, c0, x4 -- c0 lacks Permit_NMC_Compute, must trap (cause 0x1f)
1:
    j 1b
