`timescale 1ns/1ps
// Veda-Core RTL Milestone 14 negative test: an OCInvoke-entered
// compartment with a genuinely small Length (0x04, one instruction)
// must hard-trap the moment execution tries to fetch past it -- correct
// mcause/mtval/mepc, correct veda_mepcc_base/_length save, and the full
// explicit-restore-and-recover cycle across a real MRET. See
// veda_smoke_m14_neg.S.
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

    $display("handler reached   : x21=0x%0h (must be 0x600D -- correct mcause/mtval/mepc/mepcc)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET: x22=0x%0h (must be 0x900D -- MRET's own real PC redirect worked)", dut.CPU_Xreg_val_a0[22]);
    $display("pcc_length after explicit restore: x23=0x%0h (must be 0xFFFF)", dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D &&
        dut.CPU_Xreg_val_a0[23] == 64'hFFFF) begin
      $display("\n*** TEST PASSED *** (an OCInvoke-entered compartment genuinely hard-traps when execution tries to escape its own Base/Length -- cause=0x01/VEDA_CAUSE_BOUNDS_VIOLATION reused, cap_idx=16 the real PCC sentinel value; veda_mepcc_base/_length correctly save the live bounds; the trap handler's own explicit CSR-based restore correctly re-widens execution and MRET resumes at the real recovery point outside the abandoned compartment)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
