`timescale 1ns/1ps
// Veda-Core RTL Milestone 18 negative test: VEDA_ODT_POPULATE_FAST's
// veda_attr-sourced Length must genuinely bound-check a later access --
// a deliberately small Length (0x8) set via veda_attr, followed by an
// out-of-range OCS.D (offset 0x10, width 8), must hard-trap with
// cause=0x01 (Bounds Violation)/cap_idx=1 (c1), and MRET must correctly
// resume past the fault. See veda_smoke_m18_neg.S.
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

    $display("handler reached   : x21=0x%0h (must be 0x600D -- correct mcause/mtval/mepc)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET: x22=0x%0h (must be 0x900D -- MRET's own real PC redirect worked)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D) begin
      $display("\n*** TEST PASSED *** (VEDA_ODT_POPULATE_FAST's veda_attr-sourced Length genuinely bound-checked: a real out-of-range OCS.D hard-traps with cause=0x01/VEDA_CAUSE_BOUNDS_VIOLATION, cap_idx=1; MRET correctly resumes past the fault)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
