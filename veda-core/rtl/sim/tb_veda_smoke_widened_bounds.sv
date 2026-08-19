`timescale 1ns/1ps
// Length/Offset widening RTL mirror: positive proof an object's Length
// can now genuinely exceed 65535 bytes (0x50000 = 327,680 bytes, >4x
// the old 16-bit ceiling), built via VEDA_ODT_POPULATE_FAST + veda_attr
// (the only path carrying the real 20-bit Length). A round trip right
// at the object's own real widened upper edge (offset = Length-8) must
// succeed, and CGetLen must read back the full, untruncated 0x50000.
// See veda_smoke_widened_bounds.S.
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

    $display("round-trip @ offset 0   : x8 =0x%0h (must be 0x11112222)", dut.CPU_Xreg_val_a0[8]);
    $display("round-trip @ Length-8   : x11=0x%0h (must be 0x33334444)", dut.CPU_Xreg_val_a0[11]);
    $display("cgetlen (full 20-bit)   : x12=0x%0h (must be 0x50000)", dut.CPU_Xreg_val_a0[12]);

    if (dut.CPU_Xreg_val_a0[8]  == 64'h11112222 &&
        dut.CPU_Xreg_val_a0[11] == 64'h33334444 &&
        dut.CPU_Xreg_val_a0[12] == 64'h50000) begin
      $display("\n*** TEST PASSED *** (VEDA_ODT_POPULATE_FAST + veda_attr genuinely builds a >64KB object; OCL.D/OCS.D round-trip correctly right at the real, widened Length edge; CGetLen reads back the full, untruncated 20-bit Length)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
