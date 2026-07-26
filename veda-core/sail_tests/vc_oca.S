.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x10
    li   x3, 0x100
    .word 0x0220318b     # ocs.d c0, x2, x3         (store 0x100 at Base+0x10)
    .word 0x142010db      # oca c1, c0, x2           (c1.Offset = 0x10)
    li   x4, 0x55
    li   x5, 0
    .word 0x0440b28b       # nmc_add.d x5, c1, x4     (x5 <- old 0x100)
    li   x6, 0
    .word 0x0020330b        # ocl.d x6, c0, x2         (x6 <- post-add 0x155)
    li   x7, 0x100
    bne  x5, x7, fail
    li   x7, 0x155
    bne  x6, x7, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
