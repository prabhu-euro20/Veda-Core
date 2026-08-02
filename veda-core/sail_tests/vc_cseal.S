.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 3
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    li   x2, 5
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x2  # oca c2, c2, x2   (c2.Offset = 5)
    .insn r 0x5b, 0x1, 0x10, x1, x0, x2  # cseal c1, c0, c2  (c1 = c0 sealed, otype = 5)
    .insn r 0x5b, 0x0, 0x04, x10, x1, x0  # cgettype x10, c1  -- expect 5
    .insn r 0x5b, 0x0, 0x03, x11, x1, x0  # cgettag  x11, c1  -- expect 1
    li   x20, 5
    bne  x10, x20, fail
    li   x20, 1
    bne  x11, x20, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
