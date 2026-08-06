.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # SSC Milestone: the real, positive completion criterion -- a
    # hand-assembled proof standing in for what a future compiler
    # codegen mode would emit for an ordinary ABI-mandated register
    # spill/reload, run *inside* a live OCInvoke-entered compartment.
    #
    # Honest framing, stated plainly rather than overclaimed: OCL.D/OCS.D
    # against an already-bound CRF register were never blocked by
    # Milestone 19's purecap rule inside a compartment -- that rule is
    # scoped to ordinary base-ISA load/store only (veda_core.tlv's own
    # $veda_purecap_violation = ($is_load || $is_store) & ...; Veda-Core's
    # own "use" instructions were always exempt by construction). What
    # this test actually proves is narrower and real: the *intended
    # end-to-end usage pattern* -- a compartment establishing its own
    # SSC (since OCInvoke just cleared whatever was there before, per
    # vc_ssc_ocinvoke_clear_neg.S) and then using it for real spill/
    # reload traffic -- works correctly, giving a real, dedicated,
    # per-compartment-isolated register for a future compiler to target
    # instead of raw sd/ld (which purecap *does* still correctly trap).
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 220
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE

    li   x1, 221
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA

    li   x1, 222
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority

    li   x1, 220
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 221
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 222
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

landing_pad:
    # -- The compartment's own first action: establish its own SSC.
    #    Object_ID=223, a real, bounded (0x40) object -- standing in for
    #    "this compartment's own stack region". --
    li   x1, 223
    li   x2, 0x800410000040000C  # Base=0x80041000, Length=0x0040, Perms=0x000C (Load|Store)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 223
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1
    .insn r 0x5b, 0x1, 0x13, x9, x5, x2  # ospecialrw c9(discard), ssc, c5  -- SSC := c5 (this compartment's own, real)

    # -- A real spill/reload sequence: two distinct "callee-saved
    #    register" values, spilled to two distinct offsets within the
    #    same SSC-bound object, then reloaded and checked -- exercising
    #    more than one offset, matching how a real prologue/epilogue
    #    would use a growing stack frame. --
    li   x20, 0x11112222
    li   x21, 0x33334444
    li   x6, 0   # offset 0
    .insn r 0x0b, 0x3, 0x01, x20, x5, x6  # ocs.d c5, x6(=0), x20
    li   x7, 8   # offset 8
    .insn r 0x0b, 0x3, 0x01, x21, x5, x7  # ocs.d c5, x7(=8), x21

    .insn r 0x0b, 0x3, 0x00, x22, x5, x6  # ocl.d x22, c5, x6(=0)
    .insn r 0x0b, 0x3, 0x00, x23, x5, x7  # ocl.d x23, c5, x7(=8)

    li   x24, 0  # result flag: 0 = pass, 1 = fail
    li   t0, 0x11112222
    beq  x22, t0, check2
    li   x24, 1
check2:
    li   t0, 0x33334444
    beq  x23, t0, do_exit
    li   x24, 1

do_exit:
    # -- Real, honest completion: RVMODEL_HALT_PASS/FAIL themselves use
    #    ordinary sw, which purecap correctly still traps on while a
    #    compartment remains live -- exactly the property this whole
    #    milestone exists to enforce. A second, real OCInvoke (the
    #    already-established "compartment exit" pattern --
    #    STACK_FRAME_CALL_RETURN_ANALYSIS.md / rtl/MILESTONE_22_RESULTS.md:
    #    "the compartment's own eventual exit back to its invoker must
    #    use a second, real OCInvoke, never OCJALR") into a code
    #    capability whose own Length is VEDA_PCC_UNBOUNDED (0xFFFF)
    #    widens PCC back to unbounded, exactly like returning to an
    #    ordinary, non-compartmentalized caller -- only then is an
    #    ordinary sw (inside the halt macro) safe again.
    la   t0, exit_point
    slli t0, t0, 32
    li   t1, 0xFFFF0402   # Length=0xFFFF (unbounded), Perms=0x0402 (Execute|Invoke)
    or   t0, t0, t1
    li   x1, 224
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- exit CODE

    li   x1, 225
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- exit DATA

    li   x1, 224
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- exit CODE
    li   x1, 225
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- exit DATA
    # c2 still holds the original type authority (Object_ID=222) -- a
    # real, long-lived authority object, reused rather than re-derived,
    # matching this project's own established "bind once" convention.
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- widens PCC back to unbounded

exit_point:
    li   t0, 0
    bne  x24, t0, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    # Any trap here is a real failure -- this test's whole point is that
    # NO trap should fire for the spill/reload sequence or the
    # compartment-exit sequence itself.
    RVMODEL_HALT_FAIL
