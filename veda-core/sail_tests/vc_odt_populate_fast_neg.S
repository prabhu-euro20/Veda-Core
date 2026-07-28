.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 18: negative control for VEDA_ODT_POPULATE_FAST.
    # Proves the instruction's one real semantic difference from plain
    # VEDA_ODT_POPULATE -- Length/Perms come from the live `veda_attr` CSR,
    # not an immediate operand -- is actually load-bearing, not just
    # plumbed through and ignored: a deliberately small Length (0x8) set
    # via veda_attr must genuinely bound-check a later access, exactly
    # like a small Length would under plain Populate. Reuses
    # VEDA_ODT_POPULATE's own already-proven bounds-check code path
    # (veda_check_access in veda_ocl_insts.sail) -- this test targets only
    # the new instruction's own field-sourcing, not that shared logic.
    #
    # Object_ID=61, clear of every other test's own seeded/used IDs.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x10, 0x0008100c    # veda_attr = Length=0x8 (deliberately small), Perms=0x100C
    csrw 0x7c4, x10

    li   x1, 61
    li   x2, 0x80010600     # Base, direct
    .word 0x0820800b        # veda.odt.populate.fast x0, x1, x2
    .word 0x0000d08b        # veda.bind c1, x1

    li   x6, 0x10           # offset 0x10, width 8 -> offset+width=0x18 > Length=0x8
    li   x7, 0x99
fault_instr:
    .word 0x0260b38b        # ocs.d c1, x6, x7 -- must hard-trap Bounds Violation

    RVMODEL_HALT_FAIL        # falling through means the expected trap never fired

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, self_check_fail
    csrr t3, mtval
    li   t4, 0x21            # cause=0x01 (Bounds Violation), cap_idx=1 (c1)
    bne  t3, t4, self_check_fail
    RVMODEL_HALT_PASS
self_check_fail:
    RVMODEL_HALT_FAIL
