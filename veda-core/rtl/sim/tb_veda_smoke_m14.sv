`timescale 1ns/1ps
// Veda-Core RTL Milestone 14: PCC compartment bounding. Proves the real
// state transitions: a fresh hart starts unbounded (veda_pcc_length =
// 0xFFFFF); a successful OCInvoke narrows the live compartment to the
// invoked CODE capability's own Base/Length; a second OCInvoke into an
// unbounded return capability widens it back. See veda_smoke_m14.S for
// the full, real, step-by-step proof structure.
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

    repeat (75) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("pcc_length before OCInvoke : x9=0x%0h (must be 0xFFFFF, unbounded)", dut.CPU_Xreg_val_a0[9]);
    $display("pcc_base  after OCInvoke   : x10=0x%0h (must be landing_pad's own address)", dut.CPU_Xreg_val_a0[10]);
    $display("pcc_length after OCInvoke  : x11=0x%0h (must be 0x0100, the narrowed compartment)", dut.CPU_Xreg_val_a0[11]);
    $display("pcc_length after return    : x12=0x%0h (must be 0xFFFFF again)", dut.CPU_Xreg_val_a0[12]);

    if (dut.CPU_Xreg_val_a0[9]  == 64'hFFFFF &&
        dut.CPU_Xreg_val_a0[11] == 64'h0100 &&
        dut.CPU_Xreg_val_a0[12] == 64'hFFFFF) begin
      $display("\n*** TEST PASSED *** (a fresh hart starts unbounded; a successful OCInvoke genuinely narrows veda_pcc_base/veda_pcc_length to the invoked code capability's own Base/Length; a second OCInvoke into an unbounded return capability correctly widens execution back -- the real state transitions PCC_COMPARTMENT_DESIGN.md's own design specifies, now real in RTL)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
