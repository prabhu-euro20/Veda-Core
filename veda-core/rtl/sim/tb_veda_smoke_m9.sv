`timescale 1ns/1ps
// Veda-Core RTL Milestone 9: real Zicsr-lite CSR state (mtvec/mepc/mcause/
// mtval) + a real trap-and-resume cycle -- CSRRW/CSRRS/MRET all use their
// genuine, standard RISC-V encodings (confirmed via the assembler's own
// native mnemonics in veda_smoke_m9.S, no .word hand-encoding needed for
// any of the three, unlike every Veda-Core custom instruction elsewhere).
// Proves: CSRRS old-value-return + OR-write semantics, CSRRS-with-rs1=x0
// not writing, a real "use"-family violation (OCL/OCS's Tag check)
// genuinely redirecting PC to mtvec instead of silently continuing past
// the blocked access (every prior RTL milestone's own honest floor),
// mcause=0x18/mtval=cap_idx@cause landing correctly in CSR state, mepc
// pointing at the exact faulting instruction, and MRET's own real PC
// redirect closing the full cycle.
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

    $display("handler reached : x21=0x%0h (must be 0x600D -- correct mcause/mtval/mepc)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET: x22=0x%0h (must be 0x900D -- MRET's own real PC redirect worked)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D) begin
      $display("\n*** TEST PASSED *** (CSRRW/CSRRS/MRET real, standard RISC-V encoding all decode and execute correctly; a real Veda-Core 'use'-family violation genuinely traps -- PC redirects to mtvec instead of silently continuing -- with correct mcause=0x18/mtval=cap_idx@cause/mepc; MRET closes the full trap-and-resume cycle)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
