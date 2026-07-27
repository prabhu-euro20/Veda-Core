`timescale 1ns/1ps
// Veda-Core RTL Milestone 15: ODT full-Object_ID verification (real bug
// fix, ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 1). Positive control:
// proves the fix doesn't reject anything it shouldn't -- two different,
// non-aliasing objects work correctly side by side, and a legitimate
// same-ID re-populate still works too. See veda_smoke_m15.S for the full
// step-by-step proof structure.
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

    $display("Object_ID=30 (obj30_a) : x8=0x%0h  (must be 0x1111111111111111)", dut.CPU_Xreg_val_a0[8]);
    $display("Object_ID=31 (obj31)   : x9=0x%0h  (must be 0x2222222222222222)", dut.CPU_Xreg_val_a0[9]);
    $display("Object_ID=30 re-populate (obj30_b): x10=0x%0h (must be 0x3333333333333333)", dut.CPU_Xreg_val_a0[10]);

    if (dut.CPU_Xreg_val_a0[8]  == 64'h1111111111111111 &&
        dut.CPU_Xreg_val_a0[9]  == 64'h2222222222222222 &&
        dut.CPU_Xreg_val_a0[10] == 64'h3333333333333333) begin
      $display("\n*** TEST PASSED *** (two non-aliasing Object_IDs resolve to their own real objects independently, and a legitimate same-ID re-populate is still honored -- the full-Object_ID check added this milestone rejects only real aliasing collisions, nothing else)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
