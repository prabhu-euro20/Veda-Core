.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 3
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    li   x2, 5
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x2  # oca c2, c2, x2
    .insn r 0x5b, 0x1, 0x10, x1, x0, x2  # cseal c1, c0, c2  (c1 sealed, otype=5, Tag=1)
    li   x3, 0xAA
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3 -- c1 is sealed, must hard-trap (cause 0x03)
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
