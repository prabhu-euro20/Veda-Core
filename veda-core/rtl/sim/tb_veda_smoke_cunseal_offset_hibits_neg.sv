`timescale 1ns/1ps
// Adversarial-review Finding #2: CUnseal's own widened-otype compare
// site ($veda_cunseal_authorized) is independently tested here (a
// separate RTL expression from CSeal's own precondition). An attacker
// authority with Offset=0x10005 (same low 16 bits as the real
// otype=5, but nonzero bits[19:16]) must fail to unseal a capability
// whose real otype is 5 (Tag cleared on the destination), while the
// genuine, exact-match authority (Offset=5) unsealing the SAME sealed
// capability into a different destination register must succeed. See
// veda_smoke_cunseal_offset_hibits_neg.S.
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

    repeat (90) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("OCA sanity (c1 real authority)   : x10=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[10]);
    $display("CSeal mint (c3.otype=5)          : x11=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[11]);
    $display("OCA sanity (c5 attacker in-range): x12=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[12]);
    $display("CUnseal(attacker, Offset=0x10005): x13=0x%0h (must be 0 -- forgery REJECTED)", dut.CPU_Xreg_val_a0[13]);
    $display("CUnseal(real, Offset=5)          : x14=0x%0h (must be 1 -- genuine unseal succeeds)", dut.CPU_Xreg_val_a0[14]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h1 &&
        dut.CPU_Xreg_val_a0[13] == 64'h0 &&
        dut.CPU_Xreg_val_a0[14] == 64'h1) begin
      $display("\n*** TEST PASSED *** (CUnseal's own independent widened-otype compare site correctly zero-extends cs1.otype to 20 bits and rejects an attacker authority whose Offset=0x10005 aliases the real otype=5 in its low 16 bits but has nonzero bits[19:16], while the genuine exact-match authority still successfully unseals the same capability)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
