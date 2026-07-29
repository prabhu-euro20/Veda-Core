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

    repeat (20) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("[TRADITIONAL RV64I] jalr through corrupted return address -- x30 = 0x%0h", dut.CPU_Xreg_val_a0[30]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hbad1)
      $display("  ==> HIJACK SUCCEEDED. Attacker-controlled code executed. No trap. No check.");
    else
      $display("  ==> unexpected result");

    $finish;
  end
endmodule
