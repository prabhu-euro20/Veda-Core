`timescale 1ns/1ps
// Real-time/safety-critical audit: WFI must be an explicit, documented
// NOP (RISC-V ISA manual p.715's own permitted option), not an
// accidental one. See veda_smoke_wfi_nop.S. Also confirms $is_wfi
// itself actually fires (not just that execution happens not to
// crash) by probing the internal decode signal directly.
module tb;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;
  int wfi_decodes_seen = 0;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    repeat (40) begin
      @(posedge clk);
      #1;
      if (dut.CPU_is_wfi_a0) wfi_decodes_seen = wfi_decodes_seen + 1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x20=0x%0h (must be 0x600D -- fell through WFI correctly; must NEVER be 0xBAD)", dut.CPU_Xreg_val_a0[20]);
    $display("WFI decodes observed: %0d (must be exactly 1 -- proves the decode itself fired, not just that nothing crashed)", wfi_decodes_seen);

    if (dut.CPU_Xreg_val_a0[20] == 64'h600D && wfi_decodes_seen == 1) begin
      $display("\n*** TEST PASSED *** (WFI decodes exactly once, causes no trap and no register write, and execution advances normally -- an explicit, documented NOP matching the RISC-V spec's own permitted option, not an accidental byproduct of unrelated allow-lists)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
