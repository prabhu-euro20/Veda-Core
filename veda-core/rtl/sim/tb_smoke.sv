`timescale 1ns/1ps
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

    repeat (130) begin
      @(posedge clk);
      #1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h passed=%0b | x1=%0d x2=%0d x3=%0d x4=%0d x5=%0d x6=%0d x7=%0d x8=%0d x9=%0d x10=%0d x11=%0d x12=%0d x13=%0d x14=%0d x15=%0d x16=%0d x17=%0d x18=%0d x19=%0d x20=%0d x21=%0d x22=%0d x23=%0d x24=%0d x25=%0d x26=%0d x27=%0d x28=%0d x29=%0d x30=%0d x31=%0d",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0, passed,
                $signed(dut.CPU_Xreg_val_a0[1]),  $signed(dut.CPU_Xreg_val_a0[2]),  $signed(dut.CPU_Xreg_val_a0[3]),
                $signed(dut.CPU_Xreg_val_a0[4]),  $signed(dut.CPU_Xreg_val_a0[5]),  $signed(dut.CPU_Xreg_val_a0[6]),
                $signed(dut.CPU_Xreg_val_a0[7]),  $signed(dut.CPU_Xreg_val_a0[8]),  $signed(dut.CPU_Xreg_val_a0[9]),
                $signed(dut.CPU_Xreg_val_a0[10]), $signed(dut.CPU_Xreg_val_a0[11]), $signed(dut.CPU_Xreg_val_a0[12]),
                $signed(dut.CPU_Xreg_val_a0[13]), $signed(dut.CPU_Xreg_val_a0[14]), $signed(dut.CPU_Xreg_val_a0[15]),
                $signed(dut.CPU_Xreg_val_a0[16]), $signed(dut.CPU_Xreg_val_a0[17]), $signed(dut.CPU_Xreg_val_a0[18]),
                $signed(dut.CPU_Xreg_val_a0[19]), $signed(dut.CPU_Xreg_val_a0[20]), $signed(dut.CPU_Xreg_val_a0[21]),
                $signed(dut.CPU_Xreg_val_a0[22]), $signed(dut.CPU_Xreg_val_a0[23]), $signed(dut.CPU_Xreg_val_a0[24]),
                $signed(dut.CPU_Xreg_val_a0[25]), $signed(dut.CPU_Xreg_val_a0[26]), $signed(dut.CPU_Xreg_val_a0[27]),
                $signed(dut.CPU_Xreg_val_a0[28]), $signed(dut.CPU_Xreg_val_a0[29]), $signed(dut.CPU_Xreg_val_a0[30]),
                $signed(dut.CPU_Xreg_val_a0[31]));
      cyc_cnt = cyc_cnt + 1;
    end

    if (passed) $display("\n*** TEST PASSED ***");
    else        $display("\n*** TEST FAILED ***");

    $finish;
  end
endmodule
