`timescale 1ns/1ps
// Veda-Core RTL mirror of minimal OS kernel Milestone A: TSC round-trip
// via OSpecialRW's new SCR-selector operand, plus proof that TSC and ODA
// are genuinely independent registers, not an aliased read/write of one.
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

    repeat (45) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("TSC old tag (must be 0): x10=0x%0h", dut.CPU_Xreg_val_a0[10]);
    $display("TSC new tag (must be 1): x11=0x%0h", dut.CPU_Xreg_val_a0[11]);
    $display("TSC new base (must be 0x80021000): x12=0x%0h", dut.CPU_Xreg_val_a0[12]);
    $display("ODA tag, TSC-only writes (must be 0): x13=0x%0h", dut.CPU_Xreg_val_a0[13]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h0 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h80021000 &&
        dut.CPU_Xreg_val_a0[13] == 64'h0) begin
      $display("\n*** TEST PASSED *** (OSpecialRW's new SCR-selector genuinely round-trips the TSC, a real second Special Capability Register independent of the ODA, RTL mirror of minimal OS kernel Milestone A)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
