`timescale 1ns/1ps
// Veda-Core RTL Milestone 13 negative test: plain Bind against a
// never-populated Object_ID (70) must genuinely hard-trap -- PC
// redirects to mtvec, mcause=0x18/mtval=cap_idx@0x05/mepc points at the
// faulting Bind, MRET resumes exactly one instruction past it, and the
// destination capability register is left COMPLETELY untouched. See
// veda_smoke_m13_neg.S.
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

    repeat (45) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("handler reached   : x21=0x%0h (must be 0x600D -- correct mcause/mtval/mepc)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET: x22=0x%0h (must be 0x900D -- MRET's own real PC redirect worked)", dut.CPU_Xreg_val_a0[22]);
    $display("c0 tag  (untouched): x23=0x%0h (must be 0 -- trap fired before any wC/wCTag)", dut.CPU_Xreg_val_a0[23]);
    $display("c0 base (untouched): x24=0x%0h (must be 0 -- trap fired before any wC/wCTag)", dut.CPU_Xreg_val_a0[24]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D &&
        dut.CPU_Xreg_val_a0[23] == 64'h0 &&
        dut.CPU_Xreg_val_a0[24] == 64'h0) begin
      $display("\n*** TEST PASSED *** (plain Bind against a never-populated Object_ID genuinely hard-traps with cause=0x05/VEDA_CAUSE_OBJECT_NOT_FOUND, cap_idx=rd, closing the gap Milestone 9 deliberately deferred; MRET correctly resumes past the fault; the destination capability register is left completely untouched)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
