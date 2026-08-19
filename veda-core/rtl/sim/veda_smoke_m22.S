.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 22: mirrors Sail's own
    # vc_ocjalr_compartment_boundary_neg.S finding in real RTL. OCJALR
    # (Milestone 17) does NOT touch veda_pcc_base/_length -- unlike
    # OCInvoke, which narrows PCC as a deliberate part of its own real
    # compartment-entry semantics, OCJALR is a plain jump_to() with no
    # PCC interaction at all. From inside a live OCInvoke compartment, a
    # genuinely valid, properly-authorized sealed return-capability
    # (Tag/Seal/Permit_Unseal/matching-otype/Permit_Execute all correctly
    # satisfied) targeting an address OUTSIDE the compartment's own
    # bounds still hard-traps the moment execution fetches at that
    # target -- because veda_pcc_length is still narrowed to the
    # original compartment. This is NOT a security escape (Milestone
    # 14's own fetch-check remains the real backstop) -- it is a real
    # scope boundary: OCJALR alone cannot cross a compartment boundary.
    # The correct, already-established primitive for that is a SECOND
    # OCInvoke (the exact pattern veda_smoke_m10.S already proves
    # works). This test proves the RTL side matches Sail's own already-
    # verified finding, closing the last RTL-parity gap named in
    # veda-core/MILESTONE_22_RESULTS.md's own "Not yet built" section.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    # -- Object_ID=93 (RETURN TARGET, outside the compartment):
    #    Permit_Execute only, Base=return_landing. Built and sealed
    #    BEFORE OCInvoke -- capability registers are not cleared by
    #    OCInvoke, only PCC narrows, so c6/c7 survive into the
    #    compartment as the real, legitimate "call-site-prepared return
    #    capability" pattern. --
    la   t0, return_landing
    slli t0, t0, 32
    li   t1, 0x01000002        # Length=0x0100, Perms=0x0002 (Permit_Execute)
    or   t0, t0, t1
    li   x1, 93
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- RETURN TARGET

    # -- Object_ID=94: type-authority for the return-capability's own
    #    seal, Permit_Seal|Permit_Unseal. --
    li   x1, 94
    li   x2, 0x8001100000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority (return)

    li   x1, 93
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- RETURN TARGET, unsealed
    li   x1, 94
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1  -- type authority (return)

    .insn r 0x5b, 0x1, 0x10, x7, x5, x6  # cseal c7, c5, c6  -- sealed RETURN capability

    # -- The compartment itself: Object_ID=90/91/92 (CODE/DATA/type
    #    authority). CODE Length=0x0004 -- one instruction only (the
    #    OCJALR below), matching veda_smoke_m14_neg.S's own minimal-
    #    compartment convention. --
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x00040402        # Length=0x0004, Perms=0x0402 (Execute|Invoke)
    or   t0, t0, t1
    li   x1, 90
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE

    li   x1, 91
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA

    li   x1, 92
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority (compartment)

    li   x1, 90
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 91
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 92
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority (compartment)

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [landing_pad, landing_pad+4)

landing_pad:
    # -- c7 (sealed return cap) and c6 (type authority) were prepared
    #    before entry and persist across the OCInvoke jump. This is the
    #    ONLY instruction inside the compartment's own narrow bounds. --
    .insn r 0x5b, 0x1, 0x14, x0, x7, x6  # ocjalr c7, c6  -- attempt to jump outside the compartment

    # If OCJALR somehow fell through without jumping or trapping,
    # execution would reach here -- this address (landing_pad+4) is
    # itself already outside the compartment's own bounds, so it too
    # would fault, but with a DIFFERENT mepc than return_landing's own
    # address -- the trap handler's mepc check below distinguishes the
    # two cases precisely.
    li   x20, 0xBAD
    j    done

.balign 4
trap_handler:
    # -- the load-bearing assertions: a real PCC-fetch violation
    #    (cause=0x01, cap_idx=16, the same real sentinel Milestone 14's
    #    own compartment-escape enforcement already uses), mepc equal to
    #    return_landing's OWN address (proving OCJALR's jump_to() really
    #    resolved and redirected PC there BEFORE the fetch-check caught
    #    it -- not just "some fetch outside bounds failed"), and
    #    veda_pcc_length correctly back to VEDA_PCC_UNBOUNDED by the time
    #    this handler runs (Milestone 21's own fix). --
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x201              # (cap_idx=16<<5)|cause=0x01 = 0x201
    bne  t3, t4, fail
    csrr t3, mepc
    la   t4, return_landing
    bne  t3, t4, fail
    csrr t3, 0x7c1               # veda_pcc_length -- expect VEDA_PCC_UNBOUNDED
    li   t4, 0xFFFFF
    bne  t3, t4, fail

    li   x21, 0x600D             # sentinel: handler reached with correct mcause/mtval/mepc/pcc_length
    j    done

return_landing:
    # -- reached only if OCJALR somehow DID succeed in jumping outside
    #    the compartment without a fault -- would mean this milestone's
    #    own finding was wrong in RTL, a real regression to investigate. --
    li   x22, 0xE5CD
    j    done

fail:
    li   x23, 0xBAD

done:
1:
    j 1b
