.section .text
.global _start
_start:
    # MILESTONE 24: proves the new DRAM-latency stall FSM at a real,
    # nonzero DRAM_EXTRA_CYCLES (temporarily built with a nonzero value
    # for this run only -- the file's own committed default stays 0, see
    # veda_core.tlv's own comment at DRAM_EXTRA_CYCLES's declaration for
    # why). Four real DRAM-tier accesses -- two Binds, one OCS.C, one
    # OCL.C -- each should incur exactly DRAM_EXTRA_CYCLES stall cycles
    # (checked by the testbench counting real dut.CPU_veda_dram_busy_a0
    # assertions, not hand-derived here). Correctness (the real
    # capability round-trip, unaffected by the new latency) is checked
    # the same way Milestone 7's own veda_smoke_m7.S already does.
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0        # veda.bind c0, x1  (Object_ID=1) -- DRAM access #1
    li   x1, 2
    .insn i 0x0b, 0x5, x1, x1, 0        # veda.bind c1, x1  (Object_ID=2) -- DRAM access #2

    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x1, x0, x2 # ocs.c c0, x2, c1  -- DRAM access #3
    .insn r 0x0b, 0x4, 0x00, x2, x0, x2 # ocl.c c0, x2, c2  -- DRAM access #4

    .insn r 0x5b, 0x0, 0x03, x10, x2, x0 # cgettag x10, c2  -- expect 1 (real round trip, correctness unaffected by the new latency)
1:
    j 1b
