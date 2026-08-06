`timescale 1ns/1ps
// Veda-Core RTL mirror of SSC's cross-thread isolation test: THREAD_A
// binds a real object into SSC on its own first entry; THREAD_B, on its
// own first entry (after crossing back through the switcher's own
// OCRETURN at least once), reads SSC back and asserts it is genuinely
// untagged. See veda_smoke_ssc_cross_thread.S.
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

    repeat (700) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("THREAD_A counter (must be 2): x20=%0d", dut.CPU_Xreg_val_a0[20]);
    $display("THREAD_B counter (must be 2): x21=%0d", dut.CPU_Xreg_val_a0[21]);
    $display("THREAD_A bounds fidelity (must be 1): x22=%0d", dut.CPU_Xreg_val_a0[22]);
    $display("THREAD_B bounds fidelity (must be 1): x26=%0d", dut.CPU_Xreg_val_a0[26]);
    $display("TSC round-trip fidelity (must be 1): x9=%0d", dut.CPU_Xreg_val_a0[9]);
    $display("SSC cross-thread isolation (must be 0): x19=%0d", dut.CPU_Xreg_val_a0[19]);
    $display("overall sentinel (must be 0x600D): x27=0x%0h", dut.CPU_Xreg_val_a0[27]);

    if (dut.CPU_Xreg_val_a0[27] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (THREAD_A binds a real object into SSC on its own first entry; THREAD_B, after crossing back through the switcher's own OCRETURN, reads SSC back genuinely untagged -- THREAD_A's SSC-bound data never leaked across the yield/resume cycle, empirically re-verified in RTL, not just closed by construction)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
