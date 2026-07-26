`timescale 1ns/1ps
// Negative control for CSetBounds's own out-of-window soft-fail:
// requesting a Length exceeding c0's own remaining window must clear
// c2.Tag without trapping.
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

    repeat (8) begin
      @(posedge clk);
      #1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h | csetbounds=%0b | x20=0x%0h | c2:tag=%0b",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0, dut.CPU_is_veda_csetbounds_either_a0,
                dut.CPU_Xreg_val_a0[20], dut.CPU_Vreg_tag_a0[2]);
      cyc_cnt = cyc_cnt + 1;
    end

    if (dut.CPU_Xreg_val_a0[20] == 64'h0) begin
      $display("\n*** TEST PASSED *** (CSetBounds out-of-window correctly soft-failed, c2.Tag=0)");
    end else begin
      $display("\n*** TEST FAILED *** (x20=0x%0h, expected 0)", dut.CPU_Xreg_val_a0[20]);
    end

    $finish;
  end
endmodule
