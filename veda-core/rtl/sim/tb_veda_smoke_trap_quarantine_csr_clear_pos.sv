`timescale 1ns/1ps
// TRAP_QUARANTINE_RESULTS.md (adversarial RTL-mirror review, 2026-08-19):
// positive test proving the veda_trap_quarantine_clear CSR (0x7C6) round
// trip is real hardware plumbing, not a no-op. RTL mirror of
// sail_tests/vc_trap_quarantine_csr_clear_pos.S, GPR-readback convention
// (no HTIF). x24 must be 1 (the quarantine refusal, cause=0x09
// cap_idx=3, was genuinely observed after 3 real faults), x25 must be 1
// (the SAME otype faults ORDINARILY again, cause=0x01 cap_idx=16, right
// after the CSR clear -- proving the clear genuinely reset the tracker
// entry rather than merely being accepted and ignored), x21 must reach
// the success sentinel 0x600D, and x22 must never take on either
// fail-sentinel value (0xBAD1/0xDEAD).
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

    repeat (1200) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("quarantine refusal confirmed : x24=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[24]);
    $display("post-clear ordinary re-fault : x25=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[25]);
    $display("success sentinel             : x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("fail sentinel                : x22=0x%0h (must stay 0, not 0xBAD1/0xDEAD)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[24] == 64'd1 &&
        dut.CPU_Xreg_val_a0[25] == 64'd1 &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h0) begin
      $display("\n*** TEST PASSED *** (VEDA_TRAP_QUARANTINE RTL mirror: the veda_trap_quarantine_clear CSR (0x7C6) genuinely resets a quarantined otype's tracker entry -- after the CSR write, the SAME compartment identity faults ordinarily again instead of staying refused, proving the clear is real hardware plumbing, not a no-op)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
