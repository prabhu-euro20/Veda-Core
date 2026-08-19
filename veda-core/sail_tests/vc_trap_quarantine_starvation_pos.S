.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Adversarial RTL-mirror review, 2026-08-19 (TRAP_QUARANTINE_RESULTS.md):
    # the original veda_trap_tracker eviction policy (plain global-minimum
    # -count victim) let an attacker who controls several OTHER otypes
    # drive them all to the quarantine threshold (count==3, itself already
    # "quarantined") and force the table's next fresh fault to evict a
    # genuinely quarantined VICTIM entry, silently un-quarantining it and
    # reopening the repeated-trap DoS the whole mechanism exists to close.
    #
    # This test proves the fix (veda_regs.sail: never evict a quarantined
    # entry; a fault against a brand-new otype when the table is
    # completely saturated with quarantined entries is simply left
    # untracked rather than evicting anyone):
    #
    #   Phase 1: drive 8 DISTINCT otypes (0-7) to full quarantine (3 real
    #            faults each) -- the table's own fixed 8-entry capacity,
    #            completely saturated, every entry quarantined. Otype 0 is
    #            the VICTIM (the first, "oldest" identity recorded --
    #            occupies the table's lowest index via the same
    #            first-invalid-slot allocation rule the reviewer's own
    #            attack targets).
    #   Phase 2: one fresh fault against a brand-new 9th otype (8), with
    #            the table already completely full. Must NOT evict
    #            anyone.
    #   Phase 3: re-attempt OCInvoke against the VICTIM (otype 0). Must
    #            STILL be refused with VEDA_CAUSE_COMPARTMENT_QUARANTINED
    #            (0x09), proving its entry survived phase 2 intact -- if
    #            it had been evicted, this would instead show the
    #            ORDINARY bounds-violation cause (0x01), the exact
    #            starvation-bypass signature the fix exists to prevent.
    #
    # A single shared, DISTINCT one-instruction entry point per identity
    # (narrow_entry_0..8, an address table, not one shared label re-used
    # 24 times) keeps every individual faulting PC's own repeat count at
    # or below 3 -- comfortably clear of sail_riscv_sim's own unrelated
    # "possible trap loop" debug heuristic (confirmed elsewhere in this
    # project's own test corpus to trigger around ~20 identical-PC
    # repeated traps), even though this test's TOTAL trap count (24 across
    # phase 1, plus 1 each for phases 2 and 3) exceeds that figure.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x20, 0                    # identity/outer-loop index N, 0-7
    li   x21, 0                    # per-identity fault counter, reset each outer iteration
    li   x28, 0                    # count of identities fully driven to quarantine (must reach 8)
    li   x27, 0                    # phase-3 confirmation sentinel
    li   x26, 0                    # phase flag: 0 = phase 1, 1 = phase 2, 2 = phase 3
    li   x23, 0                    # fail-reason code, 0 = no failure recorded yet

    # -- DATA (Object_ID 570): Permit_Invoke only = 0x0400. --
    li   x1, 570
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- TYPE authority (Object_ID 571): Length=0x10 (room for offsets
    #    0-8), Perms=Permit_Seal|Permit_Unseal=0x0300. Bound ONCE, never
    #    re-bound -- every otype (0-8) is derived from it fresh via OCA
    #    (c.Offset := N), which is how CSeal's own `otype = cs2.Offset`
    #    produces 9 genuinely distinct identities from a single Object. --
    li   x1, 571
    li   x2, 0x80010b0000100300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 570
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 571
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- TYPE authority (Offset=0)

outer_loop:
    li   x21, 0

    # -- re-populate the SHARED CODE Object_ID (572) fresh each iteration,
    #    Base = addr_table[x20] -- a distinct one-instruction entry point
    #    per identity (see header comment). --
    la   t1, addr_table
    slli t2, x20, 3
    add  t1, t1, t2
    ld   t0, 0(t1)                 # t0 = Base(narrow_entry_<N>)
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 572
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE (re-populated)

    li   x1, 572
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE

inner_reinvoke:
    mv   x22, x20
    .insn r 0x5b, 0x1, 0x0a, x5, x2, x22  # oca c5, c2, x22  -- c5.Offset = x20
    .insn r 0x5b, 0x1, 0x10, x3, x0, x5   # cseal c3, c0, c5 -- sealed CODE, otype=x20
    .insn r 0x5b, 0x1, 0x10, x4, x1, x5   # cseal c4, c1, c5 -- sealed DATA, otype=x20
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4  -- must trap (ordinary bounds)
    j    fail_unexpected_no_trap

.balign 4
trap_handler:
    csrr t4, 0x343                 # mtval
    andi t5, t4, 0x1f               # cause
    srli t6, t4, 5                  # cap_idx

    li   a0, 1
    beq  x26, a0, phase2_trap
    li   a0, 2
    beq  x26, a0, phase3_trap

phase1_trap:
    li   t0, 0x01
    bne  t5, t0, fail_cause_mismatch
    li   t0, 16
    bne  t6, t0, fail_cause_mismatch
    addi x21, x21, 1
    li   t0, 3
    blt  x21, t0, inner_reinvoke
    addi x28, x28, 1
    addi x20, x20, 1
    li   t0, 8
    blt  x20, t0, outer_loop
    j    phase1_done

phase2_trap:
    li   t0, 0x01
    bne  t5, t0, fail_cause_mismatch
    li   t0, 16
    bne  t6, t0, fail_cause_mismatch
    j    phase2_done

phase3_trap:
    # The load-bearing assertion: the victim (otype=0) must STILL show
    # the quarantine-refusal cause, not fall back to an ordinary bounds
    # violation (which would mean it was evicted -- the exact bypass
    # this test exists to rule out).
    li   t0, 0x09
    bne  t5, t0, fail_starvation_bypassed
    li   t0, 3
    bne  t6, t0, fail_cause_mismatch
    li   x27, 1
    j    phase3_done

fail_cause_mismatch:
    li   x23, 0xDEAD
    j    real_fail
fail_unexpected_no_trap:
    li   x23, 0xBAD1
    j    real_fail
fail_starvation_bypassed:
    li   x23, 0xBAD9
    j    real_fail

phase1_done:
    # -- Phase 2: table is now completely full, all 8 identities (otype
    #    0-7) quarantined. One fresh fault against a brand-new 9th
    #    identity (otype=8) must NOT evict any of them. --
    li   x26, 1
    li   x20, 8
    la   t1, addr_table
    slli t2, x20, 3
    add  t1, t1, t2
    ld   t0, 0(t1)                 # Base(narrow_entry_8)
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 572
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 572
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1
    mv   x22, x20
    .insn r 0x5b, 0x1, 0x0a, x5, x2, x22  # oca c5, c2, x22 (Offset=8)
    .insn r 0x5b, 0x1, 0x10, x3, x0, x5   # cseal c3, c0, c5
    .insn r 0x5b, 0x1, 0x10, x4, x1, x5   # cseal c4, c1, c5
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4 -- ordinary bounds trap expected
    j    fail_unexpected_no_trap

phase2_done:
    # -- Phase 3: verify the victim (otype=0) is STILL quarantined. --
    li   x26, 2
    li   x20, 0
    la   t1, addr_table
    ld   t0, 0(t1)                 # Base(narrow_entry_0)
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 572
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 572
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1
    mv   x22, x20
    .insn r 0x5b, 0x1, 0x0a, x5, x2, x22  # oca c5, c2, x22 (Offset=0)
    .insn r 0x5b, 0x1, 0x10, x3, x0, x5   # cseal c3, c0, c5 -- otype=0, the victim
    .insn r 0x5b, 0x1, 0x10, x4, x1, x5   # cseal c4, c1, c5
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4 -- must be QUARANTINE-refused
    j    fail_starvation_bypassed

phase3_done:
    li   t2, 1
    bne  x27, t2, real_fail
    li   t2, 8
    bne  x28, t2, real_fail
    li   t2, 0
    bne  x23, t2, real_fail
    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL

.balign 8
addr_table:
    .dword narrow_entry_0
    .dword narrow_entry_1
    .dword narrow_entry_2
    .dword narrow_entry_3
    .dword narrow_entry_4
    .dword narrow_entry_5
    .dword narrow_entry_6
    .dword narrow_entry_7
    .dword narrow_entry_8

.balign 4
narrow_entry_0: nop
narrow_entry_1: nop
narrow_entry_2: nop
narrow_entry_3: nop
narrow_entry_4: nop
narrow_entry_5: nop
narrow_entry_6: nop
narrow_entry_7: nop
narrow_entry_8: nop
