.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (Length=0x40)
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0x100        # requested new length, way beyond c0.Length=0x40 -- out of window
    .insn r 0x5b, 0x1, 0x08, x2, x0, x2  # csetbounds c2, c0, x2  -- out of window -> c2.Tag cleared, soft-fail, no trap
    .insn r 0x5b, 0x0, 0x03, x20, x2, x0  # cgettag x20, c2  -- expect 0
1:
    j 1b
