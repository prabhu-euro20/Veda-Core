.include "../sail_tests/veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    # Toolchain Milestone 11 follow-up: closes the "nested veda_compartment
    # calls untested" gap TOOLCHAIN_MILESTONE_11_RESULTS.md's own "Not yet
    # built" section named honestly. Identical ceremony to
    # veda_compartment_entry.S (read that file's own comments for the full
    # rationale on SSC->C15 establishment and the SP-repurposing
    # convention); this file only differs in which compiled function it
    # invokes and what result it expects.
    la   sp, _stack_top

    # Object_IDs 410-415 -- a fresh block, one past veda_compartment_entry.S's
    # own 400-405 (grepped to confirm no collision before picking).

    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x08000402   # Length=0x0800 (2048B -- larger than the base
                           # milestone's own 0x0400, since this test covers
                           # two real compiled functions, outer_fn+inner_fn,
                           # not one), Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 410
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    li   x1, 411
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    li   x1, 412
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- type authority

    li   x1, 410
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE
    li   x1, 411
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA
    li   x1, 412
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

landing_pad:
    la   t0, _stack_top
    addi t0, t0, -0x800
    slli t0, t0, 32
    li   t1, 0x1000000C   # Length=0x1000, Perms=0x000C (Load|Store)
    or   t0, t0, t1
    li   x1, 413
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- STACK_REGION
    li   x1, 413
    .insn i 0x0b, 0x5, x15, x1, 0  # veda.bind c15, x1
    .insn r 0x5b, 0x1, 0x13, x14, x15, x2  # ospecialrw c14(discard-old), ssc, c15 -- SSC := c15

    li   sp, 0x1000

    # outer_fn(5) internally calls inner_fn 5 times: counter starts at 1,
    # doubles each call -> 1*2*2*2*2*2 = 32. outer_fn and inner_fn both
    # pin a local to x20/s4 -- the exact aliasing scenario the SP+offset
    # fix in RISCVFrameLowering.cpp exists to prevent. A wrong result here
    # (anything but 32) would mean the two frames' own SSC-routed spill
    # slots collided.
    li   a0, 5
    call outer_fn

    li   x24, 0  # result flag: 0 = pass, 1 = fail
    li   t0, 32
    beq  a0, t0, do_exit
    li   x24, 1

do_exit:
    # Toolchain Milestone 21-fix -- see veda_alloca_protect_entry.S's
    # identical fix for the full reasoning (Length/Offset widening moved
    # VEDA_PCC_UNBOUNDED from 0xFFFF to 0xFFFFF; plain populate cannot
    # represent it, so populate.fast + veda_attr is required here).
    li   t1, 0xFFFFF0402   # veda_attr: Length=0xFFFFF (unbounded), Perms=Execute|Invoke
    csrw 0x7c4, t1
    la   t0, exit_point
    li   x1, 414
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2  # veda.odt.populate.fast x5, x1, x2 -- exit CODE

    li   x1, 415
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- exit DATA

    li   x1, 414
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- exit CODE
    li   x1, 415
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- exit DATA
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4 -- widens PCC back to unbounded

exit_point:
    li   t0, 0
    bne  x24, t0, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    RVMODEL_HALT_FAIL
