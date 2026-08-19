.include "../sail_tests/veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    # Toolchain Milestone 12: hand-written compartment entry point that
    # invokes a REAL COMPILED C function (veda_alloca_protect_demo.c,
    # attributed __attribute__((veda_compartment))) whose two entry-block
    # local arrays (`lower[4]`, `upper[4]`) are protected from overflowing
    # into each other by the new Phase B0 alloca-recognition logic in
    # VedaShadowPropagation.cpp. Establishes SSC exactly as
    # veda_compartment_entry.S already does (Milestone 11) -- this
    # milestone reuses that same ceremony verbatim, since Phase B0's own
    # local-variable offsets share the SAME C15 region as Milestone 11's
    # callee-saved spills, just a disjoint sub-range within it.
    la   sp, _stack_top

    # Object_IDs 416-421 -- a fresh, non-colliding block, re-verified by
    # grep across every existing .S file's own "li x1, N" Object_ID
    # literals before picking (an earlier draft of this file wrongly
    # assumed 410-415 was free; veda_compartment_nested_entry.S already
    # owns that exact block -- highest real prior use is 415).

    la   t0, landing_pad
    slli t0, t0, 32
    # Length=0x1000 (4096B) -- a real, empirically-driven increase from
    # M11's own 0x0400: this is the FIRST compartment-attributed function
    # to CALL genuinely external, separately-linked code from inside a
    # live OCInvoke-narrowed PCC (Phase B0 redirects every tracked
    # load/store into a call to veda_rt_ocl_stack_d/veda_rt_ocs_stack_d,
    # defined in veda_compiler_rt.c/veda_rt.c/veda_rt_asm.S -- all linked
    # AFTER this function in .text). M11's own demo never called anything
    # external, so 0x0400 was never tested against this case. Confirmed
    # via a real PCC-fetch-violation trap (mtval=0x201, cap_idx=0x10=
    # ext_handle_fetch_check_error's own sentinel, postlude/step_ext.sail)
    # before this fix: riscv64-unknown-elf-size/-nm on the linked ELF
    # showed landing_pad at 0x9c and the LAST runtime-helper symbol
    # (veda_ocs_stack_d_scratch_asm) ending at 0x718 -- 0x67c (1660B) past
    # landing_pad, exceeding the old 0x400 (1024B) bound. 0x1000
    # comfortably covers this with >2x headroom, matching this project's
    # own established "comfortably covers" convention (M11's own
    # justification for its original 0x400). Real, honest scope note: this
    # widens the CODE capability, NOT the SSC/data capability -- it does
    # not weaken this milestone's own actual claim (stack-local DATA
    # isolation via OCA/CSetBounds/OCL.D/OCS.D), which is orthogonal to
    # PCC's separate code-bounding property (M10/M14's own concern, not
    # this milestone's).
    li   t1, 0x10000402   # Length=0x1000, Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 416
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    li   x1, 417
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    li   x1, 418
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- type authority

    li   x1, 416
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE
    li   x1, 417
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA
    li   x1, 418
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

landing_pad:
    # -- Establish SSC (identical ceremony to veda_compartment_entry.S,
    #    same Base/Length/Perms convention: dedicated stack-region object,
    #    Length=0x1000 matching kVedaSSCRegionLength in
    #    VedaShadowPropagation.cpp -- a real, hand-maintained cross-file
    #    constant, see that file's header comment). --
    la   t0, _stack_top
    addi t0, t0, -0x800
    slli t0, t0, 32
    li   t1, 0x1000000C   # Length=0x1000, Perms=Load|Store
    or   t0, t0, t1
    li   x1, 419
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- STACK_REGION
    li   x1, 419
    .insn i 0x0b, 0x5, x15, x1, 0  # veda.bind c15, x1
    .insn r 0x5b, 0x1, 0x13, x14, x15, x2  # ospecialrw c14(discard-old), ssc, c15

    li   sp, 0x1000  # logical, region-relative -- see veda_compartment_entry.S's
                     # own comment for the full real reasoning (16-bit Length).

    call veda_alloca_protect_thread   # no arguments -- veda_alloca_protect_thread(void)

    li   x24, 0  # result flag: 0 = pass, 1 = fail
    li   t0, 113  # lower[3](=13) + upper[0](=100) -- the real, checkable
                 # in-bounds result (see veda_alloca_protect_demo.c's own
                 # header comment for the full derivation).
    beq  a0, t0, do_exit
    li   x24, 1

do_exit:
    # Toolchain Milestone 21-fix (2026-08-19 Length/Offset widening,
    # commit 9de3742, moved VEDA_PCC_UNBOUNDED from 16-bit 0xFFFF to
    # 20-bit 0xFFFFF): plain VEDA_ODT_POPULATE's Length field stays
    # permanently 16-bit-capped by design and can never represent the new
    # sentinel, so this exit-CODE object must use VEDA_ODT_POPULATE_FAST +
    # veda_attr instead, mirroring vc_ocinvoke.S's own already-fixed
    # pattern -- otherwise the exit OCInvoke installs a still-"bounded"
    # (Length=0xFFFF != 0xFFFFF) PCC and the plain RVMODEL_HALT_PASS `sw`
    # right after it hard-traps under Milestone 19's purecap enforcement.
    li   t1, 0xFFFFF0402   # veda_attr: Length=0xFFFFF (unbounded), Perms=Execute|Invoke
    csrw 0x7c4, t1
    la   t0, exit_point
    li   x1, 420
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2  # veda.odt.populate.fast x5, x1, x2 -- exit CODE

    li   x1, 421
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- exit DATA

    li   x1, 420
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- exit CODE
    li   x1, 421
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- exit DATA
    # c2 still holds the original type authority (Object_ID=418).
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4 -- widens PCC back

exit_point:
    li   t0, 0
    bne  x24, t0, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    # Positive build: any trap here is a real failure -- lower[3]/upper[0]
    # are both genuinely in-bounds, so no OCS.D/OCL.D against the
    # CSetBounds-narrowed C13 scratch capability should ever fault.
    #
    # Negative build (VEDA_OOB_INDEX=4): a trap here IS the expected,
    # positive proof of inter-variable isolation -- but this handler alone
    # cannot distinguish "the right trap" from "some other bug's trap", so
    # run_veda_alloca_protect_test.sh separately re-runs the negative ELF
    # under --trace-instr --trace-exception --trace-csr and greps the real
    # trace for the exact expected mcause/mtval, per this milestone's own
    # honest completion criterion -- this handler's job is only to halt
    # cleanly (FAIL from a "did it print SUCCESS" perspective) so the sim
    # run terminates and the trace file is complete.
    RVMODEL_HALT_FAIL
