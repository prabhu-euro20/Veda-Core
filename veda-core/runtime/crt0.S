# Minimal bare-metal C runtime startup for veda_rt test programs. Reuses
# sail_tests/veda_selfcheck_macros.S's own real, already-verified
# RVMODEL_HALT_PASS/FAIL <-> tohost convention (same PASS/FAIL polling
# contract run_veda_selfcheck_tests.sh's SIM invocation already expects) --
# main()'s return value (0 = pass, nonzero = fail) is translated into
# exactly that same halt convention, so this runtime's own test runner can
# reuse the identical pass/fail detection logic.
.include "veda_selfcheck_macros.S"

.section .text.init
.global _start
_start:
    la   sp, _stack_top

    # Real, standard bare-metal .bss zeroing -- this runtime's allocator
    # state (veda_rt.c's g_in_use/g_retired/g_destroy_count arrays) must
    # start zeroed like any real C global, not left to chance on whatever
    # the simulator's backing memory happened to hold.
    la   t0, __bss_start
    la   t1, __bss_end
bss_zero_loop:
    bgeu t0, t1, bss_zero_done
    sb   x0, 0(t0)
    addi t0, t0, 1
    j    bss_zero_loop
bss_zero_done:

    call main
    beqz a0, rt_pass
    j    rt_fail
rt_pass:
    RVMODEL_HALT_PASS
rt_fail:
    RVMODEL_HALT_FAIL
