`timescale 1ns/1ps
// Veda-Core RTL Milestone 1 smoke test: loads a real ELF (bind, ocs.d,
// ocl.d) via the +elf_hex plusarg (the same real mechanism the base
// core's own ACT4 mode already uses -- see veda_core.tlv's elfmem
// initial block), dumps a cycle trace including the Capability Register
// File's own real state for manual review, mirroring rtl/sim/tb_smoke.sv's
// own proven structure.
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

    repeat (12) begin
      @(posedge clk);
      #1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h | bind=%0b ocl=%0b ocs=%0b viol=%0b | x1=%0d x2=%0d x3=%0d x4=0x%0h | c0: tag=%0b base=0x%0h length=0x%0h perms=0x%0h otype=0x%0h",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0,
                dut.CPU_is_veda_bind_a0, dut.CPU_is_veda_ocl_a0, dut.CPU_is_veda_ocs_a0, dut.CPU_veda_violation_a0,
                dut.CPU_Xreg_val_a0[1], dut.CPU_Xreg_val_a0[2], dut.CPU_Xreg_val_a0[3], dut.CPU_Xreg_val_a0[4],
                dut.CPU_Vreg_tag_a0[0], dut.CPU_Vreg_base_a0[0], dut.CPU_Vreg_length_a0[0],
                dut.CPU_Vreg_perms_a0[0], dut.CPU_Vreg_otype_a0[0]);
      cyc_cnt = cyc_cnt + 1;
    end

    if (dut.CPU_Xreg_val_a0[4] == 64'h1234) begin
      $display("\n*** TEST PASSED *** (x4 == 0x1234, real round trip through Veda-Core RTL)");
    end else begin
      $display("\n*** TEST FAILED *** (x4 == 0x%0h, expected 0x1234)", dut.CPU_Xreg_val_a0[4]);
    end

    $finish;
  end
endmodule
