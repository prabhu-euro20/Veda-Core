.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL Milestone 18 negative test: proves veda_attr's
    // Length field is genuinely load-bearing for VEDA_ODT_POPULATE_FAST,
    // not just plumbed through and ignored -- a deliberately small
    // Length (0x8) set via veda_attr must genuinely bound-check a later
    // access, exactly like a small Length would under plain Populate
    // (reuses the same, already-proven $veda_ocs_violation/bounds-check
    // datapath -- this test targets only the new instruction's own
    // field-sourcing).
    //
    // Object_ID=61, clear of every other RTL smoke test's own seeded/
    // used IDs (reset-seeded fixtures + veda_smoke_m18.S's own ID=6).
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x20, 0x0008100c    // veda_attr = Length=0x8 (deliberately small), Perms=0x100C
    csrw 0x7c4, x20

    li   x1, 61
    li   x2, 0x80010700     // Base, direct
    .insn r 0x0b, 0x0, 0x04, x0, x1, x2  // veda.odt.populate.fast x0, x1, x2

    .insn i 0x0b, 0x5, x1, x1, 0  // veda.bind c1, x1

    li   x6, 0x10            // offset 0x10, width 8 -> offset+width=0x18 > Length=0x8
    li   x7, 0x99
fault_instr:
    .insn r 0x0b, 0x3, 0x01, x7, x1, x6  // ocs.d c1, x6, x7 -- must hard-trap Bounds Violation

    // MRET's own real PC redirect lands EXACTLY here (mepc+4, the
    // handler's own advance past the fault). If the trap never fired at
    // all, control falls through to this same line WITHOUT ever setting
    // x21 below -- so x21 staying at its reset value (0, not 0x600D)
    // alone already catches that failure mode, no separate check needed
    // (mirrors veda_smoke_m12_neg.S's own identical convention).
    li   x22, 0x900D
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x21              // cause=0x01 (Bounds Violation), cap_idx=1 (c1)
    bne  t3, t4, fail

    csrr t3, mepc
    la   t4, fault_instr
    bne  t3, t4, fail

    addi t3, t3, 4
    csrw mepc, t3
    li   x21, 0x600D            // sentinel: reached handler with correct mcause/mtval/mepc
    mret

fail:
    li   x21, 0xBAD

done:
1:
    j 1b
