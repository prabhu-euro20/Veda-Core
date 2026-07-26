`timescale 1ns/1ps
// Veda-Core RTL Milestone 8: Rebind -- proves the project's own headline
// design claim in RTL for the first time: an object can be silently
// relocated (a fresh ODT-Populate at the same Object_ID, new Base, bumped
// generation) while a capability register's own Offset (its software-held
// cursor) is completely untouched by the relocation, and the very next
// dereference through that capability lands at the NEW physical address
// using that same, never-recomputed Offset. See veda_smoke_m8.S for the
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

    repeat (90) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("old-location round trip : x20=0x%0h (must be 5, @0x80010508)", dut.CPU_Xreg_val_a0[20]);
    $display("stale-reject sentinel   : x11=0x%0h (must stay 0xDEAD -- gen_stale blocked the AMO)", dut.CPU_Xreg_val_a0[11]);
    $display("post-rebind offset      : x12=0x%0h (must be 8 -- PRESERVED across relocation)", dut.CPU_Xreg_val_a0[12]);
    $display("post-rebind base        : x13=0x%0h (must be 0x80010600 -- the NEW, relocated Base)", dut.CPU_Xreg_val_a0[13]);
    $display("post-rebind tag         : x16=0x%0h (must be 1 -- real success)", dut.CPU_Xreg_val_a0[16]);
    $display("new-location old value  : x14=0x%0h (must be 0 -- fresh, never-written address)", dut.CPU_Xreg_val_a0[14]);
    $display("new-location round trip : x21=0x%0h (must be 5, @0x80010608 -- proves the relocation is functionally real)", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[20] == 64'h5 &&
        dut.CPU_Xreg_val_a0[11] == 64'hDEAD &&
        dut.CPU_Xreg_val_a0[12] == 64'h8 &&
        dut.CPU_Xreg_val_a0[13] == 64'h80010600 &&
        dut.CPU_Xreg_val_a0[16] == 64'h1 &&
        dut.CPU_Xreg_val_a0[14] == 64'h0 &&
        dut.CPU_Xreg_val_a0[21] == 64'h5) begin
      $display("\n*** TEST PASSED *** (Rebind refreshes Base/generation from the ODT while preserving Offset exactly as VEDA_CORE_SPEC.md Section 4 requires; a stale pre-rebind capability is correctly rejected; post-rebind memory access via the SAME, untouched Offset provably lands at the NEW physical address -- the object was silently relocated and software's own cursor never moved)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
