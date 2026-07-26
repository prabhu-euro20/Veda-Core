.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x1, 3
    .word 0x0000d10b     # veda.bind c2, x1
    li   x2, 5
    .word 0x1421115b      # oca c2, c2, x2
    .word 0x202010db       # cseal c1, c0, c2    (c1 = c0 sealed, otype = 5)
    .word 0x222091db        # cunseal c3, c1, c2  (c3 = c1 unsealed again)
    li   x4, 0x99
    .word 0x0221b20b         # ocs.d c3, x2, x4   -- must NOT trap
    li   x5, 0
    .word 0x0021b28b          # ocl.d c3, x2, x5   -- load back, expect 0x99
    li   x20, 0x99
    bne  x5, x20, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
