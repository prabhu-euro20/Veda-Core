`timescale 1ns/1ps
// Veda-Core RTL Milestone 8: Rebind's three real failure/no-op paths --
// sealed destination register, ODT miss, and the reserved mode field --
// each must leave every field except Tag completely untouched (Sail's own
// execute clause never calls wC() on either failure path), and the
// reserved mode must be a true no-op, not silently fall through to plain
// Bind's behavior (the real gap this milestone found and closed -- before
// this milestone, $veda_bind_mode was decoded but never checked, so every
// mode value silently executed as plain Bind). See veda_smoke_m8_neg.S.
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

    $display("rebind-sealed  : tag=x30=0x%0h(0) type=x31=0x%0h(0, unchanged) base=x22=0x%0h(0x80010000, unchanged)",
              dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[31], dut.CPU_Xreg_val_a0[22]);
    $display("rebind-odtmiss : tag=x23=0x%0h(0) base=x24=0x%0h(0x80010000, unchanged)",
              dut.CPU_Xreg_val_a0[23], dut.CPU_Xreg_val_a0[24]);
    $display("rebind-reserved: tag=x25=0x%0h(1, unchanged) base=x26=0x%0h(0x80010000, unchanged -- NOT re-bound to Object_ID=2)",
              dut.CPU_Xreg_val_a0[25], dut.CPU_Xreg_val_a0[26]);

    if (dut.CPU_Xreg_val_a0[30] == 64'h0 &&
        dut.CPU_Xreg_val_a0[31] == 64'h0 &&
        dut.CPU_Xreg_val_a0[22] == 64'h80010000 &&
        dut.CPU_Xreg_val_a0[23] == 64'h0 &&
        dut.CPU_Xreg_val_a0[24] == 64'h80010000 &&
        dut.CPU_Xreg_val_a0[25] == 64'h1 &&
        dut.CPU_Xreg_val_a0[26] == 64'h80010000) begin
      $display("\n*** TEST PASSED *** (Rebind on a sealed rd soft-fails without touching any other field; Rebind against a never-populated Object_ID soft-fails the same way; the reserved mode field is now a true no-op, closing the real gap where every mode value used to silently execute as plain Bind)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
