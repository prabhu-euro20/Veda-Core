.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of Sail-side Minimal OS Kernel Milestone C
    # (MILESTONE_C_RESULTS.md): a real, two-thread cooperative
    # round-robin scheduler, direct RTL port of
    # sail_tests/vc_scheduler_cooperative_yield.S -- proves Milestones
    # A (TSC + OSpecialRW selector) and B (CSealEntry + OCRETURN)
    # compose into the real OS-kernel pattern in RTL too, now that
    # Milestone 23 gives RTL a real ECALL to yield with. Same design,
    # same four compartments (THREAD_A/THREAD_B/SWITCHER/SCHEDULER),
    # same 4-yield (2 round-trip) verification target, and the same
    # three real bugs the Sail side found are applied here directly
    # since RTL was independently confirmed to share the identical
    # underlying properties: (1) ordinary lw/sw is blocked inside any
    # live OCInvoke compartment regardless of veda_purecap
    # (veda_core.tlv:2724-2725) -- SCHEDULER uses OCL.D/OCS.D for
    # thread_index, SWITCHER (unbounded) uses ordinary lw/sw freely;
    # (2) csrw-narrow-then-separate-mret is unsafe -- resume uses the
    # atomic OCA+CSealEntry+OCRETURN sequence; (3) mepc points at
    # ECALL itself with no auto-advance -- switcher does mepc+4 before
    # using it as a resume address.
    #
    # Object_IDs 110-122 (13 total) -- personally grepped every
    # existing rtl/sim/*.S file's own usage (now including the two new
    # Milestone 23 ecall tests' own 100/101/102) before picking:
    # 110-199 confirmed completely free.
    #
    # RTL Milestone 25 mirror: full GPR context save, ported from
    # sail_tests/vc_scheduler_cooperative_yield.S (proven, committed).
    # ALL of x1-x31 now survive a yield (x0 omitted, hardwired zero),
    # via the same standard mscratch-based trap-entry bootstrap (RTL
    # Milestone 25's own mscratch CSR addition, veda_core.tlv) freeing
    # one working scratch register at switcher_entry without losing it.
    # ─────────────────────────────────────────────────────────────
    la   t0, switcher_entry
    csrw mtvec, t0

    # ══════════════ THREAD_A: Object_ID 110(CODE)/111(DATA)/112(type) ══════════════
    # Length=0x0180 (384 bytes): grown from 0x0100 to fit the new
    # full-GPR-context-save test additions (measured via objdump after
    # writing the full body, matching the Sail port's own discipline).
    la   t0, thread_a_entry
    slli t0, t0, 32
    li   t1, 0x01800402        # Length=0x0180, Perms=Execute|Invoke
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

    # ══════════════ THREAD_B: Object_ID 113/114/115 (Length=0x0180, see THREAD_A) ══════════════
    la   t0, thread_b_entry
    slli t0, t0, 32
    li   t1, 0x01800402
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

    # ══════════════ save-area-A: Object_ID 119 (Base=save_area_a, Length=0x110, Load|Store) ══════════════
    # Length=0x0110 (272 bytes): 3 original dwords (saved-PC/base/length,
    # offsets 0/8/16) + 31 GPR slots x1..x31 (offsets 24..264, x0 omitted).
    la   t0, save_area_a
    slli t0, t0, 32
    li   t1, 0x0110000C
    or   t0, t0, t1
    li   x1, 119
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- save-area-A

    li   x1, 119
    .insn i 0x0b, 0x5, x6, x1, 0   # veda.bind c6, x1  -- save-area-A, unsealed (permanent)

    # ══════════════ save-area-B: Object_ID 120 (Length=0x110, see save-area-A) ══════════════
    la   t0, save_area_b
    slli t0, t0, 32
    li   t1, 0x0110000C
    or   t0, t0, t1
    li   x1, 120
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- save-area-B

    li   x1, 120
    .insn i 0x0b, 0x5, x7, x1, 0   # veda.bind c7, x1  -- save-area-B, unsealed (permanent)

    # ══════════════ thread_index capability: Object_ID 121 (Load|Store) ══════════════
    # Confirmed via veda_core.tlv:2724-2725 directly: ordinary loads/stores
    # are unconditionally blocked while veda_pcc_length != 16'hFFFF, the
    # identical rule already confirmed on the Sail side. SCHEDULER (itself
    # OCInvoke-entered) must use OCL.D/OCS.D for thread_index; SWITCHER
    # (runs unbounded) uses ordinary lw/sw freely.
    # Length=0x0030 (48 bytes): thread_index@0, plus two new memory-backed
    # flags this milestone adds -- thread_a_ok@8, thread_b_ok@16 -- reusing
    # this same capability rather than minting a new Object_ID, mirroring
    # the Sail port's own reuse pattern for its analogous capability.
    la   t0, thread_index
    slli t0, t0, 32
    li   t1, 0x0030000C
    or   t0, t0, t1
    li   x1, 121
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- thread_index cap

    li   x1, 121
    .insn i 0x0b, 0x5, x8, x1, 0   # veda.bind c8, x1  -- thread_index, unsealed (permanent)

    # ══════════════ return-sentry SOURCE: Object_ID 122 (Base=after_scheduler_return,
    #    Length=0xFFFF=VEDA_PCC_UNBOUNDED, Perms=Execute) ══════════════
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

    # ══════════════ seed mscratch=0 (RTL Milestone 25 mirror) ══════════════
    # The switcher's own full-GPR-save bootstrap parks its one working
    # scratch register's true value here via csrrw before reusing it.
    li   x5, 0
    csrw mscratch, x5

    # ══════════════ prime TSC := c6 (save-area-A, since THREAD_A runs first) ══════════════
    .insn r 0x5b, 0x1, 0x13, x14, x6, x1  # ospecialrw c14(discard), tsc, c6

    # ══════════════ enter THREAD_A for the first time ══════════════
    .insn r 0x5b, 0x1, 0x12, x0, x0, x1   # ocinvoke c0, c1
    j    fail_halt                          # must NOT be reached

# ─────────────────────────────────────────────────────────────
#  THREAD_A -- x20 is its only persistent state across a yield.
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
    # Persist bounds_ok && gpr_ok to MEMORY (thread_a_ok, via the already-
    # bound c8) -- ordinary sd is illegal here (any ordinary load/store is
    # blocked while running inside a narrowed compartment, confirmed
    # identically in this RTL as on the Sail side); a GPR-resident flag
    # would also be silently overwritten by THREAD_B's own later,
    # terminal (never-resumed) switch, since GPRs are now genuinely
    # per-thread -- memory is not part of that context, so it survives.
    and  x23, x22, x19
    li   x24, 8
    .insn r 0x0b, 0x3, 0x01, x23, x8, x24  # ocs.d c8, 8(x24), x23  -- thread_a_ok
    j    thread_a_skip_check
thread_a_first_visit:
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
#  SCHEDULER -- minimal round-robin: toggle thread_index via
#  OCL.D/OCS.D (ordinary lw/sw is blocked inside this live
#  compartment), return via OCRETURN through the switcher-minted
#  sentry (c10).
# ─────────────────────────────────────────────────────────────
.balign 4
scheduler_entry:
    li   x23, 0
    .insn r 0x0b, 0x3, 0x00, x24, x8, x23  # ocl.d c8, x23(=0), x24  -- load thread_index
    xori x24, x24, 1
    .insn r 0x0b, 0x3, 0x01, x24, x8, x23  # ocs.d c8, x23(=0), x24  -- store toggled thread_index
    .insn r 0x5b, 0x1, 0x16, x0, x10, x0   # ocreturn c10
    j    fail_halt                          # must NOT be reached

# ─────────────────────────────────────────────────────────────
#  SWITCHER -- mtvec's own target, runs fully unbounded.
# ─────────────────────────────────────────────────────────────
.balign 4
switcher_entry:
    # (0) RTL Milestone 25 mirror: full-GPR-context-save bootstrap --
    #     park x5's true (pre-trap, thread-owned) value in mscratch via
    #     the standard RISC-V trap-entry idiom, freeing x5 as the
    #     switcher's one working scratch register without permanently
    #     losing it.
    csrrw x5, mscratch, x5

    # (1) Learn who is CURRENTLY running from thread_index, using the
    #     now-free x5 (NOT x6 -- x6's own TRUE value must survive to be
    #     saved below, untouched). PRECISION NOTE: only this branch
    #     changes from x6 to x5; after_scheduler_return's own separate
    #     thread_index branch further down is intentionally left
    #     UNCHANGED (still x6) -- by that point every GPR has already
    #     been durably saved to memory, so nothing "true" is at risk
    #     there.
    la   x5, thread_index
    lw   x5, 0(x5)
    bnez x5, yielding_is_b
yielding_is_a:
    # (2) Full save of x1..x31's TRUE, still-undisturbed values into
    #     save_area_a via c6, BEFORE the guard+mepc/mepcc read below
    #     (which clobbers x28/x29/x30) is allowed to run. x5 is the
    #     running offset register throughout; x5's own slot (offset 56)
    #     is deferred to the very end, relayed through mscratch then
    #     through the already-saved x31.
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

    # (3) NOW safe to clobber x5/x28/x29/x30 -- guard (an ordinary ecall
    #     is cause 11/E_M_EnvCall) + mepc/mepcc read (mepc points at
    #     ECALL itself, no auto-advance -- advance by 4 so resume lands
    #     on the instruction AFTER ecall).
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
    # (4) Count this yield; after 4 (2 full A<->B round-trips), stop
    #     scheduling and fall into the final assertion block.
    la   x5, yield_count
    lw   x6, 0(x5)
    addi x6, x6, 1
    sw   x6, 0(x5)
    li   x27, 4
    beq  x6, x27, final_check

    # (5) Invoke SCHEDULER with a freshly-minted return sentry.
    .insn r 0x5b, 0x1, 0x15, x10, x9, x0  # csealentry c10, c9  -- mint fresh return sentry
    .insn r 0x5b, 0x1, 0x12, x0, x4, x5   # ocinvoke c4, c5     -- invoke SCHEDULER
    j    fail_halt                          # must NOT be reached (scheduler must OCRETURN)

.balign 4
after_scheduler_return:
    # (6) thread_index now holds the scheduler's own decision (who is
    #     NEXT). Swap TSC to the chosen thread's own save-area
    #     capability and verify the OLD value handed back genuinely
    #     matches the thread that was actually running before this
    #     switch.
    la   x5, thread_index
    lw   x6, 0(x5)
    bnez x6, resume_b
resume_a:
    # NOTE: do_resume is no longer a shared tail -- the eager-restore
    # loop overwrites GPR x6, which was also this code's own means of
    # remembering "A or B" for a shared tail; resume_a/resume_b are now
    # each fully self-contained, mirroring how this file already fully
    # duplicates their TSC-round-trip-check logic.
    .insn r 0x5b, 0x1, 0x13, x12, x6, x1  # ospecialrw c12, tsc, c6  -- TSC := save-area-A; c12 = old (should be save-area-B)
    .insn r 0x5b, 0x0, 0x00, x31, x12, x0 # cgetbase x31, c12
    la   x27, save_area_b
    beq  x31, x27, resume_a_tsc_ok
    la   x5, tsc_ok
    sd   x0, 0(x5)
resume_a_tsc_ok:
    # Eager restore: all of x1..x31 except {1,5,28,29,31} (needed live,
    # transiently, by the jump machinery below), 26 registers, safe in
    # any order -- the x6 token in every surrounding .insn is a
    # compile-time capability-register selector (c6), never a live GPR
    # read.
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
    li   x1, 110
    .insn i 0x0b, 0x5, x11, x1, 0         # veda.bind c11, x1  -- FRESH CODE_A, Offset=0 (x1 still transient)

    # (7) Atomic restore: freshly re-bind the chosen thread's own CODE
    #     Object_ID (Offset=0), OCA its Offset to the true resume point
    #     (delta = saved_pc - saved_base), mint a sentry, OCRETURN
    #     through it -- narrowing PCC AND jumping in the SAME
    #     instruction, never a separate csrw+mret (confirmed unsafe on
    #     the Sail side: mret itself would be fetched from OUTSIDE the
    #     just-narrowed target's bounds).
    sub  x31, x28, x29                      # delta = saved_pc - saved_base (x31 still transient)
    .insn r 0x5b, 0x1, 0x0a, x11, x11, x31  # oca c11, c11, x31    -- c11.Offset := delta, x31 now free
    .insn r 0x5b, 0x1, 0x15, x11, x11, x0   # csealentry c11, c11 -- mint sentry in place

    # NOW restore the deferred set to TRUE thread values -- transient
    # jump-machinery uses above are finished; ocreturn (next) has zero
    # GPR operands, only a capability operand, so no further leak window.
    li x5,24  ; .insn r 0x0b,0x3,0x00,x1, x6,x5   # ocl.d c6,24(x5),x1
    li x5,240 ; .insn r 0x0b,0x3,0x00,x28,x6,x5   # ocl.d c6,240(x5),x28
    li x5,248 ; .insn r 0x0b,0x3,0x00,x29,x6,x5   # ocl.d c6,248(x5),x29
    li x5,264 ; .insn r 0x0b,0x3,0x00,x31,x6,x5   # ocl.d c6,264(x5),x31
    li x5,56  ; .insn r 0x0b,0x3,0x00,x5, x6,x5   # ocl.d c6,56(x5),x5 -- self-referential:
                                                    # offset read before dest write (safe)
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
    li   x1, 113
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
    # Fully unbounded by construction -- safe to check results and
    # halt directly. All results loaded into GPRs so the testbench can
    # read them directly (no HTIF mechanism in this RTL test style).
    #
    # RTL Milestone 25 mirror: thread_a_ok/thread_b_ok are read from
    # MEMORY (committed by each thread's own second-visit code above),
    # NOT the old x20/x21/x22/x26 GPR-based checks -- GPRs are now
    # genuinely per-thread, so whatever THREAD_B's own last resume left
    # in the physical register file is what final_check would see here,
    # never THREAD_A's. Memory survives regardless of which thread
    # resumed last (same reasoning as the already-proven Sail port).
    la   x5, thread_a_ok
    ld   x6, 0(x5)
    li   x7, 1
    bne  x6, x7, fail_halt
    la   x5, thread_b_ok
    ld   x6, 0(x5)
    bne  x6, x7, fail_halt

    la   x5, tsc_ok
    ld   x9, 0(x5)                # tsc_ok reflected into a GPR for the testbench to read
    li   x5, 1
    bne  x9, x5, fail_halt        # TSC round-trip fidelity held every cycle

    li   x27, 0x600D              # sentinel: all checks passed
    j    done
fail_halt:
    li   x27, 0xDEAD
done:
1:
    j 1b

.section .data
.align 3
# save_area_a/save_area_b: 34 dwords (272 bytes) each -- offsets 0/8/16
# are the original saved-PC/PCC-base/PCC-length; offsets 24..264 are the
# new x1..x31 GPR slots (offset(n) = 24 + (n-1)*8, x0 omitted). Zero
# init is sufficient here (plain OCL.D/OCS.D, no tag involved, unlike
# the capability-slot case Toolchain Milestone 14 had to pre-populate).
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
thread_a_ok:    # offset 8 within c8's own 48-byte bound (Object_ID 121)
    .dword 0
thread_b_ok:    # offset 16 within the same bound
    .dword 0
yield_count:
    .dword 0
tsc_ok:
    .dword 0
