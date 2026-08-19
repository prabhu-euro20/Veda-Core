# A capability freshly bound via Object-Bind, spilled to ordinary memory
# via OCS.C, and restored via OCL.C into a DIFFERENT CRF register must
# survive with its tag intact and remain fully usable -- the basic
# "spill/restore round-trip" property TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md's
# runtime/veda_sched_asm.S fix depends on, isolated here from the
# scheduler entirely so a future regression is easy to localize.
#
# REAL FINDING from building that fix (recorded here, not just in the
# results doc, since a future engineer hitting the same trap deserves a
# fast answer): this round-trip only holds for ORDINARY memory (.data
# here). Placing the spill target in .tcm_scratch (veda_rt.ld's
# TCM_SCRATCH_BASE=0xA0000000) silently loses the tag under Sail
# execution -- confirmed empirically (this file originally targeted
# .tcm_scratch, failed with VEDA_CAUSE_TAG_VIOLATION, cap_idx=1, the exact
# same signature the scheduler fix hit before being corrected). Root
# cause: Sail has zero TCM concept by design (the DRAM-latency/TCM stall
# model is 100% RTL-only, per rtl/TCM_FAST_PATH_DESIGN.md's own scoping),
# so its tag-storage mechanism was never built to cover that address
# range, even though it falls inside the declared RAM memory region for
# ordinary load/store. Any future Sail-executed program doing an OCS.C/
# OCL.C round-trip must use ordinary memory, not .tcm_scratch -- that
# placement is meaningful only for code with a real RTL counterpart.
.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    # Object 1: DATA region (Load|Store) -- the capability under test.
    la   t0, g_data
    slli t0, t0, 32
    li   t1, 0x0010000C
    or   t0, t0, t1
    li   a0, 1
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0, t0
    li   a0, 1
    .insn i 0x0b, 0x5, x0, a0, 0          # veda.bind c0, a0

    # Object 2: SPILL region (Load|Store) -- ordinary .data. Length=0x0011
    # (17 bytes, was 0x0010/16 pre-widening) -- OCL.C/OCS.C now move a
    # 17-byte capability (136 bits, 2026-08-19 Length/Offset widening),
    # so a 16-byte-bounded spill slot is exactly 1 byte too small and
    # correctly BOUNDS_VIOLATION-traps; this is real, intended behavior,
    # not a bug worked around.
    la   t0, g_spill
    slli t0, t0, 32
    li   t1, 0x0011000C
    or   t0, t0, t1
    li   a0, 2
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0, t0
    li   a0, 2
    .insn i 0x0b, 0x5, x6, a0, 0          # veda.bind c6, a0

    # Spill c0 into g_spill via c6, restore into a DIFFERENT register
    # (c1), then use c1 directly -- if the round-trip lost the tag or any
    # field, this traps.
    li   x5, 0
    .insn r 0x0b, 0x4, 0x01, x0, x6, x5   # ocs.c c6, x5(=0), c0
    li   x5, 0
    .insn r 0x0b, 0x4, 0x00, x1, x6, x5   # ocl.c c6, x5(=0), c1

    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x10, x1, x5  # ocl.d c1, x5(=0), x10

    li   t0, 0xDEAD
    beq  x10, t0, pass
fail:
    RVMODEL_HALT_FAIL
pass:
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    # Any trap here is a real failure -- c1 should be a perfectly valid,
    # in-bounds, correctly-tagged restored capability.
    RVMODEL_HALT_FAIL

.section .data
.align 4
g_data:
    .dword 0xDEAD
    .dword 0
.align 4
g_spill:
    .dword 0
    .dword 0
    .dword 0
