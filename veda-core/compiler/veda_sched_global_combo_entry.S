# CRF-exhaustion fix, real combined verification test
# (TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md): proves the globals
# table-base capability (c11) genuinely survives a real scheduler
# yield/resume round-trip, including the thread's very FIRST-EVER resume
# (the exact case the bootstrap save-area pre-population fix in
# runtime/veda_sched_asm.S exists for).
#
# Deliberately simpler than Milestone 13's own compiler-pass-driven
# bootstrap (VedaShadowPropagation.cpp Phase B1 + veda_rt_init_globals):
# this test does not need to exercise per-global bounds isolation again
# (compiler/run_veda_global_protect_test.sh already proves that
# separately) -- it only needs a real, single table-base capability at
# c11 to prove IT SPECIFICALLY survives the scheduler. One capability in
# a one-entry table, bounding a small shared data region both threads
# access at their own private offset, is the minimal real exercise of
# that property.
#
# Called from ordinary, compiled C (veda_sched_global_combo_demo.c's
# main(), via crt0.S's own standard startup) BEFORE veda_scheduler_start()
# -- "wide open" PCC, no OCInvoke active yet, identical bootstrap timing
# to veda_global_protect_entry.S's own call to veda_rt_init_globals.
#
# Object_IDs 431/432 -- grep-audited fresh this session, confirmed
# collision-free past every existing .S file's own highest use (430,
# veda_global_protect_entry.S).
#   431 = g_combo_data region (Load|Store, Length=0x10 -- 2 dwords)
#   432 = g_combo_table region (Load|Store, Length=0x10 -- 1 capability slot)
# c0 used as pure transient scratch for the DATA_REGION bind -- safe here
# since this runs before veda_scheduler_start's own ceremony claims any
# CRF register and before any OCInvoke, the same "nothing claimed yet"
# window Milestone 13's own bootstrap relies on.
# c11 is bound here and held PERSISTENT from this point on -- the exact
# register under test.

.section .text
.global veda_sched_global_combo_boot
veda_sched_global_combo_boot:
    # ---- g_combo_data region -> c0 (transient), Object_ID 431 ----
    la   t0, g_combo_data
    slli t0, t0, 32
    li   t1, 0x0010000C   # Length=0x10, Perms=Load|Store
    or   t0, t0, t1
    li   a0, 431
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0
    li   a0, 431
    .insn i 0x0b, 0x5, x0, a0, 0          # veda.bind c0, a0

    # ---- g_combo_table region -> c11 (PERSISTENT), Object_ID 432 ----
    la   t0, g_combo_table
    slli t0, t0, 32
    li   t1, 0x0010000C   # Length=0x10, Perms=Load|Store
    or   t0, t0, t1
    li   a0, 432
    .insn r 0x0b, 0x0, 0x03, x5, a0, t0   # veda.odt.populate x5, a0,t0
    li   a0, 432
    .insn i 0x0b, 0x5, x11, a0, 0         # veda.bind c11, a0

    # Store the g_combo_data capability (c0) into the table (c11) at
    # offset 0 -- the ONE entry both thread bodies will OCL.C-reload on
    # every access, including across the scheduler round-trip this test
    # exists to verify.
    li   x5, 0
    .insn r 0x0b, 0x4, 0x01, x0, x11, x5  # ocs.c c11, x5(=0), c0

    ret

.section .data
.align 4
g_combo_data:
    .dword 0   # offset 0: thread 0's own slot
    .dword 0   # offset 8: thread 1's own slot
.align 4
g_combo_table:
    .dword 0   # capability slot (16 bytes)
    .dword 0
