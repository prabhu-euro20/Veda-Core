.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 19: confirms CSR 0x7c5 (veda_mode) is
    # read/write-able from Machine mode (the only privilege level this
    # project's own real test config supports -- S/U-mode are both
    # "supported": false in sail_tests/veda_test_sail.json). A true
    # non-M-mode negative case can't be exercised in Sail here -- the
    # same real, already-documented scope limitation Milestone 11 hit for
    # OSpecialRW's own privilege gate (MILESTONE_11_RESULTS.md), stated
    # honestly rather than silently skipped.
    li   x1, 1
    csrw 0x7c5, x1
    csrr x2, 0x7c5
    li   t2, 1
    bne  x2, t2, fail

    li   x1, 0
    csrw 0x7c5, x1
    csrr x3, 0x7c5
    bne  x3, x0, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
