.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0x10        # x2 = OCA delta
    .insn r 0x5b, 0x1, 0x0a, x1, x0, x2  # oca c1, c0, x2   (c1 = c0 with Offset = 0x10)
    .insn r 0x5b, 0x0, 0x00, x10, x1, x0  # cgetbase   x10, c1  -- expect 0x80010000
    .insn r 0x5b, 0x0, 0x01, x11, x1, x0  # cgetlen    x11, c1  -- expect 0x40
    .insn r 0x5b, 0x0, 0x02, x12, x1, x0  # cgetperm   x12, c1  -- expect 0x100C
    .insn r 0x5b, 0x0, 0x03, x13, x1, x0  # cgettag    x13, c1  -- expect 1
    .insn r 0x5b, 0x0, 0x04, x14, x1, x0  # cgettype   x14, c1  -- expect 0xFFFF (unsealed)
    .insn r 0x5b, 0x0, 0x05, x15, x1, x0  # cgetaddr   x15, c1  -- expect 0x80010010
    .insn r 0x5b, 0x0, 0x06, x16, x1, x0  # cgetoffset x16, c1  -- expect 0x10
1:
    j 1b
