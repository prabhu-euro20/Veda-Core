.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL mirror of sail_tests/vc_local_handler_neg_quarantine.S
    # (LOCAL_FAULT_RECOVERY_DESIGN.md / LOCAL_FAULT_RECOVERY_RESULTS.md):
    # quarantine-composition negative test. handler_entry is registered
    # once, then unconditionally re-faults every single time it runs
    # (its own body immediately re-triggers the same real out-of-bounds
    # fetch that got it invoked in the first place) -- the exact
    # self-faulting-handler DoS shape VEDA_TRAP_QUARANTINE exists to
    # bound. x25 counts every genuine redirect into handler_entry (the
    # FIRST entry is also forced via an explicit deliberate fault, not
    # ordinary fallthrough, so every increment of x25 is a real,
    # unambiguous redirect event). x26/x27/x28/x29 record the moment the
    # redirect budget is exhausted and control genuinely falls through to
    # the ordinary global mtvec fallback (NOT VEDA_CAUSE_COMPARTMENT_
    # QUARANTINED=0x09 -- that cause is specific to a fresh OCInvoke
    # attempt against an already-quarantined otype, a different real
    # trigger from this hardware-internal PC redirect, per
    # LOCAL_FAULT_RECOVERY_DESIGN.md's own explicit distinction; the
    # fallback here carries the SAME ordinary PCC-violation cause the
    # redirect itself was refused delivery of).
    #
    # The exact redirect count at which the fallback fires is NOT
    # assumed here -- x25's own final value is read back and reported;
    # LOCAL_FAULT_RECOVERY_RESULTS.md records the empirically-confirmed
    # number from a real trace, not a guess carried over from the Sail
    # side (RTL's own same-cycle combinational redirect decision
    # necessarily checks the trap-tracker's count as it stood BEFORE
    # this fault's own increment -- a real, structural difference from
    # Sail's sequential record-then-check -- see the new redirect-arm
    # comments in veda_core.tlv for the full reasoning).
    #
    # Object_IDs 597 (CODE)/598 (DATA)/599 (TYPE authority) -- grep-
    # audited fresh (590-596 used by this session's own two preceding
    # local-handler tests; 597+ is a clean, unused block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x25, 0                    # redirect-into-handler_entry visit count
    li   x26, 0                    # sentinel: 1 once the ordinary global fallback is genuinely reached
    li   x27, 0                    # x25's own value frozen at the moment of fallback
    li   x28, 0                    # sentinel: 1 once the fallback's own cause/cap_idx confirmed ordinary (0x01/16)
    li   x29, 0                    # sentinel: 1 once the fallback's own PCC confirmed genuinely reset (0/UNBOUNDED)
    li   x22, 0                    # fail-reason code, 0 = no failure recorded yet

    # -- Object_ID=597 (CODE): Base=compartment_start, Length=0x0040,
    #    Permit_Execute|Permit_Invoke=0x0402. --
    la   t0, compartment_start
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 597
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    # -- Object_ID=598 (DATA): Permit_Invoke only. --
    li   x1, 598
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    # -- Object_ID=599: type authority, Permit_Seal|Permit_Unseal. --
    li   x1, 599
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- TYPE

    li   x1, 597
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE
    li   x1, 598
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA
    li   x1, 599
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed DATA

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [compartment_start, +0x40)
poison_entry:
    j poison_entry                        # must NOT be reached

.balign 4
compartment_start:
    li   x30, 20                          # real, objdump-confirmed offset of handler_entry from
                                           # compartment_start (NOT 16 -- poison_mid's own 4-byte dead
                                           # instruction sits between the jal and handler_entry)
    .insn r 0x5b, 0x1, 0x0a, x9, x0, x30  # oca c9, c0, x30  -- c9 = {Base=compartment_start, Offset=20}
    .insn r 0x5b, 0x1, 0x17, x0, x9, x0   # osethandler c9   -- self-register handler_entry, ONCE
    jal  x0, trap_handler                  # fault #1 -- forces the FIRST entry to also be a genuine redirect

poison_mid:
    j poison_mid                          # dead code

.balign 4
handler_entry:
    addi x25, x25, 1                      # every visit here is a genuine redirect -- see header comment
    jal  x0, trap_handler                  # unconditionally re-faults, every single time -- the self-faulting
                                           # handler shape this test exists to bound

.balign 4
trap_handler:
    li   x26, 1                           # the ordinary global fallback was genuinely reached
    mv   x27, x25                          # freeze the redirect count at the moment of fallback

    csrr t4, 0x343                        # mtval
    andi t5, t4, 0x1f                     # cause
    li   t6, 0x01                         # VEDA_CAUSE_BOUNDS_VIOLATION -- the ORDINARY cause, not 0x09
    bne  t5, t6, done
    srli t5, t4, 5
    li   t6, 16                           # cap_idx=16 -- the PCC sentinel
    bne  t5, t6, done
    li   x28, 1

    csrr t1, 0x7c0                        # veda_pcc_base -- must be genuinely reset to 0
    bne  t1, x0, done
    li   t2, 0xFFFFF
    csrr a0, 0x7c1                        # veda_pcc_length -- must be genuinely reset to UNBOUNDED.
                                           # Deliberately NOT t3 -- t3 IS x28, this test's own "cause
                                           # confirmed" sentinel (already set above); reusing t3 here
                                           # would silently clobber it with the raw CSR value (a real
                                           # bug this file's own testing caught).
    bne  t2, a0, done
    li   x29, 1

    j    done

done:
1:
    j 1b
