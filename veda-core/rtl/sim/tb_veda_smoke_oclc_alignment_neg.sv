`timescale 1ns/1ps
// Length/Offset widening RTL mirror: OCL.C/OCS.C's new 32-byte
// alignment gate. An object deliberately based at a non-32-byte
// -aligned (but still 4-byte-aligned) address, accessed via OCS.C at
// offset 0, must hard-trap with the new VEDA_CAUSE_ALIGNMENT_VIOLATION
// (cause=0x08) -- confirms the new gate fires with the RIGHT cause, not
// some other check. See veda_smoke_oclc_alignment_neg.S.
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

    repeat (60) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("trap handled: x21=0x%0h (must be 0x600D -- correct mcause=0x18/mtval=0x08)", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (an OCS.C through a target capability based at a non-32-byte-aligned address correctly hard-traps VEDA_CAUSE_ALIGNMENT_VIOLATION -- proves the new alignment gate fires with the right cause, not some other check)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
