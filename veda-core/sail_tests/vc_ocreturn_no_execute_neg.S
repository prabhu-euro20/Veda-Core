.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone B: OCRETURN negative -- CSealEntry
    # carries Perms through unchanged (neither stripping nor adding
    # Permit_Execute, matching real CHERI's own CSealEntry exactly); a
    # sentry minted from a non-executable source must PERM_EXECUTE_
    # VIOLATION-trap at OCRETURN, the actual enforcement point, matching
    # OCInvoke's own already-active check for the identical condition.
    la   t0, trap_handler
    csrw mtvec, t0

    # Object_ID=54: Perms=Seal|Unseal=0x0300 -- deliberately no Execute
    # (mirrors vc_ocjalr_neg.S's own TARGET-NO-EXEC fixture exactly).
    li   x1, 54
    li   x2, 0x8005400000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 54
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- unsealed, no Execute

    .insn r 0x5b, 0x1, 0x15, x6, x5, x0  # csealentry c6, c5  -- MINT sentry, Perms carried through (still no Execute)
    .insn r 0x5b, 0x0, 0x03, x10, x6, x0  # cgettag  x10, c6  -- expect 1 (the mint itself must succeed)
    li   t2, 1
    bne  x10, t2, fail

neg_fault:
    .insn r 0x5b, 0x1, 0x16, x0, x6, x0  # ocreturn c6  -- genuine sentry, but not executable -- must TRAP
    RVMODEL_HALT_PASS

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0xD1                     # PERMIT_EXECUTE_VIOLATION(0x11), cap_idx=6 (c6) -> (6<<5)|0x11=0xD1
    bne  t3, t4, fail
    csrr t5, mepc
    la   t6, neg_fault
    bne  t5, t6, fail
    addi t5, t5, 4
    csrw mepc, t5
    mret

fail:
    RVMODEL_HALT_FAIL
