`timescale 1ns/1ps
// LOCAL_FAULT_RECOVERY_DESIGN.md / RTL mirror: real bug fix proof for
// VEDA_LOCAL_HANDLER's cross-compartment handler-table collision via
// the shared UNSEALED_OTYPE sentinel. RTL mirror of
// sail_tests/vc_local_handler_neg_unsealed_otype.S. x20 must be 1
// (trap_handler genuinely reached, i.e. osethandler correctly refused
// under the shared identity), x23 must be 1 (cause == 0x0a,
// VEDA_CAUSE_NO_LIVE_COMPARTMENT), x24 must be 1 (cap_idx == 8, the
// osethandler operand), x21 must reach the success sentinel 0x600D, and
// x22 must never take on any fail-sentinel value.
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

    $display("trap_handler genuinely reached : x20=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[20]);
    $display("cause == VEDA_CAUSE_NO_LIVE_COMPARTMENT : x23=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[23]);
    $display("cap_idx == 8 (osethandler operand)      : x24=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[24]);
    $display("legitimate fallback exit  : x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("fail sentinel             : x22=0x%0h (must stay 0)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[20] == 64'd1 &&
        dut.CPU_Xreg_val_a0[23] == 64'd1 &&
        dut.CPU_Xreg_val_a0[24] == 64'd1 &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h0) begin
      $display("\n*** TEST PASSED *** (VEDA_LOCAL_HANDLER RTL mirror: osethandler correctly refuses to register a handler while veda_pcc_otype holds the shared UNSEALED_OTYPE sentinel, even though PCC itself is genuinely bounded via an OCReturn-only entry with no OCInvoke -- closes the cross-compartment handler-table collision an adversarial review found)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
