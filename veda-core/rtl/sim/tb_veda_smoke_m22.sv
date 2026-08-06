`timescale 1ns/1ps
// Veda-Core RTL Milestone 22: OCJALR cannot cross a compartment boundary
// on its own -- a genuinely valid, correctly-authorized sealed return-
// capability targeting an address outside a live OCInvoke compartment
// still hard-traps at the target's own first fetch (cause=0x01,
// cap_idx=16, the real PCC-violation sentinel), with mepc correctly
// resolved to the jump's own real target (return_landing) and
// veda_pcc_length correctly restored to VEDA_PCC_UNBOUNDED. Mirrors
// Sail's own vc_ocjalr_compartment_boundary_neg.S finding in real RTL.
// See veda_smoke_m22.S.
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

    repeat (90) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("fallthrough (must stay 0)        : x20=0x%0h", dut.CPU_Xreg_val_a0[20]);
    $display("trap handler reached              : x21=0x%0h (must be 0x600D -- correct mcause/mtval/mepc/pcc_length)", dut.CPU_Xreg_val_a0[21]);
    $display("escaped compartment (must stay 0) : x22=0x%0h", dut.CPU_Xreg_val_a0[22]);
    $display("wrong-trap-details (must stay 0)  : x23=0x%0h", dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[20] == 64'h0 &&
        dut.CPU_Xreg_val_a0[22] == 64'h0 &&
        dut.CPU_Xreg_val_a0[23] == 64'h0) begin
      $display("\n*** TEST PASSED *** (a genuinely valid, correctly-authorized sealed return-capability's OCJALR jump out of a live OCInvoke compartment still hard-traps at the target's own first fetch -- OCJALR alone cannot cross a compartment boundary in real RTL, matching Sail's own already-verified Milestone 22 finding; mepc resolves to the real jump target before the fetch-check catches it, and veda_pcc_length is correctly restored to unbounded by the time the handler runs)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
