.include "../sail_tests/veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    la   sp, _stack_top

    # Toolchain Milestone 20-fix (TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_
    # RESULTS.md Test 3 -> TOOLCHAIN_MILESTONE_20_GLOBAL_GEP_RESULTS.md):
    # findGlobalRoot now recurses through a GEP chain instead of resolving
    # only one hop, so `g_arr[i].value` (a global ARRAY OF STRUCTS,
    # requiring array-index-GEP + field-GEP to resolve back to @g_arr) is
    # now correctly recognized by Phase B1 -- meaning this entry point,
    # UNLIKE its own pre-fix version, now genuinely needs the full
    # bootstrap-minting ceremony (mirrors veda_global_protect_entry.S's own
    # Step 1 exactly), which it previously never performed (g_arr was never
    # routed through that path at all before this fix).
    #
    # Object_IDs 440-448 (unchanged range from the pre-fix version) --
    # 446/447/448 newly added here for the bootstrap step (RODATA_REGION/
    # DATA_BSS_REGION/CAP_TABLE_REGION), the three IDs this range's own
    # original "440-448, fresh block" comment already reserved but the
    # pre-fix version never needed.

    # ================================================================
    # Step 1 (NEW): establish the two SOURCE region capabilities (c8, c9)
    # and the capability-TABLE region (c11), and mint g_arr's own exact
    # capability, ALL before the first OCInvoke -- "wide open" PCC, real
    # purecap enforcement not yet active. Identical shape to
    # veda_global_protect_entry.S's own Step 1.
    # ================================================================
    la   t2, __rodata_start
    la   t3, __rodata_end
    sub  t4, t3, t2
    slli t0, t2, 32
    slli t4, t4, 16
    ori  t4, t4, 0x0004
    or   t0, t0, t4
    li   x1, 446
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- RODATA_REGION
    li   x1, 446
    .insn i 0x0b, 0x5, x8, x1, 0  # veda.bind c8, x1

    la   t2, __data_start
    la   t3, __bss_end
    sub  t4, t3, t2
    slli t0, t2, 32
    slli t4, t4, 16
    ori  t4, t4, 0x000C
    or   t0, t0, t4
    li   x1, 447
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA_BSS_REGION
    li   x1, 447
    .insn i 0x0b, 0x5, x9, x1, 0  # veda.bind c9, x1

    la   t2, __veda_global_cap_table_bytes
    ld   t2, 0(t2)
    slli t2, t2, 16
    ori  t2, t2, 0x000C
    la   t0, g_veda_global_cap_table
    slli t0, t0, 32
    or   t0, t0, t2
    li   x1, 448
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CAP_TABLE_REGION
    li   x1, 448
    .insn i 0x0b, 0x5, x11, x1, 0  # veda.bind c11, x1

    la   sp, _stack_top   # re-establish real sp before the ordinary C call
                          # below (same real fix veda_global_protect_entry.S
                          # already needed and documented for the identical
                          # reason -- x2 doubles as sp, clobbered above).

    call veda_rt_init_globals   # mints g_arr's own capability

    # ================================================================
    # Step 2: ordinary compartment-entry ceremony (unchanged from the
    # pre-fix version).
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

    # Toolchain Milestone 20-fix: the NORMAL pass/fail convention (unlike
    # the pre-fix version, whose own question was "did it trap or not") --
    # g_arr[2].value should now be correctly, capability-checked-ly
    # computed as 0x2a (42), matching the C source's own real, in-bounds
    # semantics. A trap here is now a genuine, unexpected failure (this
    # access is legitimately in-bounds), not the expected/positive outcome
    # the pre-fix version treated it as.
    li   x24, 0  # result flag: 0 = pass, 1 = fail
    li   t0, 0x2a
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
    li   x1, 444
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2  # veda.odt.populate.fast x5, x1, x2 -- exit CODE

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
    li   t0, 0
    bne  x24, t0, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    # Toolchain Milestone 20-fix: a trap here is now a genuine failure --
    # g_arr[2].value is legitimately in-bounds and should never trap
    # post-fix.
    csrw 0x7c5, x0   # clear veda_mode.veda_purecap defensively before
                     # signaling, mirroring MILESTONE_19_RESULTS.md's own
                     # documented trap-loop-avoidance fix.
    RVMODEL_HALT_FAIL
