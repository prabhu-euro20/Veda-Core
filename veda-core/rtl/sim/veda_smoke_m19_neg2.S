.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 19 negative test 2: the second real gap
    # this milestone closes -- Purecap Enforcement's OTHER trigger
    # condition. Code entered via a successful OCInvoke can otherwise
    # still issue an ordinary `sd`/`ld` to read/write memory directly,
    # undermining the isolation OCInvoke/PCC-bounding (Milestone 14)
    # is meant to provide. Proves: WITHOUT ever touching veda_purecap
    # (it stays 0 throughout), an ordinary store/load fetched from
    # INSIDE a live, correctly-bounded compartment (the fetch itself
    # is genuinely in-bounds -- this is not Milestone 14's own PCC
    # fetch-violation, a structurally distinct trap) still hard-traps,
    # same cause/cap_idx/mtval as negative test 1 (0x227) -- both
    # trigger conditions share the identical real enforcement point.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    la   t1, scratch

    # -- Object_ID=83 (CODE): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=compartment_start, Length=0x0040 -- generous, so the
    #    fetch of the blocked ld itself is genuinely IN-bounds. --
    la   t2, compartment_start
    slli t2, t2, 32
    li   t3, 0x00400402
    or   t2, t2, t3
    li   x1, 83
    mv   x2, t2
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 84
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=84 (DATA)

    li   x1, 85
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=85 (type authority)

    li   x1, 83
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 84
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 85
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- narrows PCC to [compartment_start, compartment_start+0x40)

compartment_start:
    li   x9, 0xDEAD                 # sentinel: must survive untouched
    ld   x9, 0(t1)                  # BLOCKED: inside a live compartment, purecap bit is still 0 -- must hard-trap

    li   x22, 0xBAD1                 # must NOT be reached directly
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x18
    bne  t4, t5, fail
    csrr t4, mtval
    li   t5, 0x227                  # identical (cap_idx=17<<5)|cause=0x07 -- same enforcement point as negative test 1
    bne  t4, t5, fail

    # -- confirm veda_purecap itself was never set (this trap fired
    #    purely from the compartment-narrowed trigger, the OTHER real
    #    condition, not the one negative test 1 already proved). --
    csrr t4, 0x7c5
    bne  t4, x0, fail

    # -- confirm the trap's own save-and-reset already widened PCC
    #    back to unbounded (Milestone 14's own mechanism, reused
    #    unchanged) -- this fetch (trap_handler itself) is only
    #    reachable at all because of that. --
    csrr t4, 0x7c1
    li   t5, 0xFFFF
    bne  t4, t5, fail

    li   x21, 0x600D                 # sentinel: reached the handler with the correct mcause/mtval, purecap still 0

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

.section .data
.align 3
scratch:
    .dword 0
