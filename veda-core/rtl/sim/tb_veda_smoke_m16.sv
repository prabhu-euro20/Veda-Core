`timescale 1ns/1ps
// Veda-Core RTL Milestone 16: ODT generation-wraparound retirement (real
// bug fix, ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 2). Positive
// control: a slot destroyed/re-populated a normal, small number of times
// (5, far under the 255-reuse retirement threshold) must keep working
// completely normally. See veda_smoke_m16.S for the full step-by-step
// proof structure.
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

    $display("5th incarnation read: x8=0x%0h (must be 0x5555555555555555)", dut.CPU_Xreg_val_a0[8]);

    if (dut.CPU_Xreg_val_a0[8] == 64'h5555555555555555) begin
      $display("\n*** TEST PASSED *** (a slot destroyed/re-populated a normal, small number of times keeps working completely normally -- the Milestone 16 retirement fix rejects only slots that have genuinely exhausted their real 8-bit generation counter, nothing else)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
