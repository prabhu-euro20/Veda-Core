.include "veda_selfcheck_macros.S"

.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x2, 0
    li   x3, 0x99
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3 -- c1 was NEVER bound (Tag=0), must trap
    RVMODEL_HALT_FAIL    # falling through here means the expected trap never fired

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x22        # cause=0x02 (Tag Violation), cap_idx=1 (c1)
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
