.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 10: OCInvoke -- the CInvoke-equivalent
    # protection-domain-transition instruction (VEDA_CORE_SPEC.md
    # Section 6 item 7, now closed in both Sail and RTL). Term-for-term
    # adaptation of real CHERI's CInvoke (CHERI ISA spec p.209): a
    # sealed CODE capability and a sealed DATA capability, matching
    # otype, both carrying Permit_Invoke, atomically unseal-and-jump --
    # the code capability's own resolved address becomes the new PC (a
    # real hardware jump, not a software unseal-then-JALR sequence),
    # the unsealed data capability lands in c15 (IDC, Veda-Core's own
    # fixed-index convention, proportional to CHERI's own real C31).
    #
    # Object_ID=30 (CODE): Permit_Execute(bit1)|Permit_Invoke(bit10) =
    # 0x0402, Base = the real runtime address of landing_pad (computed
    # via `la`, not a compile-time constant, since the target is this
    # same file's own address).
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 30
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # Object_ID=31 (DATA): Permit_Invoke(bit10) ONLY = 0x0400 --
    # deliberately non-executable, matching OCInvoke's own real
    # requirement that the data capability NOT carry Permit_Execute.
    li   x1, 31
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # Object_ID=32: type-authority object, Permit_Seal|Permit_Unseal
    # (bits 8+9) = 0x0300.
    li   x1, 32
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 30
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   -- CODE, unsealed
    li   x1, 31
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   -- DATA, unsealed
    li   x1, 32
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1   -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2   -- sealed CODE, otype=0
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2   -- sealed DATA, otype=0 (MATCHES c3)

    # -- The real invoke: atomically unseals c3/c4 and jumps to c3's
    #    own resolved target address (landing_pad), installing unsealed
    #    c4 into c15 (IDC). --
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

    # If OCInvoke somehow fell through instead of jumping, execution
    # would reach here -- a real, distinct failure signature.
    li   x23, 0xBAD
    j    1f

landing_pad:
    # -- proves the jump landed at the EXACT resolved target. --
    .insn r 0x5b, 0x0, 0x03, x20, x15, x0  # cgettag  x20, c15  -- expect 1 (IDC populated)
    .insn r 0x5b, 0x0, 0x04, x21, x15, x0  # cgettype x21, c15  -- expect 0xFFFF (unsealed again)
    .insn r 0x5b, 0x0, 0x00, x22, x15, x0  # cgetbase x22, c15  -- expect 0x80010700 (really c4's own Base)
    li   x23, 0x600D
1:
    j 1b
