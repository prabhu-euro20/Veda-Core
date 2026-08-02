.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: ODT generation-wraparound retirement
    # (mirrors RTL Milestone 16, ARCHITECTURE_IMPROVEMENT_FINDINGS.md
    # Finding 2). Destroying the same Object_ID 256 times wraps the real
    # 8-bit generation counter exactly back to a stale capability's own
    # cached value -- before this fix, a subsequent re-populate would let
    # that stale capability keep dereferencing memory it should have lost
    # access to at the very first Destroy (the exact scenario empirically
    # reproduced on real RTL before either fix was designed). This test
    # proves two things Sail-side: the re-populate attempt itself must
    # now be refused (Illegal_Instruction, mcause=2 -- matching this same
    # instruction's own existing convention for its other failure mode,
    # privilege), and the stale capability's later use must still
    # correctly hard-trap (cause=0x02, Tag Violation -- the slot never
    # became valid again).
    #
    # Object_ID=50, clear of veda_test_seed_odt()'s own seeded IDs (1-5).
    li   x5, 0x80020000
    slli x5, x5, 32
    li   x9, 0x00080004      # Length=8 (one dword), Perms=PERM_LOAD
    or   x5, x5, x9
    li   x1, 50
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 50
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1

    li   x1, 50
    .rept 256
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0  # veda.odt.destroy x9, x1
    .endr

    # Fixed behavior: the slot is now permanently retired (generation
    # saturated at 0xff) -- this re-populate MUST be refused.
    la   t0, retire_trap_handler
    csrw mtvec, t0
    li   x5, 0x80020100
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 50
    mv   x2, x5
repopulate_instr:
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (must be REFUSED)

    RVMODEL_HALT_FAIL          # reached only if the repopulate above wrongly succeeded

.balign 4
retire_trap_handler:
    csrr t3, mcause
    li   t4, 2                 # standard RISC-V Illegal Instruction
    bne  t3, t4, check_fail
    csrr t3, mepc
    la   t4, repopulate_instr
    bne  t3, t4, check_fail

    # Second real check: the ORIGINAL, stale c0 (never re-bound since the
    # very first bind) must still correctly hard-trap when used directly
    # -- the slot stayed invalid, since the repopulate above was refused.
    addi t3, t3, 4
    csrw mepc, t3
    la   t0, stale_trap_handler
    csrw mtvec, t0
    li   x2, 0
fault_instr:
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0

    RVMODEL_HALT_FAIL          # reached only if the stale access wrongly succeeded

.balign 4
stale_trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x02              # cause=0x02 (Tag Violation), cap_idx=0 (c0)
    bne  t3, t4, check_fail

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
