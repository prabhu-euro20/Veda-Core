.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL mirror of sail_tests/vc_trap_quarantine_csr_clear_pos.S
    # (TRAP_QUARANTINE_RESULTS.md, adversarial RTL-mirror review,
    # 2026-08-19): no RTL test exercised the veda_trap_quarantine_clear
    # CSR (0x7C6) at all before this one -- a real coverage gap for a
    # fix already shipped in veda_core.tlv (the CSR's own
    # $veda_csr_escape_violation OR-clause and $veda_tt_clear_active's
    # (>>1$priv || >>1$veda_oda_authorized) authorization gate). Proves
    # the basic M-mode path works end to end in actual hardware: quarantine
    # a compartment (3 real faults), confirm the refusal, clear it via the
    # CSR, confirm re-entry now faults ORDINARILY again (not refused) --
    # the CSR genuinely resets the tracker entry, not a no-op.
    #
    # Object_IDs 560 (CODE)/561 (DATA)/562 (TYPE authority) -- grep-
    # audited fresh against every existing rtl/sim/*.S Object_ID literal
    # before picking (highest in use: 552, from this same session's
    # veda_smoke_trap_quarantine_starvation_pos.S; 560-562 is a clean,
    # unused block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x9, 0                     # fault counter (0-2, drives to threshold)
    li   x24, 0                    # sentinel: 1 once the post-quarantine refusal is confirmed
    li   x25, 0                    # sentinel: 1 once the post-clear ordinary re-fault is confirmed
    li   x26, 0                    # 1 once the CSR clear has been issued
    li   x22, 0                    # fail-reason code, 0 = no failure recorded yet

    # -- Object_ID=560 (CODE): Length=0x0004, Permit_Execute|Permit_Invoke. --
    la   t0, narrow_entry
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 560
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=561 (DATA): Permit_Invoke only. --
    li   x1, 561
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=562 (TYPE authority): Permit_Seal|Permit_Unseal. --
    li   x1, 562
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 560
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 561
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 562
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- TYPE authority (Offset=0 -> otype=0)

reinvoke:
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4
    j    fail_unexpected_no_trap

narrow_entry:
    nop
    j    fail_unexpected_no_trap

.balign 4
trap_handler:
    csrr t4, 0x343
    andi t5, t4, 0x1f              # cause
    li   t6, 0x09
    beq  t5, t6, quarantine_trap

    # ordinary bounds violation expected
    li   t6, 0x01
    bne  t5, t6, fail_cause_mismatch
    srli t5, t4, 5
    li   t6, 16
    bne  t5, t6, fail_cause_mismatch

    li   t6, 1
    beq  x26, t6, post_clear_confirmed
    addi x9, x9, 1
    li   t6, 3
    blt  x9, t6, reinvoke
    # x9==3: this compartment is now quarantined (its own count reached
    # the threshold on this very fault). Attempt one more re-invoke,
    # which must be REFUSED (cause=0x09), not fault ordinarily again.
    j    reinvoke

post_clear_confirmed:
    li   x25, 1
    j    recover

quarantine_trap:
    srli t5, t4, 5
    li   t6, 3
    bne  t5, t6, fail_cause_mismatch
    li   x24, 1
    # -- Clear the quarantine via the CSR under test. otype=0 (this
    #    compartment's identity). Real M-mode privilege alone must
    #    suffice ($priv, set at reset and never dropped by this test --
    #    the unconditional arm of $veda_tt_clear_active's own
    #    ($priv || $veda_oda_authorized) authorization gate). --
    li   t3, 0
    csrw 0x7c6, t3
    li   x26, 1
    j    reinvoke

fail_cause_mismatch:
    li   x22, 0xDEAD
    j    real_fail
fail_unexpected_no_trap:
    li   x22, 0xBAD1
    j    real_fail

recover:
    li   t3, 0xFFFFF
    csrw 0x7c1, t3                 # veda_pcc_length := VEDA_PCC_UNBOUNDED
    csrw 0x7c0, x0                 # veda_pcc_base := 0
    csrw 0x7c3, t3                 # veda_mepcc_length := VEDA_PCC_UNBOUNDED (self-consuming)
    la   t3, done
    csrw mepc, t3
    mret

done:
    li   t2, 1
    bne  x24, t2, real_fail
    bne  x25, t2, real_fail
    li   x21, 0x600D                # success sentinel (checked by testbench)

all_done:
1:
    j 1b

real_fail:
1:
    j 1b
