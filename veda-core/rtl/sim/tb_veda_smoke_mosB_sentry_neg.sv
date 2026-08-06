`timescale 1ns/1ps
// Veda-Core RTL mirror of minimal OS kernel Milestone B negative paths:
// (1) ordinary CSeal genuinely cannot forge the reserved sentry otype
// (0xFFFE) even when an authority capability is walked to exactly that
// Offset via OCA -- the load-bearing security property for the whole
// sentry mechanism; (2) OCRETURN through an untagged capability
// hard-traps TAG_VIOLATION and correctly resumes via a real trap-and-
// recover cycle.
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

    $display("OCA walk to Offset=0xFFFE tag (must be 1): x12=0x%0h", dut.CPU_Xreg_val_a0[12]);
    $display("forged-sentry CSeal tag (must be 0, soft-failed): x10=0x%0h", dut.CPU_Xreg_val_a0[10]);
    $display("OCRETURN-untagged trap reached with correct mcause/mtval (must be 0x600D): x11=0x%0h", dut.CPU_Xreg_val_a0[11]);

    if (dut.CPU_Xreg_val_a0[12] == 64'h1 &&
        dut.CPU_Xreg_val_a0[10] == 64'h0 &&
        dut.CPU_Xreg_val_a0[11] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (ordinary CSeal is genuinely hardware-blocked from forging the reserved sentry otype even when walked to it via OCA; OCRETURN correctly hard-traps on an untagged capability with the right cause/cap_idx, RTL mirror of minimal OS kernel Milestone B)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
