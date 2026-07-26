`timescale 1ns/1ps
// Veda-Core RTL Milestone 10: OCInvoke's own real trap paths -- Type
// Violation and Permit_Execute Violation -- mirrors vc_ocinvoke_neg.S's
// own Sail scenario exactly. Both cause codes (0x04/0x11) are activated
// for the first time in RTL by this milestone.
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

    repeat (100) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x23=0x%0h (must be 0x600D -- both real traps fired with correct mcause/mtval, both MRETs resumed correctly)", dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[23] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (OCInvoke's Type Violation and Permit_Execute Violation checks both genuinely trap -- mcause=0x18, mtval encoding the correct cause/cap_idx for each -- exactly matching real CHERI's own CInvoke check semantics, CHERI ISA spec p.209)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
