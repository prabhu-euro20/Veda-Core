.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Atomic aq/rl invariance test (ATOMIC_AQRL_SAFETY_ANALYSIS.md):
    # the same real veda.amoxor.d read-modify-write, executed twice
    # back-to-back through Object_ID=1 (reset-seeded, Load|Store), once
    # with aq=0/rl=0 and once with aq=1/rl=1 -- funct7's own
    # op(5)@aq@rl layout means only bits [26:25] differ between the two
    # encodings, op-select (XOR, 00100) held fixed. Proves the atomic
    # RMW's own real correctness (old value returned, new value
    # correctly stored) is genuinely independent of aq/rl -- the
    # precise distinction (atomicity, real and already-correct here, vs
    # ordering, currently inapplicable on this single-hart, in-order
    # core) the safety analysis rests on.
    # ─────────────────────────────────────────────────────────────
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- Object_ID=1, reset-seeded (Base=0x80010000, Load|Store)

    li   x2, 0x0                  # offset
    li   x3, 0x100                # initial value
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2  # ocs.d c0, x2, x3  -- seed the initial value

    li   x4, 0x0F                 # xor operand, identical for both ops below
    li   x5, 0
    .insn r 0x2b, 0x3, 0x10, x5, x0, x4  # veda.amoxor.d x5, c0, x4  -- aq=0,rl=0 (funct7=0010_00_0=0x10)
                                          # x5 <- old value (0x100); mem <- 0x100^0x0F=0x10F

    li   x6, 0
    .insn r 0x0b, 0x3, 0x00, x6, x0, x2  # ocl.d x6, c0, x2  -- read back, expect 0x10F

    li   x7, 0
    .insn r 0x2b, 0x3, 0x13, x7, x0, x4  # veda.amoxor.d x7, c0, x4  -- aq=1,rl=1 (funct7=0010_01_1=0x13), same op
                                          # x7 <- old value (0x10F); mem <- 0x10F^0x0F=0x100 (back to original)

    li   x8, 0
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, c0, x2  -- read back, expect 0x100 again

done:
1:
    j 1b
