.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0x20
    .insn r 0x5b, 0x1, 0x08, x1, x0, x2  # csetbounds c1, c0, x2
    .insn r 0x5b, 0x0, 0x00, x10, x1, x0  # cgetbase   x10, c1 -- expect 0x80010000
    .insn r 0x5b, 0x0, 0x01, x11, x1, x0  # cgetlen    x11, c1 -- expect 0x20
    .insn r 0x5b, 0x0, 0x06, x12, x1, x0  # cgetoffset x12, c1 -- expect 0
    .insn r 0x5b, 0x0, 0x03, x13, x1, x0  # cgettag    x13, c1 -- expect 1
    li   x20, 0x80010000
    bne  x10, x20, fail
    li   x20, 0x20
    bne  x11, x20, fail
    bne  x12, x0, fail
    li   x20, 1
    bne  x13, x20, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
