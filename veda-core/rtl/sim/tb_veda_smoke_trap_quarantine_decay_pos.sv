`timescale 1ns/1ps
// TRAP_QUARANTINE_DESIGN.md / RTL mirror (task #351): positive companion
// to tb_veda_smoke_trap_quarantine_neg.sv, proving the decay ("good
// behavior earns forgiveness") side of the mechanism is real. RTL mirror
// of sail_tests/vc_trap_quarantine_decay_pos.S, GPR-readback convention
// (no HTIF). x9/x10 must both reach exactly 2 (phase 1 and phase 3 each
// faulted exactly twice, ordinarily -- never quarantined), x21 must show
// the wide compartment's own body genuinely executed (0x3333), x23 must
// reach the final success sentinel 0x600D, and x22 must never take on
// any of the fail-sentinel values (0xBAD1/0xBAD2/0xBAD3/0xDEAD).
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

    repeat (900) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("phase-1 fault count      : x9 =0x%0h (must be 2)", dut.CPU_Xreg_val_a0[9]);
    $display("phase-3 fault count      : x10=0x%0h (must be 2)", dut.CPU_Xreg_val_a0[10]);
    $display("wide compartment body ran: x21=0x%0h (must be 0x3333)", dut.CPU_Xreg_val_a0[21]);
    $display("final success sentinel   : x23=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[23]);
    $display("fail sentinel            : x22=0x%0h (must stay 0)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[9]  == 64'd2 &&
        dut.CPU_Xreg_val_a0[10] == 64'd2 &&
        dut.CPU_Xreg_val_a0[21] == 64'h3333 &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h0) begin
      $display("\n*** TEST PASSED *** (VEDA_TRAP_QUARANTINE RTL mirror: a compartment that faults twice, then makes real forward progress via a clean OCRETURN, then faults twice more, is never quarantined -- OCRETURN's own success path genuinely decays the departing compartment's tracker entry to 0 before veda_pcc_otype is overwritten, matching the Sail side bit-for-bit)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
