.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of SSC's own real spatial bounds check
    # (SSC_STACK_SPILL_CAPABILITY_DESIGN.md, mirrors Sail's
    # vc_ssc_oob_neg.S): SSC gets the identical real bounds check every
    # other Veda-Core capability register already gets. Bind a real,
    # bounded (Length=0x40) object into SSC, attempt an OCL.D one byte
    # past the end -- must hard-trap with Bounds Violation.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 330
    li   x2, 0x800510000040000C  # Base=0x80051000, Length=0x0040, Perms=0x000C (Load|Store)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 330
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1
    .insn r 0x5b, 0x1, 0x13, x9, x5, x2  # ospecialrw c9(discard), ssc, c5  -- SSC := c5

    li   x6, 0x40  # offset == Length -- one 8-byte word past the real, valid [0,0x40) range
    .insn r 0x0b, 0x3, 0x00, x22, x5, x6  # ocl.d x22, c5, x6(=0x40)  -- MUST hard-trap

    li   x21, 0xBAD1  # must NOT be reached
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x18
    bne  t4, t5, fail
    csrr t4, mtval
    li   t5, 0xA1        # (cap_idx=5<<5)|cause=0x01 -- c5 held the SSC-derived capability; Bounds Violation
    bne  t4, t5, fail

    li   x21, 0x600D     # sentinel: reached the handler with the correct mcause/mtval
    j    done

fail:
    li   x21, 0xBAD

done:
1:
    j 1b
