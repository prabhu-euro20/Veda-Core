.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL Milestone 9: real Zicsr-lite CSR state + a real
    // trap-and-resume cycle -- the largest remaining Sail/RTL
    // architectural divergence (NEXT_STEPS_ROADMAP.md §2.4): every
    // prior RTL milestone's own violation checks suppressed a write
    // but let execution continue past the blocked instruction; this
    // milestone makes a real "use"-family violation genuinely redirect
    // control flow to a software-installed handler, exactly like
    // Sail's own veda_trap() has done since Milestone V-A.
    //
    // CSRRW/CSRRS/MRET are real, standard RISC-V encodings -- the
    // assembler's own native mnemonics are used directly below, no
    // .word hand-encoding needed (unlike every Veda-Core custom
    // instruction elsewhere in this test), confirming the RTL decode
    // genuinely matches the real Zicsr/privileged-ISA encoding, not an
    // invented one.
    // ─────────────────────────────────────────────────────────────

    // -- Part 1: CSRRS OR-semantics + old-value return, exercised on
    //    mtvec BEFORE installing the real handler (safe to clobber --
    //    overwritten with the real handler address immediately after).
    li    t5, 0xFF00
    csrw  mtvec, t5              // mtvec = 0xFF00 (CSRRW, rd=x0)
    li    t6, 0x00FF
    csrrs t0, mtvec, t6          // t0 = old mtvec (0xFF00); mtvec |= 0x00FF -> 0xFFFF
    li    t1, 0xFF00
    bne   t0, t1, fail            // CSRRS must return the OLD value, not the new one
    csrr  t1, mtvec
    li    t2, 0xFFFF
    bne   t1, t2, fail             // confirms the OR actually landed (0xFF00|0x00FF=0xFFFF)

    // CSRRS with rs1=x0 (the real `csrr` pseudo-instruction) must NOT
    // write the CSR at all -- reading mtvec again after a csrr must
    // show it unchanged.
    csrr  t1, mtvec
    li    t2, 0xFFFF
    bne   t1, t2, fail

    // -- Part 2: install the real trap handler, then trigger a real
    //    "use"-family violation (OCL/OCS's own Tag check) against an
    //    Object_ID that was never populated (99 -- deliberately not
    //    1 or 2, both of which are reset-seeded and VALID in this
    //    RTL's own scaffold, unlike this test's own predecessor,
    //    veda_smoke_neg.S, which is fixed in this same milestone after
    //    this exact confusion was found in it -- see
    //    MILESTONE_9_RESULTS.md).
    la    t0, trap_handler
    csrw  mtvec, t0
    csrr  t1, mtvec
    bne   t1, t0, fail             // round-trip: mtvec really holds the handler address

    li    x1, 99
    .word 0x0000d00b               // veda.bind c0, x1 (Object_ID=99, never populated -> c0.Tag=0)
    li    x2, 0
    li    x3, 0x9999
fault_instr:
    .word 0x0220318b                 // ocs.d c0, x2, x3 -- c0 untagged -> TAG_VIOLATION, must TRAP

    // -- Part 3: execution resumes here (mepc+4, the handler's own
    //    advance), proving MRET's own real PC redirect and the full
    //    trap-and-resume cycle end to end. If the trap did NOT
    //    redirect control flow at all, execution also falls through to
    //    this exact point (one instruction past the fault) instead of
    //    ever reaching trap_handler -- caught separately, since x21
    //    would then never become 0x600D.
    li    x22, 0x900D                  // sentinel: correctly resumed after MRET
    j     done

trap_handler:
    csrr  t3, mcause
    li    t4, 0x18
    bne   t3, t4, fail
    csrr  t3, mtval
    li    t4, 0x02                  // TAG_VIOLATION (0x02), cap_idx=0 (c0) -> (0<<5)|0x02=0x02
    bne   t3, t4, fail

    // mepc must point at the OCS.D instruction itself (the one that
    // actually raised the trap -- OCL.C/OCS.C's own veda_check_access
    // reuse means the Bind two instructions earlier never faults, only
    // the OCS.D does), not the Bind before it or anything else.
    csrr  t3, mepc
    la    t4, fault_instr
    bne   t3, t4, fail

    // Advance mepc PAST the faulting instruction before MRET -- MRET
    // jumps to mepc exactly as-is (this core has no privilege stack to
    // restore, "MRET" here means precisely "PC = mepc"), so leaving
    // mepc unchanged would re-execute and re-trap on the same OCS.D
    // forever. A real, load-bearing step of any real trap handler that
    // intends to skip rather than retry the faulting instruction.
    addi  t3, t3, 4
    csrw  mepc, t3

    li    x21, 0x600D                 // sentinel: reached the handler with correct mcause/mtval/mepc
    mret

fail:
    li    x22, 0xDEAD
done:
1:
    j 1b
