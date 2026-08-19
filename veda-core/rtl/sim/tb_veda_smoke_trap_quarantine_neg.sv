`timescale 1ns/1ps
// TRAP_QUARANTINE_DESIGN.md / RTL mirror (task #351): negative test for
// the repeated-trap DoS containment mechanism. RTL mirror of
// sail_tests/vc_repeated_trap_dos_neg.S, GPR-readback convention (no
// HTIF). x9 must reach exactly 5 (REPEAT_COUNT), x24/x25 must both be 1
// (traps 4 and 5 were genuinely refused with VEDA_CAUSE_COMPARTMENT_
// QUARANTINED against cap_idx=3, not merely counted), x21 must reach the
// success sentinel 0x600D via the legitimate mret escape, and x22 must
// never take on the fail-sentinel values (0xBAD1/0xDEAD).
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

    repeat (800) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("total trap count            : x9 =0x%0h (must be 5)", dut.CPU_Xreg_val_a0[9]);
    $display("trap #4 genuinely quarantined: x24=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[24]);
    $display("trap #5 genuinely quarantined: x25=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[25]);
    $display("legitimate mret escape       : x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("fail sentinel                : x22=0x%0h (must stay 0, not 0xBAD1/0xDEAD)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[9]  == 64'd5 &&
        dut.CPU_Xreg_val_a0[24] == 64'd1 &&
        dut.CPU_Xreg_val_a0[25] == 64'd1 &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h0) begin
      $display("\n*** TEST PASSED *** (VEDA_TRAP_QUARANTINE RTL mirror: 3 real compartment-bounds faults bring the same otype's tracker entry to threshold, and both further re-invoke attempts are hard-refused with VEDA_CAUSE_COMPARTMENT_QUARANTINED=0x09 against cap_idx=3 -- the repeated-trap DoS attack is genuinely contained, not merely observed)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
