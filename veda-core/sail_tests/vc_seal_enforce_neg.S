.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x1, 3
    .word 0x0000d10b     # veda.bind c2, x1
    li   x2, 5
    .word 0x1421115b      # oca c2, c2, x2
    .word 0x202010db       # cseal c1, c0, c2  (c1 sealed, otype=5, Tag=1)
    li   x3, 0xAA
    .word 0x0220b18b        # ocs.d c1, x2, x3 -- c1 is sealed, must hard-trap (cause 0x03)
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x23         # cause=0x03 (Seal Violation), cap_idx=1 (c1)
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
