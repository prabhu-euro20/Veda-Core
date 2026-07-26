.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (Length=0x40)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x100        # requested new length, way beyond c0.Length=0x40 -- out of window
    .word 0x1020115b        # csetbounds c2, c0, x2  -- out of window -> c2.Tag cleared, soft-fail, no trap
    .word 0x06010a5b          # cgettag x20, c2  -- expect 0
1:
    j 1b
