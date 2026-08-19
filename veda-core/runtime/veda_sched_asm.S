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
    # Length=0x0040 (64): 24B PC/base/length (unchanged) + 8B padding to a
    # 32B boundary + 17B table-base-capability slot (post-widening,
    # 2026-08-19) + 7B trailing padding to a clean 64B object (CRF
    # -exhaustion fix, TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md +
    # TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md). Toolchain Milestone
    # 21-fix: was Length=0x0030 (48)/16B-aligned slot, sized for the
    # pre-widening 16-byte OCS.C/OCL.C width -- offset(32)+width(17)=49 >
    # 48 overflowed the object by 1 byte (real VEDA_CAUSE_BOUNDS_VIOLATION,
    # confirmed via sail_riscv_sim trace). Grown to 64B and the capability
    # slot's own physical alignment requirement raised from 16B to 32B
    # (this file's own `.align 4`->`.align 5` on save_area_0 below) to
    # satisfy OCL.C/OCS.C's new post-widening 32-byte alignment gate.
    la   t0, save_area_0
    slli t0, t0, 32
    li   t1, 0x0040000C
    or   t0, t0, t1
    li   a0, 165
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0
    li   a0, 165
    .insn i 0x0b, 0x5, x6, a0, 0   # veda.bind c6, a0

    # ---- save-area-1: Object_ID 166, Load|Store, permanent bind c7 ----
    # Toolchain Milestone 21-fix -- identical reasoning as save_area_0
    # above (Length 0x0030->0x0040, capability slot now 32B-aligned).
    la   t0, save_area_1
    slli t0, t0, 32
    li   t1, 0x0040000C
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

    # ---- return-sentry SOURCE: Object_ID 168, Length=0xFFFFF(unbounded), Execute ----
    # Toolchain Milestone 21-fix (2026-08-19 Length/Offset widening,
    # commit 9de3742, moved VEDA_PCC_UNBOUNDED from 16-bit 0xFFFF to
    # 20-bit 0xFFFFF): this sentry is later consumed via OCRETURN
    # (`ocreturn c10` below), which narrows veda_pcc_length = cs1.Length
    # exactly like OCInvoke does -- so a still-16-bit Length=0xFFFF here
    # is a real, latent instance of the identical bug
    # veda_alloca_protect_entry.S's own exit ceremony had, not yet
    # observed only because an earlier, unrelated bounds violation
    # (this same file's save-area capability-slot pre-population,
    # see TOOLCHAIN_MILESTONE_21_TOOLCHAIN_WIDENING_PARITY_RESULTS.md)
    # traps first. Plain VEDA_ODT_POPULATE's Length field stays
    # permanently 16-bit-capped by design, so this must use
    # VEDA_ODT_POPULATE_FAST + veda_attr instead.
    li   t1, 0xFFFFF0002   # veda_attr: Length=0xFFFFF (unbounded), Perms=Execute
    csrw 0x7c4, t1
    la   t0, after_scheduler_return
    li   a0, 168
    .insn r 0x0b, 0x0, 0x04, x5, a0, t0   # veda.odt.populate.fast x5, a0, t0
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

    # ---- pre-populate BOTH save-areas' new capability slot (offset 32)
    #      with the caller's own already-bound c11 (the persistent
    #      globals table-base capability, established by the entry
    #      point's own bootstrap ceremony before this function is called).
    #      Without this, resume_0/resume_1's FIRST-EVER call (before any
    #      real yield has happened) would ocl.c-read the still-zeroed,
    #      untagged region and corrupt c11 on the thread's very first
    #      entry -- the same class of bug the PC/base/length
    #      pre-population above already exists to avoid. See
    #      TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md. ----
    li   x5, 32
    .insn r 0x0b, 0x4, 0x01, x11, x6, x5  # ocs.c c6, x5(=32), c11
    li   x5, 32
    .insn r 0x0b, 0x4, 0x01, x11, x7, x5  # ocs.c c7, x5(=32), c11

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
    li   x5, 32
    .insn r 0x0b, 0x4, 0x01, x11, x6, x5  # ocs.c c6, x5(=32), c11 -- spill globals table-base cap
    j    invoke_scheduler
yielding_is_1:
    li   x5, 0
    .insn r 0x0b, 0x3, 0x01, x28, x7, x5  # ocs.d c7, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x01, x29, x7, x5  # ocs.d c7, x5(=8), x29
    li   x5, 16
    .insn r 0x0b, 0x3, 0x01, x30, x7, x5  # ocs.d c7, x5(=16), x30
    li   x5, 32
    .insn r 0x0b, 0x4, 0x01, x11, x7, x5  # ocs.c c7, x5(=32), c11 -- spill globals table-base cap

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
                                           # (c12's own discard value is dead
                                           # here -- reused below as the
                                           # resume-jump scratch, see do_resume)
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x6, x5  # ocl.d c6, x5(=0), x28  -- slot0's saved PC
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x6, x5  # ocl.d c6, x5(=8), x29  -- slot0's saved base
    li   x5, 32
    .insn r 0x0b, 0x4, 0x00, x11, x6, x5  # ocl.c c6, x5(=32), c11 -- restore globals table-base cap
    li   a0, 160
    .insn i 0x0b, 0x5, x12, a0, 0         # veda.bind c12, a0  -- FRESH CODE_0, Offset=0
    j    do_resume
resume_1:
    .insn r 0x5b, 0x1, 0x13, x12, x7, x1  # ospecialrw c12(discard), tsc, c7 -- rs2=x1 selects TSC
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x7, x5  # ocl.d c7, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x7, x5  # ocl.d c7, x5(=8), x29
    li   x5, 32
    .insn r 0x0b, 0x4, 0x00, x11, x7, x5  # ocl.c c7, x5(=32), c11 -- restore globals table-base cap
    li   a0, 161
    .insn i 0x0b, 0x5, x12, a0, 0         # veda.bind c12, a0  -- FRESH CODE_1, Offset=0

do_resume:
    # Atomic restore: freshly re-bind the chosen thread's own CODE
    # Object_ID (Offset=0), OCA its Offset to the true resume point
    # (delta = saved_pc - saved_base -- exactly 0 on a thread's own
    # first-ever entry, since save_area was pre-populated with pc=base),
    # mint a sentry, OCRETURN through it -- narrowing PCC AND jumping in
    # the SAME instruction, never a separate csrw+mret (confirmed unsafe
    # on the Sail side: mret itself would be fetched from OUTSIDE the
    # just-narrowed target's bounds).
    #
    # CRF-EXHAUSTION FIX (TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md):
    # this resume-jump scratch role now uses c12, not c11 -- c12 is a
    # proven, definitionally-dead OSpecialRW discard-sink everywhere else
    # in this file (its written value is never read by anything), so
    # reusing it here creates zero cross-file collision with
    # runtime/veda_rt_asm.S's own Milestone-13 use of c10/c11. c11 is now
    # EXCLUSIVELY the persistent globals table-base capability (spilled/
    # restored above, alongside PC/base/length, never repurposed here),
    # matching the same permanent-register discipline c6/c7/c8/c9 already
    # have.
    sub  x31, x28, x29                      # delta = saved_pc - saved_base
    .insn r 0x5b, 0x1, 0x0a, x12, x12, x31  # oca c12, c12, x31    -- c12.Offset := delta
    .insn r 0x5b, 0x1, 0x15, x12, x12, x0   # csealentry c12, c12 -- mint sentry in place
    .insn r 0x5b, 0x1, 0x16, x0, x12, x0    # ocreturn c12        -- atomically narrow + jump
    j    switcher_entry                       # must NOT be reached

    # MILESTONE 24 Stage 3 (original): save_area_0/save_area_1 were moved
    # into .tcm_scratch (veda_rt.ld's own TCM_SCRATCH_BASE=0xA0000000
    # region, backed by veda_core.tlv's own tcm_scratch[]/tcm_scratch_tag[]
    # arrays) for a hypothetical future OCL.C/OCS.C-width save -- at the
    # time, save_area_0/1 held only plain OCL.D/OCS.D fields (PC/base/
    # length), which never stalled here regardless of placement (M24's
    # own honest note: "this relocation currently changes zero stall
    # cycles for the scheduler's real yield/resume path").
    #
    # REVERTED to ordinary .data (TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md),
    # a real, empirically-found correction, not a stylistic choice: this
    # file (runtime/veda_sched_asm.S) is TOOLCHAIN-LAYER, Sail-only --
    # verified exclusively via sail_riscv_sim, with no RTL mirror of any
    # kind (the RTL scheduler test, rtl/sim/veda_smoke_m23_scheduler.S, is
    # a wholly separate file/context this one never touches). The Sail
    # model has ZERO TCM concept by design (confirmed repeatedly across
    # this project: Sail is a purely functional/architectural model, the
    # DRAM-latency/TCM stall FSM is 100% RTL-only) -- and a direct,
    # isolated empirical test this session
    # (sail_tests/vc_debug_ocsc_roundtrip.S, bind-then-OCS.C-then-OCL.C on
    # a plain capability, no scheduler involved) proved Sail's own
    # tag-storage does NOT correctly round-trip a capability's tag through
    # a .tcm_scratch/0xA0000000-placed address (PASSES at an ordinary
    # .data address; FAILS with VEDA_CAUSE_TAG_VIOLATION, mtval packing
    # cap_idx=1/cause=0x02, at 0xA0000000 -- same failure this fix's own
    # new capability-slot save/restore hit before this correction). Since
    # this file only ever executes under Sail, .tcm_scratch placement here
    # provides no real benefit and actively breaks the new capability
    # slot -- moved the WHOLE save_area_0/1 struct back to .data (not just
    # the new slot) so both remain reachable through the SAME c6/c7
    # capability, avoiding a third Object_ID/CRF-register claim.
    #
    # CRF-EXHAUSTION FIX (TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md):
    # each save-area grows from 24 to 48 bytes -- the original 3
    # `.dword`s (saved PC/base/length, offsets 0/8/16) are UNCHANGED;
    # offset 24-31 is 8 bytes of padding, purely to push the new
    # capability slot onto a 16-byte boundary (Veda-Core's tag-storage
    # granule is (addr-BASE)>>4, confirmed in rtl/veda_core.tlv -- an RTL
    # concept, kept here purely as good hygiene for a future RTL mirror,
    # not because Sail itself requires 16-byte alignment); offset 32-47 is
    # the new 16-byte slot holding the spilled/restored globals table-base
    # capability (c11). `.align 3`->`.align 4` (8B->16B) guarantees offset
    # 32 is genuinely 16-byte-aligned relative to the real linked address,
    # not just the symbol-relative offset. The other five symbols below
    # (thread_index/yield_count/yield_limit/saved_ra/saved_sp) are plain
    # scalar state, not on this hot spill path, and already lived in
    # ordinary .data.
.section .data
# Toolchain Milestone 21-fix (2026-08-19 Length/Offset widening):
# `.align 4` (16B) -> `.align 5` (32B) so the capability slot at offset 32
# below lands on a genuinely 32-byte-aligned physical address, satisfying
# OCL.C/OCS.C's new post-widening alignment gate (real hardware/Sail
# requirement, not just hygiene, unlike the pre-widening 16B comment this
# replaces).
.align 5
save_area_0:
    .dword 0
    .dword 0
    .dword 0
    .dword 0   # offset 24-31: padding to the 32-byte-aligned capability slot
    .dword 0   # offset 32-39: globals table-base capability (low 8B)
    .dword 0   # offset 40-47: globals table-base capability (mid 8B)
    .dword 0   # offset 48-55: globals table-base capability (high 1B + 7B unused)
    .dword 0   # offset 56-63: trailing padding to a clean 64B object
save_area_1:
    .dword 0
    .dword 0
    .dword 0
    .dword 0   # offset 24-31: padding
    .dword 0   # offset 32-39: globals table-base capability (low 8B)
    .dword 0   # offset 40-47: globals table-base capability (mid 8B)
    .dword 0   # offset 48-55: globals table-base capability (high 1B + 7B unused)
    .dword 0   # offset 56-63: trailing padding to a clean 64B object

.section .data
.align 3
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
