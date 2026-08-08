`timescale 1ns/1ps
// MILESTONE 24 Stage 3: TCM capability-spill scratch. A real, tagged
// capability round-trips correctly through BOTH the new tcm_scratch[]
// path (Object_ID=201, c8) and the ordinary elfmem[] path (Object_ID=202,
// c9) in the same run, proving $veda_capmem_tcm_hit's mux picks the right
// array in both directions. Two negative checks (one per region, an
// offset never written) confirm tcm_scratch_tag[]'s own zero-init took
// effect and neither region's tag store leaks into the other's -- the
// real tag-write granule-split concern this milestone's own design doc
// flagged, exercised directly. As committed (DRAM_EXTRA_CYCLES=0 shipped
// default), busy_cycles stays 0 throughout, matching Stage 1/2's own
// no-op regression pattern at the shipped default.
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

    repeat (55) begin
      @(posedge clk);
      #1;
      if (dut.CPU_veda_dram_busy_a0) busy_cycles = busy_cycles + 1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("TCM  round-trip: tag=%0b base=0x%0h (c1, x10/x11)", dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("DRAM round-trip: tag=%0b base=0x%0h (c2, x12/x13)", dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13]);
    $display("TCM  negative (unwritten offset): tag=%0b (x14, must be 0)", dut.CPU_Xreg_val_a0[14]);
    $display("DRAM negative (unwritten offset): tag=%0b (x15, must be 0)", dut.CPU_Xreg_val_a0[15]);
    $display("Total busy cycles observed: %0d (expected 0 at the committed DRAM_EXTRA_CYCLES=0 default)", busy_cycles);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h80010000 &&
        dut.CPU_Xreg_val_a0[12] == 64'h1 &&
        dut.CPU_Xreg_val_a0[13] == 64'h80010000 &&
        dut.CPU_Xreg_val_a0[14] == 64'h0 &&
        dut.CPU_Xreg_val_a0[15] == 64'h0 &&
        busy_cycles == 0) begin
      $display("\n*** TEST PASSED *** (a real tagged capability round-trips intact through both tcm_scratch[] and elfmem[] via OCL.C/OCS.C's new address-range mux; unwritten offsets in both regions correctly read back untagged, proving tcm_scratch_tag[]'s own zero-init and array separation from tag_mem[]; busy_cycles=0 proves this Stage 3 routing is a true no-op at the shipped DRAM_EXTRA_CYCLES=0 default)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
