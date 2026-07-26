.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x1, 3
    .word 0x0000d10b     # veda.bind c2, x1
    li   x2, 5
    .word 0x1421115b      # oca c2, c2, x2   (c2.Offset = 5)
    .word 0x202010db       # cseal c1, c0, c2  (c1 = c0 sealed, otype = 5)
    .word 0x0800855b        # cgettype x10, c1  -- expect 5
    .word 0x060085db         # cgettag  x11, c1  -- expect 1
    li   x20, 5
    bne  x10, x20, fail
    li   x20, 1
    bne  x11, x20, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
