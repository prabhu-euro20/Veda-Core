.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL Milestone 12 negative test: plain Bind (mode=0)
    // against a LIVE object owned by a genuinely different hart must
    // hard-trap with the new cause code 0x06 (VEDA_CAUSE_OWNER_
    // VIOLATION) -- distinct in kind from "object not found" (0x05,
    // still RTL's existing deferred soft-fail per MILESTONE_9_RESULTS.md):
    // the object genuinely exists, this hart simply isn't its owner.
    //
    // Object_ID=60 is the RTL reset-seeded fixture (veda_core.tlv's own
    // top-level `initial` block), pre-claimed by owner_hart=0x63 (99
    // decimal) -- a stand-in "other hart," since this single-core RTL
    // testbench has no real second hart to own anything with (MHARTID
    // is a fixed localparam=0).
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x3, 60
fault_instr:
    .insn i 0x0b, 0x5, x0, x3, 0  // veda.bind c0, x3   -- Object_ID=60, owned by hart 0x63 -- must hard-trap (cause 0x06)

    // Correct-resume sentinel -- MRET's own real PC redirect lands
    // EXACTLY here (mepc+4, the handler's own advance past the fault),
    // mirroring veda_smoke_m9.S's own identical convention.
    li   x22, 0x900D
    // Destination register c0 must be COMPLETELY untouched by the trap
    // (Sail's own veda_trap() diverts control flow before wC()/wCTag()
    // are ever called) -- not even Tag cleared, unlike every soft-fail
    // path elsewhere in this project. c0 was never bound before this
    // test's own faulting instruction, so its true reset value (Tag=0,
    // Base=0) is the only value that proves nothing wrote to it at all.
    .insn r 0x5b, 0x0, 0x03, x23, x0, x0  // cgettag  x23, c0   -- expect 0 (reset value, untouched)
    .insn r 0x5b, 0x0, 0x00, x24, x0, x0  // cgetbase x24, c0   -- expect 0 (reset value, untouched)
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x06          // cause=0x06 (Owner Violation), cap_idx=0 (c0)
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
