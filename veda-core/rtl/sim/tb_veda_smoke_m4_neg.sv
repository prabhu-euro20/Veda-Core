`timescale 1ns/1ps
// Negative control for RTL Milestone 4: `veda.droppriv` first, then an
// ODT-Populate attempt against a never-before-seeded Object_ID must be a
// real no-op -- verified two ways: (1) through the ISA itself, matching
// Milestone 3's own "verify through a subsequent real instruction"
// discipline -- a Bind against that Object_ID must come back Tag=0,
// since no ODT entry was ever actually created; (2) directly against
// odt_mem[] itself, confirming the write genuinely never happened (not
// just that Bind's own separate check happened to also fail).
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

    repeat (14) begin
      @(posedge clk);
      #1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h | priv=%0b is_odt_pop=%0b pop_viol=%0b",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0,
                dut.CPU_priv_a0, dut.CPU_is_veda_odt_populate_a0, dut.CPU_veda_odt_populate_violation_a0);
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x6(c0 tag)=%0b odt_mem[Object_ID=5]: valid=%0b",
              dut.CPU_Xreg_val_a0[6], dut.odt_mem[32'h9000_0000+16*5+9][0]);

    if (dut.CPU_Xreg_val_a0[6] == 64'h0 &&
        dut.odt_mem[32'h9000_0000+16*5+9][0] == 1'b0) begin
      $display("\n*** TEST PASSED *** (dropped privilege correctly blocked ODT-Populate -- no ODT entry was ever created, confirmed both via odt_mem[] directly and via a subsequent Bind's own Tag=0)");
    end else begin
      $display("\n*** TEST FAILED *** (privilege gate did NOT block ODT-Populate)");
    end

    $finish;
  end
endmodule
