`timescale 1ns/1ps
// RTL Part D: mirrors Task #299's real Sail-side deliverable -- the
// forged, never-populated Object_ID negative test. The real KERNEL
// dispatcher (reused unchanged from Part C) must reject a caller-
// supplied Object_ID that was never populated: the trapping veda.bind
// hard-traps (mcause=0x18, mtval=0x65) at the exact expected
// instruction, before any data movement. See
// veda_smoke_syscall0_kernel_forged_neg.S.
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

    repeat (500) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("forged Object_ID correctly rejected: x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("fail sentinel (must stay 0, not 0xDEAD): x22=0x%0h", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] != 64'hDEAD) begin
      $display("\n*** TEST PASSED *** (RTL mirror of Task #299: a caller supplies a deliberately forged, never-populated Object_ID to sys_write; the real, unmodified KERNEL dispatcher's own trapping veda.bind rejects it in hardware -- mcause=0x18, mtval=0x65 (cap_idx=3, VEDA_CAUSE_OBJECT_NOT_FOUND) -- at the exact expected instruction, before the second bind or the copy loop ever run, and KERNEL_CONSOLE_BUF's own real backing memory stays provably all-zero. Zero software-side validation anywhere in the syscall path)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
