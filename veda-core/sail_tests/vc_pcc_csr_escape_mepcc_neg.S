.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 20 -- the second real attack this milestone's
    # fix closes, distinct from vc_pcc_csr_escape_neg.S: rather than
    # widening its own *live* bounds (veda_pcc_length, 0x7c1), code
    # inside a compartment instead corrupts the *saved* bounds
    # (veda_mepcc_length, 0x7c3) that a legitimate trap handler's own
    # restore convention would later trust. Not part of the user's
    # original PoC -- found while designing this milestone's fix, by
    # reasoning that the same unconditional-write gap generalizes to
    # every one of the four compartment-state CSRs, not just the one the
    # PoC happened to target.
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x00400402          # Length=0x0040
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
    li   t3, 0x2000               # malicious target value for veda_mepcc_length -- distinct from the real Length (0x40)
    csrw 0x7c3, t3                # attempted corruption of the SAVED bounds -- must hard-trap
    li   x21, 0xBAD
    li   x22, 0xBAD                # must NOT be reached
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 2
    bne  t3, t4, fail

    # Load-bearing: veda_mepcc_length must hold the REAL original Length
    # (0x0040 -- the value genuinely live at trap time, saved by this
    # very trap's own veda_pcc_save_and_reset() call), not the attacker's
    # requested 0x2000 -- proving the malicious write never took effect
    # and the legitimate save-and-reset ran in its place.
    csrr t5, 0x7c3
    li   t6, 0x0040
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
