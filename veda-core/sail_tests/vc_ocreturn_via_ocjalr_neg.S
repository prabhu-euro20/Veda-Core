.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone B: cross-check -- a genuine sentry
    # attempted through the OLD OCJALR path (which still requires a
    # second, explicit type-authority operand) must still trap, since no
    # ordinary-CSeal-produced `cs2.Offset` can ever equal VEDA_OTYPE_SENTRY
    # post-hardening (vc_cseal_sentry_forge_neg.S's own proof). Confirms
    # the two mechanisms -- cheap OCRETURN and general OCJALR -- do not
    # accidentally interoperate: a sentry is genuinely usable only via the
    # cheap path.
    la   t0, trap_handler
    csrw mtvec, t0

    # Object_ID=55: Perms=Execute=0x0002.
    li   x1, 55
    li   x2, 0x8005500000400002
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 55
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- unsealed source

    .insn r 0x5b, 0x1, 0x15, x6, x5, x0  # csealentry c6, c5  -- MINT sentry (otype=0xFFFE)

    # Object_ID=56: an ordinary, unrelated type-authority object,
    # Perms=Seal|Unseal=0x0300, Offset=0 by default -- deliberately NOT
    # 0xFFFE (no capability can carry that Offset post-hardening).
    li   x1, 56
    li   x2, 0x8005600000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 56
    .insn i 0x0b, 0x5, x7, x1, 0  # veda.bind c7, x1

neg_fault:
    .insn r 0x5b, 0x1, 0x14, x0, x6, x7  # ocjalr c6, c7  -- c6 is a real sentry, but the OLD path still needs a matching type-authority -- must TRAP
    RVMODEL_HALT_PASS

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0xC4                     # TYPE_VIOLATION(0x04), cap_idx=6 (c6) -> (6<<5)|0x04=0xC4
    bne  t3, t4, fail
    csrr t5, mepc
    la   t6, neg_fault
    bne  t5, t6, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

fail:
    RVMODEL_HALT_FAIL
