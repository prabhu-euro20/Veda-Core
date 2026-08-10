.include "../sail_tests/veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    la   sp, _stack_top

    # Toolchain Milestone 13 scope-limit probe: hand-written compartment
    # entry point, directly modeled on veda_global_protect_entry.S, that
    # invokes a REAL COMPILED C function (veda_demo_struct_array_global.c,
    # attributed __attribute__((veda_compartment))) whose global is a
    # STRUCT ARRAY (`struct node g_arr[4]`) accessed via a chained
    # array-index-GEP + field-GEP pair -- findGlobalRoot's own documented
    # "Only single-level GEPs are handled" scope limit predicts this
    # access is left completely UNREWRITTEN (an ordinary LLVM ld/sd, no
    # OCL.D/OCS.D rewrite). This entry point tests what actually happens
    # to that unrewritten access at runtime: does it silently succeed (a
    # real protection gap), or does Milestone 19's blanket purecap
    # enforcement (any raw load/store while inside a live OCInvoke
    # compartment hard-traps, regardless of target) catch it anyway?
    #
    # Object_IDs 440-448, a fresh block past every milestone's own
    # highest prior use (Milestone 13 itself used 422-430; 431-439 left
    # as a buffer for any concurrently-running sibling test) -- confirmed
    # via grep-audit of every existing .S file's own `li x1, <NNN>`
    # Object_ID literal before picking this block.
    #
    # Unlike veda_global_protect_entry.S, this demo's global (`g_arr`) is
    # NEVER routed through Phase B1's GlobalVariable-recognition path at
    # all (findGlobalRoot fails to resolve it), so there is no bootstrap
    # -minting step to perform here -- no c8/c9/c11 source-region setup,
    # no veda_rt_init_globals call. g_arr lives in .bss like any ordinary
    # C global, reached only by the plain ld/sd the compiler already
    # emits for it.

    # ================================================================
    # Ordinary compartment-entry ceremony (identical shape to
    # veda_global_protect_entry.S's own Step 2, renumbered Object_IDs).
    # ================================================================
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x20000402   # Length=0x2000, Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 440
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    li   x1, 441
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    li   x1, 442
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- type authority

    li   x1, 440
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE
    li   x1, 441
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA
    li   x1, 442
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

landing_pad:
    # -- Establish SSC (identical ceremony to every prior compartment demo). --
    la   t0, _stack_top
    addi t0, t0, -0x800
    slli t0, t0, 32
    li   t1, 0x1000000C   # Length=0x1000, Perms=Load|Store
    or   t0, t0, t1
    li   x1, 443
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- STACK_REGION
    li   x1, 443
    .insn i 0x0b, 0x5, x15, x1, 0  # veda.bind c15, x1
    .insn r 0x5b, 0x1, 0x13, x14, x15, x2  # ospecialrw c14(discard-old), ssc, c15

    li   sp, 0x1000  # logical, region-relative

    call veda_struct_array_global_thread   # no arguments -- (void)

    # If we get here, the call RETURNED without trapping -- meaning the
    # unrewritten g_arr[i].value access silently succeeded (the "real
    # protection gap" branch of the empirical question). Set x24=2 as a
    # distinct "returned-without-trap" sentinel (distinct from the
    # ordinary 0=pass/1=fail convention every prior demo used, since
    # THIS demo's pass/fail question is "did it trap or not", not "was
    # the arithmetic correct").
    li   x24, 2
    mv   x23, a0   # stash the returned value for post-hoc inspection too

    j do_exit

do_exit:
    la   t0, exit_point
    slli t0, t0, 32
    li   t1, 0xFFFF0402   # Length=0xFFFF (unbounded), Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 444
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- exit CODE

    li   x1, 445
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- exit DATA

    li   x1, 444
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- exit CODE
    li   x1, 445
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- exit DATA
    # c2 still holds the original type authority (Object_ID=442).
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4 -- widens PCC back

exit_point:
    # x24==2 means "returned without trapping" -- report as HALT_FAIL so
    # this test's PASS/FAIL polarity matches the trap-catcher convention
    # (veda_demo_oob_neg.c): a trap firing is the EXPECTED/positive
    # outcome here (purecap catches the unrewritten access), so the
    # untrapped-return path is the one this script must flag distinctly.
    # run_veda_struct_array_global_test.sh distinguishes "trapped" from
    # "ran to completion" purely by sail_riscv_sim's own exit code/output,
    # same discipline veda_demo_oob_neg.c's own harness already uses --
    # this HALT_FAIL is a deliberate, informative marker for the
    # "silently succeeded" branch, not a test-infrastructure failure.
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    # A trap here is the EXPECTED/positive outcome for THIS demo's real
    # empirical question (does purecap catch the unrewritten access) --
    # unlike every prior compartment demo, where trap_handler firing was
    # always the FAILURE path. We cannot call csrr from here and still
    # reliably signal via the normal RVMODEL_HALT_PASS macro (its own
    # `sd`/`sw` to tohost would ITSELF be just another ordinary,
    # non-Veda store, at risk of re-triggering the very same purecap
    # enforcement this handler is trying to report on, mirroring
    # MILESTONE_19_RESULTS.md's own documented "trap loop" pitfall) --
    # so, matching that doc's own fix, explicitly clear veda_purecap
    # before signaling completion.
    csrw 0x7c5, x0   # clear veda_mode.veda_purecap before HALT signaling
    RVMODEL_HALT_PASS
