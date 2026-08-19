`timescale 1ns/1ps
// LOCAL_FAULT_RECOVERY_DESIGN.md / RTL mirror: negative test (no handler
// registered) for VEDA_LOCAL_HANDLER. RTL mirror of
// sail_tests/vc_local_handler_neg_no_handler.S, GPR-readback convention
// (no HTIF). x20 must be 1 (the ordinary global fallback was reached),
// x23/x24 must both be 1 (veda_pcc_base/_length genuinely reset to
// 0/UNBOUNDED, completely unchanged pre-existing behavior), x21 must
// reach the success sentinel 0x600D, and x22 must never take on any of
// the fail-sentinel values (0xBAD1/0xBAD3/0xBAD4/0xBAD5/0xBAD6).
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

    $display("ordinary global fallback reached: x20=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[20]);
    $display("veda_pcc_base reset to 0        : x23=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[23]);
    $display("veda_pcc_length reset to UNBOUND: x24=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[24]);
    $display("success sentinel                : x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("fail sentinel                   : x22=0x%0h (must stay 0)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[20] == 64'd1 &&
        dut.CPU_Xreg_val_a0[23] == 64'd1 &&
        dut.CPU_Xreg_val_a0[24] == 64'd1 &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h0) begin
      $display("\n*** TEST PASSED *** (VEDA_LOCAL_HANDLER RTL mirror: a compartment with no registered handler falls through to the completely unchanged, pre-existing global fallback -- zero regression from the new mechanism)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
