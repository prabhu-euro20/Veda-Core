`timescale 1ns/1ps
// Veda-Core RTL Milestone 20 negative test 2: the same real
// self-escape gate applied to veda_mode (0x7c5) specifically -- the
// one gated CSR whose suppression needed an explicit, hand-written
// guard rather than falling out for free from the pre-existing "any
// trap resets PCC" priority. See veda_smoke_m20_neg2.S.
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

    $display("handler reached   : x21=0x%0h (must be 0x600D -- mcause=0x02, veda_mode still 0)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET: x22=0x%0h (must be 0x900D)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D) begin
      $display("\n*** TEST PASSED *** (from inside a live OCInvoke compartment, an ordinary CSRRW to veda_mode genuinely hard-traps -- mcause=0x02 -- and veda_mode itself reads back 0 afterward, never written at all. Confirms the one gated CSR whose suppression required an explicit, hand-written guard, rather than the pre-existing PCC-reset priority every other gated CSR here already had for free, is genuinely correct)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
