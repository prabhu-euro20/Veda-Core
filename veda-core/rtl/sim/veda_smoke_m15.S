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
    .word 0x0620828b        # veda.odt.populate x5, x1, x2 (Object_ID=30 -> obj30_a)
    li   x1, 30
    .word 0x0000d00b        # veda.bind c0, x1
    li   x2, 0
    .word 0x0020340b        # ocl.d x8, x2, c0   -> x8 = 0x1111... (Object_ID=30's own object)

    la   x5, obj31
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    li   x1, 31
    mv   x2, x5
    .word 0x0620828b        # veda.odt.populate x5, x1, x2 (Object_ID=31 -> obj31)
    li   x1, 31
    .word 0x0000d08b        # veda.bind c1, x1
    li   x2, 0
    .word 0x0020b48b        # ocl.d x9, x2, c1   -> x9 = 0x2222... (Object_ID=31's own object, unaffected)

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
    .word 0x0620828b        # veda.odt.populate x5, x1, x2 (Object_ID=30 -> obj30_b, real re-populate)
    li   x1, 30
    .word 0x0000d10b        # veda.bind c2, x1
    li   x2, 0
    .word 0x0021350b        # ocl.d x10, x2, c2  -> x10 = 0x3333... (the NEW obj30_b content)

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
