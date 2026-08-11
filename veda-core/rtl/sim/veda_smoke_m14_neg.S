.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 14 negative test: mirrors
    # vc_pcc_bounds_neg.S's own Sail scenario exactly. An OCInvoke-
    # entered compartment with Length=0x04 (one instruction only)
    # genuinely hard-traps the moment execution tries to fetch the very
    # next instruction -- cause=0x01 (Bounds/Length Violation, reused),
    # cap_idx=16 (the PCC sentinel, matching real CHERI's own
    # PCC_IDX=0x10). Proves the full real cycle: the trap's own
    # save-and-reset makes veda_mepcc_base/_length (CSRs 0x7c2/0x7c3)
    # hold the narrow bounds active at fault time, and the trap
    # handler's own explicit restore (a real write to veda_pcc_base/
    # _length, CSRs 0x7c0/0x7c1) correctly re-widens execution back to
    # unbounded before resuming at a real recovery point OUTSIDE the
    # abandoned compartment -- not an attempt to resume inside it, the
    # same real distinction real CHERI's own PCC-bounds-violation
    # handling makes from an ordinary skippable "use"-family violation.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    # -- Object_ID=80 (CODE): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=compartment_start, Length=0x0004 -- one instruction only. --
    la   t0, compartment_start
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 80
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 81
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=81 (DATA)

    li   x1, 82
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- Object_ID=82 (type authority)

    li   x1, 80
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 81
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 82
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- narrows PCC to [compartment_start, compartment_start+4)

compartment_start:
    addi x0, x0, 0                # the ONLY instruction inside the compartment -- fetch is genuinely in-bounds here
fault_instr:
    addi x0, x0, 0                # this fetch is OUTSIDE the compartment (compartment_start+4) -- must hard-trap

    li   x22, 0xDEAD                # must NOT be reached directly
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x201                 # (cap_idx=16<<5)|cause=0x01 = 0x201
    bne  t3, t4, fail

    csrr t3, mepc
    la   t4, fault_instr
    bne  t3, t4, fail

    # -- confirm veda_mepcc_* holds the narrow bounds live at fault time
    #    (the real save-and-reset already fired, inside the trap-taken
    #    logic itself, before this handler even started). --
    csrr t3, 0x7c2                 # veda_mepcc_base -- expect compartment_start's own address
    la   t4, compartment_start
    bne  t3, t4, fail
    csrr t3, 0x7c3                 # veda_mepcc_length -- expect 0x0004
    li   t4, 0x0004
    bne  t3, t4, fail

    li   x21, 0x600D               # sentinel: reached the handler with correct mcause/mtval/mepc/mepcc

    # -- explicit recovery: abandon the compartment, restore unbounded,
    #    resume at a real, safe address outside it. --
    li   t3, 0xFFFF
    csrw 0x7c1, t3                 # veda_pcc_length := unbounded
    csrw 0x7c0, x0                 # veda_pcc_base := 0 (irrelevant once length is unbounded)
    # RTL M21-restore mirror (MILESTONE_21_RESTORE_RTL_RESULTS.md): mret
    # now auto-restores PCC from veda_mepcc_base/_length whenever
    # mepcc_length != UNBOUNDED -- this test's own live-register restore
    # above (0x7c0/0x7c1) is no longer sufficient by itself, since mepcc
    # still holds the original narrow Length here (never cleared by that
    # write) and would otherwise re-narrow PCC right back down on the
    # mret below. Clearing mepcc_length too is the real, now-correct
    # override idiom -- matches the Sail side's own explicit-override
    # test property (vc_pcc_auto_restore_on_mret.S) exactly.
    csrw 0x7c3, t3                 # veda_mepcc_length := unbounded (t3 still 0xFFFF)
    la   t3, recovery
    csrw mepc, t3
    mret

recovery:
    csrr x23, 0x7c1                # pcc_length AFTER the explicit restore -- expect 0xFFFF
    li   x22, 0x900D               # sentinel: correctly resumed at the real recovery point
    j    done

fail:
    li   x22, 0xBAD

done:
1:
    j 1b
