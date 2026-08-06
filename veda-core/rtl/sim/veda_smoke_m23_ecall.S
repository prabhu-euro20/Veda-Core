.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 23: real ECALL support -- the RTL's own
    # header comment has said "excl. ECALL/EBREAK, deferred" since the
    # original RV64I base-ISA milestone, and Milestone 21's own results
    # doc explicitly named this as a known gap and pre-scoped its fix
    # ("wire a new violation signal into the existing $veda_trap_taken
    # OR-chain... gets PCC-reset for free, by construction"). This test
    # proves the baseline, unbounded-context case: ECALL genuinely
    # traps with the real, standard RISC-V mcause=11 (E_M_EnvCall, not
    # an invented Veda-specific code), mtval=0, mepc pointing at the
    # ECALL instruction itself (no auto-advance -- matches this core's
    # own general trap-capture convention, already established for
    # every other trap since Milestone 9), and MRET's own real PC
    # redirect closes the full trap-and-resume cycle, exactly mirroring
    # veda_smoke_m9.S's own established pattern.
    # ─────────────────────────────────────────────────────────────
    la    t0, trap_handler
    csrw  mtvec, t0
    csrr  t1, mtvec
    bne   t1, t0, fail             # round-trip: mtvec really holds the handler address

ecall_instr:
    ecall

    # -- execution resumes here (mepc+4, the handler's own advance) --
    li    x22, 0x900D                  # sentinel: correctly resumed after MRET
    j     done

trap_handler:
    csrr  t3, mcause
    li    t4, 11                    # E_M_EnvCall, the real RISC-V mcause for M-mode ecall
    bne   t3, t4, fail
    csrr  t3, mtval
    li    t4, 0                     # real spec convention: mtval=0 for ecall
    bne   t3, t4, fail

    # mepc must point at the ECALL instruction itself -- no auto-advance,
    # the same "exact trapping PC" behavior already true of every other
    # trap in this core (Milestone 9's own $mepc capture, unchanged).
    csrr  t3, mepc
    la    t4, ecall_instr
    bne   t3, t4, fail

    # Advance mepc PAST the ECALL before MRET, or MRET would re-execute
    # and re-trap on it forever -- the identical, load-bearing step
    # veda_smoke_m9.S's own trap handler already established.
    addi  t3, t3, 4
    csrw  mepc, t3

    li    x21, 0x600D                 # sentinel: reached the handler with correct mcause/mtval/mepc
    mret

fail:
    li    x22, 0xDEAD
done:
1:
    j 1b
