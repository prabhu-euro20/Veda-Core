.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 19: mirror of vc_purecap_load_after_cgetbase_neg.S
    # using STORE instead of LOAD -- a distinct union clause in
    # base_insts.sail (separate encdec/execute from LOAD), so must be
    # independently confirmed to route through vmem_write/the same
    # ext_data_get_addr hook, not assumed from the LOAD test alone.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1  -- Object_ID=1

    .insn r 0x5b, 0x0, 0x00, x5, x0, x0  # cgetbase x5, c0  -- x5 = raw Base

    li   x6, 1
    csrw 0x7c5, x6                       # veda_mode.veda_purecap := 1

    li   x7, 0x42
    sd   x7, 0(x5)                       # ordinary STORE through the raw address -- must trap
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    # Same real consequence found and fixed in
    # vc_purecap_load_after_cgetbase_neg.S: clear veda_purecap before
    # RVMODEL_HALT_PASS/FAIL's own ordinary `sw` runs, or it too traps.
    li   t5, 0
    csrw 0x7c5, t5

    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x227        # (cap_idx=17<<5)|cause=0x07 = 0x220|0x07 = 0x227
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
