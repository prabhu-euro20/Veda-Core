.section .text
.global _start
_start:
    # Veda-Core: the same shape of attack -- an unsealed (corrupted-
    # equivalent) return capability presented to OCJALR -- is a real,
    # hardware-enforced hard trap, not a jump. Setup mirrors the
    # committed, tested veda_smoke_m17_neg.S exactly (Negative 1: Seal
    # Violation), modified only to STORE the real mcause/mtval/mepc into
    # marker registers x24/x25/x26 for display, instead of comparing and
    # branching.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 70
    li   x2, 0x8001100000400002      # TARGET: Perms=0x0002 (Execute)
    .word 0x0620828b                 # veda.odt.populate x5, x1, x2

    li   x1, 71
    li   x2, 0x8001120000400300      # authority-A: Perms=0x0300 (Seal|Unseal)
    .word 0x0620828b                 # veda.odt.populate x5, x1, x2

    li   x1, 70
    .word 0x0000d00b                 # veda.bind c0, x1   -- TARGET, left UNSEALED on purpose (the attack)
    li   x1, 71
    .word 0x0000d08b                 # veda.bind c1, x1   -- authority-A

fault_instr:
    .word 0x2810105b                 # ocjalr c0, c1   -- must genuinely TRAP (Seal Violation, c0 unsealed)

    li   x30, 0xBAD                  # reached only if the trap never fired
    j    done

trap_handler:
    csrr x24, mcause                 # real mcause -> x24
    csrr x25, mtval                  # real mtval  -> x25
    csrr x26, mepc                   # real mepc   -> x26

    # OCJALR never completes on a trap -- there is no "next instruction"
    # of the faulting program to safely resume into (mepc+4 would fall
    # straight through to the deliberately-unreachable 0xBAD path right
    # after fault_instr). Redirect mepc to `done` directly instead.
    la   t3, done
    csrw mepc, t3
    li   x30, 0xca11                 # controlled, real trap -- attacker's forged capability rejected
    mret

done:
1:
    j 1b
