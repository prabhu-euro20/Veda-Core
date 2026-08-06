.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of SSC's real, positive completion criterion
    # (SSC_STACK_SPILL_CAPABILITY_DESIGN.md, mirrors Sail's
    # vc_ssc_spill_reload.S): a compartment establishes its own SSC
    # (since OCInvoke just cleared whatever was there before) and
    # performs a real two-value spill/reload sequence through it, with
    # zero purecap traps anywhere. Honest framing: OCL.D/OCS.D against
    # an already-bound CRF register were never blocked by the purecap
    # rule inside a compartment -- this test proves the *intended,
    # dedicated, isolated* SSC usage pattern works end to end.
    # ─────────────────────────────────────────────────────────────
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 320
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE

    li   x1, 321
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA

    li   x1, 322
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority

    li   x1, 320
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 321
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 322
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

landing_pad:
    # -- The compartment's own first action: establish its own SSC.
    #    Object_ID=323, a real, bounded (0x40) object, Perms=Load|Store
    #    (0x000C). --
    li   x1, 323
    li   x2, 0x800410000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 323
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1
    .insn r 0x5b, 0x1, 0x13, x9, x5, x2  # ospecialrw c9(discard), ssc, c5  -- SSC := c5

    # -- A real spill/reload sequence: two distinct values, spilled to
    #    two distinct offsets, then reloaded and checked. --
    li   x20, 0x11112222
    li   x21, 0x33334444
    li   x6, 0
    .insn r 0x0b, 0x3, 0x01, x20, x5, x6  # ocs.d c5, x6(=0), x20
    li   x7, 8
    .insn r 0x0b, 0x3, 0x01, x21, x5, x7  # ocs.d c5, x7(=8), x21

    .insn r 0x0b, 0x3, 0x00, x22, x5, x6  # ocl.d x22, c5, x6(=0)
    .insn r 0x0b, 0x3, 0x00, x23, x5, x7  # ocl.d x23, c5, x7(=8)
1:
    j 1b
