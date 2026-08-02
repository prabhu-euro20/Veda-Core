.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0x100       # x2 = delta = 0x100, way beyond c0.Length=0x40 -- out of range
    .insn r 0x5b, 0x1, 0x0a, x1, x0, x2  # oca c1, c0, x2   (out of range -> c1.Tag cleared, soft-fail, no trap here)
    li   x4, 0x55         # value operand (irrelevant, should never be used)
    .insn r 0x0b, 0x3, 0x02, x5, x1, x4  # nmc_add.d x5, c1, x4 -- c1.Tag is false, must hard-trap (Tag Violation, cause 0x02)
1:
    j 1b
