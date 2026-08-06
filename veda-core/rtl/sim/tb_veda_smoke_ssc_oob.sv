`timescale 1ns/1ps
// Veda-Core RTL mirror of SSC's own real spatial bounds check -- SSC
// gets the identical real bounds check every other Veda-Core capability
// register already gets. See veda_smoke_ssc_oob.S.
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

    $display("handler reached (must be 0x600D): x21=0x%0h", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (SSC gets the identical real spatial bounds check every other Veda-Core capability register already gets -- an out-of-bounds OCL.D against it hard-traps with mcause=0x18/mtval=0xA1, Bounds Violation)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
