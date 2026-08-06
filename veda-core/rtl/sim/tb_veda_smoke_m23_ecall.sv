`timescale 1ns/1ps
// Veda-Core RTL Milestone 23: real ECALL support, baseline unbounded-context
// case. Proves ECALL genuinely traps with mcause=11 (real RISC-V E_M_EnvCall,
// not an invented Veda-specific code), mtval=0, mepc pointing at the ECALL
// instruction itself (no auto-advance), and MRET's own real PC redirect
// closes the full trap-and-resume cycle.
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

    $display("handler reached : x21=0x%0h (must be 0x600D -- correct mcause=11/mtval=0/mepc)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET: x22=0x%0h (must be 0x900D -- MRET's own real PC redirect worked)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D) begin
      $display("\n*** TEST PASSED *** (ECALL genuinely traps with real RISC-V mcause=11/mtval=0, mepc at the ECALL's own PC with no auto-advance, MRET closes the full trap-and-resume cycle -- RTL Milestone 23)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
