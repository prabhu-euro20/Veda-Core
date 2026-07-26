.section .text
.global _start
_start:
    // Negative control for Veda-Core RTL Milestone 1's own OCS.D Tag
    // check, upgraded in Milestone 9 to a real trap-handler pattern now
    // that this RTL genuinely delivers hard traps instead of only
    // suppressing the write.
    //
    // Real bug found and fixed in this same milestone pass: this test's
    // own original version used Object_ID=2 to prove "an unpopulated
    // object's capability is untagged" -- true when this test was first
    // written (Milestone 1), but Milestone 2 later seeded Object_ID=2
    // into the RTL's own reset scaffold (veda_core.tlv's own initial
    // block) for an unrelated reason (a Permit_NMC_Compute-less object
    // for Milestone 2's own negative test) -- silently making Object_ID=2
    // VALID from that point on. The old test's own testbench
    // (tb_veda_smoke_neg.sv) also checked the WRONG memory address
    // (Object_ID=1's Base, 0x80010000, not Object_ID=2's own Base,
    // 0x80010100), so it kept reporting PASS the entire time for the
    // wrong reason -- the write was actually succeeding (c0 was really
    // tagged), just landing somewhere the old assertion never looked.
    // Found while designing this milestone's own trap-handler upgrade,
    // not by the old test failing on its own. Fixed by using Object_ID=50
    // (never populated by any RTL milestone's own reset scaffold or any
    // other test in this suite) and a real trap-handler that checks
    // mcause/mtval directly, not a raw memory snapshot.
    //
    // Milestone 13 update: plain Bind against a never-populated
    // Object_ID now genuinely hard-traps on its own (cause 0x05), which
    // would divert control flow before OCS.D below is ever reached --
    // this test's own real point is OCS.D's Tag check, not Bind's own
    // object-not-found trap (covered separately). Bind-NoTrap is the
    // architecturally correct instruction for "produce an untagged
    // capability without disrupting control flow" -- exactly its own
    // purpose since Milestone 8 -- so this Bind is switched to it here.
    la    t0, trap_handler
    csrw  mtvec, t0

    li    x1, 50
    .word 0x0010d00b     // veda.bind.notrap c0, x1 (Object_ID=50, never populated -> c0.Tag=0)
    li    x2, 0
    li    x3, 0x9999      // a value that must never actually land in memory
fault_instr:
    .word 0x0220318b       // ocs.d c0, x2, x3 -- c0 is untagged, must genuinely TRAP

    // Execution resumes here (mepc+4) after the handler's own MRET --
    // this is also where a MISSING trap would fall through to, so the
    // handler alone (not this point) is what sets x22 = 0x600D; if the
    // trap never fired at all, x22 stays at its reset value (0), a
    // real, distinct failure signature from a wrong mcause/mtval/mepc.
    j     done

trap_handler:
    csrr  t3, mcause
    li    t4, 0x18
    bne   t3, t4, fail
    csrr  t3, mtval
    li    t4, 0x02              // TAG_VIOLATION, cap_idx=0 (c0) -> (0<<5)|0x02=0x02
    bne   t3, t4, fail
    csrr  t3, mepc
    la    t4, fault_instr
    bne   t3, t4, fail

    addi  t3, t3, 4
    csrw  mepc, t3
    li    x22, 0x600D
    mret

fail:
    li    x22, 0xDEAD
done:
1:
    j 1b
