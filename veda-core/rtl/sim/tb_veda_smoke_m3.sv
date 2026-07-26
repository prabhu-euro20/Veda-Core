`timescale 1ns/1ps
// Veda-Core RTL Milestone 3 smoke test: the 7-instruction query family
// (against an OCA-positioned c1) and CSetBounds (against a freshly
// narrowed c2), verified via the query family reading the results back.
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

    repeat (18) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("c1 query results: base=0x%0h len=0x%0h perm=0x%0h tag=%0b type=0x%0h addr=0x%0h offset=0x%0h",
              dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12],
              dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16]);
    $display("c2 (CSetBounds) query results: base=0x%0h len=0x%0h offset=0x%0h tag=%0b",
              dut.CPU_Xreg_val_a0[17], dut.CPU_Xreg_val_a0[18], dut.CPU_Xreg_val_a0[19], dut.CPU_Xreg_val_a0[20]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h80010000 && dut.CPU_Xreg_val_a0[11] == 64'h40 &&
        dut.CPU_Xreg_val_a0[12] == 64'h100C && dut.CPU_Xreg_val_a0[13] == 64'h1 &&
        dut.CPU_Xreg_val_a0[14] == 64'hFFFF && dut.CPU_Xreg_val_a0[15] == 64'h80010010 &&
        dut.CPU_Xreg_val_a0[16] == 64'h10 &&
        dut.CPU_Xreg_val_a0[17] == 64'h80010000 && dut.CPU_Xreg_val_a0[18] == 64'h20 &&
        dut.CPU_Xreg_val_a0[19] == 64'h0 && dut.CPU_Xreg_val_a0[20] == 64'h1) begin
      $display("\n*** TEST PASSED *** (all 7 query results exact for c1, all 4 for CSetBounds's c2)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
