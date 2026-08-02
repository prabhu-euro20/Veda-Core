.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (the capability to be sealed)
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 3           # Object_ID = 3 (type-authority)
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    li   x2, 5            # otype value
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x2  # oca c2, c2, x2   (c2.Offset = 5)
    .insn r 0x5b, 0x1, 0x10, x1, x0, x2  # cseal c1, c0, c2  (c1 = c0 sealed, otype=5, Tag=true)
    li   x3, 0xAA          # value that must never actually get stored
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3 -- c1 is sealed, must hard-trap (Seal Violation, cause 0x03)
1:
    j 1b
