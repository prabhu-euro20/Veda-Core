.section .text
.global _start
_start:
    // RTL Milestone 16 negative control: proves the real bug this
    // milestone fixes (ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 2).
    // Destroy the same Object_ID 256 times in a loop -- before this
    // milestone, this wrapped the 8-bit generation counter exactly back
    // to a stale capability's own cached value, and a subsequent
    // re-populate let that stale capability keep dereferencing memory it
    // should have lost access to at the very first Destroy (empirically
    // reproduced before any fix was designed). This test proves the
    // slot is now permanently retired instead: the re-populate attempt
    // is silently refused, and the stale capability's own later use
    // correctly hard-traps.
    la   x5, array_a
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 200
    mv   x2, x5
    .word 0x0620828b        # veda.odt.populate x5, x1, x2

    li   x1, 200
    .word 0x0000d00b        # veda.bind c0, x1
    li   x2, 0
    .word 0x0020340b        # ocl.d x8, x2, c0   -- sanity: x8 = 0xAAAA...

    li   x6, 256
    li   x1, 200
destroy_loop:
    .word 0x0600948b        # veda.odt.destroy x9, x1
    addi x6, x6, -1
    bnez x6, destroy_loop

    // Fixed behavior: the slot is now permanently retired (generation
    // saturated at 0xFF), so this re-populate must be silently refused
    // -- object B is never actually written.
    la   x5, array_b
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 200
    mv   x2, x5
    .word 0x0620828b        # veda.odt.populate x5, x1, x2 (must be REFUSED)

    la   t0, trap_handler
    csrw mtvec, t0

    // Use the ORIGINAL, stale c0 directly. Fixed: since the re-populate
    // above was refused, the slot stayed invalid, so this must
    // hard-trap (a real OCL.D Tag/generation violation), not succeed.
    li   x2, 0
fault_instr:
    .word 0x0020340b        # ocl.d x8, x2, c0
    li   x22, 0xDEAD         # reached only if the OLD, buggy behavior recurred
    j    done

trap_handler:
    li   x22, 0x600D         # FIXED: the stale access correctly trapped
done:
1:
    j 1b

.section .data
.align 3
array_a:
    .dword 0xAAAAAAAAAAAAAAAA
array_b:
    .dword 0xBBBBBBBBBBBBBBBB
