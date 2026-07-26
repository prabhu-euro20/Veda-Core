`timescale 1ns/1ps
// Veda-Core RTL Milestone 4 smoke test: the full privileged lifecycle --
// ODT-Populate a fresh Object_ID, Bind/use it (OCS.D/OCL.D round-trip,
// CGetBase confirming the real populated fields), ODT-Destroy it, then
// two real negative checks that only make sense once Destroy is real:
// a post-destroy rebind against the same Object_ID (Tag must read 0)
// and a stale-generation re-check through the capability bound BEFORE
// the destroy (must be rejected, x11's sentinel must survive).
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

    repeat (30) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x6(ocl old)=0x%0h x7(cgetbase)=0x%0h x10(c1 tag)=%0b x11(stale-ocl sentinel)=0x%0h",
              dut.CPU_Xreg_val_a0[6], dut.CPU_Xreg_val_a0[7],
              dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("odt_mem[Object_ID=3]: base=0x%0h valid=%0b gen=%0d",
              {dut.odt_mem[32'h9000_0000+16*3+3], dut.odt_mem[32'h9000_0000+16*3+2],
               dut.odt_mem[32'h9000_0000+16*3+1], dut.odt_mem[32'h9000_0000+16*3+0]},
              dut.odt_mem[32'h9000_0000+16*3+9][0], dut.odt_mem[32'h9000_0000+16*3+8]);

    if (dut.CPU_Xreg_val_a0[6] == 64'h1234567890ABCDEF &&
        dut.CPU_Xreg_val_a0[7] == 64'h80010200 &&
        dut.CPU_Xreg_val_a0[10] == 64'h0 &&
        dut.CPU_Xreg_val_a0[11] == 64'hDEAD) begin
      $display("\n*** TEST PASSED *** (ODT-Populate/Bind/use/Destroy lifecycle correct: fresh mint, real round-trip, post-destroy rebind Tag=0, stale-generation OCL rejected)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
