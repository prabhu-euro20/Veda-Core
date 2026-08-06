`timescale 1ns/1ps
// Veda-Core RTL mirror of minimal OS kernel Milestone B: CSealEntry
// mints a real sentry (otype=0xFFFE, no authorizing capability operand),
// and a single-operand OCRETURN through it, from inside a live,
// narrowly-bounded OCInvoke compartment, both lands at the sentry's own
// target and genuinely widens veda_pcc_base/veda_pcc_length -- the
// actual, cheap cross-compartment-boundary-crossing primitive.
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

    $display("CSealEntry sentry tag (must be 1): x15=0x%0h", dut.CPU_Xreg_val_a0[15]);
    $display("CSealEntry sentry type (must be 0xFFFE): x16=0x%0h", dut.CPU_Xreg_val_a0[16]);
    $display("reached return_landing (must be 0x2222): x20=0x%0h", dut.CPU_Xreg_val_a0[20]);
    $display("veda_pcc_length after OCRETURN (must be 0xFFFF): x21=0x%0h", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[15] == 64'h1 &&
        dut.CPU_Xreg_val_a0[16] == 64'hFFFE &&
        dut.CPU_Xreg_val_a0[20] == 64'h2222 &&
        dut.CPU_Xreg_val_a0[21] == 64'hFFFF) begin
      $display("\n*** TEST PASSED *** (CSealEntry mints a real sentry with no authorizing capability operand; OCRETURN's single-operand verify-and-jump genuinely crosses the compartment boundary -- veda_pcc_length reads back as the sentry's own Length, not merely a jump inside the same window -- RTL mirror of minimal OS kernel Milestone B)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
