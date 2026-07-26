.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (Base=0x80010000, Length=0x40, Offset=0)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x20         # new length, within c0's own [0, 0x40) window
    .word 0x102010db      # csetbounds c1, c0, x2  (c1.Base=Base+0=Base, c1.Length=0x20, c1.Offset=0)
    .word 0x0000855b       # cgetbase   x10, c1 -- expect 0x80010000
    .word 0x020085db       # cgetlen    x11, c1 -- expect 0x20
    .word 0x0c00865b        # cgetoffset x12, c1 -- expect 0
    .word 0x060086db        # cgettag    x13, c1 -- expect 1 (in-window, cs1 unsealed+tagged)
1:
    j 1b
