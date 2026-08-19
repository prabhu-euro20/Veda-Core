.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL mirror of sail_tests/vc_repeated_trap_dos_neg.S
    # (TRAP_QUARANTINE_DESIGN.md / task #351): real negative test for the
    # repeated-trap DoS containment mechanism, closing the gap the
    # CHERIoT RTOS paper names as NOT prevented by capabilities alone
    # (Amar et al., ACM SOSP '25, S5.1.2: "an attacker [...] repeatedly
    # trigger[ing] traps to force a victim compartment to spend all its
    # cycles micro-rebooting").
    #
    # Mechanism, modeled on veda_smoke_pcc_restore_on_mret.S's own
    # already-verified OCInvoke/trap/mepc-CSR pattern: a compartment with
    # Length=0x0004 (one instruction) genuinely hard-traps
    # (VEDA_CAUSE_BOUNDS_VIOLATION=0x01, PCC sentinel cap_idx=16) the
    # instant it fetches its own second instruction. The trap handler
    # unconditionally re-derives the sealed CODE/DATA pair and re-invokes
    # -- simulating the exact naive "restart the crashed compartment"
    # scheduler policy the CHERIoT paper names as this DoS class's real-
    # world trigger. REPEAT_COUNT=5: 3 real compartment-bounds faults
    # bring the tracker to the quarantine threshold (3), then 2 more
    # re-invoke attempts must be refused OUTRIGHT
    # (VEDA_CAUSE_COMPARTMENT_QUARANTINED=0x09, cap_idx=3 -- the sealed
    # CODE capability register c3 OCInvoke's own rs1 names) --
    # compartment_start's own body is never reached again after that
    # point, confirmed by this test's own per-iteration mtval bookkeeping
    # below, not merely inferred from the final sentinel.
    #
    # Object_IDs 520/521/522 -- grep-audited fresh against every existing
    # rtl/sim/*.S Object_ID literal before picking (highest in use: 510;
    # 520-522 is a clean, unused block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x9, 0                     # total trap count (persists across every re-entry)
    li   x27, 5                    # REPEAT_COUNT
    li   x24, 0                    # sentinel: 1 once trap #4's own mtval is confirmed QUARANTINED
    li   x25, 0                    # sentinel: 1 once trap #5's own mtval ALSO confirms QUARANTINED

    # -- Object_ID=520 (CODE): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=compartment_start, Length=0x0004. --
    la   t0, compartment_start
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 520
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    # -- Object_ID=521 (DATA): Permit_Invoke only = 0x0400. --
    li   x1, 521
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    # -- Object_ID=522: type authority, Permit_Seal|Permit_Unseal=0x0300. --
    li   x1, 522
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- TYPE

    li   x1, 520
    .insn i 0x0b, 0x5, x0, x1, 0  # bind c0, x1 -- CODE
    li   x1, 521
    .insn i 0x0b, 0x5, x1, x1, 0  # bind c1, x1 -- DATA
    li   x1, 522
    .insn i 0x0b, 0x5, x2, x1, 0  # bind c2, x1 -- type authority

reinvoke:
    # Re-derive the sealed CODE/DATA pair fresh every iteration -- exactly
    # what a real scheduler's own "restart the compartment" retry path
    # would look like. Once quarantined, THIS is precisely the
    # instruction that must now be refused.
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed DATA

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

compartment_start:
    nop                              # the ONE instruction Length=0x0004 permits. Reached on
                                      # iterations 1-3 only.

    j fail_unexpected_no_trap

.balign 4
trap_handler:
    csrr t4, 0x343                  # mtval -- real, per-iteration cause verification.
    addi x9, x9, 1

    # mtval packs (cap_idx5 @ cause5) -- decode both halves via masking.
    andi t5, t4, 0x1f               # cause (low 5 bits)
    li   t6, 0x09                   # VEDA_CAUSE_COMPARTMENT_QUARANTINED
    bne  t5, t6, not_quarantine_trap
    # This IS a quarantine-refusal trap. Also confirm cap_idx == 3 (c3,
    # the sealed CODE capability OCInvoke's own rs1 names).
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
    # (cause=0x01, cap_idx=16 -- the PCC sentinel).
    li   t6, 0x01
    bne  t5, t6, done_check_fail
    srli t5, t4, 5
    li   t6, 16
    bne  t5, t6, done_check_fail

reinvoke_or_exit:
    blt  x9, x27, reinvoke

    # REPEAT_COUNT reached -- legitimate escape via mret, modeled on
    # veda_smoke_pcc_restore_on_mret.S's own already-verified recovery
    # sequence (explicit-clear-before-mret, since M21-restore would
    # otherwise auto-restore the narrow bounds right back).
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
    li   x21, 0x600D                 # success sentinel
    j    done

done:
1:
    j 1b
