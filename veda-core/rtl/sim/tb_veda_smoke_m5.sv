`timescale 1ns/1ps
// Veda-Core RTL Milestone 5: closes the real test-coverage gap left open
// since Milestone 2 -- NMC_ADD.W and the 8 of 9 Veda-Atomic ops never
// independently tested (only AMOXOR was, in M2). All of this RTL already
// existed (same ALU mux, same decode, same write-back path) -- this is
// pure verification, not new hardware. Also reconfirms NMC_ADD.W's own
// permission-violation signal ($veda_nmc_add_w_violation), separate from
// NMC_ADD.D's (only D's was checked in M2's own negative test).
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

    repeat (85) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("NMC_ADD.W: x10(old,sign-ext)=0x%0h x11(readback,upper-untouched)=0x%0h",
              dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("SWAP : old=0x%0h new=0x%0h", dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[20]);
    $display("ADD  : old=0x%0h new=0x%0h", dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[21]);
    $display("AND  : old=0x%0h new=0x%0h", dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[22]);
    $display("OR   : old=0x%0h new=0x%0h", dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[23]);
    $display("MIN  : old=0x%0h new=0x%0h", dut.CPU_Xreg_val_a0[16], dut.CPU_Xreg_val_a0[24]);
    $display("MAX  : old=0x%0h new=0x%0h", dut.CPU_Xreg_val_a0[17], dut.CPU_Xreg_val_a0[25]);
    $display("MINU : old=0x%0h new=0x%0h", dut.CPU_Xreg_val_a0[18], dut.CPU_Xreg_val_a0[26]);
    $display("MAXU : old=0x%0h new=0x%0h", dut.CPU_Xreg_val_a0[19], dut.CPU_Xreg_val_a0[27]);
    $display("NMC_ADD.W negative (no Permit_NMC_Compute): x28=0x%0h (must stay 0x5555)", dut.CPU_Xreg_val_a0[28]);

    if (dut.CPU_Xreg_val_a0[10] == 64'hFFFFFFFF80000000 && dut.CPU_Xreg_val_a0[11] == 64'hCAFEBABE80000020 &&
        dut.CPU_Xreg_val_a0[12] == 64'h1111 && dut.CPU_Xreg_val_a0[20] == 64'h2222 &&
        dut.CPU_Xreg_val_a0[13] == 64'h5    && dut.CPU_Xreg_val_a0[21] == 64'hF    &&
        dut.CPU_Xreg_val_a0[14] == 64'hFF   && dut.CPU_Xreg_val_a0[22] == 64'hF    &&
        dut.CPU_Xreg_val_a0[15] == 64'hF0   && dut.CPU_Xreg_val_a0[23] == 64'hFF   &&
        dut.CPU_Xreg_val_a0[16] == 64'hFFFFFFFFFFFFFFFF && dut.CPU_Xreg_val_a0[24] == 64'hFFFFFFFFFFFFFFFF &&
        dut.CPU_Xreg_val_a0[17] == 64'hFFFFFFFFFFFFFFFF && dut.CPU_Xreg_val_a0[25] == 64'h1 &&
        dut.CPU_Xreg_val_a0[18] == 64'hFFFFFFFFFFFFFFFF && dut.CPU_Xreg_val_a0[26] == 64'h1 &&
        dut.CPU_Xreg_val_a0[19] == 64'hFFFFFFFFFFFFFFFF && dut.CPU_Xreg_val_a0[27] == 64'hFFFFFFFFFFFFFFFF &&
        dut.CPU_Xreg_val_a0[28] == 64'h5555) begin
      $display("\n*** TEST PASSED *** (NMC_ADD.W sign-extension + partial-word write correct; all 8 remaining Veda-Atomic ops correct, incl. signed-vs-unsigned MIN/MAX/MINU/MAXU distinction; NMC_ADD.W's own permission gate correctly blocks a no-NMC_Compute object)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
