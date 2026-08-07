.include "../sail_tests/veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    # Toolchain Milestone 11: hand-written compartment entry point that
    # invokes a REAL COMPILED C function (veda_compartment_demo.c,
    # attributed __attribute__((veda_compartment))), the real completion
    # criterion for SSC-routed callee-saved spills. Mirrors
    # sail_tests/vc_ssc_spill_reload.S's own already-proven ceremony
    # (ODT-Populate CODE/DATA/type-authority -> Bind -> CSeal -> OCInvoke),
    # extended with the real division-of-responsibility this milestone's
    # plan requires: THIS hand-written code establishes SSC (never the
    # compiler-generated function itself), exactly mirroring how TSC is
    # already re-primed by hand-written scheduler code in
    # runtime/veda_sched_asm.S, never by an individual compiled function.
    la   sp, _stack_top

    # Object_IDs 400-405 -- fresh, non-colliding block confirmed by
    # grepping every existing Object_ID literal across sail_tests/,
    # rtl/sim/, runtime/, and compiler/ before picking (highest prior use
    # was 330, in the SSC RTL smoke tests).

    # -- CODE: covers this glue's own landing_pad AND the compiled
    #    veda_compartment_demo_thread/its own callees, since OCInvoke
    #    narrows PCC to exactly this bound and every instruction executed
    #    after landing (hand-written or compiled) must lie inside it. --
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x04000402   # Length=0x0400 (1024B, comfortably covers the
                           # glue + compiled function), Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 400
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    # -- DATA: minimal, ceremony-only (this compartment's own real "data"
    #    is the dedicated stack-region object bound directly into C15
    #    below, not IDC) -- matches vc_ssc_spill_reload.S's own precedent
    #    of a real-but-unused DATA object completing the CSeal pair. --
    li   x1, 401
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    li   x1, 402
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- type authority

    li   x1, 400
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE
    li   x1, 401
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA
    li   x1, 402
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

landing_pad:
    # -- The compartment's own first action: establish SSC. A dedicated
    #    small stack-region object (Object_ID=403), Base = _stack_top -
    #    0x2000 (a real backing address, comfortably below the ordinary
    #    pre-compartment stack usage above it -- none occurred here, since
    #    every instruction before OCInvoke was register-only, matching
    #    this project's own established "_start code never needs real
    #    memory before the first compartment entry" pattern), Length =
    #    0x1000 -- must stay <= 0xFFFF (Length is bits(16) in the real
    #    capability struct, veda_types.sail), verified before writing this.
    #
    #    Bind it DIRECTLY into C15 (not a scratch register then copied):
    #    OSpecialRW's real Sail semantics (veda_cap_insts.sail's
    #    VEDA_OSPECIALRW execute clause, re-verified before writing this)
    #    are `rd := old SCR value; SCR := rs1's value` -- rs1 is read-only,
    #    so using C15 as rs1 both installs its value into SSC AND leaves
    #    C15 itself holding that same live capability afterward, with zero
    #    extra copy instruction. --
    la   t0, _stack_top
    addi t0, t0, -0x800   # ADDI's imm is 12-bit signed (-2048..2047); -0x800
                          # (=-2048) is the largest safe single-instruction
                          # margin, ample since no real stack memory is
                          # touched anywhere before this point.
    slli t0, t0, 32
    li   t1, 0x1000000C   # Length=0x1000, Perms=0x000C (Load|Store)
    or   t0, t0, t1
    li   x1, 403
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- STACK_REGION
    li   x1, 403
    .insn i 0x0b, 0x5, x15, x1, 0  # veda.bind c15, x1
    .insn r 0x5b, 0x1, 0x13, x14, x15, x2  # ospecialrw c14(discard-old), ssc, c15 -- SSC := c15

    # -- Real, load-bearing architectural convention this milestone
    #    requires (see TOOLCHAIN_MILESTONE_11_RESULTS.md):
    #    veda_check_access computes real_loc = cap.Base + offset
    #    (veda_ocl_insts.sail, re-verified before writing this), and
    #    cap.Length is only 16 bits -- far too narrow for SP's ordinary,
    #    real absolute address (~0x8001xxxx). Inside a veda_compartment
    #    function's own call graph, SP must therefore be a SMALL, LOGICAL,
    #    SSC-region-relative offset (0 = this region's own Base, growing
    #    down from Length like an ordinary stack), NOT a raw absolute
    #    address -- a deliberate, honestly-stated departure from ordinary
    #    RV64 ABI semantics, required by the 16-bit Length field. This
    #    hand-written entry point performs that one-time repurposing;
    #    compiled veda_compartment code itself is unaffected (its own
    #    codegen already only ever computes SP + constant, unchanged
    #    either way). --
    li   sp, 0x1000

    li   a0, 5             # 5 iterations -- expect the compiled function
                           # to return 5, exercising >1 iteration so the
                           # loop body (and its OCS.D-routed spill/reload)
                           # genuinely executes more than once.
    call veda_compartment_demo_thread

    li   x24, 0  # result flag: 0 = pass, 1 = fail
    li   t0, 5
    beq  a0, t0, do_exit
    li   x24, 1

do_exit:
    # -- Real, honest completion: RVMODEL_HALT_PASS/FAIL themselves use
    #    ordinary sw, which purecap correctly still traps on while a
    #    compartment remains live -- the established "compartment exit
    #    needs a second, real OCInvoke into an unbounded code capability"
    #    pattern (STACK_FRAME_CALL_RETURN_ANALYSIS.md /
    #    rtl/MILESTONE_22_RESULTS.md), identical to
    #    vc_ssc_spill_reload.S's own do_exit. --
    la   t0, exit_point
    slli t0, t0, 32
    li   t1, 0xFFFF0402   # Length=0xFFFF (unbounded), Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 404
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- exit CODE

    li   x1, 405
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- exit DATA

    li   x1, 404
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- exit CODE
    li   x1, 405
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- exit DATA
    # c2 still holds the original type authority (Object_ID=402).
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
    # Any trap here is a real failure -- this test's whole point is that
    # NO trap (especially no VEDA_CAUSE_PURECAP_VIOLATION) should fire for
    # the compiled function's own prologue/epilogue spill/reload sequence.
    RVMODEL_HALT_FAIL
