`timescale 1ns/1ps
// LOCAL_FAULT_RECOVERY_DESIGN.md / RTL mirror: confused-deputy negative
// test for VEDA_LOCAL_HANDLER. RTL mirror of
// sail_tests/vc_local_handler_neg_bounds_guard.S, GPR-readback
// convention (no HTIF). x20 must be 1 (phase-1's own rejection --
// cause=0x01/cap_idx=10 -- confirmed), x23 must be 1 (phase-2's own
// ordinary fallback -- cause=0x01/cap_idx=16 -- confirmed, proving
// nothing was registered by the rejected phase-1 attempt), x21 must
// reach the success sentinel 0x600D, and x22 must never take on any
// fail-sentinel value.
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

    repeat (400) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("phase-1 rejection confirmed (cause=0x01/cap_idx=10): x20=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[20]);
    $display("phase-2 ordinary fallback   (cause=0x01/cap_idx=16): x23=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[23]);
    $display("success sentinel                                   : x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("fail sentinel                                      : x22=0x%0h (must stay 0)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[20] == 64'd1 &&
        dut.CPU_Xreg_val_a0[23] == 64'd1 &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h0) begin
      $display("\n*** TEST PASSED *** (VEDA_LOCAL_HANDLER RTL mirror: a genuinely valid, out-of-bounds-target capability is hard-refused by osethandler's own confused-deputy bounds check, and a subsequent ordinary fault from the SAME re-invoked compartment falls through to the plain global path -- proving the rejected attempt wrote nothing to local_handler_table)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
