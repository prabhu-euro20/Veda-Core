.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 20: positive control -- outside any OCInvoke
    # compartment (veda_pcc_length == VEDA_PCC_UNBOUNDED, the real reset
    # default, never touched by this file), ordinary CSR write/readback
    # of veda_mepcc_base/veda_mepcc_length (0x7c2/0x7c3) must continue to
    # work exactly as before -- a real, previously-uncovered case (every
    # existing test only ever *reads* these two CSRs, inside a trap
    # handler, never writes them from ordinary code) that this
    # milestone's new gate must not regress.
    #
    # 0x7c0/0x7c1 are deliberately NOT exercised with arbitrary values
    # here -- doing so would itself immediately trip Milestone 14's own
    # real PCC-fetch enforcement on the very next instruction fetch
    # (veda_pcc_base/length jointly define the live fetch window, and
    # writing either to a value that doesn't cover this file's own real
    # runtime PC would hard-fault this test's own next instruction).
    # vc_pcc_bounds.S (via OCInvoke's own legitimate narrow/widen) and
    # vc_pcc_bounds_neg.S (via its own trap-handler restore, already
    # exercising a real 0x7c1/0x7c0 write from outside a live
    # compartment) already cover that case safely and remain unmodified
    # in the regression corpus.
    li   x1, 0xABCD0000
    csrw 0x7c2, x1
    csrr x2, 0x7c2
    bne  x1, x2, fail

    li   x1, 0x5678
    csrw 0x7c3, x1
    csrr x2, 0x7c3
    bne  x1, x2, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
