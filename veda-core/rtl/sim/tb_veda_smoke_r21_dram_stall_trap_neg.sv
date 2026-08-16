`timescale 1ns/1ps
// R21 fix: a DRAM-tier OCL.C access that also violates (Object_ID=1's
// own Length=0x40 bound) must still hard-trap, not silently fall
// through past the faulting instruction. See
// veda_smoke_r21_dram_stall_trap_neg.S -- this run is at the shipped
// DRAM_EXTRA_CYCLES=0 default, where the stall path itself is
// structurally unreachable; the real escape-vs-fix comparison at a
// temporarily nonzero DRAM_EXTRA_CYCLES is a separate, non-committed
// verification pass documented in
// MILESTONE_R21_DRAM_STALL_TRAP_FIX_RESULTS.md.
module tb;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    repeat (60) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x20=0x%0h (must be 0x600D -- correctly trapped; must NEVER be 0xE5CA, the escape marker)", dut.CPU_Xreg_val_a0[20]);

    if (dut.CPU_Xreg_val_a0[20] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (a DRAM-tier OCL.C access that also violates its own Length bound correctly hard-traps at the shipped DRAM_EXTRA_CYCLES=0 default -- zero regression from the R21 fix. See MILESTONE_R21_DRAM_STALL_TRAP_FIX_RESULTS.md for the real escape-vs-fix proof at nonzero DRAM_EXTRA_CYCLES, where this fix is actually load-bearing)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
