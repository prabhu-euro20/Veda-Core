.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 20 -- the permanent regression test for a real,
    # empirically-confirmed vulnerability found via a throwaway PoC run
    # under sail_riscv_sim before this fix existed: code entered via a
    # real OCInvoke compartment could simply `csrw 0x7c1, ...` to widen
    # its own veda_pcc_length back to VEDA_PCC_UNBOUNDED and escape -- no
    # trap, no restriction, using only instructions that already existed.
    # Attempts a malicious write of 0x1000 -- deliberately distinct from
    # both the compartment's own original Length (0x0040) and
    # VEDA_PCC_UNBOUNDED (0xFFFFF, 20-bit sentinel since the 2026-08-19
    # widening) -- so a successful escape and a
    # correctly-blocked write are unambiguously distinguishable by the
    # final CSR value alone, not just by whether a trap fired at all.
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x00400402          # Length=0x0040 -- generous, the escape attempt needs more than 4 bytes
    or   t0, t0, t1
    li   x1, 60
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate  CODE

    li   x1, 61
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate  DATA

    li   x1, 62
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate  type authority

    li   x1, 60
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 61
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 62
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [landing_pad, landing_pad+0x40)

landing_pad:
    li   t3, 0x1000               # malicious target value
    csrw 0x7c1, t3                # attempted self-escape -- must now hard-trap
    li   x21, 0xBAD
    li   x22, 0xBAD                # must NOT be reached -- means the write silently succeeded (escape)
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 2                    # Illegal_Instruction -- the real mechanism write_CSR's own Err(()) triggers
    bne  t3, t4, fail

    # The load-bearing assertion: veda_pcc_length must now read exactly
    # VEDA_PCC_UNBOUNDED -- proving neither the original narrow value
    # (0x40) nor the attacker's requested malicious value (0x1000)
    # persisted, and that this handler itself runs genuinely
    # unconstrained (Milestone 20's own veda_pcc_save_and_reset() call,
    # the identical discipline every other real Veda trap already
    # follows).
    csrr t5, 0x7c1
    li   t6, 0xFFFFF
    bne  t5, t6, fail

    li   x21, 0x600D
    li   x22, 0x900D
    j    done

fail:
    li   x21, 0xDEAD
    li   x22, 0xDEAD

done:
    li   t2, 0x600D
    bne  x21, t2, real_fail
    li   t2, 0x900D
    bne  x22, t2, real_fail

    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
