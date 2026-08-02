.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 19: reset-value sanity -- confirms veda_mode
    # defaults to 0 (purecap OFF) immediately after reset, with no
    # explicit CSR write anywhere in this file. This is the single test
    # most likely to catch an ext_reset() omission bug, and the one that
    # guards the entire pre-existing self-check corpus (none of which
    # anticipates this feature) against a silent regression.
    csrr x1, 0x7c5
    bne  x1, x0, fail

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1  -- Object_ID=1

    .insn r 0x5b, 0x0, 0x00, x5, x0, x0  # cgetbase x5, c0  -- x5 = raw Base

    li   x6, 0x1357
    sd   x6, 0(x5)                       # ordinary STORE, purecap OFF (default) -- must succeed
    ld   x7, 0(x5)                       # ordinary LOAD, purecap OFF (default) -- must succeed

    li   t2, 0x1357
    bne  x7, t2, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
