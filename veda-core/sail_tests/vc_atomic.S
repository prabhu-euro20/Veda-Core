.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0
    li   x3, 0xFF
    .word 0x0220318b    # ocs.d c0, x2, x3
    li   x4, 0x0F
    li   x5, 0
    .word 0x204032ab    # veda.amoxor.d x5, c0, x4
    li   x6, 0
    .word 0x0020330b    # ocl.d x6, c0, x2
    li   x7, 0xFF
    bne  x5, x7, fail
    li   x7, 0xF0
    bne  x6, x7, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
