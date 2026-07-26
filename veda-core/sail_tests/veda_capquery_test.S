.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x10        # x2 = OCA delta
    .word 0x142010db     # oca c1, c0, x2   (c1 = c0 with Offset = 0x10)
    .word 0x0000855b     # cgetbase   x10, c1  -- expect 0x80010000
    .word 0x020085db     # cgetlen    x11, c1  -- expect 0x40
    .word 0x0400865b     # cgetperm   x12, c1  -- expect 0x100C
    .word 0x060086db      # cgettag    x13, c1  -- expect 1
    .word 0x0800875b      # cgettype   x14, c1  -- expect 0xFFFF (unsealed)
    .word 0x0a0087db      # cgetaddr   x15, c1  -- expect 0x80010010
    .word 0x0c00885b       # cgetoffset x16, c1  -- expect 0x10
1:
    j 1b
