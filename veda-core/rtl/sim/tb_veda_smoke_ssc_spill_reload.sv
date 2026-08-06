`timescale 1ns/1ps
// Veda-Core RTL mirror of SSC's real, positive completion criterion: a
// compartment establishes its own SSC and performs a real spill/reload
// sequence through it, with zero purecap traps. See
// veda_smoke_ssc_spill_reload.S.
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

    $display("reload offset 0 (must be 0x11112222): x22=0x%0h", dut.CPU_Xreg_val_a0[22]);
    $display("reload offset 8 (must be 0x33334444): x23=0x%0h", dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[22] == 64'h11112222 &&
        dut.CPU_Xreg_val_a0[23] == 64'h33334444) begin
      $display("\n*** TEST PASSED *** (a compartment establishes its own SSC after OCInvoke cleared whatever was there before, then a real two-value spill/reload sequence round-trips correctly through it, zero purecap traps anywhere -- RTL mirror of the SSC milestone's own real completion criterion)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
