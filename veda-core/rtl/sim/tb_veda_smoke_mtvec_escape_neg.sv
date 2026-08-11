`timescale 1ns/1ps
// RTL Part B (M27-mtvec-gate mirror): from inside a live OCInvoke
// compartment, an ordinary CSRRW to mtvec must hard-trap (mcause=0x02)
// instead of silently hijacking the trap vector. See
// veda_smoke_mtvec_escape_neg.S.
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

    repeat (110) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("handler reached   : x21=0x%0h (must be 0x600D -- mcause=0x02, mtvec still the real handler)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET: x22=0x%0h (must be 0x900D)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D) begin
      $display("\n*** TEST PASSED *** (from inside a live OCInvoke compartment, an ordinary CSRRW to mtvec genuinely hard-traps -- mcause=0x02 -- and mtvec itself reads back the real, originally-installed handler address afterward, never hijacked, not even partially. Confirms the RTL mirror of M27-mtvec-gate: mtvec has no pre-existing PCC-family trap-reset branch to piggyback on, so its own explicit guard is genuinely load-bearing)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
