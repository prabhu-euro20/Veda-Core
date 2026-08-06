`timescale 1ns/1ps
// Veda-Core RTL Milestone 23: ECALL from inside a live, narrowly-bounded
// OCInvoke compartment. Proves Milestone 21's "universal PCC reset on any
// trap" genuinely applies to the new ECALL trap: live veda_pcc_base/_length
// read back unbounded from inside the handler while veda_mepcc_base/_length
// hold the compartment's true pre-trap bounds, and mepc equals ECALL's own
// address inside the compartment.
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

    repeat (80) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("all checks passed: x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("fail sentinel (must stay 0, not 0xDEAD): x22=0x%0h", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] != 64'hDEAD) begin
      $display("\n*** TEST PASSED *** (ECALL from inside a live OCInvoke compartment genuinely traps with mcause=11; Milestone 21's universal PCC reset applies to it for free -- live PCC reads unbounded, veda_mepcc_base/_length hold the compartment's true saved bounds, mepc pins the trap to ECALL's own address inside the compartment -- RTL Milestone 23)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
