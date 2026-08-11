.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL Part B (M27-mtvec-gate mirror): the real gap this closes --
    # from inside a live OCInvoke compartment, a plain CSRRW to mtvec
    # (0x305) must now hard-trap (mcause=0x02, standard RISC-V
    # Illegal_Instruction) instead of silently succeeding and letting
    # a compartment hijack the trap vector out from under the kernel/
    # outer code that installed it -- the exact same self-escape class
    # already closed for veda_pcc_length/veda_pcc_base/veda_mepcc_*/
    # veda_mode (RTL Milestone 20), just applied to a standard CSR
    # that has no PCC-family "any trap resets me" branch of its own to
    # piggyback on (Sail-side precedent: vc_pcc_mtvec_escape_neg.S).
    # Proves mtvec's own value is genuinely unaffected: after the
    # trap's save-and-reset, it still reads back the REAL handler
    # address installed before entering the compartment -- neither the
    # attacker's bogus value nor a partial write.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0                        # the real, legitimate install -- from unbounded M-mode, must succeed

    # -- Object_ID=150 (CODE): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=compartment_start, Length=0x0040. --
    la   t1, compartment_start
    slli t1, t1, 32
    li   t2, 0x00400402
    or   t1, t1, t2
    li   x1, 150
    mv   x2, t1
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2

    li   x1, 151
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- Object_ID=151 (DATA)

    li   x1, 152
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2  -- Object_ID=152 (type authority)

    li   x1, 150
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 151
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 152
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- narrows PCC to [compartment_start, compartment_start+0x40)

compartment_start:
    la   t3, bogus_handler
    csrw mtvec, t3                 # BLOCKED: mtvec self-escape attempt -- must hard-trap

    li   x22, 0xBAD1                 # must NOT be reached directly
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x02                   # standard Illegal_Instruction, not Veda-Core's own 0x18
    bne  t4, t5, fail

    csrr t4, mtvec                  # mtvec after the trap's own save-and-reset
    la   t5, trap_handler            # must still hold the REAL handler address --
    bne  t4, t5, fail                # neither bogus_handler nor a partial write persisted

    li   x21, 0x600D                 # sentinel: reached the handler, self-escape genuinely blocked

    # RTL M21-restore mirror: see veda_smoke_m20_neg.S/m19_neg2.S's own
    # identical comment -- mepcc still holds this test's real narrow
    # compartment (Length=0x40), so an explicit clear is now required
    # before mret to avoid an auto-restore re-narrowing PCC right back
    # down.
    li   t4, 0xFFFF
    csrw 0x7c3, t4                   # veda_mepcc_length := unbounded

    la   t4, recovery
    csrw mepc, t4
    mret

recovery:
    li   x22, 0x900D                  # sentinel: correctly resumed outside the abandoned compartment
    j    done

fail:
    li   x22, 0xBAD

done:
1:
    j 1b

.balign 4
bogus_handler:
    li   x22, 0xBAD2                  # must NEVER execute -- proves the escape attempt never took effect
    j    done
