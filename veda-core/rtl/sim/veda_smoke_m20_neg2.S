.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 20 negative test 2: the same real
    # self-escape gate applied to veda_mode (0x7c5) specifically --
    # unlike veda_pcc_base/_length/_mepcc_*, nothing else in this file
    # ever writes veda_mode, so its own suppression relies on an
    # explicit, hand-written guard rather than falling out for free
    # from the pre-existing "any trap resets PCC" priority every other
    # gated CSR here already had. Proves that guard is real: from
    # inside a live compartment, CSRRW to veda_mode must hard-trap
    # (mcause=0x02), and veda_mode itself reads back 0 afterward --
    # never written at all, not even partially.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    la   t1, compartment_start
    slli t1, t1, 32
    li   t2, 0x00400402
    or   t1, t1, t2
    li   x1, 89
    mv   x2, t1
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=89 (CODE)

    li   x1, 90
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=90 (DATA)

    li   x1, 91
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=91 (type authority)

    li   x1, 89
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 90
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 91
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- narrows PCC to [compartment_start, compartment_start+0x40)

compartment_start:
    li   t3, 1
    csrw 0x7c5, t3                 # BLOCKED: veda_mode self-write from inside a live compartment -- must hard-trap

    li   x22, 0xBAD1                 # must NOT be reached directly
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x02
    bne  t4, t5, fail

    csrr t4, 0x7c5                   # veda_mode -- must still be 0, never written at all
    bne  t4, x0, fail

    li   x21, 0x600D                  # sentinel: reached the handler, veda_mode self-escape genuinely blocked

    # RTL M21-restore mirror: see veda_smoke_m19_neg2.S's own identical
    # comment -- mepcc still holds this test's real narrow compartment,
    # so an explicit clear is now required before mret to avoid an
    # auto-restore re-narrowing PCC right back down.
    li   t4, 0xFFFF
    csrw 0x7c3, t4                    # veda_mepcc_length := unbounded

    la   t4, recovery
    csrw mepc, t4
    mret

recovery:
    li   x22, 0x900D                   # sentinel: correctly resumed outside the abandoned compartment
    j    done

fail:
    li   x22, 0xBAD

done:
1:
    j 1b
