.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x100        # delta, way beyond c0.Length=0x40 -- out of range
    .word 0x142010db       # oca c1, c0, x2  (out of range -> c1.Tag cleared, soft-fail, no trap here)
    li   x4, 0x55
    .word 0x0440b28b        # nmc_add.d x5, c1, x4 -- c1.Tag is false, must hard-trap (cause 0x02)
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x22          # cause=0x02 (Tag Violation), cap_idx=1 (c1)
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
