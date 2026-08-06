.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of SSC's own real, load-bearing security
    # property (SSC_STACK_SPILL_CAPABILITY_DESIGN.md, mirrors Sail's
    # vc_ssc_ocinvoke_clear_neg.S): OCInvoke must clear SSC on every
    # successful compartment-boundary crossing, or a callee would
    # silently inherit full OCL.D/OCS.D access to the caller's stack
    # region. Proves operationally: (1) the caller binds a real object
    # into SSC; (2) OCInvoke into a compartment; (3) inside, SSC reads
    # back untagged; (4) an attempted OCL.D through it hard-traps.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    # -- Step 1: caller binds a real object (Object_ID=310, standing in
    #    for "the caller's own stack region") into SSC. --
    li   x1, 310
    li   x2, 0x8003100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 310
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    .insn r 0x5b, 0x1, 0x13, x9, x1, x2  # ospecialrw c9(discard), ssc, c1  -- SSC := c1

    # -- Step 2: the identical real compartment-entry fixture every
    #    prior OCInvoke RTL test uses (CODE=311/DATA=312/type-authority
    #    =313). --
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 311
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE

    li   x1, 312
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA

    li   x1, 313
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority

    li   x1, 311
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 312
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 313
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC, and clears SSC's own tag

landing_pad:
    # -- Step 3+4: read SSC back (via c9, a definitely-never-bound
    #    register, as the throwaway "new" value), confirm untagged, then
    #    attempt an actual OCL.D through it -- must hard-trap. --
    .insn r 0x5b, 0x1, 0x13, x8, x9, x2  # ospecialrw c8, ssc, c9  -- c8 = SSC's OLD value (expect Tag=0)
    .insn r 0x5b, 0x0, 0x03, x20, x8, x0  # cgettag x20, c8  -- expect 0

    li   x21, 0
    .insn r 0x0b, 0x3, 0x00, x22, x8, x21  # ocl.d c8, x21(=0), x22  -- MUST hard-trap: c8 is untagged

    li   x23, 0xBAD1  # must NOT be reached
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x18
    bne  t4, t5, fail
    csrr t4, mtval
    li   t5, 0x102       # (cap_idx=8<<5)|cause=0x02 -- c8 held the readback of SSC's own cleared value
    bne  t4, t5, fail

    li   x23, 0x600D     # sentinel: reached the handler with the correct mcause/mtval

    la   t4, recovery
    csrw mepc, t4
    mret

recovery:
    li   x24, 0x900D    # sentinel: correctly resumed
    j    done

fail:
    li   x23, 0xBAD

done:
1:
    j 1b
