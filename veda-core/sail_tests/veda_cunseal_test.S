.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (capability to be sealed then unsealed)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x1, 3           # Object_ID = 3 (type-authority)
    .word 0x0000d10b     # veda.bind c2, x1
    li   x2, 5            # otype value / access offset
    .word 0x1421115b      # oca c2, c2, x2   (c2.Offset = 5)
    .word 0x202010db      # cseal c1, c0, c2   (c1 = c0 sealed, otype = 5)
    .word 0x222091db       # cunseal c3, c1, c2 (c3 = c1 unsealed again, using c2 as authority)
    li   x4, 0x99           # value to store through the newly-unsealed c3
    .word 0x0221b20b        # ocs.d c3, x2, x4   -- must NOT trap: c3 is unsealed and usable
    li   x5, 0
    .word 0x0021b28b         # ocl.d c3, x2, x5   -- load back, expect 0x99
1:
    j 1b
