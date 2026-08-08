# Hand-written thread bodies for the CRF-exhaustion combined test
# (TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md). MUST contain zero
# ordinary memory traffic outside the Veda-Core capability path -- same
# constraint veda_sched_demo_threads.S's own header already documents
# (Milestone 19's purecap rule + the scheduler's own OCInvoke-free
# resume convention).
#
# Each thread: (1) loads the shared data-region capability from the
# table via c11 (the register under test), writes its own known
# constant to its own private offset via OCL.C-then-OCS.D; (2) yields;
# (3) on resume, RE-LOADS the SAME capability from the table via c11 a
# SECOND time -- this is the real, discriminating check: if c11 was
# corrupted by the scheduler's own resume-jump machinery (the original
# bug), this second OCL.C either reads an untagged/garbage capability
# (traps) or a stale one (wrong readback); (4) stashes the read-back
# value into a dedicated persistent GPR (x22/x23) for main() to inspect
# after veda_scheduler_start() returns, matching veda_sched_demo.c's own
# established read-back convention; (5) parks in an infinite ecall loop
# so the scheduler's own round count can finish cleanly.
#
# x5/x6 are pure thread-local scratch (offset/value temporaries) --
# thread bodies run strictly after the switcher's own OCRETURN jump, so
# nothing depends on their value surviving into or out of a thread's own
# code, unlike the switcher's own x28-x31 (reloaded fresh every trap).

.section .text

.balign 4
.global veda_combo_thread0
veda_combo_thread0:
    li   x6, 0
    .insn r 0x0b, 0x4, 0x00, x10, x11, x6  # ocl.c c10, x6(=0), c11 -- load data-region cap
    li   x5, 0xAAAA
    li   x6, 0
    .insn r 0x0b, 0x3, 0x01, x5, x10, x6   # ocs.d c10, x6(=0), x5  -- write 0xAAAA to slot 0
    ecall                                    # yield 1

    # Resume: re-load through c11 a SECOND time -- the real discriminator.
    li   x6, 0
    .insn r 0x0b, 0x4, 0x00, x10, x11, x6  # ocl.c c10, x6(=0), c11
    li   x6, 0
    .insn r 0x0b, 0x3, 0x00, x22, x10, x6  # ocl.d c10, x6(=0), x22 -- x22 := readback

combo0_park:
    ecall
    j    combo0_park

.balign 4
.global veda_combo_thread1
veda_combo_thread1:
    li   x6, 0
    .insn r 0x0b, 0x4, 0x00, x10, x11, x6  # ocl.c c10, x6(=0), c11 -- load data-region cap
    li   x5, 0xBBBB
    li   x6, 8
    .insn r 0x0b, 0x3, 0x01, x5, x10, x6   # ocs.d c10, x6(=8), x5  -- write 0xBBBB to slot 1
    ecall                                    # yield 1

    li   x6, 0
    .insn r 0x0b, 0x4, 0x00, x10, x11, x6  # ocl.c c10, x6(=0), c11
    li   x6, 8
    .insn r 0x0b, 0x3, 0x00, x23, x10, x6  # ocl.d c10, x6(=8), x23 -- x23 := readback

combo1_park:
    ecall
    j    combo1_park
