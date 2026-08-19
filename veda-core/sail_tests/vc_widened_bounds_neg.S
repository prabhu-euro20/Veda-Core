.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Length/Offset widening (NEXT_STEPS_ROADMAP.md, 2026-08-19) -- the
    # negative counterpart to vc_widened_bounds.S: an access that reaches
    # just 4 bytes PAST the real, widened Length (0x50000) must still
    # hard-trap (VEDA_CAUSE_BOUNDS_VIOLATION), proving the bounds check
    # itself is genuinely comparing against the real 20-bit Length, not
    # e.g. a truncated-to-16-bit value that would make this offset
    # (0x4FFFC, well above 0xFFFF) alias to some smaller, already-past
    # value and trap for the wrong reason (or a value that overflowed
    # silently and never trapped at all).
    la   t0, trap_handler
    csrw mtvec, t0

    li   t1, 0x50000000C   # veda_attr: Length=0x50000, Perms=0x000C (Load|Store)
    csrw 0x7c4, t1
    li   x1, 461
    li   x2, 0x80010000
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast x5, x1, x2

    li   x1, 461
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1

    # offset = Length-4 (0x4FFFC), width=8 -> [0x4FFFC, 0x50004), which
    # exceeds Length (0x50000) by 4 bytes -- must trap.
    li   x9, 0x4FFFC
    li   x10, 0x55556666
    .insn r 0x0b, 0x3, 0x01, x10, x0, x9  # ocs.d c0, x9, x10

    li   x20, 0xBAD                        # must NOT be reached
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x01                          # (cap_idx=0<<5)|cause=0x01 (VEDA_CAUSE_BOUNDS_VIOLATION)
    bne  t3, t4, fail
    li   x20, 0x600D
    j    done

fail:
    li   x20, 0xDEAD

done:
    li   t2, 0x600D
    bne  x20, t2, real_fail
    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
