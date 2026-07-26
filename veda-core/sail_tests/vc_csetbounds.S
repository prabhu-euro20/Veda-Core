.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x20
    .word 0x102010db     # csetbounds c1, c0, x2
    .word 0x0000855b      # cgetbase   x10, c1 -- expect 0x80010000
    .word 0x020085db       # cgetlen    x11, c1 -- expect 0x20
    .word 0x0c00865b        # cgetoffset x12, c1 -- expect 0
    .word 0x060086db         # cgettag    x13, c1 -- expect 1
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
