.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Adversarial RTL-mirror review, 2026-08-19 (TRAP_QUARANTINE_RESULTS.md):
    # no Sail test exercised the veda_trap_quarantine_clear CSR (0x7C6) at
    # all before this one -- a real coverage gap, found while verifying the
    # review's own CSR-authorization finding (write_CSR(0x7C6,...) was
    # missing its documented veda_oda_authorized() OR-clause, since fixed).
    # Proves the basic M-mode path works end to end: quarantine a
    # compartment (3 real faults), confirm the refusal, clear it via the
    # CSR, confirm re-entry now faults ORDINARILY again (not refused) --
    # the CSR genuinely resets the tracker entry, not a no-op.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x9, 0                     # fault counter (0-2, drives to threshold)
    li   x24, 0                    # sentinel: 1 once the post-quarantine refusal is confirmed
    li   x25, 0                    # sentinel: 1 once the post-clear ordinary re-fault is confirmed
    li   x26, 0                    # 1 once the CSR clear has been issued

    # -- Object_ID=580 (CODE): Length=0x0004, Permit_Execute|Permit_Invoke. --
    la   t0, narrow_entry
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 580
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=581 (DATA): Permit_Invoke only. --
    li   x1, 581
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=582 (TYPE authority): Permit_Seal|Permit_Unseal. --
    li   x1, 582
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 580
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 581
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 582
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
    #    suffice (the unconditional arm, unaffected by this session's own
    #    fix, which only ADDED an alternative OR-path). --
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
    csrw 0x7c1, t3
    csrw 0x7c0, x0
    csrw 0x7c3, t3
    la   t3, done
    csrw mepc, t3
    mret

done:
    li   t2, 1
    bne  x24, t2, real_fail
    bne  x25, t2, real_fail
    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
