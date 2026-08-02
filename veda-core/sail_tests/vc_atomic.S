.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0
    li   x3, 0xFF
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2  # ocs.d c0, x2, x3
    li   x4, 0x0F
    li   x5, 0
    .insn r 0x2b, 0x3, 0x10, x5, x0, x4  # veda.amoxor.d x5, c0, x4
    li   x6, 0
    .insn r 0x0b, 0x3, 0x00, x6, x0, x2  # ocl.d x6, c0, x2
    li   x7, 0xFF
    bne  x5, x7, fail
    li   x7, 0xF0
    bne  x6, x7, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
