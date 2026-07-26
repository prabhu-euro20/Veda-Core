`timescale 1ns/1ps
// Negative control for RTL Milestone 2's own NMC_ADD.D permission check --
// upgraded in Milestone 9 to check a real hard trap (mcause=0x18,
// mtval=PERM_NMC_COMPUTE_VIOLATION via c1) and a real post-MRET resume,
// alongside the original x5-sentinel-survives check (still real and
// meaningful: a trap must never partially commit its writeback).
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

    repeat (30) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x22=0x%0h (must be 0x600D -- real trap fired with correct mcause/mtval/mepc, MRET resumed correctly)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[22] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (NMC_ADD.D via a Permit_NMC_Compute-less capability genuinely trapped -- mcause=0x18, mtval=PERM_NMC_COMPUTE_VIOLATION -- x5's sentinel survived untouched, MRET correctly resumed past the fault)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
