.section .text
.global _start
_start:
    # MILESTONE 24 Stage 2: TCM ODT tier. Object_ID=1 (pre-seeded by the
    # RTL's own initial block, < TCM_ODT_ENTRIES=32) must NOT stall on
    # Bind -- $veda_odt_tcm_hit gates it out of the DRAM-tier path
    # entirely. Object_ID=300 (freshly populated here, >= 32) must still
    # stall exactly as Stage 1 already proved for every Object_ID before
    # this tier existed. At the committed DRAM_EXTRA_CYCLES=0 default
    # both cases show busy=0 throughout (a real, valid regression check
    # in its own right -- see the testbench); the tier DISTINCTION itself
    # (TCM-tier never contributes to stall_req regardless of E, DRAM-tier
    # does whenever E!=0) was additionally verified this session with a
    # temporarily nonzero E build, documented in
    # veda-core/rtl/MILESTONE_24_RESULTS.md, matching Stage 1's own
    # verification pattern exactly.
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0        # veda.bind c0, x1  (Object_ID=1, TCM-tier)

    la   t0, dram_tier_obj
    slli t0, t0, 32
    li   t1, 0x0040000C                 # Length=0x40, Perms=Load|Store
    or   t0, t0, t1
    li   x1, 300
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2 # veda.odt.populate x5, x1, x2 -- Object_ID=300
    li   x1, 300
    .insn i 0x0b, 0x5, x1, x1, 0        # veda.bind c1, x1  (Object_ID=300, DRAM-tier)
1:
    j 1b

.section .data
.align 4
dram_tier_obj:
    .space 64
