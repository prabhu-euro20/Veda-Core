.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL Milestone 13 negative test: plain Bind (mode=0)
    // against a never-populated Object_ID must hard-trap with the
    // real cause code 0x05 (VEDA_CAUSE_OBJECT_NOT_FOUND) -- the gap
    // Milestone 9 itself named and deliberately deferred
    // (MILESTONE_9_RESULTS.md's own "Also deliberately deferred" note),
    // closed here. Distinct in kind from Milestone 12's own owner-
    // violation (cause 0x06): this Object_ID has no ODT entry at all,
    // versus a live entry owned by someone else.
    //
    // Object_ID=70 is never populated by this RTL's own reset scaffold
    // (veda_core.tlv's `initial` block seeds only 1, 2, 60) or by this
    // test itself.
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 70
fault_instr:
    .word 0x0000d00b     // veda.bind c0, x1 -- Object_ID=70, never populated -- must hard-trap (cause 0x05)

    // Correct-resume sentinel -- MRET's own real PC redirect lands
    // EXACTLY here (mepc+4), mirroring veda_smoke_m12_neg.S's own
    // identical convention.
    li   x22, 0x900D
    // Destination register c0 must be COMPLETELY untouched by the trap
    // (Sail's own veda_trap() diverts control flow before wC()/wCTag()
    // are ever called) -- not even Tag cleared.
    .word 0x06000bdb      // cgettag  x23, c0   -- expect 0 (reset value, untouched)
    .word 0x00000c5b       // cgetbase x24, c0   -- expect 0 (reset value, untouched)
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x05          // cause=0x05 (Object Not Found), cap_idx=0 (c0)
    bne  t3, t4, fail

    // mepc must point at the OWN faulting Bind instruction.
    csrr t3, mepc
    la   t4, fault_instr
    bne  t3, t4, fail

    addi t3, t3, 4
    csrw mepc, t3
    li   x21, 0x600D          // sentinel: reached the handler with correct mcause/mtval/mepc
    mret

fail:
    li   x22, 0xBAD

done:
1:
    j 1b
