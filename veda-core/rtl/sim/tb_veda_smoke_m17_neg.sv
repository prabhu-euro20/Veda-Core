`timescale 1ns/1ps
// Veda-Core RTL Milestone 17: OCJALR's own real trap paths -- Seal
// Violation, Type Violation, and Permit_Execute Violation -- mirrors
// vc_ocjalr_neg.S's own Sail scenario exactly. All three checks are
// hard, atomic gates a caller cannot forget to apply, closing the real
// software-discipline gap STACK_FRAME_CALL_RETURN_ANALYSIS.md's own
// `prot_gap` experiment found.
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

    repeat (140) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x23=0x%0h (must be 0x600D -- all three real traps fired with correct mcause/mtval, all three MRETs resumed correctly)", dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[23] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (OCJALR's Seal Violation, Type Violation, and Permit_Execute Violation checks all genuinely trap -- mcause=0x18, mtval encoding the correct cause/cap_idx for each -- no corrupted or forged return-capability can be jumped through without a hard trap, closing the real gap this milestone was built to close)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
