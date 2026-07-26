.section .text
.global _start
_start:
    // Negative control for Veda-Core RTL Milestone 2's own NMC_ADD
    // permission check -- upgraded in Milestone 9 to check a real hard
    // trap (mcause=0x18, mtval=PERM_NMC_COMPUTE_VIOLATION via c1) rather
    // than only confirming the write was suppressed. Object_ID=2's own
    // Perms (0x000C, Load+Store only, no Permit_NMC_Compute) is correct
    // as originally written -- unlike veda_smoke_neg.S's own Object_ID
    // mistake, this test's premise was never wrong, only its own
    // assertion mechanism needed real trap support to exist first.
    la    t0, trap_handler
    csrw  mtvec, t0

    li   x1, 2          // Object_ID = 2 -- Load+Store only, NO Permit_NMC_Compute
    .word 0x0000d00b    // veda.bind c0, x1
    li   x2, 0x10         // OCA delta
    .word 0x142010db       // oca c1, c0, x2   (c1.Offset = 0x10; OCA itself needs no permission)
    li   x4, 0x23             // value operand (irrelevant, should never be used)
    li   x5, 0x5555             // sentinel: must stay unchanged if NMC_ADD is correctly blocked
fault_instr:
    .word 0x0440b28b               // nmc_add.d x5, c1, x4 -- c1 lacks Permit_NMC_Compute, must genuinely TRAP

    // Execution resumes here (mepc+4) after the handler's own MRET --
    // also where a MISSING trap would fall through to; the handler
    // alone sets x22 = 0x600D, so a missing trap leaves x22 at its
    // reset value (0), a distinct failure signature from a wrong
    // mcause/mtval/mepc/x5.
    j     done

trap_handler:
    csrr  t3, mcause
    li    t4, 0x18
    bne   t3, t4, fail
    csrr  t3, mtval
    li    t4, 0x3F               // PERM_NMC_COMPUTE_VIOLATION (0x1f), cap_idx=1 (c1) -> (1<<5)|0x1f=0x3F
    bne   t3, t4, fail
    csrr  t3, mepc
    la    t4, fault_instr
    bne   t3, t4, fail

    // x5's own sentinel must have survived untouched -- the trap fired
    // BEFORE any writeback, matching Sail's own real all-or-nothing
    // trap semantics (an instruction that traps never partially commits).
    li    t4, 0x5555
    bne   x5, t4, fail

    addi  t3, t3, 4
    csrw  mepc, t3
    li    x22, 0x600D
    mret

fail:
    li    x22, 0xDEAD
done:
1:
    j 1b
