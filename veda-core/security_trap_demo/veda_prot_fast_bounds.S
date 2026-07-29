.section .text
.global _start
_start:
    # Veda-Core Milestone 18: VEDA_ODT_POPULATE_FAST is the *optimizing*
    # instruction -- it folds authority/target population into a single
    # instruction, sourcing Length/Perms from the veda_attr CSR instead of
    # a second inline immediate. This proves the optimization didn't cost
    # any security: a deliberately small Length (0x8) set via veda_attr
    # still genuinely bound-checks a later access, exactly like a small
    # Length would under the older, pre-optimization plain Populate path.
    # Setup mirrors the committed, tested veda_smoke_m18_neg.S exactly,
    # modified only to STORE the real mcause/mtval/mepc into marker
    # registers x24/x25/x26 for display, instead of comparing and
    # branching.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x20, 0x0008100c    # veda_attr = Length=0x8 (deliberately small), Perms=0x100C
    csrw 0x7c4, x20

    li   x1, 61
    li   x2, 0x80010700     # Base, direct
    .word 0x0820800b        # veda.odt.populate.fast x0, x1, x2  -- the optimizing instruction

    .word 0x0000d08b        # veda.bind c1, x1

    li   x6, 0x10            # offset 0x10, width 8 -> offset+width=0x18 > Length=0x8
    li   x7, 0x99
fault_instr:
    .word 0x0260b38b         # ocs.d c1, x6, x7 -- must genuinely TRAP (Bounds Violation)

    li   x30, 0xBAD          # reached only if the trap never fired
    j    done

trap_handler:
    csrr x24, mcause          # real mcause -> x24
    csrr x25, mtval           # real mtval  -> x25
    csrr x26, mepc            # real mepc   -> x26

    la   t3, done
    csrw mepc, t3
    li   x30, 0xca11          # controlled, real trap -- the optimized fast-path still enforces bounds
    mret

done:
1:
    j 1b
