`timescale 1ns/1ps
// Veda-Core RTL mirror of Sail-side Minimal OS Kernel Milestone C: a real,
// two-thread cooperative round-robin scheduler composing TSC/OSpecialRW
// (Milestone A) and CSealEntry/OCRETURN (Milestone B), yielding via the new
// real ECALL (Milestone 23). Proves 4 yields (2 full A<->B round-trips):
// each thread's own counter incremented exactly twice, live PCC-bounds
// fidelity on each thread's second visit, and TSC round-trip fidelity
// every cycle.
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

    // RTL Milestone 25 mirror: raised from 700 -- the save/restore path
    // now covers 31 GPRs per direction instead of 3, roughly 8x more
    // OCL.D/OCS.D traffic per yield across the same 4 yields. Generous
    // on purpose for the first real run; tighten only after observing
    // actual cycles needed (this project's own established practice,
    // MILESTONE_14_RESULTS.md).
    repeat (5000) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    // NOTE: x20/x21/x22/x26 below are debug visibility only -- they
    // reflect whichever thread's own eager-restore loop last ran
    // (GPRs are now genuinely per-thread), NOT necessarily THREAD_A's
    // own state. The real pass/fail gate is x27 alone, which itself
    // depends on the memory-backed thread_a_ok/thread_b_ok flags
    // (see final_check in the .S file), not these GPRs directly.
    $display("THREAD_A counter (debug only, last-resumed thread's state): x20=%0d", dut.CPU_Xreg_val_a0[20]);
    $display("THREAD_B counter (debug only, last-resumed thread's state): x21=%0d", dut.CPU_Xreg_val_a0[21]);
    $display("THREAD_A bounds fidelity (debug only): x22=%0d", dut.CPU_Xreg_val_a0[22]);
    $display("THREAD_B bounds fidelity (debug only): x26=%0d", dut.CPU_Xreg_val_a0[26]);
    $display("TSC round-trip fidelity (must be 1): x9=%0d", dut.CPU_Xreg_val_a0[9]);
    $display("overall sentinel (must be 0x600D): x27=0x%0h", dut.CPU_Xreg_val_a0[27]);

    if (dut.CPU_Xreg_val_a0[27] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (a real 2-thread cooperative round-robin scheduler -- 4 yields via real ECALL, TSC swap via OSpecialRW, SCHEDULER invoked via OCInvoke and returning via OCRETURN through a CSealEntry-minted sentry -- proves Milestones A/B/23 compose into the real OS-kernel pattern in RTL, RTL mirror of Sail-side Milestone C)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
