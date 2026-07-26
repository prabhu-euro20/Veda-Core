`timescale 1ns/1ps
// Veda-Core RTL Milestone 6: CSeal/CUnseal -- real, working RTL for the
// first time, ties together Milestone 4's ODT-Populate (mints a real
// type-authority capability with Permit_Seal/Permit_Unseal, since neither
// reset-seeded object carries those bits) and activates $veda_sealed's own
// enforcement in OCL (wired in since Milestone 1 but structurally dead
// code until a sealed capability could actually exist). Full lifecycle:
// seal -> blocked-use -> unseal -> usable-again, plus two negative checks
// (missing Permit_Seal, mismatched type-authority for unseal).
// RTL Milestone 9 addendum: the sealed-use-blocked check is now a real
// hard trap (mcause=0x18, mtval=SEAL_VIOLATION) instead of only a
// suppressed write -- veda_smoke_m6.S installs a real trap handler for
// just that one check and MRETs back into this file's own original
// CUnseal/reuse/negative-check flow, unchanged.
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

    repeat (55) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("c1 (sealed) : tag=%0b type=0x%0h base=0x%0h perm=0x%0h", dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13]);
    $display("sealed-use blocked: x20=0x%0h (must stay 0xDEAD)", dut.CPU_Xreg_val_a0[20]);
    $display("c3 (unsealed): tag=%0b", dut.CPU_Xreg_val_a0[24]);
    $display("c3 use works : x21=0x%0h", dut.CPU_Xreg_val_a0[21]);
    $display("cseal neg (no Permit_Seal)   : c5.tag=%0b (x22, must be 0)", dut.CPU_Xreg_val_a0[22]);
    $display("cunseal neg (wrong authority): c6.tag=%0b (x23, must be 0)", dut.CPU_Xreg_val_a0[23]);
    $display("sealed-use trap correctly caught: x25=0x%0h (must be 0x600D -- real handler ran to completion)", dut.CPU_Xreg_val_a0[25]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 && dut.CPU_Xreg_val_a0[11] == 64'h0 &&
        dut.CPU_Xreg_val_a0[12] == 64'h80010000 && dut.CPU_Xreg_val_a0[13] == 64'h100C &&
        dut.CPU_Xreg_val_a0[20] == 64'hDEAD &&
        dut.CPU_Xreg_val_a0[24] == 64'h1 &&
        dut.CPU_Xreg_val_a0[21] == 64'hABCD1234ABCD5678 &&
        dut.CPU_Xreg_val_a0[22] == 64'h0 &&
        dut.CPU_Xreg_val_a0[23] == 64'h0 &&
        dut.CPU_Xreg_val_a0[25] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (CSeal mints a real sealed capability with full field copy from cs1; sealed-use now genuinely traps -- mcause=0x18, mtval=SEAL_VIOLATION -- caught by a real handler and MRET-resumed correctly, RTL Milestone 9; CUnseal correctly restores usability; both negative paths -- missing Permit_Seal, mismatched type-authority -- correctly soft-fail, unaffected by Milestone 9's trap infra since they're 'manipulate', not 'use', instructions)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
