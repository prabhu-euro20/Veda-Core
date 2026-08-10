.include "../sail_tests/veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Mutation/comparison control for the struct-array-global purecap probe:
    # calls the SAME compiled function (built WITHOUT __attribute__((
    # veda_compartment)), so plain -O1 -c single-stage clang, no OCInvoke,
    # no live compartment at all -- veda_pcc_length stays VEDA_PCC_UNBOUNDED
    # and veda_purecap is never set) directly from _start, with NO
    # compartment ceremony whatsoever. If the earlier trap was really
    # caused by purecap/live-compartment enforcement catching the
    # unrewritten g_arr[i].value access (not some unrelated bug in the
    # entry point's own bootstrap/linking), this baseline run must
    # complete WITHOUT ever reaching trap_handler.
    la   t0, trap_handler
    csrw mtvec, t0
    la   sp, _stack_top

    call veda_struct_array_global_thread   # ordinary function call, no compartment

    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    # A trap here on the BASELINE (non-compartment) run would mean the
    # earlier compartment run's trap was NOT specifically caused by
    # purecap/live-compartment enforcement -- i.e. it would invalidate the
    # earlier result. Report as FAIL so the comparison is unambiguous.
    RVMODEL_HALT_FAIL
