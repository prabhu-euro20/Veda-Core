`timescale 1ns/1ps
// Veda-Core RTL Milestone 2 smoke test: OCA repositions a capability's
// persistent Offset, then NMC_ADD.D and Veda-Atomic (AMOXOR.D) both
// operate through it in sequence, with a final OCL.D confirming the real
// memory state. Mirrors sim/tb_veda_smoke.sv's own structure.
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

    repeat (16) begin
      @(posedge clk);
      #1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h | oca=%0b nmc_add=%0b atomic=%0b viol=%0b | x5=0x%0h x7=0x%0h x8=0x%0h | c1: tag=%0b base=0x%0h perms=0x%0h",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0,
                dut.CPU_is_veda_oca_a0, dut.CPU_is_veda_nmc_add_d_a0, dut.CPU_is_veda_atomic_a0, dut.CPU_veda_violation_a0,
                dut.CPU_Xreg_val_a0[5], dut.CPU_Xreg_val_a0[7], dut.CPU_Xreg_val_a0[8],
                dut.CPU_Vreg_tag_a0[1], dut.CPU_Vreg_base_a0[1], dut.CPU_Vreg_perms_a0[1]);
      cyc_cnt = cyc_cnt + 1;
    end

    if (dut.CPU_Xreg_val_a0[5] == 64'h100 && dut.CPU_Xreg_val_a0[7] == 64'h123 && dut.CPU_Xreg_val_a0[8] == 64'h12C) begin
      $display("\n*** TEST PASSED *** (x5=0x100 old-via-NMC_ADD, x7=0x123 old-via-Atomic, x8=0x12C final memory)");
    end else begin
      $display("\n*** TEST FAILED *** (x5=0x%0h x7=0x%0h x8=0x%0h, expected 0x100/0x123/0x12C)",
                dut.CPU_Xreg_val_a0[5], dut.CPU_Xreg_val_a0[7], dut.CPU_Xreg_val_a0[8]);
    end

    $finish;
  end
endmodule
