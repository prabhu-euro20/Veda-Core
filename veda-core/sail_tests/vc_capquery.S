.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x10
    .word 0x142010db     # oca c1, c0, x2   (c1.Offset = 0x10)
    .word 0x0000855b      # cgetbase   x10, c1  -- expect 0x80010000
    .word 0x020085db       # cgetlen    x11, c1  -- expect 0x40
    .word 0x0400865b        # cgetperm   x12, c1  -- expect 0x100C
    .word 0x060086db         # cgettag    x13, c1  -- expect 1
    .word 0x0800875b          # cgettype   x14, c1  -- expect 0xFFFF
    .word 0x0a0087db           # cgetaddr   x15, c1  -- expect 0x80010010
    .word 0x0c00885b            # cgetoffset x16, c1  -- expect 0x10
    li   x20, 0x80010000
    bne  x10, x20, fail
    li   x20, 0x40
    bne  x11, x20, fail
    li   x20, 0x100C
    bne  x12, x20, fail
    li   x20, 1
    bne  x13, x20, fail
    li   x20, 0xFFFF
    bne  x14, x20, fail
    li   x20, 0x80010010
    bne  x15, x20, fail
    li   x20, 0x10
    bne  x16, x20, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
