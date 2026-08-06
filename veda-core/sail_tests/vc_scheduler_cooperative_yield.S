.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone C (MINIMAL_OS_KERNEL_MILESTONE_C_RESULTS.md): a real,
    # two-thread cooperative round-robin scheduler, proving Milestones A (TSC,
    # OSpecialRW selector) and B (CSealEntry, OCRETURN) compose into the actual
    # OS pattern this whole initiative is named for -- not a new instruction, a pure
    # software-integration test of already-proven primitives. Grounded in a complete
    # re-read of CHERIoT RTOS's own architecture.md (all 109 lines): the switcher
    # "is responsible for all cross-compartment and cross-thread transitions... uses
    # [Access_System_Registers] to store a capability to the current thread's trusted
    # stack and register-save area in the mtdc capability special register" (the real
    # register Veda-Core's own TSC is modeled on); "yielding is implemented with the
    # mcall instruction, which enters the switcher and then invokes the scheduler's
    # interrupt entry point" (Veda-Core has no mcall; ordinary ecall is used instead,
    # already proven to correctly reach a handler outside a live compartment via
    # Milestone 21's own universal PCC reset on any trap); "the scheduler... is just a
    # compartment... not more privileged than the threads it schedules."
    #
    # Four compartments: THREAD_A / THREAD_B (each an independent OCInvoke-entered
    # compartment looping "increment my own counter, yield"), SWITCHER (mtvec's own
    # target, runs fully unbounded by construction -- Milestone 20's own CSR gate
    # requires veda_pcc_length==UNBOUNDED before veda_pcc_base/_length/veda_mepcc_*
    # can be written at all, which this design depends on; matches the real text's
    # own "the switcher is the most privileged component" exactly), SCHEDULER
    # (OCInvoke-entered by the switcher, decides round-robin, returns via OCRETURN
    # through a switcher-minted sentry -- the exact pattern already proven in
    # vc_switcher_register_clear_fast_return.S, now given a real, non-synthetic job).
    #
    # TSC used for real for the first time in this project: always holds a capability
    # describing the CURRENTLY RUNNING thread's own save-area block. The switcher
    # swaps it (via OSpecialRW) to the newly-chosen thread's own save-area capability
    # as part of every switch, mirroring CHERIoT's real "swap mtdc" step precisely --
    # not used for addressing in this pass (that's done via c6/c7 directly, chosen
    # from thread_index), but genuinely, verifiably updated every cycle (see the
    # tsc_ok check below), the single real consumer of TSC in this whole project.
    #
    # GPR scope, stated explicitly: each thread's only relied-upon persistent state
    # across a yield is its own counter (x20 for THREAD_A, x21 for THREAD_B) plus
    # mepc/PCC-bounds, restored explicitly by the switcher below. Scratch temporaries
    # are never assumed to survive a yield by either thread -- ordinary calling-
    # convention discipline, not a new mechanism. Full GPR context-save is a real,
    # named, later refinement, not silently dropped.
    la   t0, switcher_entry
    csrw mtvec, t0

    # ══════════════ THREAD_A: Object_ID 100(CODE)/101(DATA)/102(type-authority) ══════════════
    la   t0, thread_a_entry
    slli t0, t0, 32
    li   t1, 0x01000402        # Length=0x0100, Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 100
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- CODE_A

    li   x1, 101
    li   x2, 0x8010070000400400            # Perms=Permit_Invoke only
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- DATA_A

    li   x1, 102
    li   x2, 0x8010080000400300            # Perms=Seal|Unseal
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- type authority A

    li   x1, 100
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1  -- CODE_A unsealed
    li   x1, 101
    .insn i 0x0b, 0x5, x1, x1, 0   # veda.bind c1, x1  -- DATA_A unsealed
    li   x1, 102
    .insn i 0x0b, 0x5, x13, x1, 0  # veda.bind c13, x1 -- type authority A (transient)

    .insn r 0x5b, 0x1, 0x10, x0, x0, x13  # cseal c0, c0, c13  -- sealed CODE_A
    .insn r 0x5b, 0x1, 0x10, x1, x1, x13  # cseal c1, c1, c13  -- sealed DATA_A

    # ══════════════ THREAD_B: Object_ID 110/111/112 ══════════════
    la   t0, thread_b_entry
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 110
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- CODE_B

    li   x1, 111
    li   x2, 0x8011070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- DATA_B

    li   x1, 112
    li   x2, 0x8011080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- type authority B

    li   x1, 110
    .insn i 0x0b, 0x5, x2, x1, 0   # veda.bind c2, x1  -- CODE_B unsealed
    li   x1, 111
    .insn i 0x0b, 0x5, x3, x1, 0   # veda.bind c3, x1  -- DATA_B unsealed
    li   x1, 112
    .insn i 0x0b, 0x5, x13, x1, 0  # veda.bind c13, x1 -- type authority B (transient)

    .insn r 0x5b, 0x1, 0x10, x2, x2, x13  # cseal c2, c2, c13  -- sealed CODE_B
    .insn r 0x5b, 0x1, 0x10, x3, x3, x13  # cseal c3, c3, c13  -- sealed DATA_B

    # ══════════════ SCHEDULER: Object_ID 120/121/122 ══════════════
    la   t0, scheduler_entry
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 120
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- CODE_SCHED

    li   x1, 121
    li   x2, 0x8012070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- DATA_SCHED

    li   x1, 122
    li   x2, 0x8012080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- type authority SCHED

    li   x1, 120
    .insn i 0x0b, 0x5, x4, x1, 0   # veda.bind c4, x1  -- CODE_SCHED unsealed
    li   x1, 121
    .insn i 0x0b, 0x5, x5, x1, 0   # veda.bind c5, x1  -- DATA_SCHED unsealed
    li   x1, 122
    .insn i 0x0b, 0x5, x13, x1, 0  # veda.bind c13, x1 -- type authority SCHED (transient)

    .insn r 0x5b, 0x1, 0x10, x4, x4, x13  # cseal c4, c4, c13  -- sealed CODE_SCHED
    .insn r 0x5b, 0x1, 0x10, x5, x5, x13  # cseal c5, c5, c13  -- sealed DATA_SCHED

    # ══════════════ save-area-A: Object_ID 140 (Base=save_area_a, Length=0x20, Load|Store) ══════════════
    la   t0, save_area_a
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   x1, 140
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- save-area-A

    li   x1, 140
    .insn i 0x0b, 0x5, x6, x1, 0   # veda.bind c6, x1  -- save-area-A, unsealed (permanent)

    # ══════════════ save-area-B: Object_ID 141 ══════════════
    la   t0, save_area_b
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   x1, 141
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- save-area-B

    li   x1, 141
    .insn i 0x0b, 0x5, x7, x1, 0   # veda.bind c7, x1  -- save-area-B, unsealed (permanent)

    # ══════════════ thread_index capability: Object_ID 150 (Load|Store) ══════════════
    # Real, empirically-confirmed constraint (ext_data_get_addr,
    # postlude/step_ext.sail): ANY ordinary load/store while running inside a
    # live, narrowed compartment (veda_pcc_length != UNBOUNDED) is blocked --
    # a deliberate Milestone 19 security property ("compartmentalized code
    # could still issue an ordinary LOAD/STORE to read/write memory anywhere
    # -- undermining the isolation OCInvoke/PCC-bounding is meant to
    # provide"), NOT specific to the veda_purecap CSR bit (this test never
    # sets it). The SWITCHER runs unbounded so its own ordinary ld/sd/lw/sw
    # to scratch memory are fine; the SCHEDULER runs inside its own
    # OCInvoke-narrowed bounds and therefore MUST use Veda's own capability-
    # checked OCL.D/OCS.D for thread_index -- confirmed via direct
    # instruction trace (sail_riscv_sim --trace-instr), not assumed.
    la   t0, thread_index
    slli t0, t0, 32
    li   t1, 0x0020000C
    or   t0, t0, t1
    li   x1, 150
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- thread_index cap

    li   x1, 150
    .insn i 0x0b, 0x5, x8, x1, 0   # veda.bind c8, x1  -- thread_index, unsealed (permanent)

    # ══════════════ return-sentry SOURCE: Object_ID 130 (Base=after_scheduler_return,
    #    Length=0xFFFF=VEDA_PCC_UNBOUNDED, Perms=Execute) -- the switcher trusts itself
    #    completely, so its own return-continuation is unbounded, not narrowly scoped;
    #    avoids a repeat of the Length-sizing bug MINIMAL_OS_KERNEL_DESIGN.md's own
    #    Section 5 already documented once. ══════════════
    la   t0, after_scheduler_return
    slli t0, t0, 32
    li   t1, 0xFFFF0002
    or   t0, t0, t1
    li   x1, 130
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- return-sentry source

    li   x1, 130
    .insn i 0x0b, 0x5, x9, x1, 0   # veda.bind c9, x1  -- return-sentry source, unsealed (permanent)

    # ══════════════ pre-populate save_area_b with THREAD_B's own bootstrap state ══════════════
    # THREAD_B has never run yet -- its "saved PC" must be its own true entry point
    # (including its own one-time x21:=0 init), and its own PCC bounds must be its
    # own CODE cap's Base/Length, so the switcher's first-ever "restore B" behaves
    # exactly like resuming a legitimately-yielded thread, not a special case.
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

# ─────────────────────────────────────────────────────────────
#  THREAD_A -- x20 is its only persistent state across a yield.
#  thread_a_entry's own `li x20,0`/`li x22,1` execute EXACTLY ONCE: a genuinely
#  wrong resume (restarting at entry instead of the true saved PC) would reset
#  x20 to 0 every cycle, so the final x20==2 assertion is discriminating by
#  construction, not merely plausible.
# ─────────────────────────────────────────────────────────────
.balign 4
thread_a_entry:
    li   x20, 0
    li   x22, 1                # THREAD_A's own bounds_ok marker, starts true
thread_a_loop:
    addi x20, x20, 1
    li   x25, 2
    bne  x20, x25, thread_a_skip_check
    # -- THREAD_A's own second visit: verify live PCC bounds are genuinely its
    #    own, not THREAD_B's and not unbounded (Plan-agent-recommended check --
    #    proves the switcher restored the right BOUNDS, not just a PC that
    #    happens to still fetch correctly for a few instructions). --
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

# ─────────────────────────────────────────────────────────────
#  SCHEDULER -- "just a compartment... not more privileged than the threads it
#  schedules" (real text). Minimal round-robin: toggle thread_index, return
#  cheaply via OCRETURN through the switcher-minted sentry (c10) -- the exact
#  vc_switcher_register_clear_fast_return.S pattern, given a real job here.
# ─────────────────────────────────────────────────────────────
.balign 4
scheduler_entry:
    li   x23, 0
    .insn r 0x0b, 0x3, 0x00, x24, x8, x23  # ocl.d c8, x23(=0), x24  -- load thread_index
    xori x24, x24, 1
    .insn r 0x0b, 0x3, 0x01, x24, x8, x23  # ocs.d c8, x23(=0), x24  -- store toggled thread_index
    .insn r 0x5b, 0x1, 0x16, x0, x10, x0  # ocreturn c10
    j    fail_halt                          # must NOT be reached

# ─────────────────────────────────────────────────────────────
#  SWITCHER -- mtvec's own target, runs fully unbounded by construction (never
#  itself OCInvoke-entered -- required by the Milestone 20 CSR gate this design
#  depends on for the restore step below). Real division of labor from the
#  CHERIoT text: the switcher does the actual save/restore mechanics; the
#  scheduler (invoked below) only decides.
# ─────────────────────────────────────────────────────────────
.balign 4
switcher_entry:
    # (1) Guard, closing the real gap a Plan agent found in review: an ordinary
    #     ecall is cause 11 (E_M_EnvCall). Without this check, any unrelated
    #     fault while the switcher/scheduler runs would be silently
    #     misinterpreted as a legitimate yield, corrupting the wrong thread's
    #     save slot. Real fault recovery is out of scope this pass; silently
    #     absent is not.
    csrr x28, mcause
    li   x29, 11
    bne  x28, x29, fail_halt

    # (2) Read the yielding thread's own saved PC + PCC bounds (already saved
    #     into veda_mepcc_base/_length by Milestone 21's own universal reset,
    #     which fired before this handler was ever fetched). mepc points at the
    #     ecall itself (RISC-V ecall never auto-advances epc) -- advance by 4
    #     so resume lands on the instruction AFTER ecall, not back on ecall
    #     itself (found empirically: without this, both threads perpetually
    #     re-executed the same ecall forever and their loop counters never
    #     advanced past their first increment).
    csrr x28, mepc
    addi x28, x28, 4
    csrr x29, 0x7c2             # veda_mepcc_base
    csrr x30, 0x7c3             # veda_mepcc_length

    # (3) Learn who is CURRENTLY running (= who is yielding) from thread_index,
    #     read BEFORE the scheduler's own toggle -- store the yielding thread's
    #     state into ITS OWN save area.
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
    # (4) Count this yield; after 4 (2 full A<->B round-trips -- the Plan
    #     agent's own recommended minimum to distinguish genuine independent
    #     per-thread restoration from a coincidental single-pass success),
    #     stop scheduling and fall into the final, fully-unbounded assertion
    #     block instead of resuming anyone again.
    la   x5, yield_count
    lw   x6, 0(x5)
    addi x6, x6, 1
    sw   x6, 0(x5)
    li   x27, 4
    beq  x6, x27, final_check

    # (5) Invoke the SCHEDULER (real cross-compartment call, matching "invoking
    #     the scheduler's interrupt entry point") with a freshly-minted return
    #     sentry.
    .insn r 0x5b, 0x1, 0x15, x10, x9, x0  # csealentry c10, c9  -- mint fresh return sentry
    .insn r 0x5b, 0x1, 0x12, x0, x4, x5   # ocinvoke c4, c5     -- invoke SCHEDULER
    j    fail_halt                          # must NOT be reached (scheduler must OCRETURN)

.balign 4
after_scheduler_return:
    # (6) thread_index now holds the scheduler's own decision (who is NEXT).
    #     Swap TSC to the chosen thread's own save-area capability -- the real
    #     "current thread" update real CHERIoT's own switcher performs on
    #     mtdc -- and verify the OLD value handed back genuinely matches the
    #     thread that was actually running before this switch (TSC round-trip
    #     fidelity, the same "read back and check" discipline
    #     vc_switcher_tsc_roundtrip.S already established for TSC in
    #     isolation).
    la   x5, thread_index
    lw   x6, 0(x5)
    bnez x6, resume_b
resume_a:
    .insn r 0x5b, 0x1, 0x13, x12, x6, x1  # ospecialrw c12, tsc, c6  -- TSC := save-area-A; c12 = old (should be save-area-B)
    .insn r 0x5b, 0x0, 0x00, x31, x12, x0 # cgetbase x31, c12
    la   x27, save_area_b
    beq  x31, x27, resume_a_tsc_ok
    la   x5, tsc_ok
    sd   x0, 0(x5)
resume_a_tsc_ok:
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x6, x5  # ocl.d c6, x5(=0), x28  -- A's saved PC
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x6, x5  # ocl.d c6, x5(=8), x29  -- A's saved base
    li   x1, 100
    .insn i 0x0b, 0x5, x11, x1, 0         # veda.bind c11, x1  -- FRESH CODE_A, Offset=0
    j    do_resume
resume_b:
    .insn r 0x5b, 0x1, 0x13, x12, x7, x1  # ospecialrw c12, tsc, c7  -- TSC := save-area-B; c12 = old (should be save-area-A)
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
    li   x1, 110
    .insn i 0x0b, 0x5, x11, x1, 0         # veda.bind c11, x1  -- FRESH CODE_B, Offset=0

do_resume:
    # (7) The actual context switch -- a REAL, empirically-found correctness
    #     gap this design surfaced (via direct sail_riscv_sim instruction
    #     tracing, not assumed): the established Milestone 14/20/21
    #     "csrw veda_pcc_base/_length then mret" pattern (never actually
    #     exercised end-to-end before this milestone -- vc_pcc_generic_
    #     trap_reset.S itself never re-narrows PCC before its own mret,
    #     confirmed by re-reading it) is UNSAFE here: narrowing PCC via
    #     ordinary csrw, then falling through to a separate mret
    #     instruction, requires FETCHING mret ITSELF from the switcher's
    #     own code -- now OUTSIDE the just-narrowed target compartment's
    #     bounds. The real, atomic-by-construction fix: freshly re-bind
    #     the chosen thread's own CODE Object_ID (Offset=0), OCA its
    #     Offset to the true resume point (delta = saved_pc - saved_base),
    #     mint a sentry, and OCRETURN through it -- narrowing PCC AND
    #     jumping in the SAME instruction, exactly like OCInvoke/OCRETURN
    #     already do everywhere else in this project, never as two
    #     separate steps.
    sub  x31, x28, x29                      # delta = saved_pc - saved_base
    .insn r 0x5b, 0x1, 0x0a, x11, x11, x31  # oca c11, c11, x31    -- c11.Offset := delta
    .insn r 0x5b, 0x1, 0x15, x11, x11, x0   # csealentry c11, c11 -- mint sentry in place
    .insn r 0x5b, 0x1, 0x16, x0, x11, x0    # ocreturn c11        -- atomically narrow + jump
    j    fail_halt                            # must NOT be reached

.balign 4
final_check:
    # Fully unbounded by construction (never re-entered a compartment after
    # the 4th yield's own save step) -- safe to check results and halt
    # directly, no return-to-unbounded dance needed.
    li   x27, 2
    bne  x20, x27, fail_halt      # THREAD_A ran its own increment exactly twice
    bne  x21, x27, fail_halt      # THREAD_B likewise
    li   x27, 1
    bne  x22, x27, fail_halt      # THREAD_A's own bounds fidelity held
    bne  x26, x27, fail_halt      # THREAD_B's own bounds fidelity held
    la   x5, tsc_ok
    ld   x27, 0(x5)
    li   x5, 1
    bne  x27, x5, fail_halt       # TSC round-trip fidelity held every cycle
    RVMODEL_HALT_PASS

fail_halt:
    RVMODEL_HALT_FAIL

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
