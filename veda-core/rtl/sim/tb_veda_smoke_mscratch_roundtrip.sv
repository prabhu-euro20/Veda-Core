`timescale 1ns/1ps
// RTL Milestone 25 mirror: standalone mscratch CSR round-trip proof, run
// BEFORE the full 31-register scheduler port trusts this brand-new
// register in real clocked simulation. See veda_smoke_mscratch_roundtrip.S.
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

    repeat (40) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("mscratch round-trip result (must be 0x600D): x21=0x%0h", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (mscratch CSR round-trips correctly: plain write/read AND csrrw's atomic read-old/write-new semantics both hold for the newly-added register)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
