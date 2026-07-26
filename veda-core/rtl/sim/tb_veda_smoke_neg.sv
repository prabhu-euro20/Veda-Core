`timescale 1ns/1ps
// Negative control for Veda-Core RTL Milestone 1's own OCS.D Tag check --
// upgraded in Milestone 9 to check a real hard trap (mcause=0x18,
// mtval=TAG_VIOLATION) and a real post-MRET resume, not a raw memory
// snapshot. See veda_smoke_neg.S's own header comment for the real
// Object_ID/testbench-address bug this milestone found and fixed in the
// process (the old version's Object_ID=2 was actually valid by the time
// Milestone 2 seeded it, and the old testbench checked the wrong address
// besides -- it was reporting PASS for the wrong reason the entire time).
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
      $display("\n*** TEST PASSED *** (untagged OCS.D genuinely trapped -- mcause=0x18, mtval=TAG_VIOLATION -- rather than silently continuing; MRET correctly resumed past the fault)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
