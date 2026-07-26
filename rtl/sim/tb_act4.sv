`timescale 1ns/1ps
// ACT4 conformance testbench: loads a real ACT4 ELF's memory image (via
// the +elf_hex plusarg, read inside the DUT itself -- see rv64i_core.tlv's
// elfmem initial block) and polls the `tohost` word (address supplied via
// +tohost_addr, resolved per-ELF since it shifts with each test's own
// data/signature-table size -- confirmed empirically, not assumed).
//
// Real HTIF convention used by this ACT4 config's rvmodel_macros.h (confirmed
// by reading the macro in full, not just RVMODEL_HALT_PASS/FAIL in isolation):
// `tohost` is a 64-bit word shared between two distinct producers --
//   - RVMODEL_HALT_PASS/FAIL: writes low word = 1 (pass) or 3 (fail), and
//     ALWAYS writes high word = 0, then spins rewriting the same value.
//   - RVMODEL_IO_WRITE_STR (diagnostic string printing on the failure-report
//     path): writes low word = one ASCII character, high word = 0x01010000
//     (HTIF device=1/cmd=1), one character at a time.
// A naive "low word nonzero => terminal" check (as this testbench originally
// had) misfires on the first character of a diagnostic string -- confirmed
// empirically: tohost=0x0000000a matches '\n', the first byte of failstr
// ("\nRVCP-SUMMARY: TEST FAILED..."). Checking "high word == 0" alone is
// ALSO insufficient: the low and high words are written by two separate
// store instructions two cycles apart (lo=char first, hi=0x01010000
// second), so a single-cycle poll can land in the transient window where
// lo is already the character but hi hasn't been overwritten from 0 yet --
// confirmed empirically via a targeted store-address trace (I-add-00: lo
// written at cyc=4336, hi written at cyc=4338; polling at cyc=4337 lands
// in between). RVMODEL_HALT_PASS/FAIL, by contrast, spin forever rewriting
// the SAME lo/hi values (an infinite loop), while character printing moves
// on to a different address/pc within a couple cycles. So the real
// distinguishing test is stability, not just an instantaneous snapshot:
// once a lo!=0/hi==0 candidate is seen, recheck a few cycles later and only
// declare terminal if it's still unchanged.
// A generous cycle-bound backstop reports TIMEOUT (distinct from FAIL,
// since a hang is diagnostically different from a wrong-answer) per the
// approved plan's Milestone C design.
module tb;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  logic [31:0] tohost_addr;
  logic [31:0] tohost_lo;
  logic [31:0] tohost_hi;
  integer      i;

  function automatic [31:0] read_lo();
    read_lo = {dut.elfmem[tohost_addr+3], dut.elfmem[tohost_addr+2],
               dut.elfmem[tohost_addr+1], dut.elfmem[tohost_addr+0]};
  endfunction

  function automatic [31:0] read_hi();
    read_hi = {dut.elfmem[tohost_addr+7], dut.elfmem[tohost_addr+6],
               dut.elfmem[tohost_addr+5], dut.elfmem[tohost_addr+4]};
  endfunction

  initial begin
    if (!$value$plusargs("tohost_addr=%h", tohost_addr)) begin
      $display("ERROR: +tohost_addr=<hex> plusarg required");
      $finish;
    end

    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    for (i = 0; i < 200000; i = i + 1) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
      tohost_lo = read_lo();
      tohost_hi = read_hi();
      if (tohost_lo != 32'b0 && tohost_hi == 32'b0) begin
        // Candidate halt write -- confirm it's a genuine spin (stable),
        // not a transient mid-sequence character-print state.
        repeat (4) @(posedge clk);
        #1;
        if (read_lo() == tohost_lo && read_hi() == 32'b0) begin
          if (tohost_lo == 32'd1) $display("RESULT: PASS (cyc=%0d, tohost=0x%08h)", cyc_cnt, tohost_lo);
          else                    $display("RESULT: FAIL (cyc=%0d, tohost=0x%08h)", cyc_cnt, tohost_lo);
          $finish;
        end
        cyc_cnt = cyc_cnt + 4;
      end
    end

    $display("RESULT: TIMEOUT (cyc=%0d, tohost never reached a halt code)", cyc_cnt);
    $finish;
  end
endmodule
