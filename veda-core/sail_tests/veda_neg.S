.section .text
.global _start
_start:
    li   x2, 0
    li   x3, 0x99
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3 -- c1 was NEVER bound (Tag=0), must trap
1:
    j 1b
