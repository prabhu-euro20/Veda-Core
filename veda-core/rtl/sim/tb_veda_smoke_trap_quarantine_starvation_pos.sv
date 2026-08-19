`timescale 1ns/1ps
// TRAP_QUARANTINE_RESULTS.md (adversarial RTL-mirror review, 2026-08-19):
// positive test proving the eviction-starvation-bypass fix
// ($veda_tt_any_safe in veda_core.tlv) is real and load-bearing, not a
// no-op. RTL mirror of sail_tests/vc_trap_quarantine_starvation_pos.S,
// GPR-readback convention (no HTIF). x28 must reach exactly 8 (all 8
// distinct otypes driven to full quarantine), x27 must be 1 (the victim,
// otype=0, was STILL refused with VEDA_CAUSE_COMPARTMENT_QUARANTINED
// after phase 2's fresh-otype fault against a saturated table -- proving
// it was never evicted), x24 must reach exactly 26 (24 phase-1 faults + 1
// phase-2 fault + 1 phase-3 refusal, confirming every real trap in this
// test was accounted for, not merely the final state), x29 must reach the
// success sentinel 0x600D, and x23 must never take on any of the
// fail-sentinel values (0xBAD1/0xBAD9/0xDEAD).
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

    repeat (5000) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("identities fully quarantined : x28=0x%0h (must be 8)", dut.CPU_Xreg_val_a0[28]);
    $display("victim still quarantined     : x27=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[27]);
    $display("total real trap count        : x24=0x%0h (must be 26)", dut.CPU_Xreg_val_a0[24]);
    $display("success sentinel             : x29=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[29]);
    $display("fail sentinel                : x23=0x%0h (must stay 0, not 0xBAD1/0xBAD9/0xDEAD)", dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[28] == 64'd8 &&
        dut.CPU_Xreg_val_a0[27] == 64'd1 &&
        dut.CPU_Xreg_val_a0[24] == 64'd26 &&
        dut.CPU_Xreg_val_a0[29] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'h0) begin
      $display("\n*** TEST PASSED *** (VEDA_TRAP_QUARANTINE RTL mirror: the eviction-starvation-bypass fix is real -- 8 distinct otypes driven to full quarantine saturate the 8-entry table, a 9th fresh otype's fault does NOT evict any of them, and the victim (otype=0) is still hard-refused with VEDA_CAUSE_COMPARTMENT_QUARANTINED on a fresh attempt, proving its entry survived intact)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
