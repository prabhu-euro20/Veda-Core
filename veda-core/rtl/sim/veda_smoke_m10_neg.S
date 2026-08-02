.section .text
.global _start
_start:
    # Veda-Core RTL Milestone 10: OCInvoke's own real trap paths --
    # Type Violation (mismatched otype) and Permit_Execute Violation (an
    # executable "data" capability) -- mirrors vc_ocinvoke_neg.S's own
    # Sail scenario exactly (same objects, same encodings, identical bit
    # layout in both layers), now proven as a real RTL hard trap via
    # Milestone 9's own trap infrastructure.
    la   t0, generic_trap_handler
    csrw mtvec, t0

    li   x1, 30
    li   x2, 0x8001050000400402      # CODE: Perms=0x0402 (Execute|Invoke)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 31
    li   x2, 0x8001070000400400      # DATA (well-formed): Perms=0x0400 (Invoke only)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 32
    li   x2, 0x8001080000400300      # type authority: Perms=0x0300 (Seal|Unseal)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 35
    li   x2, 0x8001090000400402      # "data" WRONGLY executable: Perms=0x0402
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 30
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   -- CODE
    li   x1, 31
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   -- DATA (well-formed)
    li   x1, 32
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1   -- type authority
    li   x1, 35
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1   -- wrongly-executable "data"

    # -- Negative 1: Type Violation. --
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2   -- c3.otype = 0
    li   x9, 1
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x9  # oca c2, c2, x9      -- c2.Offset: 0 -> 1
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2   -- c4.otype = 1 (MISMATCHED with c3)

neg1_fault:
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- must genuinely TRAP (Type Violation)
    # Falls through here on the handler's own MRET (mepc+4) --
    # identical real placement lesson as MILESTONE_9_RESULTS.md's own
    # Bug 2: no separate catcher instruction goes here.

    # -- Negative 2: Permit_Execute Violation. --
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2   -- c3.otype = 1 (c2.Offset still 1)
    .insn r 0x5b, 0x1, 0x10, x6, x5, x2  # cseal c6, c5, c2   -- c6.otype = 1 (MATCHES c3)

neg2_fault:
    .insn r 0x5b, 0x1, 0x12, x0, x3, x6  # ocinvoke c3, c6   -- must genuinely TRAP (Permit_Execute Violation, on c6)
    # Falls through here on the handler's own second MRET -- the real
    # success path.
    li   x23, 0x600D
1:
    j 1b

generic_trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval

    csrr t5, mepc
    la   t6, neg1_fault
    beq  t5, t6, 1f
    la   t6, neg2_fault
    beq  t5, t6, 2f
    j    fail

1:  li   t4, 0x64                     # TYPE_VIOLATION(0x04), cap_idx=3 (c3) -> (3<<5)|0x04=0x64
    bne  t3, t4, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

2:  li   t4, 0xD1                     # PERMIT_EXECUTE_VIOLATION(0x11), cap_idx=6 (c6) -> (6<<5)|0x11=0xD1
    bne  t3, t4, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

fail:
    li   x23, 0xDEAD
2:
    j 2b
