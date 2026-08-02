`timescale 1ns/1ps
// Veda-Core RTL Milestone 19 negative test 1: the real, previously-open
// CGetBase-then-ordinary-load/store bypass this milestone closes. With
// veda_purecap set, an ordinary ld through a plain GPR address must
// hard-trap -- cause=0x07 (VEDA_CAUSE_PURECAP_VIOLATION), cap_idx=17,
// mtval=0x227 -- and the destination register must never be corrupted
// with load data. See veda_smoke_m19_neg.S.
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

    $display("handler reached      : x21=0x%0h (must be 0x600D -- correct mcause=0x18/mtval=0x227)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET   : x22=0x%0h (must be 0x900D -- MRET's own real PC redirect worked)", dut.CPU_Xreg_val_a0[22]);
    $display("blocked-load dest reg: x9=0x%0h  (must still be 0xDEAD -- the write was genuinely suppressed)", dut.CPU_Xreg_val_a0[9]);
    $display("ordinary ld after purecap cleared: x23=0x%0h (must be 0x1234)", dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D &&
        dut.CPU_Xreg_val_a0[9]  == 64'hDEAD &&
        dut.CPU_Xreg_val_a0[23] == 64'h1234) begin
      $display("\n*** TEST PASSED *** (with veda_purecap set, an ordinary ld through a plain GPR address genuinely hard-traps -- mcause=0x18, mtval=0x227 (cap_idx=17, cause=0x07/VEDA_CAUSE_PURECAP_VIOLATION) -- the destination register is never corrupted with load data, and the real, previously-open CGetBase-then-ordinary-load/store bypass is closed. Software's own explicit CSR-based restore correctly clears purecap and MRET resumes at the real recovery point, where ordinary access works again)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
