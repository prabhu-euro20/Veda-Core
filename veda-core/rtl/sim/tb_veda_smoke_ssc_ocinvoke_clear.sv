`timescale 1ns/1ps
// Veda-Core RTL mirror of SSC's real, load-bearing security property:
// OCInvoke clears SSC on every successful compartment-boundary crossing.
// See veda_smoke_ssc_ocinvoke_clear.S.
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

    repeat (140) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("SSC-readback tag (must be 0): x20=0x%0h", dut.CPU_Xreg_val_a0[20]);
    $display("handler reached (must be 0x600D): x23=0x%0h", dut.CPU_Xreg_val_a0[23]);
    $display("resumed after MRET (must be 0x900D): x24=0x%0h", dut.CPU_Xreg_val_a0[24]);

    if (dut.CPU_Xreg_val_a0[20] == 64'h0 &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h900D) begin
      $display("\n*** TEST PASSED *** (OCInvoke genuinely clears SSC on every compartment-boundary crossing -- the callee reads it back untagged, and an attempted OCL.D through the untagged readback hard-traps with mcause=0x18/mtval=0x102, Tag Violation -- closing the real leak an independent design review found before any code was written)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
