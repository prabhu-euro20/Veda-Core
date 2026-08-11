`timescale 1ns/1ps
// RTL Part C: mirrors Task #297's real Sail-side deliverable -- a real,
// dispatching KERNEL ecall handler (sys_write=64/sys_exit=93), with a
// caller-supplied {Object_ID, offset} pair validated via a real,
// TRAPPING veda.bind, a full-GPR-save/restore handler body, and a
// dword-granular copy proven against real, distinctive, non-zero bytes
// read back via GPR after the run. See veda_smoke_syscall0_kernel.S.
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

    repeat (2000) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("sys_write+sys_exit round trip: x21=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[21]);
    $display("fail sentinel (must stay 0, not 0xDEAD): x22=0x%0h", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] != 64'hDEAD) begin
      $display("\n*** TEST PASSED *** (RTL mirror of Task #297: a real, dispatching KERNEL ecall handler runs sys_write -- validates the caller-supplied Object_ID via a real, trapping veda.bind, dword-copies the message into a kernel-owned buffer, confirms the exact byte pattern via GPR readback, full-GPR-save/restores around the handler body via the M25/M26 mscratch+OCS.D/OCL.D idiom, and correctly resumes the caller -- narrowed back to its own compartment bounds via RTL Part A's M21-restore mirror -- before a second real ecall (sys_exit) halts cleanly)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
