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
    # GPR scope: ALL of x1-x31 now survive a yield, not just each thread's own
    # counter. The switcher below saves the full register file (via the standard
    # mscratch trap-entry trick to free one bootstrap scratch register without
    # losing it) into a per-thread 31-slot region of its own save area, and
    # restores it symmetrically on resume -- x0 is never saved (hardwired zero).
    # A handful of registers (x1/x5/x28/x29/x31) are still needed transiently by
    # the switcher's own save/restore and resume-jump mechanics, so their TRUE
    # restore is deferred until after that mechanics finishes reading them; every
    # other GPR, including ones the switcher itself uses as scratch (x27, x30),
    # is proven to survive by thread_a_entry/thread_b_entry's own distinctive
    # GPR-pattern check below.
    la   t0, switcher_entry
    csrw mtvec, t0

    # ══════════════ THREAD_A: Object_ID 100(CODE)/101(DATA)/102(type-authority) ══════════════
    # Length=0x0180 (384 bytes): grown from the original 0x0100 (256) to fit
    # the new full-GPR-context-save test additions in thread_a_entry (its own
    # real body is 0x12c/300 bytes after those additions -- confirmed via
    # objdump, not assumed -- 0x0180 leaves comfortable margin).
    la   t0, thread_a_entry
    slli t0, t0, 32
    li   t1, 0x01800402        # Length=0x0180, Perms=Execute|Invoke
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

    # ══════════════ THREAD_B: Object_ID 110/111/112 (Length=0x0180, see THREAD_A comment) ══════════════
    la   t0, thread_b_entry
    slli t0, t0, 32
    li   t1, 0x01800402
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

    # ══════════════ save-area-A: Object_ID 140 (Base=save_area_a, Length=0x110, Load|Store) ══════════════
    # Length=0x0110 (272 bytes): 3 dwords (saved-PC/base/length, offsets 0/8/16,
    # unchanged) + 31 GPR slots x1..x31 (offsets 24..264, 8 bytes each, x0 omitted).
    la   t0, save_area_a
    slli t0, t0, 32
    li   t1, 0x0110000C
    or   t0, t0, t1
    li   x1, 140
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- save-area-A

    li   x1, 140
    .insn i 0x0b, 0x5, x6, x1, 0   # veda.bind c6, x1  -- save-area-A, unsealed (permanent)

    # ══════════════ save-area-B: Object_ID 141 (Length=0x110, see save-area-A comment) ══════════════
    la   t0, save_area_b
    slli t0, t0, 32
    li   t1, 0x0110000C
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
    li   x30, 0x0180
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

    # ══════════════ seed mscratch=0: the switcher's own full-GPR-save bootstrap
    #    (switcher_entry below) parks its one working scratch register's true
    #    value here via csrrw before reusing it -- real, standard RISC-V trap-
    #    entry idiom (mscratch, CSR 0x340, confirmed unconditionally accessible,
    #    never gated by any Veda compartment check: model/core/ext_regs.sail's
    #    ext_check_CSR is an unconditional true stub, no override anywhere in
    #    model/extensions/Veda/). Not load-bearing (Sail zero-inits registers
    #    with no explicit reset assignment anyway) -- explicit over implicit. ══
    li   x5, 0
    csrw mscratch, x5

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
    li   x19, 1                # THREAD_A's own gpr_ok marker, starts true
thread_a_loop:
    addi x20, x20, 1
    li   x25, 1
    beq  x20, x25, thread_a_first_visit
    li   x25, 2
    bne  x20, x25, thread_a_skip_check
    # -- THREAD_A's own second visit (right after its one real resume): verify
    #    live PCC bounds are genuinely its own, not THREAD_B's and not
    #    unbounded (Plan-agent-recommended check -- proves the switcher
    #    restored the right BOUNDS, not just a PC that happens to still fetch
    #    correctly for a few instructions). --
    csrr x23, 0x7c0
    la   x24, thread_a_entry
    bne  x23, x24, thread_a_bounds_bad
    csrr x23, 0x7c1
    li   x24, 0x0180
    bne  x23, x24, thread_a_bounds_bad
    j    thread_a_gpr_check
thread_a_bounds_bad:
    li   x22, 0
thread_a_gpr_check:
    # -- also verify the distinctive GPR pattern stamped below (first visit,
    #    before the first yield) survived the resume intact, including
    #    registers the switcher itself uses as its own scratch (x27, x30) --
    #    proves the NEW full-context-save mechanism, not just PC/bounds. --
    li   x24, 0xAAAA0002
    bne  x2,  x24, thread_a_gpr_bad
    li   x24, 0xAAAA0009
    bne  x9,  x24, thread_a_gpr_bad
    li   x24, 0xAAAA000F
    bne  x15, x24, thread_a_gpr_bad
    li   x24, 0xAAAA0012
    bne  x18, x24, thread_a_gpr_bad
    li   x24, 0xAAAA001B
    bne  x27, x24, thread_a_gpr_bad
    li   x24, 0xAAAA001E
    beq  x30, x24, thread_a_commit
thread_a_gpr_bad:
    li   x19, 0
thread_a_commit:
    # -- Persist bounds_ok && gpr_ok to MEMORY (thread_a_ok, via the already-
    #    bound c8 -- ordinary sd is illegal here, same Milestone 19 rule
    #    the thread_index comment above already explains), not a GPR: a
    #    GPR-resident flag would silently be overwritten by THREAD_B's own
    #    later, TERMINAL (never-resumed) switch -- final_check runs in
    #    whatever GPR state THREAD_B's own last resume left behind, never
    #    THREAD_A's, since GPRs are genuinely per-thread now. Memory is not
    #    part of that per-thread context at all, so it survives.
    and  x23, x22, x19
    li   x24, 8
    .insn r 0x0b, 0x3, 0x01, x23, x8, x24  # ocs.d c8, 8(x24), x23  -- thread_a_ok
    j    thread_a_skip_check
thread_a_first_visit:
    # -- THREAD_A's own first visit, about to take its first-ever yield: stamp
    #    a distinctive pattern (0xAAAA0000 | register number) across a
    #    representative GPR spread before yielding. --
    li   x2,  0xAAAA0002
    li   x9,  0xAAAA0009
    li   x15, 0xAAAA000F
    li   x18, 0xAAAA0012
    li   x27, 0xAAAA001B
    li   x30, 0xAAAA001E
thread_a_skip_check:
    ecall
    j    thread_a_loop

.balign 4
thread_b_entry:
    li   x21, 0
    li   x26, 1                # THREAD_B's own bounds_ok marker, starts true
    li   x17, 1                # THREAD_B's own gpr_ok marker, starts true
thread_b_loop:
    addi x21, x21, 1
    li   x25, 1
    beq  x21, x25, thread_b_first_visit
    li   x25, 2
    bne  x21, x25, thread_b_skip_check
    csrr x23, 0x7c0
    la   x24, thread_b_entry
    bne  x23, x24, thread_b_bounds_bad
    csrr x23, 0x7c1
    li   x24, 0x0180
    bne  x23, x24, thread_b_bounds_bad
    j    thread_b_gpr_check
thread_b_bounds_bad:
    li   x26, 0
thread_b_gpr_check:
    li   x24, 0xBBBB0002
    bne  x2,  x24, thread_b_gpr_bad
    li   x24, 0xBBBB0009
    bne  x9,  x24, thread_b_gpr_bad
    li   x24, 0xBBBB000F
    bne  x15, x24, thread_b_gpr_bad
    li   x24, 0xBBBB0012
    bne  x18, x24, thread_b_gpr_bad
    li   x24, 0xBBBB001B
    bne  x27, x24, thread_b_gpr_bad
    li   x24, 0xBBBB001E
    beq  x30, x24, thread_b_commit
thread_b_gpr_bad:
    li   x17, 0
thread_b_commit:
    and  x23, x26, x17
    li   x24, 16
    .insn r 0x0b, 0x3, 0x01, x23, x8, x24  # ocs.d c8, 16(x24), x23  -- thread_b_ok
    j    thread_b_skip_check
thread_b_first_visit:
    li   x2,  0xBBBB0002
    li   x9,  0xBBBB0009
    li   x15, 0xBBBB000F
    li   x18, 0xBBBB0012
    li   x27, 0xBBBB001B
    li   x30, 0xBBBB001E
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
    # (0) Full-GPR-context-save bootstrap: park x5's true (pre-trap, thread-
    #     owned) value in mscratch via the standard RISC-V trap-entry idiom,
    #     freeing x5 as the switcher's one working scratch register without
    #     permanently losing it -- confirmed real, standard, and never gated
    #     by any Veda compartment check (see the mscratch-seed comment above).
    csrrw x5, mscratch, x5

    # (1) Learn who is CURRENTLY running (= who is yielding) from thread_index,
    #     read BEFORE the scheduler's own toggle, using the now-free x5 (NOT
    #     x6 -- x6's own TRUE value must survive to be saved below, untouched).
    la   x5, thread_index
    lw   x5, 0(x5)
    bnez x5, yielding_is_b
yielding_is_a:
    # (2) Full save of x1..x31's TRUE, still-undisturbed values into
    #     save_area_a via c6, BEFORE anything below touches x28/x29/x30 for
    #     switcher bookkeeping -- a real ordering hazard found by re-reading
    #     this file literally: mcause/mepc/mepcc reads already clobber
    #     x28/x29/x30, and used to run before thread_index was even read, so
    #     this full save must happen first or the thread's real x28/x29/x30
    #     would already be gone. x5 is the running offset register throughout;
    #     x5's own slot (offset 56) is deferred to the very end, relayed
    #     through mscratch then through the already-saved x31.
    li x5,24  ; .insn r 0x0b,0x3,0x01,x1, x6,x5   # ocs.d c6,24(x5),x1
    li x5,32  ; .insn r 0x0b,0x3,0x01,x2, x6,x5   # ocs.d c6,32(x5),x2
    li x5,40  ; .insn r 0x0b,0x3,0x01,x3, x6,x5   # ocs.d c6,40(x5),x3
    li x5,48  ; .insn r 0x0b,0x3,0x01,x4, x6,x5   # ocs.d c6,48(x5),x4
    li x5,64  ; .insn r 0x0b,0x3,0x01,x6, x6,x5   # ocs.d c6,64(x5),x6
    li x5,72  ; .insn r 0x0b,0x3,0x01,x7, x6,x5   # ocs.d c6,72(x5),x7
    li x5,80  ; .insn r 0x0b,0x3,0x01,x8, x6,x5   # ocs.d c6,80(x5),x8
    li x5,88  ; .insn r 0x0b,0x3,0x01,x9, x6,x5   # ocs.d c6,88(x5),x9
    li x5,96  ; .insn r 0x0b,0x3,0x01,x10,x6,x5   # ocs.d c6,96(x5),x10
    li x5,104 ; .insn r 0x0b,0x3,0x01,x11,x6,x5   # ocs.d c6,104(x5),x11
    li x5,112 ; .insn r 0x0b,0x3,0x01,x12,x6,x5   # ocs.d c6,112(x5),x12
    li x5,120 ; .insn r 0x0b,0x3,0x01,x13,x6,x5   # ocs.d c6,120(x5),x13
    li x5,128 ; .insn r 0x0b,0x3,0x01,x14,x6,x5   # ocs.d c6,128(x5),x14
    li x5,136 ; .insn r 0x0b,0x3,0x01,x15,x6,x5   # ocs.d c6,136(x5),x15
    li x5,144 ; .insn r 0x0b,0x3,0x01,x16,x6,x5   # ocs.d c6,144(x5),x16
    li x5,152 ; .insn r 0x0b,0x3,0x01,x17,x6,x5   # ocs.d c6,152(x5),x17
    li x5,160 ; .insn r 0x0b,0x3,0x01,x18,x6,x5   # ocs.d c6,160(x5),x18
    li x5,168 ; .insn r 0x0b,0x3,0x01,x19,x6,x5   # ocs.d c6,168(x5),x19
    li x5,176 ; .insn r 0x0b,0x3,0x01,x20,x6,x5   # ocs.d c6,176(x5),x20
    li x5,184 ; .insn r 0x0b,0x3,0x01,x21,x6,x5   # ocs.d c6,184(x5),x21
    li x5,192 ; .insn r 0x0b,0x3,0x01,x22,x6,x5   # ocs.d c6,192(x5),x22
    li x5,200 ; .insn r 0x0b,0x3,0x01,x23,x6,x5   # ocs.d c6,200(x5),x23
    li x5,208 ; .insn r 0x0b,0x3,0x01,x24,x6,x5   # ocs.d c6,208(x5),x24
    li x5,216 ; .insn r 0x0b,0x3,0x01,x25,x6,x5   # ocs.d c6,216(x5),x25
    li x5,224 ; .insn r 0x0b,0x3,0x01,x26,x6,x5   # ocs.d c6,224(x5),x26
    li x5,232 ; .insn r 0x0b,0x3,0x01,x27,x6,x5   # ocs.d c6,232(x5),x27
    li x5,240 ; .insn r 0x0b,0x3,0x01,x28,x6,x5   # ocs.d c6,240(x5),x28
    li x5,248 ; .insn r 0x0b,0x3,0x01,x29,x6,x5   # ocs.d c6,248(x5),x29
    li x5,256 ; .insn r 0x0b,0x3,0x01,x30,x6,x5   # ocs.d c6,256(x5),x30
    li x5,264 ; .insn r 0x0b,0x3,0x01,x31,x6,x5   # ocs.d c6,264(x5),x31
    csrr x31, mscratch                            # x31 already saved above -- relay x5's true value
    li x5,56  ; .insn r 0x0b,0x3,0x01,x31,x6,x5   # ocs.d c6,56(x5),x31 (== x5's true value)

    # (3) NOW safe to clobber x5/x28/x29/x30 -- their true values are already
    #     durably saved above. Guard (closing the real gap a Plan agent found
    #     in review: an ordinary ecall is cause 11/E_M_EnvCall; without this
    #     check, any unrelated fault while the switcher/scheduler runs would
    #     be silently misinterpreted as a legitimate yield, corrupting the
    #     wrong thread's save slot -- real fault recovery is out of scope this
    #     pass, silently absent is not), then read the yielding thread's own
    #     saved PC + PCC bounds (already captured into veda_mepcc_base/_length
    #     by Milestone 21's own universal reset, which fired before this
    #     handler was ever fetched; mepc points at the ecall itself -- RISC-V
    #     ecall never auto-advances epc -- so advance by 4 so resume lands on
    #     the instruction AFTER ecall, not back on ecall itself, found
    #     empirically: without this, both threads perpetually re-executed the
    #     same ecall forever and their loop counters never advanced).
    csrr x28, mcause
    li   x29, 11
    bne  x28, x29, fail_halt
    csrr x28, mepc
    addi x28, x28, 4
    csrr x29, 0x7c2             # veda_mepcc_base
    csrr x30, 0x7c3             # veda_mepcc_length
    li x5,0  ; .insn r 0x0b,0x3,0x01,x28,x6,x5    # ocs.d c6,0(x5),x28
    li x5,8  ; .insn r 0x0b,0x3,0x01,x29,x6,x5    # ocs.d c6,8(x5),x29
    li x5,16 ; .insn r 0x0b,0x3,0x01,x30,x6,x5    # ocs.d c6,16(x5),x30
    j    invoke_scheduler
yielding_is_b:
    # Mirror of yielding_is_a, identically, every ocs.d target c7/save_area_b.
    li x5,24  ; .insn r 0x0b,0x3,0x01,x1, x7,x5   # ocs.d c7,24(x5),x1
    li x5,32  ; .insn r 0x0b,0x3,0x01,x2, x7,x5   # ocs.d c7,32(x5),x2
    li x5,40  ; .insn r 0x0b,0x3,0x01,x3, x7,x5   # ocs.d c7,40(x5),x3
    li x5,48  ; .insn r 0x0b,0x3,0x01,x4, x7,x5   # ocs.d c7,48(x5),x4
    li x5,64  ; .insn r 0x0b,0x3,0x01,x6, x7,x5   # ocs.d c7,64(x5),x6
    li x5,72  ; .insn r 0x0b,0x3,0x01,x7, x7,x5   # ocs.d c7,72(x5),x7
    li x5,80  ; .insn r 0x0b,0x3,0x01,x8, x7,x5   # ocs.d c7,80(x5),x8
    li x5,88  ; .insn r 0x0b,0x3,0x01,x9, x7,x5   # ocs.d c7,88(x5),x9
    li x5,96  ; .insn r 0x0b,0x3,0x01,x10,x7,x5   # ocs.d c7,96(x5),x10
    li x5,104 ; .insn r 0x0b,0x3,0x01,x11,x7,x5   # ocs.d c7,104(x5),x11
    li x5,112 ; .insn r 0x0b,0x3,0x01,x12,x7,x5   # ocs.d c7,112(x5),x12
    li x5,120 ; .insn r 0x0b,0x3,0x01,x13,x7,x5   # ocs.d c7,120(x5),x13
    li x5,128 ; .insn r 0x0b,0x3,0x01,x14,x7,x5   # ocs.d c7,128(x5),x14
    li x5,136 ; .insn r 0x0b,0x3,0x01,x15,x7,x5   # ocs.d c7,136(x5),x15
    li x5,144 ; .insn r 0x0b,0x3,0x01,x16,x7,x5   # ocs.d c7,144(x5),x16
    li x5,152 ; .insn r 0x0b,0x3,0x01,x17,x7,x5   # ocs.d c7,152(x5),x17
    li x5,160 ; .insn r 0x0b,0x3,0x01,x18,x7,x5   # ocs.d c7,160(x5),x18
    li x5,168 ; .insn r 0x0b,0x3,0x01,x19,x7,x5   # ocs.d c7,168(x5),x19
    li x5,176 ; .insn r 0x0b,0x3,0x01,x20,x7,x5   # ocs.d c7,176(x5),x20
    li x5,184 ; .insn r 0x0b,0x3,0x01,x21,x7,x5   # ocs.d c7,184(x5),x21
    li x5,192 ; .insn r 0x0b,0x3,0x01,x22,x7,x5   # ocs.d c7,192(x5),x22
    li x5,200 ; .insn r 0x0b,0x3,0x01,x23,x7,x5   # ocs.d c7,200(x5),x23
    li x5,208 ; .insn r 0x0b,0x3,0x01,x24,x7,x5   # ocs.d c7,208(x5),x24
    li x5,216 ; .insn r 0x0b,0x3,0x01,x25,x7,x5   # ocs.d c7,216(x5),x25
    li x5,224 ; .insn r 0x0b,0x3,0x01,x26,x7,x5   # ocs.d c7,224(x5),x26
    li x5,232 ; .insn r 0x0b,0x3,0x01,x27,x7,x5   # ocs.d c7,232(x5),x27
    li x5,240 ; .insn r 0x0b,0x3,0x01,x28,x7,x5   # ocs.d c7,240(x5),x28
    li x5,248 ; .insn r 0x0b,0x3,0x01,x29,x7,x5   # ocs.d c7,248(x5),x29
    li x5,256 ; .insn r 0x0b,0x3,0x01,x30,x7,x5   # ocs.d c7,256(x5),x30
    li x5,264 ; .insn r 0x0b,0x3,0x01,x31,x7,x5   # ocs.d c7,264(x5),x31
    csrr x31, mscratch
    li x5,56  ; .insn r 0x0b,0x3,0x01,x31,x7,x5   # ocs.d c7,56(x5),x31 (== x5's true value)

    csrr x28, mcause
    li   x29, 11
    bne  x28, x29, fail_halt
    csrr x28, mepc
    addi x28, x28, 4
    csrr x29, 0x7c2
    csrr x30, 0x7c3
    li x5,0  ; .insn r 0x0b,0x3,0x01,x28,x7,x5    # ocs.d c7,0(x5),x28
    li x5,8  ; .insn r 0x0b,0x3,0x01,x29,x7,x5    # ocs.d c7,8(x5),x29
    li x5,16 ; .insn r 0x0b,0x3,0x01,x30,x7,x5    # ocs.d c7,16(x5),x30

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
    # NOTE: do_resume is no longer a shared tail (see below) -- the new eager-
    # restore loop overwrites GPR x6 with its true thread value, but x6 is
    # also this code's own means of remembering "A or B" for a shared tail;
    # rather than preserve a selector register across a 26-register restore
    # loop, resume_a/resume_b are now each fully self-contained, matching how
    # this file already fully duplicates their TSC-round-trip-check logic.
    .insn r 0x5b, 0x1, 0x13, x12, x6, x1  # ospecialrw c12, tsc, c6  -- TSC := save-area-A; c12 = old (should be save-area-B)
    .insn r 0x5b, 0x0, 0x00, x31, x12, x0 # cgetbase x31, c12
    la   x27, save_area_b
    beq  x31, x27, resume_a_tsc_ok
    la   x5, tsc_ok
    sd   x0, 0(x5)
resume_a_tsc_ok:
    # Eager restore: all of x1..x31 except the deferred set {x1,x5,x28,x29,x31}
    # (needed live, transiently, by the jump machinery below), 26 registers,
    # safe in any order here -- the x6 token in every surrounding .insn is a
    # compile-time capability-register selector (c6), never a live GPR read.
    li x5,32  ; .insn r 0x0b,0x3,0x00,x2, x6,x5   # ocl.d c6,32(x5),x2
    li x5,40  ; .insn r 0x0b,0x3,0x00,x3, x6,x5   # ocl.d c6,40(x5),x3
    li x5,48  ; .insn r 0x0b,0x3,0x00,x4, x6,x5   # ocl.d c6,48(x5),x4
    li x5,64  ; .insn r 0x0b,0x3,0x00,x6, x6,x5   # ocl.d c6,64(x5),x6
    li x5,72  ; .insn r 0x0b,0x3,0x00,x7, x6,x5   # ocl.d c6,72(x5),x7
    li x5,80  ; .insn r 0x0b,0x3,0x00,x8, x6,x5   # ocl.d c6,80(x5),x8
    li x5,88  ; .insn r 0x0b,0x3,0x00,x9, x6,x5   # ocl.d c6,88(x5),x9
    li x5,96  ; .insn r 0x0b,0x3,0x00,x10,x6,x5   # ocl.d c6,96(x5),x10
    li x5,104 ; .insn r 0x0b,0x3,0x00,x11,x6,x5   # ocl.d c6,104(x5),x11
    li x5,112 ; .insn r 0x0b,0x3,0x00,x12,x6,x5   # ocl.d c6,112(x5),x12
    li x5,120 ; .insn r 0x0b,0x3,0x00,x13,x6,x5   # ocl.d c6,120(x5),x13
    li x5,128 ; .insn r 0x0b,0x3,0x00,x14,x6,x5   # ocl.d c6,128(x5),x14
    li x5,136 ; .insn r 0x0b,0x3,0x00,x15,x6,x5   # ocl.d c6,136(x5),x15
    li x5,144 ; .insn r 0x0b,0x3,0x00,x16,x6,x5   # ocl.d c6,144(x5),x16
    li x5,152 ; .insn r 0x0b,0x3,0x00,x17,x6,x5   # ocl.d c6,152(x5),x17
    li x5,160 ; .insn r 0x0b,0x3,0x00,x18,x6,x5   # ocl.d c6,160(x5),x18
    li x5,168 ; .insn r 0x0b,0x3,0x00,x19,x6,x5   # ocl.d c6,168(x5),x19
    li x5,176 ; .insn r 0x0b,0x3,0x00,x20,x6,x5   # ocl.d c6,176(x5),x20
    li x5,184 ; .insn r 0x0b,0x3,0x00,x21,x6,x5   # ocl.d c6,184(x5),x21
    li x5,192 ; .insn r 0x0b,0x3,0x00,x22,x6,x5   # ocl.d c6,192(x5),x22
    li x5,200 ; .insn r 0x0b,0x3,0x00,x23,x6,x5   # ocl.d c6,200(x5),x23
    li x5,208 ; .insn r 0x0b,0x3,0x00,x24,x6,x5   # ocl.d c6,208(x5),x24
    li x5,216 ; .insn r 0x0b,0x3,0x00,x25,x6,x5   # ocl.d c6,216(x5),x25
    li x5,224 ; .insn r 0x0b,0x3,0x00,x26,x6,x5   # ocl.d c6,224(x5),x26
    li x5,232 ; .insn r 0x0b,0x3,0x00,x27,x6,x5   # ocl.d c6,232(x5),x27
    li x5,256 ; .insn r 0x0b,0x3,0x00,x30,x6,x5   # ocl.d c6,256(x5),x30

    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x6, x5  # ocl.d c6, x5(=0), x28  -- A's saved PC (transient)
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x6, x5  # ocl.d c6, x5(=8), x29  -- A's saved base (transient)
    li   x1, 100
    .insn i 0x0b, 0x5, x11, x1, 0         # veda.bind c11, x1  -- FRESH CODE_A, Offset=0 (x1 still transient)

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
    sub  x31, x28, x29                      # delta = saved_pc - saved_base (x31 still transient)
    .insn r 0x5b, 0x1, 0x0a, x11, x11, x31  # oca c11, c11, x31    -- c11.Offset := delta, x31 now free
    .insn r 0x5b, 0x1, 0x15, x11, x11, x0   # csealentry c11, c11 -- mint sentry in place

    # NOW restore the deferred set to TRUE thread values -- transient jump-
    # machinery uses above are finished, so nothing below can observe a wrong
    # value: ocreturn (next) has zero GPR operands, only a capability operand.
    li x5,24  ; .insn r 0x0b,0x3,0x00,x1, x6,x5   # ocl.d c6,24(x5),x1
    li x5,240 ; .insn r 0x0b,0x3,0x00,x28,x6,x5   # ocl.d c6,240(x5),x28
    li x5,248 ; .insn r 0x0b,0x3,0x00,x29,x6,x5   # ocl.d c6,248(x5),x29
    li x5,264 ; .insn r 0x0b,0x3,0x00,x31,x6,x5   # ocl.d c6,264(x5),x31
    li x5,56  ; .insn r 0x0b,0x3,0x00,x5, x6,x5   # ocl.d c6,56(x5),x5 -- self-referential:
                                                    # offset read before dest write, confirmed
                                                    # against VEDA_OCL's real execute clause
    .insn r 0x5b, 0x1, 0x16, x0, x11, x0    # ocreturn c11        -- atomically narrow + jump
    j    fail_halt                            # must NOT be reached
resume_b:
    .insn r 0x5b, 0x1, 0x13, x12, x7, x1  # ospecialrw c12, tsc, c7  -- TSC := save-area-B; c12 = old (should be save-area-A)
    .insn r 0x5b, 0x0, 0x00, x31, x12, x0 # cgetbase x31, c12
    la   x27, save_area_a
    beq  x31, x27, resume_b_tsc_ok
    la   x5, tsc_ok
    sd   x0, 0(x5)
resume_b_tsc_ok:
    li x5,32  ; .insn r 0x0b,0x3,0x00,x2, x7,x5   # ocl.d c7,32(x5),x2
    li x5,40  ; .insn r 0x0b,0x3,0x00,x3, x7,x5   # ocl.d c7,40(x5),x3
    li x5,48  ; .insn r 0x0b,0x3,0x00,x4, x7,x5   # ocl.d c7,48(x5),x4
    li x5,64  ; .insn r 0x0b,0x3,0x00,x6, x7,x5   # ocl.d c7,64(x5),x6
    li x5,72  ; .insn r 0x0b,0x3,0x00,x7, x7,x5   # ocl.d c7,72(x5),x7
    li x5,80  ; .insn r 0x0b,0x3,0x00,x8, x7,x5   # ocl.d c7,80(x5),x8
    li x5,88  ; .insn r 0x0b,0x3,0x00,x9, x7,x5   # ocl.d c7,88(x5),x9
    li x5,96  ; .insn r 0x0b,0x3,0x00,x10,x7,x5   # ocl.d c7,96(x5),x10
    li x5,104 ; .insn r 0x0b,0x3,0x00,x11,x7,x5   # ocl.d c7,104(x5),x11
    li x5,112 ; .insn r 0x0b,0x3,0x00,x12,x7,x5   # ocl.d c7,112(x5),x12
    li x5,120 ; .insn r 0x0b,0x3,0x00,x13,x7,x5   # ocl.d c7,120(x5),x13
    li x5,128 ; .insn r 0x0b,0x3,0x00,x14,x7,x5   # ocl.d c7,128(x5),x14
    li x5,136 ; .insn r 0x0b,0x3,0x00,x15,x7,x5   # ocl.d c7,136(x5),x15
    li x5,144 ; .insn r 0x0b,0x3,0x00,x16,x7,x5   # ocl.d c7,144(x5),x16
    li x5,152 ; .insn r 0x0b,0x3,0x00,x17,x7,x5   # ocl.d c7,152(x5),x17
    li x5,160 ; .insn r 0x0b,0x3,0x00,x18,x7,x5   # ocl.d c7,160(x5),x18
    li x5,168 ; .insn r 0x0b,0x3,0x00,x19,x7,x5   # ocl.d c7,168(x5),x19
    li x5,176 ; .insn r 0x0b,0x3,0x00,x20,x7,x5   # ocl.d c7,176(x5),x20
    li x5,184 ; .insn r 0x0b,0x3,0x00,x21,x7,x5   # ocl.d c7,184(x5),x21
    li x5,192 ; .insn r 0x0b,0x3,0x00,x22,x7,x5   # ocl.d c7,192(x5),x22
    li x5,200 ; .insn r 0x0b,0x3,0x00,x23,x7,x5   # ocl.d c7,200(x5),x23
    li x5,208 ; .insn r 0x0b,0x3,0x00,x24,x7,x5   # ocl.d c7,208(x5),x24
    li x5,216 ; .insn r 0x0b,0x3,0x00,x25,x7,x5   # ocl.d c7,216(x5),x25
    li x5,224 ; .insn r 0x0b,0x3,0x00,x26,x7,x5   # ocl.d c7,224(x5),x26
    li x5,232 ; .insn r 0x0b,0x3,0x00,x27,x7,x5   # ocl.d c7,232(x5),x27
    li x5,256 ; .insn r 0x0b,0x3,0x00,x30,x7,x5   # ocl.d c7,256(x5),x30

    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x28, x7, x5  # ocl.d c7, x5(=0), x28
    li   x5, 8
    .insn r 0x0b, 0x3, 0x00, x29, x7, x5  # ocl.d c7, x5(=8), x29
    li   x1, 110
    .insn i 0x0b, 0x5, x11, x1, 0         # veda.bind c11, x1  -- FRESH CODE_B, Offset=0 (x1 still transient)

    sub  x31, x28, x29
    .insn r 0x5b, 0x1, 0x0a, x11, x11, x31  # oca c11, c11, x31
    .insn r 0x5b, 0x1, 0x15, x11, x11, x0   # csealentry c11, c11

    li x5,24  ; .insn r 0x0b,0x3,0x00,x1, x7,x5   # ocl.d c7,24(x5),x1
    li x5,240 ; .insn r 0x0b,0x3,0x00,x28,x7,x5   # ocl.d c7,240(x5),x28
    li x5,248 ; .insn r 0x0b,0x3,0x00,x29,x7,x5   # ocl.d c7,248(x5),x29
    li x5,264 ; .insn r 0x0b,0x3,0x00,x31,x7,x5   # ocl.d c7,264(x5),x31
    li x5,56  ; .insn r 0x0b,0x3,0x00,x5, x7,x5   # ocl.d c7,56(x5),x5
    .insn r 0x5b, 0x1, 0x16, x0, x11, x0    # ocreturn c11
    j    fail_halt                            # must NOT be reached

.balign 4
final_check:
    # Fully unbounded by construction (never re-entered a compartment after
    # the 4th yield's own save step) -- safe to check results and halt
    # directly, no return-to-unbounded dance needed. Reads thread_a_ok/
    # thread_b_ok from MEMORY (committed by each thread's own second-visit
    # code, see thread_a_commit/thread_b_commit above), NOT the old x20/x21/
    # x22/x26 GPR-based checks -- those are no longer reliable here: GPRs
    # are now genuinely per-thread (this milestone's whole point), so
    # whatever THREAD_B's own last resume left in the physical register
    # file is what final_check would see, not THREAD_A's. Memory survives
    # regardless of which thread resumed last.
    la   x5, thread_a_ok
    ld   x27, 0(x5)
    li   x6, 1
    bne  x27, x6, fail_halt       # THREAD_A: reached its 2nd visit, bounds+GPR pattern intact
    la   x5, thread_b_ok
    ld   x27, 0(x5)
    bne  x27, x6, fail_halt       # THREAD_B: likewise
    la   x5, tsc_ok
    ld   x27, 0(x5)
    li   x5, 1
    bne  x27, x5, fail_halt       # TSC round-trip fidelity held every cycle
    RVMODEL_HALT_PASS

fail_halt:
    RVMODEL_HALT_FAIL

.section .data
.align 3
# save_area_a/save_area_b: 34 dwords (272 bytes) each -- offsets 0/8/16 are the
# original saved-PC/PCC-base/PCC-length; offsets 24..264 are the new x1..x31
# GPR slots (offset(n) = 24 + (n-1)*8, x0 omitted -- hardwired zero, never
# saved). Zero-initialized here is sufficient (no pre-population needed, unlike
# Toolchain Milestone 14's analogous-looking capability-slot bug): these are
# plain OCL.D/OCS.D 64-bit values, not capabilities -- no tag is involved, so a
# zero-initialized read simply returns a valid, harmless zero, never a trap.
.align 4
save_area_a:
    .dword 0
    .dword 0
    .dword 0
    .dword 0    # x1
    .dword 0    # x2
    .dword 0    # x3
    .dword 0    # x4
    .dword 0    # x5
    .dword 0    # x6
    .dword 0    # x7
    .dword 0    # x8
    .dword 0    # x9
    .dword 0    # x10
    .dword 0    # x11
    .dword 0    # x12
    .dword 0    # x13
    .dword 0    # x14
    .dword 0    # x15
    .dword 0    # x16
    .dword 0    # x17
    .dword 0    # x18
    .dword 0    # x19
    .dword 0    # x20
    .dword 0    # x21
    .dword 0    # x22
    .dword 0    # x23
    .dword 0    # x24
    .dword 0    # x25
    .dword 0    # x26
    .dword 0    # x27
    .dword 0    # x28
    .dword 0    # x29
    .dword 0    # x30
    .dword 0    # x31
.align 4
save_area_b:
    .dword 0
    .dword 0
    .dword 0
    .dword 0    # x1
    .dword 0    # x2
    .dword 0    # x3
    .dword 0    # x4
    .dword 0    # x5
    .dword 0    # x6
    .dword 0    # x7
    .dword 0    # x8
    .dword 0    # x9
    .dword 0    # x10
    .dword 0    # x11
    .dword 0    # x12
    .dword 0    # x13
    .dword 0    # x14
    .dword 0    # x15
    .dword 0    # x16
    .dword 0    # x17
    .dword 0    # x18
    .dword 0    # x19
    .dword 0    # x20
    .dword 0    # x21
    .dword 0    # x22
    .dword 0    # x23
    .dword 0    # x24
    .dword 0    # x25
    .dword 0    # x26
    .dword 0    # x27
    .dword 0    # x28
    .dword 0    # x29
    .dword 0    # x30
    .dword 0    # x31
thread_index:
    .dword 0
thread_a_ok:    # offset 8 within c8's own 32-byte bound (Object_ID 150) --
    .dword 0    # committed by thread_a_commit; read by final_check
thread_b_ok:    # offset 16 within the same bound -- committed by
    .dword 0    # thread_b_commit; read by final_check
yield_count:
    .dword 0
tsc_ok:
    .dword 0
