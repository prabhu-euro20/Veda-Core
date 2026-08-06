.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of SSC's cross-thread isolation test (Sail:
    # sail_tests/vc_ssc_cross_thread_isolation.S). Direct RTL port of
    # veda_smoke_m23_scheduler.S, with the identical two targeted
    # additions the Sail side already proved: THREAD_A binds a real
    # object into SSC on its own first entry; THREAD_B, on its own
    # first entry (reached only after crossing back through the
    # switcher's own OCRETURN at least once), reads SSC back and
    # asserts it is genuinely untagged -- closing the one real,
    # honestly-named gap left open by SSC_STACK_SPILL_CAPABILITY_
    # DESIGN.md ("closed by construction... not yet independently
    # re-verified with its own test"), now in RTL too.
    #
    # Object_ID=123 for the new SSC-bound object -- confirmed free
    # (veda_smoke_m23_scheduler.S's own header already grepped
    # 110-199 as completely free in this corpus; 110-122 are consumed
    # by this file's own copy of that scheduler, 123 is the next
    # unused slot).
    # ─────────────────────────────────────────────────────────────
    la   t0, switcher_entry
    csrw mtvec, t0

    # ══════════════ THREAD_A: Object_ID 110(CODE)/111(DATA)/112(type) ══════════════
    la   t0, thread_a_entry
    slli t0, t0, 32
    li   t1, 0x01000402        # Length=0x0100, Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 110
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- CODE_A

    li   x1, 111
    li   x2, 0x8011070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- DATA_A

    li   x1, 112
    li   x2, 0x8011080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- type authority A

    li   x1, 110
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1  -- CODE_A unsealed
    li   x1, 111
    .insn i 0x0b, 0x5, x1, x1, 0   # veda.bind c1, x1  -- DATA_A unsealed
    li   x1, 112
    .insn i 0x0b, 0x5, x13, x1, 0  # veda.bind c13, x1 -- type authority A (transient)

    .insn r 0x5b, 0x1, 0x10, x0, x0, x13  # cseal c0, c0, c13  -- sealed CODE_A
    .insn r 0x5b, 0x1, 0x10, x1, x1, x13  # cseal c1, c1, c13  -- sealed DATA_A

    # ══════════════ THREAD_B: Object_ID 113/114/115 ══════════════
    la   t0, thread_b_entry
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 113
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- CODE_B

    li   x1, 114
    li   x2, 0x8011090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- DATA_B

    li   x1, 115
    li   x2, 0x80110a0000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- type authority B

    li   x1, 113
    .insn i 0x0b, 0x5, x2, x1, 0   # veda.bind c2, x1  -- CODE_B unsealed
    li   x1, 114
    .insn i 0x0b, 0x5, x3, x1, 0   # veda.bind c3, x1  -- DATA_B unsealed
    li   x1, 115
    .insn i 0x0b, 0x5, x13, x1, 0  # veda.bind c13, x1 -- type authority B (transient)

    .insn r 0x5b, 0x1, 0x10, x2, x2, x13  # cseal c2, c2, c13  -- sealed CODE_B
    .insn r 0x5b, 0x1, 0x10, x3, x3, x13  # cseal c3, c3, c13  -- sealed DATA_B

    # ══════════════ SCHEDULER: Object_ID 116/117/118 ══════════════
    la   t0, scheduler_entry
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 116
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- CODE_SCHED

    li   x1, 117
    li   x2, 0x80110b0000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- DATA_SCHED

    li   x1, 118
    li   x2, 0x80110c0000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- type authority SCHED

    li   x1, 116
    .insn i 0x0b, 0x5, x4, x1, 0   # veda.bind c4, x1  -- CODE_SCHED unsealed
    li   x1, 117
    .insn i 0x0b, 0x5, x5, x1, 0   # veda.bind c5, x1  -- DATA_SCHED unsealed
    li   x1, 118
    .insn i 0x0b, 0x5, x13, x1, 0  # veda.bind c13, x1 -- type authority SCHED (transient)

    .insn r 0x5b, 0x1, 0x10, x4, x4, x13  # cseal c4, c4, c13  -- sealed CODE_SCHED
    .insn r 0x5b, 0x1, 0x10, x5, x5, x13  # cseal c5, c5, c13  -- sealed DATA_SCHED

    # ══════════════ save-area-A: Object_ID 119 ══════════════
    la   t0, save_area_a
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   x1, 119
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- save-area-A

    li   x1, 119
    .insn i 0x0b, 0x5, x6, x1, 0   # veda.bind c6, x1  -- save-area-A, unsealed (permanent)

    # ══════════════ save-area-B: Object_ID 120 ══════════════
    la   t0, save_area_b
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   x1, 120
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- save-area-B

    li   x1, 120
    .insn i 0x0b, 0x5, x7, x1, 0   # veda.bind c7, x1  -- save-area-B, unsealed (permanent)

    # ══════════════ thread_index capability: Object_ID 121 ══════════════
    la   t0, thread_index
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   x1, 121
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- thread_index cap

    li   x1, 121
    .insn i 0x0b, 0x5, x8, x1, 0   # veda.bind c8, x1  -- thread_index, unsealed (permanent)

    # ══════════════ return-sentry SOURCE: Object_ID 122 ══════════════
    la   t0, after_scheduler_return
    slli t0, t0, 32
    li   t1, 0xFFFF0002
    or   t0, t0, t1
    li   x1, 122
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- return-sentry source

    li   x1, 122
    .insn i 0x0b, 0x5, x9, x1, 0   # veda.bind c9, x1  -- return-sentry source, unsealed (permanent)

    # ══════════════ pre-populate save_area_b with THREAD_B's own bootstrap state ══════════════
    la   x28, thread_b_entry
    la   x29, thread_b_entry
    li   x30, 0x0100
    li   x5, 0
    .insn r 0x0b, 0x3, 0x01, x28, x7, x5  # ocs.d c7, x5(=0), x28  -- save B's entry PC
    li   x5, 8
    .insn r 0x0b, 0x3, 0x01, x29, x7, x5  # ocs.d c7, x5(=8), x29  -- save B's own Base
    li   x5, 16
    .insn r 0x0b, 0x3, 0x01, x30, x7, x5  # ocs.d c7, x5(=16), x30 -- save B's own Length

    # ══════════════ init thread_index=0 (A current), yield_count=0, tsc_ok=1 ══════════════
    la   x5, thread_index
    sd   x0, 0(x5)
    la   x5, yield_count
    sd   x0, 0(x5)
    la   x5, tsc_ok
    li   x6, 1
    sd   x6, 0(x5)

    # ══════════════ prime TSC := c6 (save-area-A, since THREAD_A runs first) ══════════════
    .insn r 0x5b, 0x1, 0x13, x14, x6, x1  # ospecialrw c14(discard), tsc, c6

    # ══════════════ enter THREAD_A for the first time ══════════════
    .insn r 0x5b, 0x1, 0x12, x0, x0, x1   # ocinvoke c0, c1
    j    fail_halt                          # must NOT be reached

.balign 4
thread_a_entry:
    li   x20, 0
    li   x22, 1                # THREAD_A's own bounds_ok marker, starts true

    # SSC-MILESTONE: bind Object_ID=123 into SSC. c1 (sealed DATA_A) is
    # the discard destination -- genuinely dead here, only consumed by
    # the already-succeeded first ocinvoke above (matches the Sail
    # side's own identically-reasoned choice, NOT c9, which is the
    # scheduler's own live return-sentry source register).
    li   x1, 123
    li   x2, 0x8017100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 123
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    .insn r 0x5b, 0x1, 0x13, x1, x2, x2  # ospecialrw c1(discard), ssc, c2  -- SSC := c2 (real, tagged)

thread_a_loop:
    addi x20, x20, 1
    li   x25, 2
    bne  x20, x25, thread_a_skip_check
    csrr x23, 0x7c0
    la   x24, thread_a_entry
    bne  x23, x24, thread_a_bounds_bad
    csrr x23, 0x7c1
    li   x24, 0x0100
    beq  x23, x24, thread_a_skip_check
thread_a_bounds_bad:
    li   x22, 0
thread_a_skip_check:
    ecall
    j    thread_a_loop

.balign 4
thread_b_entry:
    li   x21, 0
    li   x26, 1                # THREAD_B's own bounds_ok marker, starts true

    # SSC-MILESTONE: read SSC back via c14 (genuinely untagged, from its
    # one-time TSC-priming use above) into c13 (transient, dead after
    # setup). x19 is a fresh register, never otherwise touched, so it
    # survives to final_check unmodified.
    .insn r 0x5b, 0x1, 0x13, x13, x14, x2  # ospecialrw c13, ssc, c14  -- c13 = SSC's OLD value
    .insn r 0x5b, 0x0, 0x03, x19, x13, x0  # cgettag x19, c13  -- expect 0: THREAD_A's SSC never leaked here

thread_b_loop:
    addi x21, x21, 1
    li   x25, 2
    bne  x21, x25, thread_b_skip_check
    csrr x23, 0x7c0
    la   x24, thread_b_entry
    bne  x23, x24, thread_b_bounds_bad
    csrr x23, 0x7c1
    li   x24, 0x0100
    beq  x23, x24, thread_b_skip_check
thread_b_bounds_bad:
    li   x26, 0
thread_b_skip_check:
    ecall
    j    thread_b_loop

.balign 4
scheduler_entry:
    li   x23, 0
    .insn r 0x0b, 0x3, 0x00, x24, x8, x23  # ocl.d c8, x23(=0), x24  -- load thread_index
    xori x24, x24, 1
    .insn r 0x0b, 0x3, 0x01, x24, x8, x23  # ocs.d c8, x23(=0), x24  -- store toggled thread_index
    .insn r 0x5b, 0x1, 0x16, x0, x10, x0   # ocreturn c10
    j    fail_halt                          # must NOT be reached

.balign 4
switcher_entry:
    csrr x28, mcause
    li   x29, 11
    bne  x28, x29, fail_halt

    csrr x28, mepc
    addi x28, x28, 4
    csrr x29, 0x7c2             # veda_mepcc_base
    csrr x30, 0x7c3             # veda_mepcc_length

    la   x5, thread_index
    lw   x6, 0(x5)
    bnez x6, yielding_is_b
yielding_is_a:
    li   x5, 0
    .insn r 0x0b, 0x3, 0x01, x28, x6, x5  # ocs.d c6, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x01, x29, x6, x5  # ocs.d c6, x5(=8), x29
    li   x5, 16
    .insn r 0x0b, 0x3, 0x01, x30, x6, x5  # ocs.d c6, x5(=16), x30
    j    invoke_scheduler
yielding_is_b:
    li   x5, 0
    .insn r 0x0b, 0x3, 0x01, x28, x7, x5  # ocs.d c7, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x01, x29, x7, x5  # ocs.d c7, x5(=8), x29
    li   x5, 16
    .insn r 0x0b, 0x3, 0x01, x30, x7, x5  # ocs.d c7, x5(=16), x30

invoke_scheduler:
    la   x5, yield_count
    lw   x6, 0(x5)
    addi x6, x6, 1
    sw   x6, 0(x5)
    li   x27, 4
    beq  x6, x27, final_check

    .insn r 0x5b, 0x1, 0x15, x10, x9, x0  # csealentry c10, c9  -- mint fresh return sentry
    .insn r 0x5b, 0x1, 0x12, x0, x4, x5   # ocinvoke c4, c5     -- invoke SCHEDULER
    j    fail_halt                          # must NOT be reached (scheduler must OCRETURN)

.balign 4
after_scheduler_return:
    la   x5, thread_index
    lw   x6, 0(x5)
    bnez x6, resume_b
resume_a:
    .insn r 0x5b, 0x1, 0x13, x12, x6, x1  # ospecialrw c12, tsc, c6
    .insn r 0x5b, 0x0, 0x00, x31, x12, x0 # cgetbase x31, c12
    la   x27, save_area_b
    beq  x31, x27, resume_a_tsc_ok
    la   x5, tsc_ok
    sd   x0, 0(x5)
resume_a_tsc_ok:
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x6, x5  # ocl.d c6, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x6, x5  # ocl.d c6, x5(=8), x29
    li   x1, 110
    .insn i 0x0b, 0x5, x11, x1, 0         # veda.bind c11, x1
    j    do_resume
resume_b:
    .insn r 0x5b, 0x1, 0x13, x12, x7, x1  # ospecialrw c12, tsc, c7
    .insn r 0x5b, 0x0, 0x00, x31, x12, x0 # cgetbase x31, c12
    la   x27, save_area_a
    beq  x31, x27, resume_b_tsc_ok
    la   x5, tsc_ok
    sd   x0, 0(x5)
resume_b_tsc_ok:
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x7, x5  # ocl.d c7, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x7, x5  # ocl.d c7, x5(=8), x29
    li   x1, 113
    .insn i 0x0b, 0x5, x11, x1, 0         # veda.bind c11, x1

do_resume:
    sub  x31, x28, x29
    .insn r 0x5b, 0x1, 0x0a, x11, x11, x31  # oca c11, c11, x31
    .insn r 0x5b, 0x1, 0x15, x11, x11, x0   # csealentry c11, c11
    .insn r 0x5b, 0x1, 0x16, x0, x11, x0    # ocreturn c11
    j    fail_halt

.balign 4
final_check:
    li   x27, 2
    bne  x20, x27, fail_halt      # THREAD_A ran its own increment exactly twice
    bne  x21, x27, fail_halt      # THREAD_B likewise
    li   x27, 1
    bne  x22, x27, fail_halt      # THREAD_A's own bounds fidelity held
    bne  x26, x27, fail_halt      # THREAD_B's own bounds fidelity held
    la   x5, tsc_ok
    ld   x9, 0(x5)
    li   x5, 1
    bne  x9, x5, fail_halt        # TSC round-trip fidelity held every cycle
    li   x5, 0
    bne  x19, x5, fail_halt       # SSC-MILESTONE: THREAD_B genuinely never saw THREAD_A's SSC

    li   x27, 0x600D              # sentinel: all checks passed
    j    done
fail_halt:
    li   x27, 0xDEAD
done:
1:
    j 1b

.section .data
.align 3
save_area_a:
    .dword 0
    .dword 0
    .dword 0
save_area_b:
    .dword 0
    .dword 0
    .dword 0
thread_index:
    .dword 0
yield_count:
    .dword 0
tsc_ok:
    .dword 0
