`timescale 1ns/1ps
// Length/Offset widening RTL mirror: CSeal's new otype-truncation
// precondition ($veda_cs2_offset[19:16] == 4'b0000). An authority
// capability with Offset=0x10005 (upper bits genuinely nonzero,
// comfortably in-bounds) must soft-fail CSeal (CGetTag of the result
// reads 0) -- proves the new precondition fires rather than silently
// truncating to a colliding otype=0x0005. See
// veda_smoke_cseal_offset_hibits_neg.S.
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

    $display("OCA sanity (c1 in-range)  : x10=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[10]);
    $display("CSeal(Offset=0x10005) tag : x11=0x%0h (must be 0 -- soft-fail)", dut.CPU_Xreg_val_a0[11]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h0) begin
      $display("\n*** TEST PASSED *** (CSeal's new precondition -- cs2.Offset[19:16] == 0 -- correctly fires and soft-fails (Tag cleared) for an authority whose Offset=0x10005 has nonzero upper bits, rather than silently truncating to a colliding otype=0x0005)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
