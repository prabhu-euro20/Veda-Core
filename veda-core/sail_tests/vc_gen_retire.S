.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: ODT generation-wraparound retirement,
    # positive control (mirrors RTL Milestone 16's own veda_smoke_m16.S).
    # A slot destroyed/re-populated a normal, small number of times (5,
    # far under the 255-reuse retirement threshold) must keep working
    # completely normally -- proves the fix rejects only slots that have
    # genuinely exhausted their real generation counter, nothing else.
    #
    # Object_ID=51, clear of veda_test_seed_odt()'s own seeded IDs (1-5)
    # and vc_gen_retire_neg.S's own Object_ID=50.
    li   x7, 51

    li   x5, 0x80020200
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v1)

    li   x5, 0x80020300
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v2, real re-populate #1)

    li   x5, 0x80020400
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v3, real re-populate #2)

    li   x5, 0x80020500
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v4, real re-populate #3)

    li   x5, 0x80020600
    slli x5, x5, 32
    li   x20, 0x0008000C      # Perms = PERM_LOAD | PERM_STORE this time (write-then-read below)
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v5, real re-populate #4)

    # Fresh bind to the 5th incarnation -- must succeed normally (not
    # refused, not stale). Real write-then-read round trip (the object's
    # own backing memory was never otherwise initialized, so reading
    # first would only prove access was permitted, not that it reached
    # the real, correct object).
    mv   x1, x7
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0
    li   x11, 0x5555
    .insn r 0x0b, 0x3, 0x01, x11, x0, x2  # ocs.d c0, x2, x11
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0

    li   t4, 0x5555
    bne  x8, t4, check_fail

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
