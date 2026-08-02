.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: OCInvoke's own real trap paths --
    # Type Violation (mismatched otype between code/data) and
    # Permit_Execute Violation (an executable "data" capability, which
    # OCInvoke must reject exactly like real CHERI's own
    # `cs2_val.permit_execute` check, CHERI ISA spec p.209). Both are
    # cause codes VEDA_CORE_SPEC.md Section 3 reserved by exact value
    # (0x04/0x11) pending this design -- now exercised for real for the
    # first time.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 30
    li   x2, 0x8001050000400402      # CODE: Base=0x80010500 Length=0x40 Perms=0x0402 (Execute|Invoke)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 31
    li   x2, 0x8001070000400400      # DATA (well-formed): Perms=0x0400 (Invoke only, no Execute)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 32
    li   x2, 0x8001080000400300      # type authority: Perms=0x0300 (Seal|Unseal)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 35
    li   x2, 0x8001090000400402      # "data" that's WRONGLY executable: Perms=0x0402 (Execute|Invoke)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 30
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   -- CODE
    li   x1, 31
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   -- DATA (well-formed)
    li   x1, 32
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1   -- type authority
    li   x1, 35
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1   -- wrongly-executable "data"

    # -- Negative 1: Type Violation. Seal c3 (code) at c2's CURRENT
    #    Offset (0), walk c2's Offset forward via OCA, then seal c4
    #    (data) at the NEW Offset (1) -- c3.otype(0) != c4.otype(1),
    #    a genuine, deliberate mismatch. --
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2   -- c3.otype = 0
    li   x9, 1
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x9  # oca c2, c2, x9      -- c2.Offset: 0 -> 1
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2   -- c4.otype = 1 (MISMATCHED with c3)

neg1_fault:
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- must genuinely TRAP (Type Violation)
    # Execution resumes here (mepc+4) only via the handler's own MRET --
    # a missing/wrong trap would ALSO fall through to this exact point
    # sequentially, so no separate catcher instruction is placed here
    # (the same real placement lesson from RTL MILESTONE_9_RESULTS.md's
    # own Bug 2, applied identically in Sail). A missing trap is instead
    # caught structurally: neg2_fault below depends on c3 already
    # holding its Negative-2 reseal, which only happens if the handler
    # itself executed the reseal code that follows here.

    # -- Negative 2: Permit_Execute Violation. Reseal c3 (code) at c2's
    #    now-current Offset (1), so it matches c6 (the wrongly-
    #    executable "data") sealed at the same Offset -- otype matches
    #    this time, isolating the real check under test. --
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2   -- c3.otype = 1 (c2.Offset is still 1 from above)
    .insn r 0x5b, 0x1, 0x10, x6, x5, x2  # cseal c6, c5, c2   -- c6.otype = 1 (MATCHES c3)

neg2_fault:
    .insn r 0x5b, 0x1, 0x12, x0, x3, x6  # ocinvoke c3, c6   -- must genuinely TRAP (Permit_Execute Violation, on c6)
    # Execution resumes here (mepc+4) only via the handler's own second
    # MRET -- the real success path, identical reasoning as neg1_fault
    # above.
    RVMODEL_HALT_PASS

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval

    # Which of the two faults are we resuming from? mepc tells us --
    # compare against each fault site's own address.
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
    li   t4, 0x600D
    addi t5, t5, 4
    csrw mepc, t5
    mret

fail:
    RVMODEL_HALT_FAIL
