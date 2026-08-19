`timescale 1ns/1ps
// Length/Offset widening RTL mirror: negative counterpart to
// tb_veda_smoke_widened_bounds.sv. An access reaching 4 bytes past the
// real, widened Length (0x50000) must hard-trap VEDA_CAUSE_BOUNDS_
// VIOLATION (cause=0x01), proving the bounds check compares the FULL
// 20-bit Length, not a silently-truncated one. See
// veda_smoke_widened_bounds_neg.S.
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

    $display("trap handled: x21=0x%0h (must be 0x600D -- correct mcause=0x18/mtval=0x01)", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (an access reaching 4 bytes past the real, widened Length=0x50000 correctly hard-traps VEDA_CAUSE_BOUNDS_VIOLATION -- proves the bounds check compares the full 20-bit Length, not a truncated/aliased/overflowed value)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
