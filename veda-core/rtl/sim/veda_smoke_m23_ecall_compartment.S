.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 23: ECALL from inside a live, narrowly-
    # bounded OCInvoke compartment -- proves Milestone 21's "universal
    # PCC reset on any trap" applies to the new ECALL trap too, not just
    # assumed: veda_pcc_base/veda_pcc_length must read back unbounded
    # (0 / 0xFFFFF) from inside the trap handler, while veda_mepcc_base/
    # veda_mepcc_length (CSR 0x7c2/0x7c3) must hold the compartment's
    # true pre-trap bounds -- and mepc must equal ECALL's own address
    # inside the compartment (== comp_entry itself, since ECALL is the
    # compartment's very first instruction), positively distinguishing
    # this trap from the OCInvoke-entry that preceded it. Reuses the
    # exact OCInvoke/Object_ID/populate/bind scaffold already proven in
    # veda_smoke_mosB_sentry.S.
    #
    # compartment (Object_ID=100/101/102, Length=0x0040) --
    # Object_IDs personally grepped against every existing rtl/sim/*.S
    # file's own usage before picking: 100-199 is completely free.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, comp_entry
    slli t0, t0, 32
    li   t1, 0x00400402                   # Length=0x0040, Perms=Execute|Invoke
    or   t0, t0, t1
    li   x1, 100
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE
    li   x1, 101
    li   x2, 0x8002000000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA
    li   x1, 102
    li   x2, 0x8002010000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority

    li   x1, 100
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 101
    .insn i 0x0b, 0x5, x3, x1, 0  # veda.bind c3, x1
    li   x1, 102
    .insn i 0x0b, 0x5, x4, x1, 0  # veda.bind c4, x1
    .insn r 0x5b, 0x1, 0x10, x6, x0, x4  # cseal c6, c0, c4
    .insn r 0x5b, 0x1, 0x10, x7, x3, x4  # cseal c7, c3, c4

    .insn r 0x5b, 0x1, 0x12, x0, x6, x7  # ocinvoke c6, c7  -- narrows PCC to [comp_entry, comp_entry+0x40)
poison1:
    j poison1                             # must NOT be reached

.balign 4
comp_entry:
    ecall                                 # trap fires from inside the live, narrowed compartment
poison2:
    j poison2                             # must NOT be reached

trap_handler:
    csrr x10, mcause
    li   x11, 11                          # E_M_EnvCall
    bne  x10, x11, fail

    # Milestone 21's universal reset must have already fired before this
    # handler was ever fetched -- live PCC reads back genuinely unbounded.
    csrr x10, 0x7c0                       # veda_pcc_base
    bnez x10, fail
    csrr x10, 0x7c1                       # veda_pcc_length
    li   x11, 0xFFFFF
    bne  x10, x11, fail

    # veda_mepcc_base/_length must hold the compartment's TRUE pre-trap
    # bounds -- the actual proof this is a real save, not a discard.
    csrr x10, 0x7c2                       # veda_mepcc_base
    la   x11, comp_entry
    bne  x10, x11, fail
    csrr x10, 0x7c3                       # veda_mepcc_length
    li   x11, 0x0040
    bne  x10, x11, fail

    # mepc must equal ECALL's own address (== comp_entry, its first
    # instruction) -- distinguishes this trap from the OCInvoke-entry
    # that preceded it, not just "some trap happened."
    csrr x10, mepc
    la   x11, comp_entry
    bne  x10, x11, fail

    li   x21, 0x600D                      # sentinel: all checks passed
    j    done

fail:
    li   x22, 0xDEAD
done:
1:
    j 1b
