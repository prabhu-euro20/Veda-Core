`timescale 1ns/1ps
// Veda-Core RTL Milestone 15 negative control: proves the real bug this
// milestone fixes (ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 1) is
// genuinely closed. Object_ID=32 and Object_ID=288 (32+256) alias onto
// the same physical ODT slot under the RTL's 256-entry, low-8-bit-index
// scheme; before this milestone, a fresh Bind for Object_ID=32 issued
// after Object_ID=288 was populated silently resolved to Object_ID=288's
// own object instead (empirically reproduced before any fix was
// designed). This test proves it now hard-traps instead. See
// veda_smoke_m15_neg.S for the full step-by-step proof structure.
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

    repeat (40) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("aliased Bind correctly rejected: x22=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[22] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (a fresh Bind for Object_ID=32, issued after the low-byte-aliasing Object_ID=288 was populated, now correctly hard-traps with cause=0x05/object-not-found instead of silently resolving to Object_ID=288's own data)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
