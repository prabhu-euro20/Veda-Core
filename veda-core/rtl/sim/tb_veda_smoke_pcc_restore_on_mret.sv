`timescale 1ns/1ps
// RTL M21-restore mirror: automatic PCC restore-on-mret. Three real,
// independently-checkable properties, mirroring the Sail side's own
// vc_pcc_auto_restore_on_mret.S exactly: (1) positive automatic restore +
// real enforcement (x21), (2) explicit override still honored (x25),
// (3) nested-trap staleness + repeatability (x26). x22 must stay 0 (never
// hit the shared fail: label).
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

    repeat (600) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("Phase 1 (positive restore+enforcement): x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("Phase 2 (explicit override honored)    : x25=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[25]);
    $display("Phase 3 (nested-trap staleness+repeat)  : x26=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[26]);
    $display("fail sentinel (must stay 0, not 0xDEAD) : x22=0x%0h", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[25] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] != 64'hDEAD) begin
      $display("\n*** TEST PASSED *** (RTL M21-restore mirror: mret automatically restores veda_pcc_base/_length from veda_mepcc_base/_length whenever a compartment was genuinely narrowed at trap time, with real fetch-bounds enforcement after resume; an explicit software clear of veda_mepcc_length before mret is still honored, resuming unbounded instead; a second, unrelated trap firing inside a handler before its own mret does not corrupt the first trap's pending restore, and the restore is correctly self-consuming)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
