.section .text
.global _start
_start:
    # RTL Milestone 9 addendum: the downstream NMC_ADD.D below is a
    # "use"-family violation -- since Milestone 9 this now genuinely
    # traps instead of only suppressing the write. Install a generic
    # "skip and resume" handler up front (see veda_smoke_m4.S's own
    # identical addendum) -- this test's own 8-cycle window happened to
    # still pass without one (too short to ever fetch the undefined
    # instruction at the default mtvec=0), but that was a coincidence
    # of this file's own short cycle count, not a real guarantee, and
    # would break the moment anyone lengthened it, exactly like
    # veda_smoke_m4.S/m5.S/m8.S's own real Milestone 9 regressions this
    # same pass found and fixed.
    la   t0, generic_trap_handler
    csrw mtvec, t0

    li   x1, 1          # Object_ID = 1 (Length=0x40)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x100        # delta, way beyond c0.Length=0x40 -- out of range
    .word 0x142010db       # oca c1, c0, x2  (out of range -> c1.Tag cleared, soft-fail, no trap)
    li   x4, 0x23             # value operand (irrelevant, should never be used)
    li   x5, 0x5555             # sentinel: must stay unchanged if NMC_ADD is correctly blocked
    .word 0x0440b28b               # nmc_add.d x5, c1, x4 -- c1.Tag is false, must be a violation
1:
    j 1b

generic_trap_handler:
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret
