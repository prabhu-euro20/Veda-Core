.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0x10
    li   x3, 0x100
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2  # ocs.d c0, x2, x3         (store 0x100 at Base+0x10)
    .insn r 0x5b, 0x1, 0x0a, x1, x0, x2  # oca c1, c0, x2           (c1.Offset = 0x10)
    li   x4, 0x55
    li   x5, 0
    .insn r 0x0b, 0x3, 0x02, x5, x1, x4  # nmc_add.d x5, c1, x4     (x5 <- old 0x100)
    li   x6, 0
    .insn r 0x0b, 0x3, 0x00, x6, x0, x2  # ocl.d x6, c0, x2         (x6 <- post-add 0x155)
    li   x7, 0x100
    bne  x5, x7, fail
    li   x7, 0x155
    bne  x6, x7, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
