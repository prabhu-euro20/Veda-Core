.section .text
.global _start
_start:
    # Veda-Core RTL Milestone 17: OCJALR's own real trap paths -- Seal
    # Violation (the exact condition STACK_FRAME_CALL_RETURN_ANALYSIS.md's
    # own `prot_gap` experiment showed a hand-rolled CUnseal+CGetAddr+
    # JALR sequence could silently miss), Type Violation (wrong seal-
    # authority, matching real CHERI's own CJALR precedent, CHERI ISA
    # spec p.213), and Permit_Execute Violation (a jump target lacking
    # execute permission) -- mirrors vc_ocjalr_neg.S's own Sail scenario
    # exactly (same objects, same encodings, identical bit layout in
    # both layers).
    la   t0, generic_trap_handler
    csrw mtvec, t0

    li   x1, 70
    li   x2, 0x8001100000400002      # TARGET: Perms=0x0002 (Execute)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 71
    li   x2, 0x8001120000400300      # authority-A: Perms=0x0300 (Seal|Unseal)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 72
    li   x2, 0x8001140000400300      # authority-B: Perms=0x0300 (Seal|Unseal) -- DIFFERENT authority
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 73
    li   x2, 0x8001160000400300      # TARGET-NO-EXEC: Perms=0x0300 (no Execute)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 70
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   -- TARGET, left UNSEALED on purpose (Negative 1)
    li   x1, 71
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   -- authority-A
    li   x1, 72
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1   -- authority-B
    li   x1, 73
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1   -- TARGET-NO-EXEC, unsealed

    # -- Negative 1: Seal Violation. c0 was never sealed. --
neg1_fault:
    .insn r 0x5b, 0x1, 0x14, x0, x0, x1  # ocjalr c0, c1   -- must genuinely TRAP (Seal Violation, c0 unsealed)
    # Falls through here on the handler's own MRET (mepc+4) -- no
    # separate catcher instruction, same real placement lesson as
    # MILESTONE_9_RESULTS.md's own Bug 2.

    # -- Negative 2: Type Violation. --
    .insn r 0x5b, 0x1, 0x10, x4, x0, x1  # cseal c4, c0, c1   -- c4.otype = c1.Offset = 0
    li   x9, 1
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x9  # oca c2, c2, x9      -- c2.Offset: 0 -> 1

neg2_fault:
    .insn r 0x5b, 0x1, 0x14, x0, x4, x2  # ocjalr c4, c2   -- must genuinely TRAP (Type Violation: c2.Offset(1) != c4.otype(0))

    # -- Negative 3: Permit_Execute Violation. --
    .insn r 0x5b, 0x1, 0x10, x6, x5, x1  # cseal c6, c5, c1   -- c6.otype = c1.Offset = 0

neg3_fault:
    .insn r 0x5b, 0x1, 0x14, x0, x6, x1  # ocjalr c6, c1   -- must genuinely TRAP (Permit_Execute Violation, c6 lacks Execute)
    # Falls through here on the handler's own third MRET -- the real
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
    la   t6, neg3_fault
    beq  t5, t6, 3f
    j    fail

1:  li   t4, 0x03                    # SEAL_VIOLATION(0x03), cap_idx=0 (c0) -> (0<<5)|0x03=0x03
    bne  t3, t4, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

2:  li   t4, 0x84                    # TYPE_VIOLATION(0x04), cap_idx=4 (c4) -> (4<<5)|0x04=0x84
    bne  t3, t4, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

3:  li   t4, 0xD1                    # PERMIT_EXECUTE_VIOLATION(0x11), cap_idx=6 (c6) -> (6<<5)|0x11=0xD1
    bne  t3, t4, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

fail:
    li   x23, 0xDEAD
2:
    j 2b
