`timescale 1ns/1ps
// MILESTONE 24 Stage 2: as committed (DRAM_EXTRA_CYCLES=0 shipped
// default), the permanent regression check is that busy_cycles stays 0
// for BOTH the TCM-tier Bind (Object_ID=1) and the DRAM-tier Bind
// (Object_ID=300) -- the tier classification itself is a pure latency
// distinction with no effect at E=0, matching Stage 1's own no-op
// regression pattern. The real tier DISTINCTION (TCM-tier never stalls
// regardless of E; DRAM-tier stalls whenever E!=0) was verified this
// session with a temporarily nonzero E build -- documented in
// veda-core/rtl/MILESTONE_24_RESULTS.md, not re-asserted here.
module tb;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;
  int busy_cycles = 0;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    repeat (40) begin
      @(posedge clk);
      #1;
      if (dut.CPU_veda_dram_busy_a0) busy_cycles = busy_cycles + 1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h busy=%0b | x1=%0d",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0, dut.CPU_veda_dram_busy_a0,
                dut.CPU_Xreg_val_a0[1]);
      cyc_cnt = cyc_cnt + 1;
    end

    $display("\nTotal busy cycles observed: %0d (expected 0 at the committed DRAM_EXTRA_CYCLES=0 default)", busy_cycles);

    if (busy_cycles == 0) begin
      $display("\n*** TEST PASSED *** (TCM-tier and DRAM-tier Binds both show zero stall at the shipped E=0 default -- the tier classification itself introduces no regression)");
    end else begin
      $display("\n*** TEST FAILED *** (busy_cycles=%0d expected 0)", busy_cycles);
    end

    $finish;
  end
endmodule
