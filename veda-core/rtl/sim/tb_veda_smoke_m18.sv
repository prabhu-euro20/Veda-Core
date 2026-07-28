`timescale 1ns/1ps
// Veda-Core RTL Milestone 18 smoke test: VEDA_ODT_POPULATE_FAST +
// veda_attr CSR (0x7C4) positive control. Sets veda_attr, mints a fresh
// object via the new instruction (Base direct in rs2, Length/Perms from
// the CSR), binds it, and proves both an ordinary-position and a
// boundary-position (offset+width == Length) write-then-read round trip
// land correctly. See veda_smoke_m18.S.
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

    $display("x21(veda_attr readback)=0x%0h x6(ocl old)=0x%0h x9(ocl boundary)=0x%0h",
              dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[6], dut.CPU_Xreg_val_a0[9]);
    $display("odt_mem[Object_ID=6]: base=0x%0h length=0x%0h perms=0x%0h valid=%0b",
              {dut.odt_mem[32'h9000_0000+16*6+3], dut.odt_mem[32'h9000_0000+16*6+2],
               dut.odt_mem[32'h9000_0000+16*6+1], dut.odt_mem[32'h9000_0000+16*6+0]},
              {dut.odt_mem[32'h9000_0000+16*6+5], dut.odt_mem[32'h9000_0000+16*6+4]},
              {dut.odt_mem[32'h9000_0000+16*6+7], dut.odt_mem[32'h9000_0000+16*6+6]},
              dut.odt_mem[32'h9000_0000+16*6+9][0]);

    if (dut.CPU_Xreg_val_a0[21] == 64'h0040100c &&
        dut.CPU_Xreg_val_a0[6] == 64'h1234567890ABCDEF &&
        dut.CPU_Xreg_val_a0[9] == 64'h66) begin
      $display("\n*** TEST PASSED *** (VEDA_ODT_POPULATE_FAST + veda_attr correct: CSR readback exact, Base(direct)/Perms(from CSR) round trip correct, Length(from CSR) boundary access correct)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
