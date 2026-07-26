.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x1, 4           # Object_ID = 4 (seeded WITHOUT Permit_Seal)
    .word 0x0000d10b     # veda.bind c2, x1
    li   x2, 5
    .word 0x1421115b      # oca c2, c2, x2   (structurally fine, no Permit_Seal needed for OCA)
    .word 0x202010db       # cseal c1, c0, c2  -- c2 lacks Permit_Seal: must SOFT-FAIL, not trap
    .word 0x0600855b        # cgettag x10, c1  -- expect 0 (soft-fail confirmed, no trap occurred)
    bne  x10, x0, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
