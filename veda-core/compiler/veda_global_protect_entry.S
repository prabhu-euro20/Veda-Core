.include "../sail_tests/veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    la   sp, _stack_top

    # Toolchain Milestone 13: hand-written compartment entry point that
    # invokes a REAL COMPILED C function (veda_global_protect_demo.c,
    # attributed __attribute__((veda_compartment))) whose two module
    # -scope globals (`g_lower[4]`, `g_upper[4]`) are protected from
    # overflowing into each other by the new Phase B1 GlobalVariable
    # recognition logic in VedaShadowPropagation.cpp -- individually
    # -bounded per-global capabilities, minted once at bootstrap (below)
    # and cached in an in-memory capability table, real CHERI's own
    # __cap_relocs property (see TOOLCHAIN_MILESTONE_13_DESIGN.md).
    #
    # Object_IDs 422-430, a fresh block one past Milestone 12's own
    # highest use (421, veda_alloca_protect_entry.S) -- confirmed via the
    # same grep-audit discipline every prior milestone used before
    # picking a fresh block.

    # ================================================================
    # Step 1: establish the two SOURCE region capabilities (c8, c9) and
    # the capability-TABLE region (c11), and mint every in-scope global's
    # own exact capability, ALL before the first OCInvoke -- "wide open"
    # PCC, purecap enforcement genuinely not yet active
    # (VEDA_CORE_SPEC.md Section 3: gated on veda_mode.veda_purecap OR
    # live OCInvoke-narrowing, neither holds here), so veda_rt_init_globals
    # below is called as a completely ordinary C function (real absolute
    # sp, standard ABI, no compartment convention in effect yet) -- not
    # veda_compartment-attributed, unlike every OTHER runtime helper this
    # milestone adds.
    # ================================================================

    # -- .rodata SOURCE region -> c8. Base/Length are REAL, runtime-
    #    computed values (the real linker symbols this milestone's own
    #    veda_rt.ld addition provides), not compile-time literals, unlike
    #    every prior milestone's own entry-point Object_ID descriptors --
    #    a real, new wrinkle this milestone's own bootstrap step
    #    introduces. Perms=0x0004 (Load only) -- .rodata-derived globals
    #    must never be writable, even via a narrowed capability. --
    la   t2, __rodata_start
    la   t3, __rodata_end
    sub  t4, t3, t2
    slli t0, t2, 32
    slli t4, t4, 16
    ori  t4, t4, 0x0004
    or   t0, t0, t4
    li   x1, 422
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- RODATA_REGION
    li   x1, 422
    .insn i 0x0b, 0x5, x8, x1, 0  # veda.bind c8, x1

    # -- .data+.bss SOURCE region -> c9. __data_start..__bss_end is ONE
    #    contiguous span honestly over-covering the small .tohost gap the
    #    real linker script places between .data and .bss -- see that
    #    file's own comment for the full reasoning (harmless: an
    #    Object_ID's own bounds accounting never affects an ordinary
    #    access to the same physical bytes). Perms=0x000C (Load|Store). --
    la   t2, __data_start
    la   t3, __bss_end
    sub  t4, t3, t2
    slli t0, t2, 32
    slli t4, t4, 16
    ori  t4, t4, 0x000C
    or   t0, t0, t4
    li   x1, 423
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA_BSS_REGION
    li   x1, 423
    .insn i 0x0b, 0x5, x9, x1, 0  # veda.bind c9, x1

    # -- capability-TABLE region -> c11 (PERSISTENT: held across every
    #    subsequent OCInvoke/OCRETURN crossing for the rest of the
    #    program's life, unlike c8/c9 above, which are bootstrap-only and
    #    discarded the moment minting finishes). Length=0x100 (256B,
    #    matching g_veda_global_cap_table's own real, hardcoded C array
    #    size -- runtime/veda_rt.h/.c). Perms=0x000C (Load|Store: OCL.C
    #    reads a slot at every access, OCS.C writes one during minting). --
    la   t0, g_veda_global_cap_table
    slli t0, t0, 32
    li   t1, 0x0100000C   # Length=0x100, Perms=Load|Store
    or   t0, t0, t1
    li   x1, 424
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CAP_TABLE_REGION
    li   x1, 424
    .insn i 0x0b, 0x5, x11, x1, 0  # veda.bind c11, x1

    # Real bug found and fixed via a real sail_riscv_sim trace (not
    # assumed): x2 IS sp -- every `mv x2, t0` above (the SAME convention
    # veda_alloca_protect_entry.S's own CODE/DATA/type-authority setup
    # already uses) harmlessly clobbers sp there ONLY because nothing
    # reads it again before `li sp, 0x1000` much later, at landing_pad.
    # veda_rt_init_globals is a genuine, ordinary C function call (its own
    # real prologue does `addi sp,sp,-0x20; sd ra,0x18(sp)`), inserted
    # HERE, before that re-establishment point -- confirmed via trace: a
    # real store/amo-access-fault at veda_rt_init_globals+16, sp still
    # holding the STALE capability-table descriptor value from the `mv
    # x2, t0` two instructions above, not a real stack address. Fixed by
    # re-establishing the real sp here, immediately before the one call
    # in this whole ceremony that genuinely needs it before landing_pad.
    la   sp, _stack_top

    call veda_rt_init_globals   # mints every in-scope global's own capability

    # ================================================================
    # Step 2: ordinary compartment-entry ceremony (identical shape to
    # Milestone 12's own veda_alloca_protect_entry.S).
    # ================================================================
    la   t0, landing_pad
    slli t0, t0, 32
    # Length=0x2000 (8192B) -- a real, empirically-driven increase from
    # Milestone 12's own 0x1000: this program links substantially MORE
    # code than Milestone 12's own (the new bootstrap-minting chain, on
    # top of the per-access global-helper chain) -- verified via
    # riscv64-unknown-elf-size/-nm on the linked ELF before finalizing
    # this number, the identical empirical discipline Milestone 12's own
    # entry point used (see TOOLCHAIN_MILESTONE_12_RESULTS.md).
    li   t1, 0x20000402   # Length=0x2000, Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 425
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    li   x1, 426
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    li   x1, 427
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- type authority

    li   x1, 425
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE
    li   x1, 426
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA
    li   x1, 427
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

landing_pad:
    # -- Establish SSC (Milestone 11/12's own real ceremony, unchanged --
    #    this milestone's own globals mechanism shares NOTHING with SSC,
    #    a real, deliberate design choice: c11's own table-region
    #    capability is completely independent of c15). --
    la   t0, _stack_top
    addi t0, t0, -0x800
    slli t0, t0, 32
    li   t1, 0x1000000C   # Length=0x1000, Perms=Load|Store
    or   t0, t0, t1
    li   x1, 428
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- STACK_REGION
    li   x1, 428
    .insn i 0x0b, 0x5, x15, x1, 0  # veda.bind c15, x1
    .insn r 0x5b, 0x1, 0x13, x14, x15, x2  # ospecialrw c14(discard-old), ssc, c15

    li   sp, 0x1000  # logical, region-relative -- see veda_compartment_entry.S's
                     # own comment for the full real reasoning (16-bit Length).

    call veda_global_protect_thread   # no arguments -- (void)

    li   x24, 0  # result flag: 0 = pass, 1 = fail
    li   t0, 113  # g_lower[3](=13) + g_upper[0](=100) -- the real,
                 # checkable in-bounds result (see
                 # veda_global_protect_demo.c's own header comment).
    beq  a0, t0, do_exit
    li   x24, 1

do_exit:
    la   t0, exit_point
    slli t0, t0, 32
    li   t1, 0xFFFF0402   # Length=0xFFFF (unbounded), Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 429
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- exit CODE

    li   x1, 430
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- exit DATA

    li   x1, 429
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- exit CODE
    li   x1, 430
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- exit DATA
    # c2 still holds the original type authority (Object_ID=427).
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
    # Positive build: any trap here is a real failure -- g_lower[3]/
    # g_upper[0] are both genuinely in-bounds.
    #
    # Negative build (VEDA_OOB_INDEX=4): a trap here IS the expected,
    # positive proof of inter-global isolation -- but this handler alone
    # cannot distinguish "the right trap" from "some other bug's trap", so
    # run_veda_global_protect_test.sh separately re-runs the negative ELF
    # under --trace-instr --trace-exception --trace-csr and greps the real
    # trace for the exact expected mcause/mtval, the identical honest
    # completion criterion Milestone 12's own test already established.
    RVMODEL_HALT_FAIL
