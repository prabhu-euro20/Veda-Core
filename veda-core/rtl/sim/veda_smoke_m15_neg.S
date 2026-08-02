.section .text
.global _start
_start:
    // RTL Milestone 15 negative control: the real bug this milestone
    // fixes (ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 1). Object_ID=
    // 32 and Object_ID=288 (32+256) share the same low byte, so the RTL's
    // 256-entry ODT's own low-8-bit index aliases them onto one physical
    // slot. Before this milestone, a fresh Bind for Object_ID=32 issued
    // after Object_ID=288 was populated would silently resolve to
    // Object_ID=288's own object instead -- proven via a real reproduction
    // (odt_alias.S) before any fix was designed. This test proves the fix:
    // the same sequence must now hard-trap (cause=0x05, object-not-found)
    // instead of silently succeeding with the wrong object's data.
    la   x5, array_a
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 32
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (Object_ID=32 -> array_a)

    li   x1, 32
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0   -- sanity: x8 = 0xAAAA...

    la   x5, array_b
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 288
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (Object_ID=288, alias -> array_b)

    la   t0, trap_handler
    csrw mtvec, t0

    // Fresh Bind for Object_ID=32, AFTER the alias populate. Fixed
    // behavior: the slot's stored full Object_ID no longer matches 32 ->
    // "not found" -> plain Bind hard-traps (cause=0x05, cap_idx=1 for
    // the c1 destination -> mtval=(1<<5)|0x05=0x25).
    li   x1, 32
fault_instr:
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x22, 0xDEAD         # reached only if the old, buggy behavior recurred
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x25
    bne  t3, t4, fail
    li   x22, 0x600D         # FIXED: correctly rejected the aliased lookup
    j    done
fail:
    li   x22, 0x0BAD
done:
1:
    j 1b

.section .data
.align 3
array_a:
    .dword 0xAAAAAAAAAAAAAAAA
array_b:
    .dword 0xBBBBBBBBBBBBBBBB
