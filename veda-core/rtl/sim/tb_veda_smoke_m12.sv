`timescale 1ns/1ps
// Veda-Core RTL Milestone 12: owner-hart ODT enforcement. Proves the two
// real, single-hart-reachable paths in RTL: a genuinely-unowned object
// can be claimed by Bind, a self-owned object can be idempotently
// re-claimed by Rebind, and both Bind-NoTrap and Rebind correctly
// soft-fail (Tag cleared, no trap) against the reset-seeded wrong-owner
// fixture (Object_ID=3, owner_hart=0x63). See veda_smoke_m12.S for the
// full, real, step-by-step proof structure.
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

    $display("bind-unowned   : tag=x10=0x%0h(1) base=x11=0x%0h(0x80010000)", dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("rebind-self    : tag=x12=0x%0h(1) base=x13=0x%0h(0x80010000)", dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13]);
    $display("bind.notrap-wrongowner: tag=x14=0x%0h(0)", dut.CPU_Xreg_val_a0[14]);
    $display("pre-rebind     : tag=x15=0x%0h(1) base=x16=0x%0h(0x80010000)", dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16]);
    $display("rebind-wrongowner: tag=x17=0x%0h(0) base=x18=0x%0h(0x80010000, unchanged)", dut.CPU_Xreg_val_a0[17], dut.CPU_Xreg_val_a0[18]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h80010000 &&
        dut.CPU_Xreg_val_a0[12] == 64'h1 &&
        dut.CPU_Xreg_val_a0[13] == 64'h80010000 &&
        dut.CPU_Xreg_val_a0[14] == 64'h0 &&
        dut.CPU_Xreg_val_a0[15] == 64'h1 &&
        dut.CPU_Xreg_val_a0[16] == 64'h80010000 &&
        dut.CPU_Xreg_val_a0[17] == 64'h0 &&
        dut.CPU_Xreg_val_a0[18] == 64'h80010000) begin
      $display("\n*** TEST PASSED *** (Bind claims a genuinely-unowned object and Rebind idempotently re-claims it as this same hart's own; Bind-NoTrap and Rebind both correctly soft-fail -- Tag cleared, no trap -- against a live object owned by a different hart)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
