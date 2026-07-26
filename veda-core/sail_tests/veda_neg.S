.section .text
.global _start
_start:
    li   x2, 0
    li   x3, 0x99
    .word 0x0220b18b    # ocs.d c1, x2, x3 -- c1 was NEVER bound (Tag=0), must trap
1:
    j 1b
