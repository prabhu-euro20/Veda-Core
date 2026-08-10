.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core -- PoC / permanent regression test for a real,
    # empirically-confirmed privilege-escalation gap, found while
    # explaining the Milestone-21 PCC-restore-on-mret mechanism, not
    # invented speculatively:
    #
    # MILESTONE_20_RESULTS.md already found and documented that mtvec (the
    # standard RISC-V trap-vector CSR) has zero compartment-aware gating --
    # any OCInvoke'd compartment can rewrite it with an ordinary csrw, no
    # trap. At the time this was judged not independently exploitable,
    # because an *ordinary* trap left veda_pcc_length narrowed across the
    # trap, so a handler placed outside the compartment's own bounds would
    # immediately fetch-fault itself (that doc's own words: "this gap does
    # not, by itself, let a compartment jump to attacker-chosen code
    # outside its own bounds").
    #
    # Milestone 21 (handle_trap_extension, universal PCC-reset-on-any-trap)
    # deliberately removed exactly that backstop, for good, independent
    # functional reasons (it is what makes any real system handler
    # reachable at all): PCC now unconditionally resets to unbounded
    # BEFORE the trap-vector target is computed and fetched, for every
    # trap regardless of cause -- confirmed directly in this project's own
    # sys_control.sail: handle_trap_extension(...) runs strictly before
    # prepare_trap_vector(...).
    #
    # Nobody appears to have gone back and re-examined the mtvec gap in
    # light of that change. Combined, the two already-independently-true
    # facts compose into a real escape: a compartment can (1) rewrite
    # mtvec to point at attacker-chosen code -- anywhere, not even
    # necessarily outside its own writable memory, (2) trigger any
    # ordinary trap (a plain ecall suffices) -- and that attacker code now
    # runs with fully unbounded PCC, and (per Milestone 20's own gate
    # condition, "currently unbounded") can go on to freely rewrite its
    # own compartment bounds too.
    #
    # This test asserts the SECURE outcome (mtvec write from inside a
    # bounded compartment must hard-trap, mirroring Milestone 20's own
    # 0x7c0-0x7c3/0x7c5 gate exactly) as its primary, load-bearing check.
    # Run against the current, unfixed model, that assertion is expected
    # to genuinely FAIL -- the empirical confirmation the vulnerability is
    # real, matching this project's own established discipline (the same
    # thing Milestone 19/20 each did before any fix was designed). A
    # second, independent marker (x23) directly proves whether the
    # attacker's own payload got to execute at all, for unambiguous
    # diagnosis regardless of how the primary check comes out.
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x00400402          # Length=0x0040
    or   t0, t0, t1
    li   x1, 60
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate  CODE

    li   x1, 61
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate  DATA

    li   x1, 62
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate  type authority

    li   x1, 60
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 61
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 62
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    li   x23, 0xFEED              # "attacker payload never ran" sentinel, set from unconstrained context

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [landing_pad, landing_pad+0x40)

landing_pad:
    # ---- attacker-controlled code, now running inside the Length=0x40 compartment ----
    la   t3, evil_target          # address OUTSIDE this compartment's own [landing_pad, +0x40) bounds
    csrw mtvec, t3                # the attack: redirect the trap vector -- SHOULD hard-trap once fixed
    ecall                         # if the write above silently succeeded, this lands in evil_target instead of trap_handler
    li   x21, 0xBAD1
    li   x22, 0xBAD2
    j    done

.balign 4
trap_handler:
    # legitimate target -- reached whenever mtvec is genuinely still this
    # handler's own address (either the csrw above was correctly blocked,
    # or some other trap landed here first).
    csrr t3, mcause
    li   t4, 2                    # Illegal_Instruction -- write_CSR's own Err(()) mechanism, Milestone 20's exact convention
    bne  t3, t4, fail

    la   t3, trap_handler
    csrr t5, mtvec
    bne  t3, t5, fail              # mtvec must still point here, unchanged by the blocked write

    li   x21, 0x600D
    li   x22, 0x900D
    j    done

.balign 4
evil_target:
    # attacker's payload -- placed deliberately OUTSIDE the compartment's
    # own Length=0x40 window. Reaching this at all, with unbounded PCC, is
    # the vulnerability itself, independent of the x21/x22 check above.
    li   x23, 0xE5CA               # ESCAPED marker: unauthorized code ran here
    j    done

fail:
    li   x21, 0xDEAD
    li   x22, 0xDEAD

done:
    li   t2, 0x600D
    bne  x21, t2, real_fail
    li   t2, 0x900D
    bne  x22, t2, real_fail
    li   t2, 0xFEED
    bne  x23, t2, real_fail        # x23 must still read the untouched init value -- 0xE5CA here means the escape happened

    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
