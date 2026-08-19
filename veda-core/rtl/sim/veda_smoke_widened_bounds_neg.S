.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Length/Offset widening RTL mirror: negative counterpart to
    # veda_smoke_widened_bounds.S (mirrors vc_widened_bounds_neg.S's
    # own Sail scenario exactly). An access that reaches just 4 bytes
    # PAST the real, widened Length (0x50000) must still hard-trap
    # (VEDA_CAUSE_BOUNDS_VIOLATION).
    #
    # SCOPING NOTE (adversarial-review Finding #4): this negative test
    # ALONE does not prove the bounds check is genuinely comparing
    # against the real, full 20-bit Length -- it cannot distinguish
    # that from "Length was silently truncated to 0", since a
    # truncated-to-0 Length would ALSO make this same offset
    # (0x4FFFC) trap, with the same cause/mtval. What actually proves
    # "genuinely 20-bit, not truncated" is this file TAKEN TOGETHER
    # WITH its positive sibling, veda_smoke_widened_bounds.S: that
    # file's own round trip right at the real edge (offset=Length-8)
    # MUST succeed, which is only possible against a genuinely-20-bit
    # Length -- a truncated-to-0 Length would wrongly trap there too.
    # Only the pair together -- the positive edge succeeding AND this
    # negative case (4 bytes further) trapping -- pins down that the
    # real widened Length (not a truncated one) is what's actually
    # being enforced. This file by itself proves only "an access past
    # 0x50000 traps", not by itself the full widening claim.
    #
    # Object_ID=501 (fresh block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   t1, 0x50000000C   # veda_attr: Length=0x50000, Perms=0x000C (Load|Store)
    csrw 0x7c4, t1
    li   x1, 501
    li   x2, 0x80010000
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast x5, x1, x2

    li   x1, 501
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1

    # offset = Length-4 (0x4FFFC), width=8 -> [0x4FFFC, 0x50004), which
    # exceeds Length (0x50000) by 4 bytes -- must trap.
    li   x9, 0x4FFFC
    li   x10, 0x55556666
    .insn r 0x0b, 0x3, 0x01, x10, x0, x9  # ocs.d c0, x9, x10  -- MUST hard-trap

    li   x21, 0xBAD1  # must NOT be reached
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x18
    bne  t4, t5, fail
    csrr t4, mtval
    li   t5, 0x01        # (cap_idx=0<<5)|cause=0x01 (VEDA_CAUSE_BOUNDS_VIOLATION)
    bne  t4, t5, fail

    li   x21, 0x600D     # sentinel: reached the handler with the correct mcause/mtval
    j    done

fail:
    li   x21, 0xBAD

done:
1:
    j 1b
