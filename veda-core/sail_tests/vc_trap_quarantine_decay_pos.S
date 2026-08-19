.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # TRAP_QUARANTINE_DESIGN.md verification plan, positive companion to
    # vc_repeated_trap_dos_neg.S: "a compartment that faults twice, then
    # makes real forward progress via a clean return, then faults twice
    # more, must NOT be quarantined." Proves the decay side of the
    # mechanism is real, not merely that the threshold side works.
    #
    # Three phases, same compartment IDENTITY (otype=0, derived from
    # CSeal's `otype = cs2.Offset[15..0]` against a single, never-moved
    # type-authority capability c2 -- Offset stays zero for the whole
    # test, so every capability sealed with c2, narrow or wide, shares
    # the identical tracker entry) --
    #
    #   Phase 1: 2 real PCC-bounds-violation faults against a Length=4
    #            narrow compartment (Object_ID 480/481/482). Tracker
    #            count for otype=0 goes 0 -> 1 -> 2. Below threshold (3),
    #            so no quarantine trap is expected here -- this phase
    #            alone is not the interesting case, it just seeds the
    #            counter close to the edge.
    #   Phase 2: a genuine, clean OCInvoke into a WIDE compartment
    #            (Object_ID 483/484, Length=0x40, same otype=0) that
    #            executes real body code and exits via OCRETURN through
    #            a sentry minted before entry (mirrors
    #            vc_ocreturn_basic.S's own already-verified pattern).
    #            OCRETURN's own success path calls
    #            veda_trap_tracker_decay(veda_pcc_otype) -- veda_pcc_otype
    #            is 0 (the compartment being LEFT) at that point, so this
    #            resets otype=0's count 2 -> 0.
    #   Phase 3: 2 more real PCC-bounds-violation faults against the SAME
    #            narrow compartment identity. If decay were fake (or
    #            never wired), the tracker would still read 2 from phase
    #            1, and phase 3's SECOND OCInvoke attempt would already
    #            be the 4th real trap against this otype -- refused with
    #            VEDA_CAUSE_COMPARTMENT_QUARANTINED instead of faulting
    #            ordinarily. This test's trap handler hard-fails on ANY
    #            cause other than the ordinary bounds violation, so
    #            reaching `done` with phase 3's counter at 2 is itself the
    #            proof the streak restarted from zero.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x9,  0                    # phase-1 fault counter
    li   x10, 0                    # phase-3 fault counter
    li   x21, 0                    # sentinel: 1 once wide_entry's real body executes
    li   x22, 0                    # fail-reason code, 0 = no failure recorded yet
    li   x26, 0                    # phase flag: 0 = phase 1, 1 = phase 3
    li   x27, 2                    # PHASE_REPEAT_COUNT, both phase 1 and phase 3

    # -- Object_ID=480 (CODE_NARROW): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=compartment_narrow_start, Length=0x0004 -- one instruction
    #    only, the identical fault-inducing shape
    #    vc_repeated_trap_dos_neg.S already established and verified. --
    la   t0, compartment_narrow_start
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 480
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=481 (DATA_N): Permit_Invoke only = 0x0400. --
    li   x1, 481
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=482 (TYPE authority): Permit_Seal|Permit_Unseal=0x0300.
    #    Bound ONCE and never moved (no CIncOffset) -- its Offset stays
    #    zero for the whole test, which is exactly what makes every
    #    capability CSeal'd against it (narrow AND wide) share otype=0. --
    li   x1, 482
    li   x2, 0x80010a0000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 480
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE_NARROW
    li   x1, 481
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA_N
    li   x1, 482
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- TYPE authority

phase1_reinvoke:
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed CODE_NARROW
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed DATA_N
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- must trap (bounds)

fail_unexpected_no_trap:
    li   x22, 0xBAD1                # compartment_narrow_start's own second
                                     # instruction was somehow reached, or
                                     # ocinvoke itself fell through.
    j    real_fail

compartment_narrow_start:
    nop                              # the ONE instruction Length=0x0004 permits.
    j    fail_unexpected_no_trap

.balign 4
trap_handler:
    # Every real trap in this test, phase 1 or phase 3, must be the
    # ordinary compartment-bounds violation (cause=0x01, cap_idx=16, the
    # PCC sentinel -- matching vc_pcc_bounds_neg.S's own convention). A
    # quarantine-refusal trap (cause=0x09) here at any point is itself a
    # test failure -- it would mean phase 1's residual count leaked into
    # phase 3 (decay didn't really happen), or the mechanism misfired.
    csrr t4, 0x343                  # mtval
    andi t5, t4, 0x1f               # cause (low 5 bits)
    li   t6, 0x01
    bne  t5, t6, fail_cause_mismatch
    srli t5, t4, 5                  # cap_idx
    li   t6, 16
    bne  t5, t6, fail_cause_mismatch

    beqz x26, phase1_count
    j    phase3_count

phase1_count:
    addi x9, x9, 1
    blt  x9, x27, phase1_reinvoke
    j    phase1_done

phase3_count:
    addi x10, x10, 1
    blt  x10, x27, phase3_reinvoke
    j    phase3_done

fail_cause_mismatch:
    li   x22, 0xDEAD
    j    real_fail

phase1_done:
    # -- Phase 2: mint an OCRETURN sentry BEFORE entering the wide
    #    compartment (capability registers other than PCC survive
    #    OCInvoke, exactly vc_ocreturn_basic.S's own "prepared before
    #    entry" pattern). Object_ID=485, Base=return_landing,
    #    Length=UNBOUNDED (0xFFFFF), Perms=Execute only. --
    la   t0, return_landing
    mv   x20, t0                    # save expected Base for the post-return check
    li   t1, 0xFFFFF0002            # veda_attr: Length=0xFFFFF, Perms=0x0002
    csrw 0x7c4, t1
    li   x1, 485
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2  # veda.odt.populate.fast x5, x1, x2

    li   x1, 485
    .insn i 0x0b, 0x5, x8, x1, 0          # veda.bind c8, x1  -- sentry source

    .insn r 0x5b, 0x1, 0x15, x9, x8, x0   # csealentry c9, c8  -- MINT sentry
                                           # (x9 here is a CRF index literal in
                                           # the .insn r encoding, NOT the GPR
                                           # x9 phase-1 fault counter -- capability
                                           # registers c0-c15 are a separate
                                           # register file from x0-x31.)

    # -- Object_ID=483 (CODE_WIDE): Base=wide_entry, Length=0x0040 --
    #    real room for a body plus OCRETURN. Sealed with the SAME type
    #    authority c2 (Object_ID 482, Offset still 0) as the narrow
    #    compartment -- shares the identical otype=0 tracker identity. --
    la   t0, wide_entry
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 483
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE_WIDE

    # -- Object_ID=484 (DATA_WIDE): Permit_Invoke only. --
    li   x1, 484
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA_WIDE

    li   x1, 483
    .insn i 0x0b, 0x5, x10, x1, 0  # veda.bind c10, x1  -- CODE_WIDE
    li   x1, 484
    .insn i 0x0b, 0x5, x11, x1, 0  # veda.bind c11, x1  -- DATA_WIDE
    .insn r 0x5b, 0x1, 0x10, x6, x10, x2  # cseal c6, c10, c2  -- sealed CODE_WIDE
    .insn r 0x5b, 0x1, 0x10, x7, x11, x2  # cseal c7, c11, c2  -- sealed DATA_WIDE

    .insn r 0x5b, 0x1, 0x12, x0, x6, x7  # ocinvoke c6, c7  -- narrows PCC to wide_entry
    j    fail_unexpected_wide_no_entry    # must NOT be reached

wide_entry:
    # -- real forward progress, genuinely inside the wide compartment. --
    li   x21, 0x3333
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0  # ocreturn c9 -- widen PCC to sentry
                                          # bounds, jump to return_landing. Its
                                          # own success path decays otype=0's
                                          # tracker entry (2 -> 0) BEFORE
                                          # resetting veda_pcc_otype.
    j    fail_unexpected_wide_no_entry    # must NOT be reached -- OCRETURN fell through

fail_unexpected_wide_no_entry:
    li   x22, 0xBAD2
    j    real_fail

.balign 4
return_landing:
    # -- load-bearing assertion: OCRETURN genuinely crossed back out. --
    csrr t3, 0x7c1                       # veda_pcc_length
    li   t4, 0xFFFFF
    bne  t3, t4, fail_return_mismatch
    csrr t3, 0x7c0                       # veda_pcc_base
    bne  t3, x20, fail_return_mismatch

    li   x26, 1                          # enter phase 3
    li   x10, 0

phase3_reinvoke:
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- re-seal CODE_NARROW
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- re-seal DATA_N
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- must trap (bounds,
                                          # NOT quarantine -- this is the real
                                          # claim under test)
    j    fail_unexpected_no_trap

fail_return_mismatch:
    li   x22, 0xBAD3
    j    real_fail

phase3_done:
    # -- the real finding this test proves: phase 1 faulted exactly
    #    twice, the wide compartment's own body genuinely executed, and
    #    phase 3 faulted exactly twice more -- every one of those four
    #    total real faults was the ordinary bounds violation (checked
    #    per-trap above), never the quarantine refusal, because the
    #    clean OCRETURN in between reset the streak. --
    li   t2, 2
    bne  x9, t2, real_fail
    li   t2, 0x3333
    bne  x21, t2, real_fail
    li   t2, 2
    bne  x10, t2, real_fail
    li   t2, 0
    bne  x22, t2, real_fail

    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
