`timescale 1ns/1ps
// Veda-Core RTL Milestone 12 negative test: plain Bind against a LIVE
// object owned by a genuinely different hart (the reset-seeded
// Object_ID=3 fixture, owner_hart=0x63) must genuinely hard-trap --
// PC redirects to mtvec, mcause=0x18/mtval=cap_idx@0x06/mepc points at
// the faulting Bind, MRET resumes exactly one instruction past it, and
// the destination capability register is left COMPLETELY untouched
// (not even Tag cleared -- Sail's own veda_trap() diverts control flow
// before any wC()/wCTag() call). See veda_smoke_m12_neg.S.
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
      $display("\n*** TEST PASSED *** (plain Bind against a live, wrong-owner object genuinely hard-traps with cause=0x06/VEDA_CAUSE_OWNER_VIOLATION, cap_idx=rd; MRET correctly resumes past the fault; the destination capability register is left completely untouched, matching Sail's own veda_trap() semantics exactly)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
