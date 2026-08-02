.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 3
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    li   x2, 5
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x2  # oca c2, c2, x2
    .insn r 0x5b, 0x1, 0x10, x1, x0, x2  # cseal c1, c0, c2    (c1 = c0 sealed, otype = 5)
    .insn r 0x5b, 0x1, 0x11, x3, x1, x2  # cunseal c3, c1, c2  (c3 = c1 unsealed again)
    li   x4, 0x99
    .insn r 0x0b, 0x3, 0x01, x4, x3, x2  # ocs.d c3, x2, x4   -- must NOT trap
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x5, x3, x2  # ocl.d c3, x2, x5   -- load back, expect 0x99
    li   x20, 0x99
    bne  x5, x20, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
