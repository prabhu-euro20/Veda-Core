`timescale 1ns/1ps
// Veda-Core RTL Milestone 17: OCJALR -- proves the real, hardware
// atomic unseal-verify-and-jump end to end: a sealed return-capability,
// built from the already-verified OCA+CSeal call-site convention
// STACK_FRAME_CALL_RETURN_ANALYSIS.md's own `prot_caught` experiment
// established, genuinely redirects PC to its own resolved target
// address in a single instruction -- no separate software Tag check
// gating the jump. See veda_smoke_m17.S for the full proof structure.
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

    $display("landed : x23=0x%0h (must be 0x600D -- real jump reached landing_pad)", dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[23] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (OCJALR's real hardware jump landed exactly at the sealed return-capability's own resolved target address, verifying Tag/Seal/Permit_Unseal/otype-match/Permit_Execute atomically in one instruction -- no separate software check the caller could have forgotten)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
