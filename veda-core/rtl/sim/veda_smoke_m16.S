.section .text
.global _start
_start:
    // RTL Milestone 16 positive control: proves the fix doesn't reject
    // anything it shouldn't. A slot destroyed/re-populated a normal, small
    // number of times (5, far under the 255-reuse retirement threshold)
    // must keep working completely normally -- fresh binds correctly see
    // each new incarnation's own real data, not retired, not stale.
    li   x7, 210          # Object_ID, reused across all 5 cycles

    la   x5, obj_v1
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v1)

    la   x5, obj_v2
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v2, real re-populate #1)

    la   x5, obj_v3
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v3, real re-populate #2)

    la   x5, obj_v4
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v4, real re-populate #3)

    la   x5, obj_v5
    slli x5, x5, 32
    li   x20, 0x00080004
    or   x5, x5, x20
    mv   x1, x7
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (v5, real re-populate #4)

    // Fresh bind to the 5th incarnation -- must succeed normally (not
    // refused, not stale) and see v5's own real value.
    mv   x1, x7
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0   -> x8 must be 0x5555...

done:
1:
    j 1b

.section .data
.align 3
obj_v1:
    .dword 0x1111111111111111
obj_v2:
    .dword 0x2222222222222222
obj_v3:
    .dword 0x3333333333333333
obj_v4:
    .dword 0x4444444444444444
obj_v5:
    .dword 0x5555555555555555
