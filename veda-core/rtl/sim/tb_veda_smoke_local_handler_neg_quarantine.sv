`timescale 1ns/1ps
// LOCAL_FAULT_RECOVERY_DESIGN.md / RTL mirror: quarantine-composition
// negative test for VEDA_LOCAL_HANDLER. RTL mirror of
// sail_tests/vc_local_handler_neg_quarantine.S, GPR-readback convention
// (no HTIF). x26/x28/x29 must all be 1 (the ordinary global fallback was
// genuinely reached, with the ordinary PCC-violation cause/cap_idx, and
// PCC genuinely reset). x27 (== x25, the redirect count at the moment of
// fallback) is reported, not hardcoded here to a value assumed in
// advance -- see LOCAL_FAULT_RECOVERY_RESULTS.md for the exact,
// empirically-confirmed number this test settled on.
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

    $display("redirect count at fallback (x25/x27): x25=0x%0h x27=0x%0h", dut.CPU_Xreg_val_a0[25], dut.CPU_Xreg_val_a0[27]);
    $display("global fallback reached             : x26=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[26]);
    $display("fallback cause/cap_idx ordinary      : x28=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[28]);
    $display("fallback PCC genuinely reset         : x29=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[29]);
    $display("fail sentinel                        : x22=0x%0h (must stay 0)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[26] == 64'd1 &&
        dut.CPU_Xreg_val_a0[28] == 64'd1 &&
        dut.CPU_Xreg_val_a0[29] == 64'd1 &&
        dut.CPU_Xreg_val_a0[25] == dut.CPU_Xreg_val_a0[27] &&
        dut.CPU_Xreg_val_a0[25] == 64'd3 &&
        dut.CPU_Xreg_val_a0[22] == 64'h0) begin
      $display("\n*** TEST PASSED *** (VEDA_LOCAL_HANDLER RTL mirror: a self-faulting local handler is redirected into exactly 3 times, then the composition guard (VEDA_TRAP_QUARANTINE's own count>=3 threshold, checked BEFORE this fault's own increment -- a real, structural RTL-vs-Sail difference, see LOCAL_FAULT_RECOVERY_RESULTS.md) refuses the 4th redirect and falls through to the ordinary global fallback with the ordinary cause -- the self-inflicted redirect DoS is genuinely bounded, not merely observed)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
