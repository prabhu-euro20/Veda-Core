`timescale 1ns/1ps
// Veda-Core RTL mirror of SSC (Stack-Spill Capability) round-trip via
// OSpecialRW's new scr_sel=2 arm, plus proof that SSC, TSC, and ODA are
// three genuinely independent registers. See veda_smoke_ssc_roundtrip.S.
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

    repeat (55) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("SSC old tag (must be 0): x10=0x%0h", dut.CPU_Xreg_val_a0[10]);
    $display("SSC new tag (must be 1): x11=0x%0h", dut.CPU_Xreg_val_a0[11]);
    $display("SSC new base (must be 0x80021000): x12=0x%0h", dut.CPU_Xreg_val_a0[12]);
    $display("ODA tag, SSC-only writes (must be 0): x13=0x%0h", dut.CPU_Xreg_val_a0[13]);
    $display("TSC tag, SSC-only writes (must be 0): x14=0x%0h", dut.CPU_Xreg_val_a0[14]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h0 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h80021000 &&
        dut.CPU_Xreg_val_a0[13] == 64'h0 &&
        dut.CPU_Xreg_val_a0[14] == 64'h0) begin
      $display("\n*** TEST PASSED *** (OSpecialRW's new scr_sel=2 arm genuinely round-trips the SSC, a real third Special Capability Register independent of ODA and TSC)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
