.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Real-time/safety-critical audit (2026-08-16): WFI must behave as
    # the RISC-V spec's own explicitly-permitted "implement WFI as a
    # NOP" option (ISA manual p.715) -- no trap, no register write, pc+4
    # advance. Previously this was true only by accident (no $is_wfi
    # decode existed at all); now it's an explicit, documented decode.
    # Raw .word encoding (0x10500073 = funct12=0x105, rs1=rd=0,
    # funct3=PRIV, opcode=SYSTEM) rather than the "wfi" mnemonic, to
    # avoid depending on assembler support for it under -march=rv64i_zicsr.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x20, 0xDEAD                       # sentinel: not yet past WFI
    .word 0x10500073                       # wfi -- must fall through, not trap
    li   x20, 0x600D                       # must be reached: proves no trap/hang
    j    done

trap_handler:
    li   x20, 0xBAD                        # must NEVER be reached
    j    done

done:
1:
    j 1b
