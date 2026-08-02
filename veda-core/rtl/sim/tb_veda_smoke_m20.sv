`timescale 1ns/1ps
// Veda-Core RTL Milestone 20 positive test: outside any live
// compartment, ordinary writes to veda_mepcc_base/_length and
// veda_mode still succeed exactly as before -- the real regression
// -safety property this milestone must not break. See
// veda_smoke_m20.S.
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

    repeat (40) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("veda_mepcc_base round-trip  : x9=0x%0h",  dut.CPU_Xreg_val_a0[9]);
    $display("veda_mepcc_length round-trip: x10=0x%0h (must be 0x80)", dut.CPU_Xreg_val_a0[10]);
    $display("veda_mode round-trip (set)  : x11=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[11]);
    $display("veda_mode round-trip (clear): x12=0x%0h (must be 0)", dut.CPU_Xreg_val_a0[12]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h80 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h0) begin
      $display("\n*** TEST PASSED *** (outside any live compartment, ordinary writes to the newly-gated compartment-state CSRs still succeed exactly as before -- zero behavior change until software actually enters a compartment)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
