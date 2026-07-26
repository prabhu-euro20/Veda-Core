.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x10         # OCA delta
    .word 0x142010db       # oca c1, c0, x2   (c1.Offset = 0x10)
    .word 0x0000855b        # cgetbase   x10, c1  -- expect 0x80010000
    .word 0x020085db         # cgetlen    x11, c1  -- expect 0x40
    .word 0x0400865b          # cgetperm   x12, c1  -- expect 0x100C
    .word 0x060086db           # cgettag    x13, c1  -- expect 1
    .word 0x0800875b            # cgettype   x14, c1  -- expect 0xFFFF
    .word 0x0a0087db             # cgetaddr   x15, c1  -- expect 0x80010010
    .word 0x0c00885b              # cgetoffset x16, c1  -- expect 0x10
    li   x2, 0x20                  # new length for CSetBounds
    .word 0x1020115b                 # csetbounds c2, c0, x2  (c2.Base=Base+0, c2.Length=0x20, c2.Offset=0)
    .word 0x000108db                  # cgetbase   x17, c2  -- expect 0x80010000
    .word 0x0201095b                   # cgetlen    x18, c2  -- expect 0x20
    .word 0x0c0109db                    # cgetoffset x19, c2  -- expect 0
    .word 0x06010a5b                     # cgettag    x20, c2  -- expect 1
1:
    j 1b
