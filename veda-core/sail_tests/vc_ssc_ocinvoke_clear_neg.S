.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # SSC Milestone: the real, load-bearing security property an
    # independent design review found necessary before any code was
    # written (see the SSC results doc). If SSC followed ODA/TSC's own
    # "untouched by OCInvoke" convention, a callee compartment would
    # silently inherit full OCL.D/OCS.D read/write access to whatever
    # stack region the caller had bound into SSC -- a real leak bigger
    # than the purecap trap this whole mechanism exists to safely
    # replace. This test proves the fix operationally, not just
    # structurally: (1) the caller binds a real, valid object into SSC;
    # (2) OCInvoke into a compartment; (3) inside the compartment, SSC
    # reads back genuinely untagged; (4) attempting an actual OCL.D
    # through that untagged value hard-traps (Tag Violation), the same
    # real gate every other Veda-Core "use" instruction already has --
    # proving the leak is closed at the point of *access*, not merely at
    # the point of register state.
    la   t0, trap_handler
    csrw mtvec, t0

    # -- Step 1: caller binds a real object (Object_ID=213, standing in
    #    for "the caller's own stack region") into SSC, from OUTSIDE any
    #    compartment. --
    li   x1, 213
    li   x2, 0x8003100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 213
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    .insn r 0x5b, 0x1, 0x13, x9, x1, x2  # ospecialrw c9(discard), ssc, c1  -- SSC := c1 (now tagged, real)

    # -- Step 2: the identical real compartment-entry fixture every prior
    #    OCInvoke test uses (CODE=210/DATA=211/type-authority=212),
    #    invoked so control lands at landing_pad. --
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 210
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE

    li   x1, 211
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA

    li   x1, 212
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority

    li   x1, 210
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 211
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 212
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC, and (this milestone) clears SSC's own tag

landing_pad:
    # -- Step 3+4: read SSC back (via a definitely-never-bound register,
    #    c9, as the throwaway "new" value -- we only care about the OLD
    #    value this read extracts), confirm untagged, then attempt an
    #    actual OCL.D through it -- must hard-trap, not silently read
    #    stale data. --
    .insn r 0x5b, 0x1, 0x13, x8, x9, x2  # ospecialrw c8, ssc, c9  -- c8 = SSC's OLD value (expect Tag=0, cleared by ocinvoke); ssc := c9 (untagged, harmless)
    .insn r 0x5b, 0x0, 0x03, x20, x8, x0  # cgettag x20, c8  -- expect 0

    li   x21, 0  # offset
    .insn r 0x0b, 0x3, 0x00, x22, x8, x21  # ocl.d c8, x21(=0), x22  -- MUST hard-trap: c8 is untagged

    RVMODEL_HALT_FAIL  # unreachable if the trap above fired correctly

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x102         # (cap_idx=8<<5)|cause=0x02 -- c8 held the readback of SSC's own (cleared)
                            # value, and cause=0x02 is Tag Violation -- confirms the trap fired for
                            # the right reason
    bne  t3, t4, check_fail
    li   t0, 0
    bne  x20, t0, check_fail  # also confirm the earlier cgettag really read 0, not a coincidental trap elsewhere
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
