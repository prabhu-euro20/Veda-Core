.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # TRAP_QUARANTINE_DESIGN.md: real negative test for the repeated-trap
    # DoS containment mechanism, closing the gap the CHERIoT RTOS paper
    # names as NOT prevented by capabilities alone (Amar et al., ACM SOSP
    # '25, S5.1.2: "an attacker [...] repeatedly trigger[ing] traps to
    # force a victim compartment to spend all its cycles micro-rebooting").
    #
    # Empirically confirmed BEFORE this mechanism existed (an earlier,
    # unmitigated version of this same probe, no longer in this repo):
    # Veda-Core's hardware/Sail trap model placed ZERO limit on repeated
    # trap-then-immediate-reinvoke cycles against the identical
    # compartment. This test proves the fix: the SAME attack pattern must
    # now be hardware-refused after VEDA_TRAP_QUARANTINE_THRESHOLD (3)
    # real faults, not silently permitted to continue.
    #
    # Mechanism, modeled on vc_pcc_bounds_neg.S's own already-verified
    # OCInvoke/trap pattern: a compartment with Length=0x0004 (one
    # instruction) genuinely hard-traps (VEDA_CAUSE_BOUNDS_VIOLATION, PCC
    # sentinel cap_idx=16) the instant it fetches its own second
    # instruction. The trap handler unconditionally re-derives the sealed
    # CODE/DATA pair and re-invokes -- simulating the exact naive "restart
    # the crashed compartment" scheduler policy the CHERIoT paper names as
    # this DoS class's real-world trigger. REPEAT_COUNT is deliberately
    # small (5, not the original probe's 20): 3 real compartment-bounds
    # faults bring the tracker to the quarantine threshold, then 2 more
    # re-invoke attempts must be refused OUTRIGHT (VEDA_CAUSE_COMPARTMENT_
    # QUARANTINED, cap_idx=3 -- the sealed CODE capability register c3
    # OCInvoke's own rs1 names) -- compartment_start's own body is never
    # reached again after that point, confirmed by this test's own
    # per-iteration mcause/mtval bookkeeping below, not merely inferred
    # from the final HALT_PASS.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x9, 0                     # total trap count (persists across every re-entry)
    li   x27, 5                    # REPEAT_COUNT (x27/s11 -- deliberately NOT t3/x28, which
                                    # trap_handler's own legitimate-exit path below reuses as
                                    # scratch for the 0xFFFFF PCC-unbounded literal). Small,
                                    # deliberately: past the quarantine threshold (3), every
                                    # further trap repeats at the SAME PC (the ocinvoke
                                    # instruction itself), and sail_riscv_sim's own unrelated
                                    # "possible trap loop" debug heuristic (confirmed directly,
                                    # this session, to trigger on ~20 identical-PC traps) exists
                                    # to catch genuinely runaway test programs -- 5 real trap
                                    # round-trips is already conclusive proof and stays
                                    # comfortably clear of that unrelated limit.
    li   x24, 0                    # sentinel: 1 once trap #4's own mtval is confirmed to be
                                    # the expected QUARANTINED cause (not the ordinary bounds
                                    # violation every earlier trap showed)
    li   x25, 0                    # sentinel: 1 once trap #5's own mtval ALSO confirms
                                    # QUARANTINED (proves refusal persists, not a one-shot fluke)

    # -- Object_ID=470 (CODE): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=compartment_start, Length=0x0004 -- one instruction only,
    #    the identical real fault-inducing shape vc_pcc_bounds_neg.S
    #    already established and verified. --
    la   t0, compartment_start
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 470
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=471 (DATA): Permit_Invoke only = 0x0400. --
    li   x1, 471
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=472: type authority, Permit_Seal|Permit_Unseal=0x0300. --
    li   x1, 472
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 470
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 471
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 472
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

reinvoke:
    # Re-derive the sealed CODE/DATA pair fresh every iteration -- exactly
    # what a real scheduler's own "restart the compartment" retry path
    # would look like: re-seal, re-invoke, from scratch, every time. Once
    # quarantined, THIS is precisely the instruction that must now be
    # refused (ocinvoke c3, c4, with c3 = the sealed CODE capability whose
    # otype the tracker keys on).
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed DATA

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

compartment_start:
    nop                              # the ONE instruction Length=0x0004 permits. Reached on
                                      # iterations 1-3 only -- from iteration 4 onward, the
                                      # ocinvoke above must itself trap before ever reaching here.

    j fail_unexpected_no_trap

.balign 4
trap_handler:
    csrr t4, 0x343                  # mtval -- real, per-iteration cause verification, not
                                     # inferred from the final outcome alone.
    addi x9, x9, 1

    # mtval packs (cap_idx5 @ cause5) per veda_xtval -- decode both halves
    # via masking, matching this project's own established convention
    # (vc_*.S's own shell-side `mtval.*0x...` trace checks, done here
    # in-program instead so the .S file itself is the complete proof, not
    # merely the harness around it).
    andi t5, t4, 0x1f               # cause (low 5 bits)
    li   t6, 0x09                   # VEDA_CAUSE_COMPARTMENT_QUARANTINED
    bne  t5, t6, not_quarantine_trap
    # This IS a quarantine-refusal trap. Also confirm cap_idx == 3 (c3,
    # the sealed CODE capability OCInvoke's own rs1 names) -- real, exact
    # proof this is the SAME compartment identity being refused, not some
    # unrelated quarantine entry.
    srli t5, t4, 5
    li   t6, 3
    bne  t5, t6, done_check_fail
    li   t6, 4
    beq  x9, t6, mark_trap4_quarantined
    li   t6, 5
    beq  x9, t6, mark_trap5_quarantined
    j    reinvoke_or_exit
mark_trap4_quarantined:
    li   x24, 1
    j    reinvoke_or_exit
mark_trap5_quarantined:
    li   x25, 1
    j    reinvoke_or_exit

not_quarantine_trap:
    # Traps 1-3 are expected to be the ordinary PCC-bounds violation
    # (cause=0x01, cap_idx=16 -- the PCC sentinel, matching
    # vc_pcc_bounds_neg.S's own already-verified convention) -- any OTHER
    # cause here on traps 1-3 is a real, distinct failure.
    li   t6, 0x01
    bne  t5, t6, done_check_fail
    srli t5, t4, 5
    li   t6, 16
    bne  t5, t6, done_check_fail

reinvoke_or_exit:
    blt  x9, x27, reinvoke

    # REPEAT_COUNT reached -- legitimate escape, modeled on
    # vc_pcc_bounds_neg.S's own already-verified recovery sequence.
    li   t3, 0xFFFFF
    csrw 0x7c1, t3                 # veda_pcc_length := VEDA_PCC_UNBOUNDED
    csrw 0x7c0, x0
    csrw 0x7c3, t3                 # veda_mepcc_length := VEDA_PCC_UNBOUNDED (self-consuming)
    la   t3, recovery
    csrw mepc, t3
    mret

fail_unexpected_no_trap:
    li   x22, 0xBAD1                # compartment_start's own second instruction was somehow
                                     # reached without faulting -- a real, distinct bug.
    j    done

done_check_fail:
    li   x22, 0xDEAD
    j    done

recovery:
    li   x22, 0x900D
    j    done

done:
    # The real finding this test proves: exactly REPEAT_COUNT total traps
    # occurred (nothing hung or looped unboundedly), traps 1-3 were the
    # ordinary compartment-bounds fault, and traps 4-5 were BOTH genuinely
    # refused via VEDA_CAUSE_COMPARTMENT_QUARANTINED against the exact
    # same compartment identity (c3) -- the mechanism contains the attack,
    # it does not merely happen to stop it once.
    bne  x9, x27, real_fail
    li   t2, 0x900D
    bne  x22, t2, real_fail
    li   t2, 1
    bne  x24, t2, real_fail
    bne  x25, t2, real_fail

    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
