.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 22 -- a real, empirically-confirmed scope
    # boundary found while auditing compartmentalization against Simon
    # Moore's/CHERI's own real pillars: OCJALR (`vc_ocjalr.S`'s own
    # sealed-return-capability verify-and-jump) does NOT reset
    # veda_pcc_base/_length -- unlike OCInvoke, which narrows PCC as a
    # deliberate part of its own real compartment-entry semantics, OCJALR
    # is a plain `jump_to()` with no PCC interaction at all (confirmed by
    # reading its execute clause in full). This was never previously
    # tested in combination with a live compartment (`vc_ocjalr.S`
    # exercises it entirely outside any OCInvoke) -- an honest gap in
    # test coverage, not a previously-known-and-accepted limitation.
    #
    # Real, empirical finding: from inside a live OCInvoke compartment, a
    # genuinely valid, properly-authorized sealed return-capability
    # (Tag/Seal/Permit_Unseal/matching-otype/Permit_Execute all correctly
    # satisfied) targeting an address OUTSIDE the compartment's own
    # bounds still hard-traps on the very next instruction fetch at that
    # target -- because veda_pcc_length is still narrowed to the original
    # compartment when that fetch is attempted. This is NOT a security
    # escape (Milestone 14's own fetch-check remains the real backstop,
    # exactly as intended) -- it is a real scope boundary: OCJALR alone
    # cannot be used to cross a compartment boundary. The correct,
    # already-established primitive for that is a SECOND OCInvoke (into a
    # return-authorized code/data capability pair, widening PCC back to
    # unbounded as part of its own real narrowing logic) -- the exact
    # pattern `vc_pcc_bounds.S`/`vc_ocinvoke.S` (post-Milestone-19 fix)
    # already prove works. Milestone 21's own generic-trap PCC-reset fix
    # means the resulting fault is at least *safely recoverable* now
    # (reaches a real trap handler rather than hanging) -- this test
    # documents and locks in that recoverable-but-blocked behavior, so a
    # future OS implementer sees it fail loudly and predictably in the
    # test suite rather than discovering it the hard way.
    la   t0, generic_trap_handler
    csrw mtvec, t0

    # -- Object_ID=70 (the OUTSIDE return target): Permit_Execute only,
    #    deliberately far from the compartment's own code. --
    la   t0, return_landing
    slli t0, t0, 32
    li   t1, 0x01000002
    or   t0, t0, t1
    li   x1, 70
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate  RETURN TARGET

    # -- Object_ID=71: type-authority, shared by the compartment's own
    #    entry seal and the return-capability seal. --
    li   x1, 71
    li   x2, 0x8001100000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate  type authority

    li   x1, 70
    .insn i 0x0b, 0x5, x6, x1, 0   # veda.bind c6, x1  -- RETURN TARGET, unsealed
    li   x1, 71
    .insn i 0x0b, 0x5, x1, x1, 0   # veda.bind c1, x1  -- type authority

    # -- Seal the return target BEFORE entering the compartment, matching
    #    the real "prepare a sealed return-capability at the call site"
    #    convention. --
    .insn r 0x5b, 0x1, 0x10, x2, x6, x1  # cseal c2, c6, c1  -- sealed RETURN capability, otype=c1.Offset=0

    # -- The compartment itself: Object_ID=60/61/62 (CODE/DATA/type
    #    authority), Length=0x40, deliberately narrow. --
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x00400402
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
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, 61
    .insn i 0x0b, 0x5, x3, x1, 0
    li   x1, 62
    .insn i 0x0b, 0x5, x4, x1, 0
    .insn r 0x5b, 0x1, 0x10, x7, x0, x4  # cseal c7, c0, c4
    .insn r 0x5b, 0x1, 0x10, x8, x3, x4  # cseal c8, c3, c4

    .insn r 0x5b, 0x1, 0x12, x0, x7, x8  # ocinvoke c7, c8  -- narrows PCC to [landing_pad, landing_pad+0x40)

landing_pad:
    # c2 (sealed return cap) and c1 (type authority) were prepared before
    # entry and persist across the OCInvoke jump (capability registers
    # are not cleared by OCInvoke, only PCC narrows) -- the real,
    # legitimate "call-site-prepared return capability" pattern.
    .insn r 0x5b, 0x1, 0x14, x0, x2, x1  # ocjalr c2, c1  -- attempt to jump outside the compartment
    li   x21, 0xBAD                      # must NOT be reached -- would mean OCJALR silently reset PCC
    j    done

.balign 4
generic_trap_handler:
    # -- the load-bearing assertion: a real PCC-fetch violation
    #    (cause=0x01, cap_idx=16, the same real sentinel/cause Milestone
    #    14's own compartment-escape enforcement already uses), and
    #    veda_pcc_length correctly back to VEDA_PCC_UNBOUNDED by the time
    #    this handler runs (Milestone 21's own fix -- proving the fault
    #    is safely recoverable, not a hang). --
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, real_fail
    csrr t3, mtval
    li   t4, 0x201                       # (cap_idx=16<<5)|cause=0x01 = 0x201
    bne  t3, t4, real_fail
    csrr t3, 0x7c1
    li   t4, 0xFFFFF
    bne  t3, t4, real_fail
    li   x21, 0x600D
    j    done

return_landing:
    # -- reached only if OCJALR somehow DID succeed in jumping outside
    #    the compartment without a fault -- would mean this milestone's
    #    own finding was wrong, a real regression to investigate. --
    li   x21, 0xE5CD
    j    done

done:
    li   t2, 0x600D
    bne  x21, t2, real_fail
    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
