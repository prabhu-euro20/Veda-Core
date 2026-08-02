.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0          # x2 = offset = 0
    li   x3, 0xFF       # x3 = initial value to store
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2  # ocs.d c0, x2, x3   (store 0xFF at c0.Base + 0)
    li   x4, 0x0F       # x4 = XOR operand
    li   x5, 0          # clear x5 so a no-op can't accidentally look right
    .insn r 0x2b, 0x3, 0x10, x5, x0, x4  # veda.amoxor.d x5, c0, x4  (x5 <- old 0xFF; memory <- 0xFF^0x0F=0xF0)
    li   x6, 0          # clear x6
    .insn r 0x0b, 0x3, 0x00, x6, x0, x2  # ocl.d x6, c0, x2   (load back, should be 0xF0)
    # Expected: x5 == 0xFF (old value), x6 == 0xF0 (post-xor value).
1:
    j 1b
