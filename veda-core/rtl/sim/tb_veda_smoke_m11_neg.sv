`timescale 1ns/1ps
// Veda-Core RTL Milestone 11 negative test: dropped privilege AND an
// unauthorized (reset-state, Tag=0) ODA together must still correctly
// block ODT-Populate -- the OR'd authorization check's own "both paths
// absent" case, distinct from Milestone 4's own negative test (which
// predates the ODA existing at all) only in exercising the new check
// expression, not a new failure mode.
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

    repeat (15) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("dropped privilege + unauthorized ODA: c0.tag=x6=0x%0h (must be 0 -- no ODT entry was ever created)", dut.CPU_Xreg_val_a0[6]);

    if (dut.CPU_Xreg_val_a0[6] == 64'h0) begin
      $display("\n*** TEST PASSED *** (with BOTH ordinary privilege dropped AND the ODA left unauthorized, ODT-Populate is still correctly blocked -- confirmed via a subsequent Bind's own Tag=0, no ODT entry was ever actually created)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
