.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x1, 5                     # a fresh Object_ID, never touched by the test scaffold
    li   x2, 0x800104000040100c    # descriptor: Base=0x80010400, Length=0x40, Perms=0x100C
    .word 0x0620800b               # veda.odt.populate x0, x1, x2
    .word 0x0000d00b                # veda.bind c0, x1
    li   x3, 0                       # access offset
    li   x4, 0x77                     # value to store
    .word 0x0230320b                  # ocs.d c0, x3, x4  -- must succeed
    li   x5, 0
    .word 0x0030328b                   # ocl.d c0, x3, x5  -- load back, expect 0x77
    li   x20, 0x77
    bne  x5, x20, self_check_fail       # positive phase must hold before continuing
    .word 0x0600900b                     # veda.odt.destroy x0, x1  -- destroys Object_ID=5
    .word 0x0230320b                      # ocs.d c0, x3, x4 (again) -- c0's generation is now
                                           # stale, must hard-trap Tag Violation (cause 0x02)
    j    self_check_fail                  # falling through means the expected trap never fired

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, self_check_fail
    csrr t3, mtval
    li   t4, 0x02          # cause=0x02 (Tag Violation), cap_idx=0 (c0)
    bne  t3, t4, self_check_fail
    RVMODEL_HALT_PASS
self_check_fail:
    RVMODEL_HALT_FAIL
