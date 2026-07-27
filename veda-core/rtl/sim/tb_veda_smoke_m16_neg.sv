`timescale 1ns/1ps
// Veda-Core RTL Milestone 16 negative control: proves the real bug this
// milestone fixes (ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 2) is
// genuinely closed. Destroying the same Object_ID 256 times wraps the
// RTL's 8-bit generation counter exactly back to a stale capability's own
// cached value; before this milestone, a subsequent re-populate let that
// stale capability keep dereferencing memory it should have lost access
// to at the very first Destroy (empirically reproduced before any fix
// was designed). This test proves the slot is now permanently retired
// instead. See veda_smoke_m16_neg.S for the full step-by-step proof
// structure.
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

    repeat (900) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("stale access after 256 destroys: x22=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[22] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (after 256 real Destroy operations wrap the 8-bit generation counter, the slot is now permanently retired -- a re-populate attempt is silently refused, and the original, now-genuinely-stale capability correctly hard-traps instead of successfully dereferencing memory it should have lost access to at the very first Destroy)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
