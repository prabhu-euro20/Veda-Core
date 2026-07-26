`timescale 1ns/1ps
// Veda-Core RTL Milestone 7: OCL.C/OCS.C -- real, working capability-width
// (128-bit), Tag-preserving memory access for the first time in RTL. A
// real capability round-trips through elfmem[]+tag_mem[] with its Tag
// intact (positive), and a plain OCS.D overwriting the same bytes
// correctly clears the tag store's own record, so a subsequent OCL.C
// reads back untagged (negative) -- the core security property this
// milestone exists to prove.
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

    repeat (35) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("c2 (round-tripped): tag=%0b base=0x%0h len=0x%0h perm=0x%0h",
              dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11],
              dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13]);
    $display("c3 (after plain OCS.D overwrite): tag=%0b (must be 0)", dut.CPU_Xreg_val_a0[14]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h80010100 &&
        dut.CPU_Xreg_val_a0[12] == 64'h40 &&
        dut.CPU_Xreg_val_a0[13] == 64'h000C &&
        dut.CPU_Xreg_val_a0[14] == 64'h0) begin
      $display("\n*** TEST PASSED *** (OCL.C/OCS.C: a real capability round-trips through memory with Tag intact via a real out-of-band tag store; a plain OCS.D overwrite correctly strips the tag, confirmed via a subsequent OCL.C reading back untagged)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
