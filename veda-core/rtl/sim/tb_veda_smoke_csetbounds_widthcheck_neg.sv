`timescale 1ns/1ps
// Length/Offset widening RTL mirror: CSetBounds's own full-width
// window check ($veda_csetbounds_window_ok). A pre-existing RTL-only
// divergence (since Milestone 3, not introduced by the 2026-08-19
// widening) found and fixed while auditing this exact line: the
// window check must compare cs1.Offset against the FULL 64-bit rs2
// value, not the already-truncated 20-bit new_length. An rs2 whose
// low 20 bits alias a small, in-window value but whose full 64-bit
// value is enormous must soft-fail (Tag cleared). See
// veda_smoke_csetbounds_widthcheck_neg.S.
//
// Adversarial-review Finding #5: a second phase (x11/x12 below) also
// proves CSetBounds's own SUCCESS path at a genuinely widened
// new_length (bits[19:16] nonzero) -- the soft-fail phase above alone
// never exercised the positive path at all.
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

    $display("CSetBounds(rs2=huge, low20=in-window) tag: x10=0x%0h (must be 0 -- soft-fail)", dut.CPU_Xreg_val_a0[10]);
    $display("CSetBounds(widened new_length) tag       : x11=0x%0h (must be 1 -- success)", dut.CPU_Xreg_val_a0[11]);
    $display("CSetBounds(widened new_length) cgetlen   : x12=0x%0h (must be 0x30000)", dut.CPU_Xreg_val_a0[12]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h0 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h30000) begin
      $display("\n*** TEST PASSED *** ($veda_csetbounds_window_ok correctly compares cs1.Offset against the FULL 64-bit rs2 value, not the already-truncated 20-bit new_length -- an rs2 whose low 20 bits alias a small in-window value but whose full value is enormous correctly soft-fails (Tag cleared) instead of wrongly succeeding; a genuinely widened new_length=0x30000, bits[19:16] nonzero, correctly succeeds and threads through to CGetLen's own readback)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
