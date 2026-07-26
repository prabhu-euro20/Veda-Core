.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: plain Bind's own object-not-found hard-trap
    # (VEDA_CAUSE_OBJECT_NOT_FOUND, 0x05) -- Milestone 13. This exact
    # behavior has existed in veda_bind_insts.sail's own VEDA_BINDINST
    # catch-all else-branch since early in this project (the RTL side
    # only closed the equivalent gap this same milestone), but no prior
    # Sail self-check test ever explicitly asserted mcause/mtval for it
    # -- a real, genuine test-coverage gap, not a design gap, closed
    # here for the first time.
    #
    # Object_ID=6 is never populated by veda_test_seed_odt() (seeds
    # Object_ID 1-5 only, veda_regs.sail) -- a genuine ODT miss, distinct
    # in kind from Object_ID=5's own live-but-wrong-owner fixture
    # (vc_owner_hart_neg.S's own cause=0x06 scenario).
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 6
fault_instr:
    .word 0x0000d00b     # veda.bind c0, x1 -- Object_ID=6, never populated -- must hard-trap (cause 0x05)

    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x05          # cause=0x05 (Object Not Found), cap_idx=0 (c0)
    bne  t3, t4, check_fail

    # mepc must point at the OWN faulting Bind instruction.
    csrr t3, mepc
    la   t4, fault_instr
    bne  t3, t4, check_fail

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
