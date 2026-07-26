.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (the capability to be sealed)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x1, 3           # Object_ID = 3 (type-authority)
    .word 0x0000d10b     # veda.bind c2, x1
    li   x2, 5            # otype value
    .word 0x1421115b      # oca c2, c2, x2   (c2.Offset = 5)
    .word 0x202010db      # cseal c1, c0, c2  (c1 = c0 sealed, otype=5, Tag=true)
    li   x3, 0xAA          # value that must never actually get stored
    .word 0x0220b18b       # ocs.d c1, x2, x3 -- c1 is sealed, must hard-trap (Seal Violation, cause 0x03)
1:
    j 1b
