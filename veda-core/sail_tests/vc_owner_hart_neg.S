.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: owner-hart ODT enforcement -- Milestone 12
    # negative test. Plain Bind (mode=0) against a LIVE object owned by a
    # genuinely different hart must hard-trap with the new cause code
    # 0x06 (VEDA_CAUSE_OWNER_VIOLATION) -- the real, distinct-in-kind
    # violation from "object not found" (cause 0x05): the object
    # genuinely exists, this hart simply isn't its owner.
    #
    # Object_ID=5 is injected directly into the ODT by
    # veda_test_seed_odt() (veda_regs.sail), pre-claimed by owner_hart
    # =0x63 (99 decimal) -- a stand-in "other hart," since this
    # single-process Sail C emulator has no real second hart to own
    # anything with (mhartid is config-fixed at 0, veda_test_sail.json).
    la   t0, trap_handler
    csrw mtvec, t0

    li   x5, 5
    .word 0x0002d00b     # veda.bind c0, x5   -- Object_ID=5, owned by hart 99 -- must hard-trap (cause 0x06)
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x06          # cause=0x06 (Owner Violation), cap_idx=0 (c0)
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
