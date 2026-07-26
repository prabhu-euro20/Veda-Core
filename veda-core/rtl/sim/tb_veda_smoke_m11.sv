`timescale 1ns/1ps
// Veda-Core RTL Milestone 11: OSpecialRW + capability-authority-gated
// ODT-Populate/ODT-Destroy. Proves OSpecialRW's own real atomic
// read-then-write semantics (mirroring CHERI's CSpecialRW), and -- the
// one proof Sail's own test config genuinely could not provide (S/U-mode
// disabled there) -- that a live, unsealed, PERMIT_ACCESS_SYSTEM_
// REGISTERS-carrying capability delegated into the ODA authorizes
// ODT-Populate on its own, with ordinary M-mode privilege dropped
// entirely via a real `veda.droppriv`.
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

    repeat (45) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("OSpecialRW old-ODA : x10=0x%0h (must be 0)", dut.CPU_Xreg_val_a0[10]);
    $display("OSpecialRW new-ODA tag : x11=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[11]);
    $display("OSpecialRW new-ODA base: x12=0x%0h (must be 0x80011000)", dut.CPU_Xreg_val_a0[12]);
    $display("post-droppriv ODT-Populate via ODA alone: c4.tag=x13=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[13]);
    $display("post-droppriv ODT-Populate via ODA alone: c4.base=x14=0x%0h (must be 0x80012000)", dut.CPU_Xreg_val_a0[14]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h0 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h80011000 &&
        dut.CPU_Xreg_val_a0[13] == 64'h1 &&
        dut.CPU_Xreg_val_a0[14] == 64'h80012000) begin
      $display("\n*** TEST PASSED *** (OSpecialRW's real atomic read-then-write correctly captures the ODA's old value before overwriting it; ODT-Populate genuinely succeeds via the ODA's own capability-authority path alone, with ordinary M-mode privilege dropped entirely -- the real capability-permission-gated version VEDA_CORE_SPEC.md named and deferred since Milestone 4 now actually exists)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
