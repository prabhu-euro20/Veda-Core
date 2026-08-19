.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone B (MINIMAL_OS_KERNEL_DESIGN.md): OCRETURN
    # -- the actual cheap, cross-compartment-boundary-crossing counterpart
    # to OCJALR's own always-two-operand design. A sentry is minted here in
    # _start (c9, via CSealEntry) BEFORE entering a narrow compartment --
    # capability registers survive OCInvoke (only PCC narrows), the same
    # real, legitimate "prepared before entry" pattern
    # vc_switcher_register_clear.S already established for its own target
    # capabilities. Proves: (a) a single-operand OCRETURN through that
    # sentry, executed from INSIDE the narrow compartment, genuinely lands
    # at the sentry's own target; (b) veda_pcc_base/veda_pcc_length now read
    # back as the sentry's own Base/Length -- the direct proof this crosses
    # the compartment boundary, not merely jumps (mirrors RTL Milestone 22's
    # own `mepc == return_landing` technique for distinguishing a real jump
    # from a coincidental fault).

    # -- sentry SOURCE (Object_ID=90): Base=return_landing, Length=0xFFFFF
    #    (VEDA_PCC_UNBOUNDED, 20-bit sentinel since the 2026-08-19
    #    widening), Perms=Execute only -- Permit_Invoke is not needed,
    #    OCRETURN never checks it, by design. Plain VEDA_ODT_POPULATE's
    #    own 16-bit-capped Length field can never represent this value
    #    (NEXT_STEPS_ROADMAP.md "Break 3"), so VEDA_ODT_POPULATE_FAST +
    #    veda_attr is required here. --
    la   t0, return_landing
    mv   x18, t0                # save the runtime Base for the later CSR-readback check
    li   t1, 0xFFFFF0002        # veda_attr: Length=0xFFFFF, Perms=0x0002
    csrw 0x7c4, t1
    li   x1, 90
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2  # veda.odt.populate.fast x5, x1, x2

    li   x1, 90
    .insn i 0x0b, 0x5, x8, x1, 0  # veda.bind c8, x1  -- sentry source, unsealed

    .insn r 0x5b, 0x1, 0x15, x9, x8, x0  # csealentry c9, c8  -- MINT sentry

    # -- a narrow compartment (Object_ID=60/61/62, Length=0x0040) --
    #    deliberately small, so a successful OCRETURN out of it can only be
    #    explained by a genuine PCC-widen, not by the target merely already
    #    being reachable. --
    la   t0, comp_entry
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 60
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE
    li   x1, 61
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA
    li   x1, 62
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority

    li   x1, 60
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 61
    .insn i 0x0b, 0x5, x3, x1, 0  # veda.bind c3, x1
    li   x1, 62
    .insn i 0x0b, 0x5, x4, x1, 0  # veda.bind c4, x1
    .insn r 0x5b, 0x1, 0x10, x6, x0, x4  # cseal c6, c0, c4
    .insn r 0x5b, 0x1, 0x10, x7, x3, x4  # cseal c7, c3, c4

    .insn r 0x5b, 0x1, 0x12, x0, x6, x7  # ocinvoke c6, c7  -- narrows PCC to [comp_entry, comp_entry+0x40)
    j    fail                             # must NOT be reached

comp_entry:
    # -- c9 (sentry) survives OCInvoke's own PCC-narrow-only semantics. --
    li   x20, 0x1111
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0  # ocreturn c9  -- widen PCC to sentry's own bounds, jump there
    j    fail                             # must NOT be reached -- would mean OCRETURN fell through

.balign 4
return_landing:
    # -- the load-bearing assertion: OCRETURN genuinely crossed the
    #    compartment boundary. --
    li   x20, 0x2222
    csrr t3, 0x7c1                        # veda_pcc_length
    li   t4, 0xFFFFF
    bne  t3, t4, fail
    csrr t3, 0x7c0                        # veda_pcc_base
    bne  t3, x18, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
