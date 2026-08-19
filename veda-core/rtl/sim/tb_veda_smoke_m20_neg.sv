`timescale 1ns/1ps
// Veda-Core RTL Milestone 20 negative test 1: the real, empirically
// -confirmed compartment-state CSR self-escape. From inside a live
// OCInvoke compartment, a plain CSRRW to veda_pcc_length (0x7c1) must
// hard-trap (mcause=0x02, standard Illegal_Instruction) instead of
// silently undoing the compartment's own bounding. See
// veda_smoke_m20_neg.S.
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

    $display("handler reached   : x21=0x%0h (must be 0x600D -- mcause=0x02, veda_pcc_length back to 0xFFFFF)", dut.CPU_Xreg_val_a0[21]);
    $display("resumed after MRET: x22=0x%0h (must be 0x900D)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h900D) begin
      $display("\n*** TEST PASSED *** (from inside a live OCInvoke compartment, an ordinary CSRRW to veda_pcc_length genuinely hard-traps -- mcause=0x02, standard RISC-V Illegal_Instruction, not Veda-Core's own 0x18 -- and the CSR's own value is provably unaffected: it reads back exactly 0xFFFFF/unbounded afterward, neither the original narrow Length nor the attacker's own write value. The real, empirically-confirmed compartment-state CSR self-escape is closed)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
