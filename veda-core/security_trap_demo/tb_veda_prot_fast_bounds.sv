`timescale 1ns/1ps
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

    $display("[VEDA-CORE M18] OCS.D past the veda_attr-sourced Length set by the OPTIMIZING instruction (VEDA_ODT_POPULATE_FAST):");
    $display("  mcause = 0x%0h  (0x18 = E_Extension, real hard trap)", dut.CPU_Xreg_val_a0[24]);
    $display("  mtval  = 0x%0h  (cap_idx<<5 | cause -- 0x21 = Bounds Violation, cap c1)", dut.CPU_Xreg_val_a0[25]);
    $display("  mepc   = 0x%0h  (faulting instruction address, precise)", dut.CPU_Xreg_val_a0[26]);
    $display("  x30    = 0x%0h", dut.CPU_Xreg_val_a0[30]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hca11)
      $display("  ==> TRAP CAUGHT. The fast-path optimization did not weaken bounds enforcement.");
    else
      $display("  ==> unexpected result");

    $finish;
  end
endmodule
