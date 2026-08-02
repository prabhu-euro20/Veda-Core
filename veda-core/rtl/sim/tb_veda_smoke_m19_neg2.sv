`timescale 1ns/1ps
// Veda-Core RTL Milestone 19 negative test 2: the second real gap this
// milestone closes -- code entered via a successful OCInvoke can
// otherwise still issue an ordinary sd/ld to read/write memory
// directly. WITHOUT veda_purecap ever being set, an ordinary ld fetched
// from inside a live, correctly-bounded compartment (the fetch itself
// is genuinely in-bounds -- structurally distinct from Milestone 14's
// own PCC fetch-violation) still hard-traps, same cause/cap_idx/mtval
// as negative test 1 (0x227) -- both trigger conditions share the
// identical real enforcement point. See veda_smoke_m19_neg2.S.
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

    $display("handler reached      : x21=0x%0h (must be 0x600D -- correct mcause=0x18/mtval=0x227, purecap still 0)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET   : x22=0x%0h (must be 0x900D -- MRET's own real PC redirect worked)", dut.CPU_Xreg_val_a0[22]);
    $display("blocked-load dest reg: x9=0x%0h  (must still be 0xDEAD -- the write was genuinely suppressed)", dut.CPU_Xreg_val_a0[9]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D &&
        dut.CPU_Xreg_val_a0[9]  == 64'hDEAD) begin
      $display("\n*** TEST PASSED *** (an ordinary ld fetched from inside a live, correctly-bounded OCInvoke compartment genuinely hard-traps -- same mcause=0x18/mtval=0x227 as the global-purecap trigger -- even though veda_purecap itself was never set and the fetch of the blocked instruction was genuinely in-bounds (not a Milestone 14 PCC fetch-violation). The second real gap this milestone closes: code inside a compartment can no longer bypass isolation via ordinary loads/stores)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
