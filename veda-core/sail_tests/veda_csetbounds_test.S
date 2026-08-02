.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (Base=0x80010000, Length=0x40, Offset=0)
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0x20         # new length, within c0's own [0, 0x40) window
    .insn r 0x5b, 0x1, 0x08, x1, x0, x2  # csetbounds c1, c0, x2  (c1.Base=Base+0=Base, c1.Length=0x20, c1.Offset=0)
    .insn r 0x5b, 0x0, 0x00, x10, x1, x0  # cgetbase   x10, c1 -- expect 0x80010000
    .insn r 0x5b, 0x0, 0x01, x11, x1, x0  # cgetlen    x11, c1 -- expect 0x20
    .insn r 0x5b, 0x0, 0x06, x12, x1, x0  # cgetoffset x12, c1 -- expect 0
    .insn r 0x5b, 0x0, 0x03, x13, x1, x0  # cgettag    x13, c1 -- expect 1 (in-window, cs1 unsealed+tagged)
1:
    j 1b
