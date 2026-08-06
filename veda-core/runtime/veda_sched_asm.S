# Veda-Core cooperative-scheduler C API: ISA-level mechanism.
#
# Every Veda-Core custom instruction here uses the identical raw `.insn`
# encoding already proven in sail_tests/vc_scheduler_cooperative_yield.S
# and rtl/sim/veda_smoke_m23_scheduler.S -- deliberately NOT the named
# LLVM mnemonics for csealentry/ocreturn (neither has MC-layer support at
# all -- confirmed by exhaustively listing every mnemonic in
# RISCVInstrInfoXVeda.td) or for the TSC-selector form of ospecialrw
# (the named mnemonic hardwires rs2=0, the ODA-only selector). Rather than
# mix named mnemonics for the rest with raw .insn for these three, every
# Veda-Core instruction here uses raw .insn uniformly, for consistency
# with the two already-proven test files this is a direct port of.
#
# Design simplification found during implementation (not in the original
# hand-assembled tests, which always gave each thread its own CODE+DATA+
# type-authority trio): a thread here is entered exclusively through the
# atomic OCA+CSealEntry+OCRETURN resume path (unified for both its very
# first entry and every subsequent resume -- see veda_sched_run_asm),
# never through OCInvoke. OCRETURN's own real violation check
# (veda_core.tlv: !tag || !sealed || otype!=0xFFFE || !perms[1]) needs
# only a sealed-as-sentry, Execute-permitted capability -- no DATA
# capability, no type-authority object, no CSeal at all (CSealEntry mints
# a sentry with no authorizing capability). Only SCHEDULER, which IS
# entered via real OCInvoke, needs a true sealed CODE+DATA pair from a
# real type-authority. This cuts thread setup from 3 Object_IDs each to 1.
#
# Object_IDs 160-168 (9 total), personally grepped fresh against every
# existing sail_tests/*.S and rtl/sim/*.S file before picking -- confirmed
# collision-free.
#   160 = THREAD0 CODE (Execute only)      164 = SCHEDULER type-authority
#   161 = THREAD1 CODE (Execute only)      165 = save-area-0
#   162 = SCHEDULER CODE                   166 = save-area-1
#   163 = SCHEDULER DATA                   167 = thread_index
#                                           168 = return-sentry-source

.section .text

# void veda_sched_init_asm(uint64_t entry0 /*a0*/, uint64_t len0 /*a1*/,
#                           uint64_t entry1 /*a2*/, uint64_t len1 /*a3*/)
.global veda_sched_init_asm
veda_sched_init_asm:
    mv   t3, a0   # entry0
    mv   t4, a1   # len0
    mv   t5, a2   # entry1
    mv   t6, a3   # len1

    # ---- THREAD0 CODE: Object_ID 160, Perms=Execute(0x0002) ----
    slli t0, t3, 32
    slli t1, t4, 16
    li   t2, 0x0002
    or   t1, t1, t2
    or   t0, t0, t1
    li   a0, 160
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0

    # ---- THREAD1 CODE: Object_ID 161, Perms=Execute(0x0002) ----
    slli t0, t5, 32
    slli t1, t6, 16
    li   t2, 0x0002
    or   t1, t1, t2
    or   t0, t0, t1
    li   a0, 161
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0

    # ---- SCHEDULER: Object_ID 162(CODE)/163(DATA)/164(type-authority) ----
    la   t0, scheduler_entry
    slli t0, t0, 32
    li   t1, 0x01000402        # Length=0x0100, Perms=Execute|Invoke
    or   t0, t0, t1
    li   a0, 162
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0

    li   a0, 163
    li   t1, 0x8020000000400400            # Perms=Permit_Invoke only
    .insn r 0x0b, 0x0, 0x03, x5, a0, t1   # veda.odt.populate x5, a0,t1

    li   a0, 164
    li   t1, 0x8020010000400300            # Perms=Seal|Unseal
    .insn r 0x0b, 0x0, 0x03, x5, a0, t1   # veda.odt.populate x5, a0,t1

    li   a0, 162
    .insn i 0x0b, 0x5, x4, a0, 0   # veda.bind c4, a0  -- CODE_SCHED unsealed
    li   a0, 163
    .insn i 0x0b, 0x5, x5, a0, 0   # veda.bind c5, a0  -- DATA_SCHED unsealed
    li   a0, 164
    .insn i 0x0b, 0x5, x13, a0, 0  # veda.bind c13, a0 -- type authority (transient)

    .insn r 0x5b, 0x1, 0x10, x4, x4, x13  # cseal c4, c4, c13  -- sealed CODE_SCHED
    .insn r 0x5b, 0x1, 0x10, x5, x5, x13  # cseal c5, c5, c13  -- sealed DATA_SCHED

    # ---- save-area-0: Object_ID 165, Load|Store, permanent bind c6 ----
    la   t0, save_area_0
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   a0, 165
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0
    li   a0, 165
    .insn i 0x0b, 0x5, x6, a0, 0   # veda.bind c6, a0

    # ---- save-area-1: Object_ID 166, Load|Store, permanent bind c7 ----
    la   t0, save_area_1
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   a0, 166
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0
    li   a0, 166
    .insn i 0x0b, 0x5, x7, a0, 0   # veda.bind c7, a0

    # ---- thread_index: Object_ID 167, Load|Store, permanent bind c8 ----
    la   t0, thread_index
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   a0, 167
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0
    li   a0, 167
    .insn i 0x0b, 0x5, x8, a0, 0   # veda.bind c8, a0

    # ---- return-sentry SOURCE: Object_ID 168, Length=0xFFFF(unbounded), Execute ----
    la   t0, after_scheduler_return
    slli t0, t0, 32
    li   t1, 0xFFFF0002
    or   t0, t0, t1
    li   a0, 168
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0
    li   a0, 168
    .insn i 0x0b, 0x5, x9, a0, 0   # veda.bind c9, a0

    # ---- pre-populate BOTH threads' own save areas with their true entry
    #      state (pc=base=entry, length=code_length) -- thread 0's "first
    #      entry" and every later resume both go through the identical
    #      do_resume path in veda_sched_run_asm, so thread 0 needs the
    #      same bootstrap pre-population thread B needed in the original
    #      hand-assembled test. ----
    li   x5, 0
    .insn r 0x0b, 0x3, 0x01, t3, x6, x5  # ocs.d c6, x5(=0), t3(entry0)
    li   x5, 8
    .insn r 0x0b, 0x3, 0x01, t3, x6, x5  # ocs.d c6, x5(=8), t3(entry0 again = base)
    li   x5, 16
    .insn r 0x0b, 0x3, 0x01, t4, x6, x5  # ocs.d c6, x5(=16), t4(len0)

    li   x5, 0
    .insn r 0x0b, 0x3, 0x01, t5, x7, x5  # ocs.d c7, x5(=0), t5(entry1)
    li   x5, 8
    .insn r 0x0b, 0x3, 0x01, t5, x7, x5  # ocs.d c7, x5(=8), t5(entry1 again = base)
    li   x5, 16
    .insn r 0x0b, 0x3, 0x01, t6, x7, x5  # ocs.d c7, x5(=16), t6(len1)

    # ---- init thread_index=0, yield_count=0 ----
    la   x5, thread_index
    sd   x0, 0(x5)
    la   x5, yield_count
    sd   x0, 0(x5)
    ret

# uint32_t veda_sched_run_asm(uint32_t max_yields /*a0*/)
.global veda_sched_run_asm
veda_sched_run_asm:
    la   t0, yield_limit
    sw   a0, 0(t0)

    # Save the real C-level return context -- once we OCReturn into
    # thread 0, control only ever comes back via a trap, never a `ret`;
    # the switcher restores these when yield_limit is reached.
    la   t0, saved_ra
    sd   ra, 0(t0)
    la   t0, saved_sp
    sd   sp, 0(t0)

    la   t0, switcher_entry
    csrw mtvec, t0

    # Prime TSC := save-area-0 (thread 0 runs first)
    .insn r 0x5b, 0x1, 0x13, x14, x6, x1  # ospecialrw c14(discard), tsc, c6
                                           # -- rs2=x1 selects TSC (index=1
                                           # IS the selector value, never a
                                           # GPR read -- must stay x1, not a0

    # Unified first-entry: identical path as every later resume of slot 0.
    li   x5, 0
    la   x27, thread_index
    sw   x5, 0(x27)
    j    resume_0

# ─────────────────────────────────────────────────────────────
#  SCHEDULER -- OCInvoke-entered, round-robin toggle via OCL.D/OCS.D
#  (ordinary lw/sw is blocked inside this live compartment), returns via
#  a raw-.insn OCRETURN through the switcher-minted sentry (c10).
# ─────────────────────────────────────────────────────────────
.balign 4
scheduler_entry:
    li   x23, 0
    .insn r 0x0b, 0x3, 0x00, x24, x8, x23  # ocl.d c8, x23(=0), x24  -- load thread_index
    xori x24, x24, 1
    .insn r 0x0b, 0x3, 0x01, x24, x8, x23  # ocs.d c8, x23(=0), x24  -- store toggled thread_index
    .insn r 0x5b, 0x1, 0x16, x0, x10, x0   # ocreturn c10
    j    scheduler_entry                     # must NOT be reached

# ─────────────────────────────────────────────────────────────
#  SWITCHER -- mtvec's own target, runs fully unbounded by construction.
# ─────────────────────────────────────────────────────────────
.balign 4
switcher_entry:
    csrr x28, mcause
    li   x29, 11
    bne  x28, x29, switcher_entry            # not our ecall -- ignore (real fault
                                              # recovery out of scope this pass)

    csrr x28, mepc
    addi x28, x28, 4
    csrr x29, 0x7c2             # veda_mepcc_base
    csrr x30, 0x7c3             # veda_mepcc_length

    la   x5, thread_index
    lw   x6, 0(x5)
    bnez x6, yielding_is_1
yielding_is_0:
    li   x5, 0
    .insn r 0x0b, 0x3, 0x01, x28, x6, x5  # ocs.d c6, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x01, x29, x6, x5  # ocs.d c6, x5(=8), x29
    li   x5, 16
    .insn r 0x0b, 0x3, 0x01, x30, x6, x5  # ocs.d c6, x5(=16), x30
    j    invoke_scheduler
yielding_is_1:
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
    la   x27, yield_limit
    lw   x27, 0(x27)
    beq  x6, x27, return_to_caller

    .insn r 0x5b, 0x1, 0x15, x10, x9, x0  # csealentry c10, c9  -- mint fresh return sentry
    .insn r 0x5b, 0x1, 0x12, x0, x4, x5   # ocinvoke c4, c5     -- invoke SCHEDULER
    j    switcher_entry                     # must NOT be reached (scheduler must OCRETURN)

return_to_caller:
    la   t0, saved_ra
    ld   ra, 0(t0)
    la   t0, saved_sp
    ld   sp, 0(t0)
    mv   a0, x6                              # a0 := final yield count
    ret

.balign 4
after_scheduler_return:
    la   x5, thread_index
    lw   x6, 0(x5)
    bnez x6, resume_1
resume_0:
    .insn r 0x5b, 0x1, 0x13, x12, x6, x1  # ospecialrw c12(discard), tsc, c6 -- rs2=x1 selects TSC
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x6, x5  # ocl.d c6, x5(=0), x28  -- slot0's saved PC
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x6, x5  # ocl.d c6, x5(=8), x29  -- slot0's saved base
    li   a0, 160
    .insn i 0x0b, 0x5, x11, a0, 0         # veda.bind c11, a0  -- FRESH CODE_0, Offset=0
    j    do_resume
resume_1:
    .insn r 0x5b, 0x1, 0x13, x12, x7, x1  # ospecialrw c12(discard), tsc, c7 -- rs2=x1 selects TSC
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x7, x5  # ocl.d c7, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x7, x5  # ocl.d c7, x5(=8), x29
    li   a0, 161
    .insn i 0x0b, 0x5, x11, a0, 0         # veda.bind c11, a0  -- FRESH CODE_1, Offset=0

do_resume:
    # Atomic restore: freshly re-bind the chosen thread's own CODE
    # Object_ID (Offset=0), OCA its Offset to the true resume point
    # (delta = saved_pc - saved_base -- exactly 0 on a thread's own
    # first-ever entry, since save_area was pre-populated with pc=base),
    # mint a sentry, OCRETURN through it -- narrowing PCC AND jumping in
    # the SAME instruction, never a separate csrw+mret (confirmed unsafe
    # on the Sail side: mret itself would be fetched from OUTSIDE the
    # just-narrowed target's bounds).
    sub  x31, x28, x29                      # delta = saved_pc - saved_base
    .insn r 0x5b, 0x1, 0x0a, x11, x11, x31  # oca c11, c11, x31    -- c11.Offset := delta
    .insn r 0x5b, 0x1, 0x15, x11, x11, x0   # csealentry c11, c11 -- mint sentry in place
    .insn r 0x5b, 0x1, 0x16, x0, x11, x0    # ocreturn c11        -- atomically narrow + jump
    j    switcher_entry                       # must NOT be reached

.section .data
.align 3
save_area_0:
    .dword 0
    .dword 0
    .dword 0
save_area_1:
    .dword 0
    .dword 0
    .dword 0
thread_index:
    .dword 0
yield_count:
    .dword 0
yield_limit:
    .dword 0
saved_ra:
    .dword 0
saved_sp:
    .dword 0
