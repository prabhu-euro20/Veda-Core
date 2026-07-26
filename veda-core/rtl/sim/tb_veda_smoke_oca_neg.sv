`timescale 1ns/1ps
// Negative control for OCA's own out-of-bounds soft-fail path (distinct
// from the Permit_NMC_Compute negative control already tested): OCA with
// a delta pushing Offset past Length must clear c1.Tag without trapping,
// and the downstream NMC_ADD.D through the now-untagged c1 must be a
// violation, with x5 retaining its sentinel value.
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

    repeat (20) begin
      @(posedge clk);
      #1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h | oca=%0b nmc_add=%0b viol=%0b | x5=0x%0h | c1: tag=%0b",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0,
                dut.CPU_is_veda_oca_a0, dut.CPU_is_veda_nmc_add_d_a0, dut.CPU_veda_violation_a0,
                dut.CPU_Xreg_val_a0[5], dut.CPU_Vreg_tag_a0[1]);
      cyc_cnt = cyc_cnt + 1;
    end

    if (dut.CPU_Vreg_tag_a0[1] == 1'b0 && dut.CPU_Xreg_val_a0[5] == 64'h5555) begin
      $display("\n*** TEST PASSED *** (OCA soft-fail cleared c1.Tag, downstream NMC_ADD correctly blocked)");
    end else begin
      $display("\n*** TEST FAILED *** (c1.tag=%0b x5=0x%0h, expected tag=0 x5=0x5555)",
                dut.CPU_Vreg_tag_a0[1], dut.CPU_Xreg_val_a0[5]);
    end

    $finish;
  end
endmodule
