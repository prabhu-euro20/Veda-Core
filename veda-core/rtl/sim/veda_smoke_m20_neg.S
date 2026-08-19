.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 20 negative test 1: the real,
    # empirically-confirmed compartment-state CSR self-escape this
    # milestone closes. From inside a live OCInvoke compartment, a
    # plain CSRRW to veda_pcc_length (0x7c1) must now hard-trap
    # (mcause=0x02, standard RISC-V Illegal_Instruction, NOT Veda-
    # Core's own 0x18) instead of silently succeeding and undoing the
    # compartment's own bounding. Proves the CSR's own value is
    # genuinely unaffected: after the trap's save-and-reset, it reads
    # back exactly 0xFFFFF (unbounded) -- neither the original narrow
    # Length nor the attacker's own write value.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    # -- Object_ID=86 (CODE): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=compartment_start, Length=0x0040. --
    la   t1, compartment_start
    slli t1, t1, 32
    li   t2, 0x00400402
    or   t1, t1, t2
    li   x1, 86
    mv   x2, t1
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 87
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=87 (DATA)

    li   x1, 88
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=88 (type authority)

    li   x1, 86
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 87
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 88
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- narrows PCC to [compartment_start, compartment_start+0x40)

compartment_start:
    li   t3, 0x1000                # a value distinct from both the original Length (0x40) and UNBOUNDED (0xFFFF)
    csrw 0x7c1, t3                 # BLOCKED: self-escape attempt -- must hard-trap

    li   x22, 0xBAD1                 # must NOT be reached directly
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x02                   # standard Illegal_Instruction, not Veda-Core's own 0x18
    bne  t4, t5, fail

    csrr t4, 0x7c1                  # veda_pcc_length after the trap's own save-and-reset
    li   t5, 0xFFFFF                # must be UNBOUNDED -- neither 0x40 (original) nor 0x1000 (attacker's value) persisted
    bne  t4, t5, fail

    li   x21, 0x600D                 # sentinel: reached the handler, self-escape genuinely blocked

    # RTL M21-restore mirror: see veda_smoke_m19_neg2.S's own identical
    # comment -- mepcc still holds this test's real narrow compartment
    # (Length=0x40), so an explicit clear is now required before mret to
    # avoid an auto-restore re-narrowing PCC right back down.
    li   t4, 0xFFFFF
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
