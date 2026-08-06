.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of minimal OS kernel Milestone B
    # (MILESTONE_B_RESULTS.md): CSealEntry + OCRETURN, combining
    # Sail's own already-verified vc_cseal_entry.S and
    # vc_ocreturn_basic.S into one representative RTL smoke test.
    #
    # CSealEntry mints a sentry (otype=0xFFFE) with no authorizing
    # capability operand; a sentry minted before entry survives a real
    # OCInvoke (capability registers are not cleared, only PCC narrows);
    # from inside that narrow, OCInvoke-entered compartment, a single-
    # operand OCRETURN through the sentry both lands at the sentry's own
    # target AND narrows veda_pcc_base/veda_pcc_length to the sentry's
    # own Base/Length -- the direct proof this crosses the compartment
    # boundary, not merely jumps.
    #
    # sentry SOURCE (Object_ID=90): Base=return_landing, Length=0xFFFF
    # (VEDA_PCC_UNBOUNDED), Perms=Execute only.
    # ─────────────────────────────────────────────────────────────
    la   t0, return_landing
    slli t0, t0, 32
    li   t1, 0xFFFF0002
    or   t0, t0, t1
    li   x1, 90
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 90
    .insn i 0x0b, 0x5, x8, x1, 0  # veda.bind c8, x1  -- sentry source, unsealed

    .insn r 0x5b, 0x1, 0x15, x9, x8, x0  # csealentry c9, c8  -- MINT sentry
    .insn r 0x5b, 0x0, 0x03, x15, x9, x0  # cgettag  x15, c9  -- expect 1
    .insn r 0x5b, 0x0, 0x04, x16, x9, x0  # cgettype x16, c9  -- expect 0xFFFE

    # -- narrow compartment (Object_ID=70/71/72, Length=0x0040). --
    la   t0, comp_entry
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 70
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE
    li   x1, 71
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA
    li   x1, 72
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority

    li   x1, 70
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 71
    .insn i 0x0b, 0x5, x3, x1, 0  # veda.bind c3, x1
    li   x1, 72
    .insn i 0x0b, 0x5, x4, x1, 0  # veda.bind c4, x1
    .insn r 0x5b, 0x1, 0x10, x6, x0, x4  # cseal c6, c0, c4
    .insn r 0x5b, 0x1, 0x10, x7, x3, x4  # cseal c7, c3, c4

    .insn r 0x5b, 0x1, 0x12, x0, x6, x7  # ocinvoke c6, c7  -- narrows PCC to [comp_entry, comp_entry+0x40)
poison1:
    j poison1                             # must NOT be reached

comp_entry:
    li   x20, 0x1111
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0  # ocreturn c9  -- widen PCC to sentry's own bounds, jump there
poison2:
    j poison2                             # must NOT be reached -- would mean OCRETURN fell through

.balign 4
return_landing:
    li   x20, 0x2222
    csrr x21, 0x7c1                       # veda_pcc_length -- expect 0xFFFF (genuinely widened)
loop:
    j loop
