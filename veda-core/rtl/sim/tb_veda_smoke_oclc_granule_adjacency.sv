`timescale 1ns/1ps
// Length/Offset widening RTL mirror: the 2-granule tag-store design's
// honest contract, both directions. A plain write OUTSIDE the real
// 2-granule span a 17-byte capability store occupies must NOT
// spuriously invalidate its tag; a plain write INSIDE the second
// (spillover) granule, even at an unused byte, correctly DOES
// invalidate it. See veda_smoke_oclc_granule_adjacency.S.
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

    repeat (70) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("immediate round trip           : x9 =0x%0h (must be 1)", dut.CPU_Xreg_val_a0[9]);
    $display("after writes OUTSIDE 2-granule span: x10=0x%0h (must be STILL 1)", dut.CPU_Xreg_val_a0[10]);
    $display("after write INSIDE granule G+1     : x11=0x%0h (must be 0 now)", dut.CPU_Xreg_val_a0[11]);
    $display("no unexpected trap              : x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[9]  == 64'h1 &&
        dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h0 &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (the 2-granule tag-store design's honest contract holds both ways: plain writes outside the real 2-granule span a 17-byte capability store occupies do not spuriously invalidate its tag, but a plain write inside the second/spillover granule -- even at an unused byte -- correctly does)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
