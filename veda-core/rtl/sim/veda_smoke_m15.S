.section .text
.global _start
_start:
    // RTL Milestone 15: ODT full-Object_ID verification (real bug fix,
    // see ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 1). This is the
    // positive control -- two DIFFERENT, non-aliasing objects (Object_ID
    // 30 and 31, low bytes distinct) work correctly side by side, and a
    // legitimate SAME-ID re-populate (30 again, new backing memory)
    // still works too -- proving the new full-ID check doesn't reject
    // anything it shouldn't.
    la   x5, obj30_a
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    li   x1, 30
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (Object_ID=30 -> obj30_a)
    li   x1, 30
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0   -> x8 = 0x1111... (Object_ID=30's own object)

    la   x5, obj31
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    li   x1, 31
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (Object_ID=31 -> obj31)
    li   x1, 31
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x9, x1, x2  # ocl.d x9, x2, c1   -> x9 = 0x2222... (Object_ID=31's own object, unaffected)

    // Legitimate same-ID re-populate: Object_ID=30 again, new backing
    // memory (obj30_b) -- must succeed and correctly reflect the NEW
    // object, not be rejected by the new full-ID check (which should
    // still match, since it's genuinely the same real Object_ID).
    la   x5, obj30_b
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    li   x1, 30
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (Object_ID=30 -> obj30_b, real re-populate)
    li   x1, 30
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x10, x2, x2  # ocl.d x10, x2, c2  -> x10 = 0x3333... (the NEW obj30_b content)

done:
1:
    j 1b

.section .data
.align 3
obj30_a:
    .dword 0x1111111111111111
obj31:
    .dword 0x2222222222222222
obj30_b:
    .dword 0x3333333333333333
