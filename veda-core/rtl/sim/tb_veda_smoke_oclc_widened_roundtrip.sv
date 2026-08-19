`timescale 1ns/1ps
// Adversarial-review Finding #1: a genuinely WIDENED (>0xFFFF)
// Length/Offset capability round-trips through OCS.C/OCL.C's own
// 136-bit pack/unpack with Tag/Base/Length/Offset all surviving
// bit-for-bit. Also closes Finding #6 (CGetOffset queried at a
// widened value, x14 below). See
// veda_smoke_oclc_widened_roundtrip.S.
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

    repeat (90) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("OCA sanity (c1 in-range)     : x10=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[10]);
    $display("round-trip cgettag           : x11=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[11]);
    $display("round-trip cgetbase          : x12=0x%0h (must be 0x80010000)", dut.CPU_Xreg_val_a0[12]);
    $display("round-trip cgetlen           : x13=0x%0h (must be 0x50000)", dut.CPU_Xreg_val_a0[13]);
    $display("round-trip cgetoffset        : x14=0x%0h (must be 0x10005)", dut.CPU_Xreg_val_a0[14]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h80010000 &&
        dut.CPU_Xreg_val_a0[13] == 64'h50000 &&
        dut.CPU_Xreg_val_a0[14] == 64'h10005) begin
      $display("\n*** TEST PASSED *** (a widened Length=0x50000/Offset=0x10005 capability -- both with genuinely nonzero bits[19:16] -- round-trips through OCS.C's 136-bit pack and OCL.C's unpack with Tag, Base, Length, and Offset all bit-for-bit intact; CGetOffset independently confirms the widened Offset value)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
