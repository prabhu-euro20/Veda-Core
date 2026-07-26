\m4_TLV_version 1d: tl-x.org
\SV
   // ═══════════════════════════════════════════════════════════════════
   //  RVA23 Base Core — RV64I Single-Cycle CPU (Phase 1, Milestone B)
   //  Clean-slate build, not derived from warp-v.tlv. Structural
   //  conventions (encoder-function idiom, /xreg and /dmem array-of-
   //  registers, PASS/FAIL assertion pattern) follow arm_single_cycle.tlv;
   //  all instruction encodings and datapath logic are RV64I-specific.
   //
   //  All 50 RV64I encodings implemented: the 38 RV32I-equivalent
   //  instructions (incl. FENCE, excl. ECALL/EBREAK, deferred) plus the
   //  12 RV64-only *W encodings.
   //
   //  Waveform signals to watch (add in Makerchip waveform panel):
   //    |cpu @0  $pc, $instr, $opcode, $funct3, $funct7, $reg_write,
   //             $alu_result, $branch_taken, $pc_src, $wr_data,
   //             $is_load, $is_store, $mem_addr
   //    /xreg[1..31] $val   — register file values
   //    /dmem[0..63] $val   — data memory (64 doublewords, byte addr 0-511)
   // ═══════════════════════════════════════════════════════════════════
   m4_makerchip_module

   // ═══════════════════════════════════════════════════════════════════
   //  INSTRUCTION ENCODER — computes real RV64I 32-bit encodings at
   //  elaboration time. Field layouts verified directly against the
   //  RISC-V ISA manual (R/I/S/B/U/J-type formats, base opcode map,
   //  Zaamo-adjacent shift-immediate conventions for RV64).
   //  Store mnemonics follow real assembly operand order: SB(rs2,rs1,imm)
   //  means "store rs2's value to address rs1+imm" (sb rs2, imm(rs1)).
   // ═══════════════════════════════════════════════════════════════════

   // ── R-type (OP, 0x33) ──
   function automatic logic [31:0] ADD(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b000, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SUB(int rd, int rs1, int rs2);
      return {7'b0100000, rs2[4:0], rs1[4:0], 3'b000, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SLL(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b001, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SLT(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b010, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SLTU(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b011, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] XOR(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b100, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SRL(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SRA(int rd, int rs1, int rs2);
      return {7'b0100000, rs2[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] OR(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b110, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] AND(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b111, rd[4:0], 7'b0110011};
   endfunction

   // ── I-type ALU (OP-IMM, 0x13) ──
   function automatic logic [31:0] ADDI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b000, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] SLTI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b010, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] SLTIU(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b011, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] XORI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b100, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] ORI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b110, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] ANDI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b111, rd[4:0], 7'b0010011};
   endfunction
   // RV64 shift-immediates use a 6-bit shamt (instr[25:20]); instr[31:26]
   // discriminates SLLI/SRLI (000000) from SRAI (010000).
   function automatic logic [31:0] SLLI(int rd, int rs1, int shamt6);
      return {6'b000000, shamt6[5:0], rs1[4:0], 3'b001, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] SRLI(int rd, int rs1, int shamt6);
      return {6'b000000, shamt6[5:0], rs1[4:0], 3'b101, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] SRAI(int rd, int rs1, int shamt6);
      return {6'b010000, shamt6[5:0], rs1[4:0], 3'b101, rd[4:0], 7'b0010011};
   endfunction

   // ── Branches (BRANCH, 0x63, B-type) ──
   function automatic logic [31:0] BEQ(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b000, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BNE(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b001, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BLT(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b100, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BGE(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b101, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BLTU(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b110, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BGEU(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b111, imm13[4:1], imm13[11], 7'b1100011};
   endfunction

   // ── Jumps ──
   function automatic logic [31:0] JAL(int rd, int imm21);
      return {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd[4:0], 7'b1101111};
   endfunction
   function automatic logic [31:0] JALR(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b000, rd[4:0], 7'b1100111};
   endfunction

   // ── Upper immediate (U-type) ──
   function automatic logic [31:0] LUI(int rd, int imm20);
      return {imm20[19:0], rd[4:0], 7'b0110111};
   endfunction
   function automatic logic [31:0] AUIPC(int rd, int imm20);
      return {imm20[19:0], rd[4:0], 7'b0010111};
   endfunction

   // ── Loads (LOAD, 0x03, I-type) ──
   function automatic logic [31:0] LB(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b000, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LH(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b001, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LW(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b010, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LD(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b011, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LBU(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b100, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LHU(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b101, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LWU(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b110, rd[4:0], 7'b0000011};
   endfunction

   // ── Stores (STORE, 0x23, S-type) ──
   function automatic logic [31:0] SB(int rs2, int rs1, int imm12);
      return {imm12[11:5], rs2[4:0], rs1[4:0], 3'b000, imm12[4:0], 7'b0100011};
   endfunction
   function automatic logic [31:0] SH(int rs2, int rs1, int imm12);
      return {imm12[11:5], rs2[4:0], rs1[4:0], 3'b001, imm12[4:0], 7'b0100011};
   endfunction
   function automatic logic [31:0] SW(int rs2, int rs1, int imm12);
      return {imm12[11:5], rs2[4:0], rs1[4:0], 3'b010, imm12[4:0], 7'b0100011};
   endfunction
   function automatic logic [31:0] SD(int rs2, int rs1, int imm12);
      return {imm12[11:5], rs2[4:0], rs1[4:0], 3'b011, imm12[4:0], 7'b0100011};
   endfunction

   // ── RV64-only *W word ops (OP-IMM-32=0x1B, OP-32=0x3B) ──
   function automatic logic [31:0] ADDIW(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b000, rd[4:0], 7'b0011011};
   endfunction
   // *W shift-immediates use a 5-bit shamt (instr[24:20]); instr[31:25]
   // discriminates SLLIW/SRLIW (0000000) from SRAIW (0100000).
   function automatic logic [31:0] SLLIW(int rd, int rs1, int shamt5);
      return {7'b0000000, shamt5[4:0], rs1[4:0], 3'b001, rd[4:0], 7'b0011011};
   endfunction
   function automatic logic [31:0] SRLIW(int rd, int rs1, int shamt5);
      return {7'b0000000, shamt5[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0011011};
   endfunction
   function automatic logic [31:0] SRAIW(int rd, int rs1, int shamt5);
      return {7'b0100000, shamt5[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0011011};
   endfunction
   function automatic logic [31:0] ADDW(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b000, rd[4:0], 7'b0111011};
   endfunction
   function automatic logic [31:0] SUBW(int rd, int rs1, int rs2);
      return {7'b0100000, rs2[4:0], rs1[4:0], 3'b000, rd[4:0], 7'b0111011};
   endfunction
   function automatic logic [31:0] SLLW(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b001, rd[4:0], 7'b0111011};
   endfunction
   function automatic logic [31:0] SRLW(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0111011};
   endfunction
   function automatic logic [31:0] SRAW(int rd, int rs1, int rs2);
      return {7'b0100000, rs2[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0111011};
   endfunction

   // ── FENCE (MISC-MEM, 0x0F) — implemented as a functional NOP (see
   // decode below): no operands needed for that treatment, so pred/succ/
   // fm/rd/rs1 are all just zeroed.
   function automatic logic [31:0] FENCE();
      return {4'b0000, 4'b0000, 4'b0000, 5'b00000, 3'b000, 5'b00000, 7'b0001111};
   endfunction

   // ═══════════════════════════════════════════════════════════════════
   //  THE PROGRAM — hand-assembled, touches all 50 RV64I encodings at
   //  least once. Branch/jump offsets are computed as ROM-index
   //  differences times 4 (byte size), so they are correct by
   //  construction rather than hand-computed hex. Expected values for
   //  every instruction are documented inline for the manual trace
   //  review required by Milestone B's done criteria.
   // ═══════════════════════════════════════════════════════════════════
   localparam int ROM_SIZE = 81;
   logic [31:0] ROM [0:ROM_SIZE-1];
   initial begin
      // ── Phase 1: ALU reg-imm + reg-reg (x1=10, x2=20 held constant
      // throughout the whole program for the branch-comparator tests) ──
      ROM[0]  = ADDI(1, 0, 10);      // x1 = 10
      ROM[1]  = ADDI(2, 0, 20);      // x2 = 20
      ROM[2]  = ADD (3, 1, 2);       // x3 = 30
      ROM[3]  = SUB (4, 2, 1);       // x4 = 10
      ROM[4]  = SLTI (7, 1, 100);    // x7 = 1
      ROM[5]  = SLTIU(8, 1, 100);    // x8 = 1
      ROM[6]  = XORI (9, 1, 15);     // x9 = 5
      ROM[7]  = ORI  (10, 1, 5);     // x10 = 15
      ROM[8]  = ANDI (11, 1, 6);     // x11 = 2
      ROM[9]  = SLLI (12, 1, 2);     // x12 = 40
      ROM[10] = SRLI (13, 12, 2);    // x13 = 10
      ROM[11] = SRAI (14, 12, 2);    // x14 = 10
      ROM[12] = SLL  (15, 1, 11);    // x15 = 40 (10 << x11=2)
      ROM[13] = SLT  (16, 1, 2);     // x16 = 1
      ROM[14] = SLTU (17, 1, 2);     // x17 = 1
      ROM[15] = XOR  (18, 1, 2);     // x18 = 30
      ROM[16] = SRL  (19, 12, 11);   // x19 = 10 (40 >> x11=2)
      ROM[17] = SRA  (20, 12, 11);   // x20 = 10
      ROM[18] = OR   (21, 1, 2);     // x21 = 30
      ROM[19] = AND  (22, 1, 2);     // x22 = 0

      // ── Phase 2: branches, each taken, skipping exactly one decoy
      // (offset = +8 bytes = 2 instructions ahead) ──
      ROM[20] = BNE (1, 2, (22-20)*4);  // 10!=20 taken -> ROM[22]
      ROM[21] = ADDI(23, 0, 999);       // decoy, skipped
      ROM[22] = ADDI(23, 0, 1);         // x23 = 1
      ROM[23] = BLT (1, 2, (25-23)*4);  // 10<20 signed taken -> ROM[25]
      ROM[24] = ADDI(24, 0, 999);       // decoy, skipped
      ROM[25] = ADDI(24, 0, 1);         // x24 = 1 (transient, reused later)
      ROM[26] = BGE (2, 1, (28-26)*4);  // 20>=10 signed taken -> ROM[28]
      ROM[27] = ADDI(25, 0, 999);       // decoy, skipped
      ROM[28] = ADDI(25, 0, 1);         // x25 = 1 (transient, reused later)
      ROM[29] = BLTU(1, 2, (31-29)*4);  // 10<20 unsigned taken -> ROM[31]
      ROM[30] = ADDI(26, 0, 999);       // decoy, skipped
      ROM[31] = ADDI(26, 0, 1);         // x26 = 1 (transient, reused later)
      ROM[32] = BGEU(2, 1, (34-32)*4);  // 20>=10 unsigned taken -> ROM[34]
      ROM[33] = ADDI(27, 0, 999);       // decoy, skipped
      ROM[34] = ADDI(27, 0, 1);         // x27 = 1 (transient, reused later)
      ROM[35] = BEQ (1, 1, (37-35)*4);  // 10==10 taken -> ROM[37]
      ROM[36] = ADDI(28, 0, 999);       // decoy, skipped (x28 stays 0)

      // ── Phase 3: JAL (link register + forward jump) ──
      ROM[37] = JAL (29, (39-37)*4);    // x29 = link = addr(37)+4 = 152; -> ROM[39]
      ROM[38] = ADDI(29, 0, 999);       // decoy, skipped (JAL always taken)
      ROM[39] = ADDI(30, 0, 1);         // x30 = 1 (JAL landing confirmed)

      // ── Phase 4: LUI / AUIPC ──
      ROM[40] = AUIPC(7, 0);            // x7 = pc(this instr) = 160 -- verify against trace's own pc column
      ROM[41] = LUI  (8, 1);            // x8 = 0x1000 = 4096
      ROM[42] = ADDI (9, 0, 64);        // x9 = 64 (memory test base address)

      // ── Phase 5: load/store byte-lane round trips ──
      ROM[43] = ADDI(10, 0, -1);        // x10 = -1 (all-ones, 0xFFFF...FFFF)
      ROM[44] = SD  (10, 9, 0);         // mem[64] (doubleword) = all-ones
      ROM[45] = LD  (11, 9, 0);         // x11 = -1 (full doubleword round trip)
      ROM[46] = ADDI(12, 0, 2047);      // x12 = 2047 (0x7FF)
      ROM[47] = SW  (12, 9, 8);         // mem word @72 = 2047
      ROM[48] = LW  (13, 9, 8);         // x13 = 2047 (sign-extend path, positive)
      ROM[49] = LWU (14, 9, 8);         // x14 = 2047 (zero-extend path)
      ROM[50] = ADDI(15, 0, -100);      // x15 = -100 (transient, reused later)
      ROM[51] = SH  (15, 9, 16);        // mem halfword @80 = 0xFF9C
      ROM[52] = LH  (16, 9, 16);        // x16 = -100 (sign-extend path)
      ROM[53] = LHU (17, 9, 16);        // x17 = 65436 (zero-extend path, =0xFF9C unsigned)
      ROM[54] = ADDI(18, 0, -5);        // x18 = -5
      ROM[55] = SB  (18, 9, 24);        // mem byte @88 = 0xFB
      ROM[56] = LB  (19, 9, 24);        // x19 = -5 (sign-extend path)
      ROM[57] = LBU (20, 9, 24);        // x20 = 251 (zero-extend path)
      // Unaligned, same-doubleword-different-byte-lane round trip: byte
      // @91 shares word_idx=11 with byte @88 (written above at offset 0
      // within that word) but at byte_off=3 -- proves byte-lane write
      // masking updates only its own lane without clobbering byte 0.
      ROM[58] = ADDI(21, 0, 42);        // x21 = 42
      ROM[59] = SB  (21, 9, 27);        // mem byte @91 (same word as @88, byte_off 3) = 42
      ROM[60] = LB  (22, 9, 27);        // x22 = 42 (readback of the just-written byte)
      ROM[61] = LB  (31, 9, 24);        // x31 = -5 again (re-check byte @88/byte_off 0 unclobbered)

      // ── Phase 6: RV64-only *W ops. x24 = 0x80000000 (2^31) is the key
      // operand: as a *W (32-bit) op, adding 1 to it overflows the 32-bit
      // sign bit, giving a large NEGATIVE 64-bit result after sign
      // extension -- dramatically different from a plain 64-bit ADD on
      // the same bit pattern, which stays a small POSITIVE number. This
      // is the required spot-check proving *W truncate+sign-extend is
      // real and distinct from the non-W path. ──
      ROM[62] = ADDI(24, 0, 1);
      ROM[63] = SLLI(24, 24, 31);       // x24 = 1<<31 = 0x0000000080000000 (2147483648)
      ROM[64] = ADDI(25, 0, 1);         // x25 = 1
      ROM[65] = ADDW(26, 24, 25);       // x26 = sign-extend32(0x80000001) = -2147483647
      ROM[66] = ADD (27, 24, 25);       // x27 = 0x0000000080000001 = +2147483649 (DIFFERS from x26)
      ROM[67] = SUBW(28, 25, 24);       // x28 = sign-extend32(1-0x80000000 mod 2^32) = -2147483647 (cross-check vs x26)
      ROM[68] = SLLIW(5, 25, 31);       // x5 = sign-extend32(1<<31 truncated) = -2147483648 (INT32_MIN)
      ROM[69] = SRLIW(6, 24, 4);        // x24[31:0]=0x80000000 >>logical 4 = 0x08000000, sign-extend positive = 134217728
      ROM[70] = SRAIW(8, 24, 4);        // x24[31:0]=0x80000000 >>arith 4 = 0xF8000000, sign-extend negative = -134217728
      ROM[71] = ADDIW(9, 24, 1);        // x24[31:0]+1 = 0x80000001, sign-extend = -2147483647 (matches x26/x28)
      ROM[72] = SLLW(10, 1, 25);        // x1=10, shift by x25[4:0]=1 -> 20 (32-bit, sign-extend positive)
      ROM[73] = SRLW(11, 24, 25);       // x24[31:0]=0x80000000 >>logical 1 = 0x40000000, sign-extend positive = 1073741824
      ROM[74] = SRAW(12, 24, 25);       // x24[31:0]=0x80000000 >>arith 1 = 0xC0000000, sign-extend negative = -1073741824

      // ── Phase 7: JALR (rs1=x0, so target = imm12 directly = an
      // absolute address -- valid since the whole program fits well
      // within the +-2047 range of a 12-bit signed immediate) ──
      ROM[75] = JALR(13, 0, 77*4);      // x13 = link = addr(75)+4 = 304; jump to ROM[77]
      ROM[76] = ADDI(14, 0, 999);       // decoy, skipped
      ROM[77] = ADDI(15, 0, 1);         // x15 = 1 (JALR landing confirmed)

      // ── Phase 8: FENCE (functional NOP) ──
      ROM[78] = FENCE();
      ROM[79] = ADDI(16, 0, 1);         // x16 = 1 (confirms execution continued normally past FENCE)

      // ── Final: jump to self, freezes state for the PASS assertion ──
      ROM[80] = JAL(0, 0);
   end

   // ═══════════════════════════════════════════════════════════════════
   //  MILESTONE C: ACT4 ELF-loaded memory. A real ACT4 test ELF places
   //  code, data, signature region, and tohost/fromhost all in one
   //  unified 0x80000000-based address space (confirmed via readelf on
   //  a real generated ELF: .text.init@0x80000000, .data@0x8000c000,
   //  .tohost shifting per-test e.g. 0x80037920/0x80025310/0x8003a6f0
   //  depending on each test's own signature-table size). This is
   //  structurally different from the small, hand-assembled, Harvard-
   //  style ROM[]/dmem[] used above for Milestones A/B, so it is added
   //  as a parallel, independently-selected memory rather than altering
   //  that already-verified path. Sized 512KiB (0x80000), comfortably
   //  covering real ELF footprints observed (~208KiB for I-add-00).
   //  The array's own index range is declared to match real ELF byte
   //  addresses directly (0x80000000..0x8007FFFF) so objcopy -O verilog
   //  output -- confirmed empirically to emit byte-level data with
   //  absolute-address @-annotations -- loads via $readmemh with no
   //  address translation needed in the datapath logic below.
   // ═══════════════════════════════════════════════════════════════════
   localparam bit [31:0] ELFMEM_BASE = 32'h8000_0000;
   localparam bit [31:0] ELFMEM_SIZE = 32'h0008_0000;
   logic [7:0] elfmem [ELFMEM_BASE : ELFMEM_BASE + ELFMEM_SIZE - 1];
   logic act4_mode;
   initial begin
      string elf_hex_path;
      act4_mode = 1'b0;
      if ($value$plusargs("elf_hex=%s", elf_hex_path)) begin
         $readmemh(elf_hex_path, elfmem);
         act4_mode = 1'b1;
      end
   end

\TLV

   |cpu
      @0
         // ─────────────────────────────────────────────────────────
         //  RESET
         // ─────────────────────────────────────────────────────────
         $reset = *reset;

         // ─────────────────────────────────────────────────────────
         //  CYCLE COUNTER
         // ─────────────────────────────────────────────────────────
         $cyc_cnt[31:0] = $reset ? 32'b0 : >>1$cyc_cnt + 32'd1;

         // ─────────────────────────────────────────────────────────
         //  PROGRAM COUNTER — same one-extra-cycle-after-reset handling
         //  as Milestone A / arm_single_cycle.tlv.
         // ─────────────────────────────────────────────────────────
         $reset_just_released = >>1$reset && !$reset;
         $pc[63:0] =
            ($reset || $reset_just_released) ? (act4_mode ? {32'b0, ELFMEM_BASE} : 64'b0) :
            >>1$pc_src                       ? >>1$alt_pc :
                                                >>1$pc + 64'd4;

         // ─────────────────────────────────────────────────────────
         //  INSTRUCTION MEMORY — Milestone A/B hand-assembled ROM[]
         //  (pc[8:2] gives a 7-bit index, 0-127, byte addresses 0-508,
         //  comfortably covering ROM_SIZE=81), or Milestone C's
         //  ELF-loaded elfmem[] (little-endian 4-byte read at $pc, real
         //  absolute address), selected by act4_mode.
         // ─────────────────────────────────────────────────────────
         $instr_rom[31:0]  = ROM[($pc[8:2] >= ROM_SIZE) ? ROM_SIZE - 1 : $pc[8:2]];
         $instr_elf[31:0]  = {elfmem[$pc[31:0]+3], elfmem[$pc[31:0]+2], elfmem[$pc[31:0]+1], elfmem[$pc[31:0]+0]};
         $instr[31:0] = act4_mode ? $instr_elf : $instr_rom;

         // ─────────────────────────────────────────────────────────
         //  DECODE
         // ─────────────────────────────────────────────────────────
         $opcode[6:0] = $instr[6:0];
         $funct3[2:0] = $instr[14:12];
         $funct7[6:0] = $instr[31:25];
         // RV64I's 6-bit-shamt SLLI/SRLI/SRAI use instr[25:20] as a
         // 6-bit shamt (needed to encode shifts up to 63) -- meaning
         // bit 25 is part of the *shamt*, not the opcode discriminator,
         // for these three instructions specifically. The real
         // discriminator is funct6 = instr[31:26] (6 bits: 000000 for
         // SLLI/SRLI, 010000 for SRAI), verified against the RISC-V ISA
         // manual's own RV64I shift-immediate encoding. Using the full
         // 7-bit $funct7 (as the *W shift-immediates correctly do, since
         // those only need a 5-bit shamt and bit 25 is genuinely part of
         // their discriminator) would misdecode any SLLI/SRLI/SRAI whose
         // shift amount is >=32 as an unrecognized instruction, since
         // bit 25 (shamt[5]) would then be 1, not matching funct7==0.
         $funct6[5:0] = $instr[31:26];
         $rd[4:0]     = $instr[11:7];
         $rs1[4:0]    = $instr[19:15];
         $rs2[4:0]    = $instr[24:20];
         $shamt6[5:0] = $instr[25:20];
         $shamt5[4:0] = $instr[24:20];

         $op_is_load   = ($opcode == 7'b0000011);
         $op_is_imm    = ($opcode == 7'b0010011);
         $op_is_auipc  = ($opcode == 7'b0010111);
         $op_is_store  = ($opcode == 7'b0100011);
         $op_is_reg    = ($opcode == 7'b0110011);
         $op_is_lui    = ($opcode == 7'b0110111);
         $op_is_branch = ($opcode == 7'b1100011);
         $op_is_jalr   = ($opcode == 7'b1100111);
         $op_is_jal    = ($opcode == 7'b1101111);
         $op_is_immw   = ($opcode == 7'b0011011);
         $op_is_regw   = ($opcode == 7'b0111011);
         $op_is_fence  = ($opcode == 7'b0001111);

         $is_lb  = $op_is_load && ($funct3 == 3'b000);
         $is_lh  = $op_is_load && ($funct3 == 3'b001);
         $is_lw  = $op_is_load && ($funct3 == 3'b010);
         $is_ld  = $op_is_load && ($funct3 == 3'b011);
         $is_lbu = $op_is_load && ($funct3 == 3'b100);
         $is_lhu = $op_is_load && ($funct3 == 3'b101);
         $is_lwu = $op_is_load && ($funct3 == 3'b110);
         $is_load = $op_is_load;

         $is_addi  = $op_is_imm && ($funct3 == 3'b000);
         $is_slti  = $op_is_imm && ($funct3 == 3'b010);
         $is_sltiu = $op_is_imm && ($funct3 == 3'b011);
         $is_xori  = $op_is_imm && ($funct3 == 3'b100);
         $is_ori   = $op_is_imm && ($funct3 == 3'b110);
         $is_andi  = $op_is_imm && ($funct3 == 3'b111);
         $is_slli  = $op_is_imm && ($funct3 == 3'b001) && ($funct6 == 6'b000000);
         $is_srli  = $op_is_imm && ($funct3 == 3'b101) && ($funct6 == 6'b000000);
         $is_srai  = $op_is_imm && ($funct3 == 3'b101) && ($funct6 == 6'b010000);

         $is_auipc = $op_is_auipc;

         $is_sb = $op_is_store && ($funct3 == 3'b000);
         $is_sh = $op_is_store && ($funct3 == 3'b001);
         $is_sw = $op_is_store && ($funct3 == 3'b010);
         $is_sd = $op_is_store && ($funct3 == 3'b011);
         $is_store = $op_is_store;

         $is_add  = $op_is_reg && ($funct3 == 3'b000) && ($funct7 == 7'b0000000);
         $is_sub  = $op_is_reg && ($funct3 == 3'b000) && ($funct7 == 7'b0100000);
         $is_sll  = $op_is_reg && ($funct3 == 3'b001) && ($funct7 == 7'b0000000);
         $is_slt  = $op_is_reg && ($funct3 == 3'b010) && ($funct7 == 7'b0000000);
         $is_sltu = $op_is_reg && ($funct3 == 3'b011) && ($funct7 == 7'b0000000);
         $is_xor  = $op_is_reg && ($funct3 == 3'b100) && ($funct7 == 7'b0000000);
         $is_srl  = $op_is_reg && ($funct3 == 3'b101) && ($funct7 == 7'b0000000);
         $is_sra  = $op_is_reg && ($funct3 == 3'b101) && ($funct7 == 7'b0100000);
         $is_or   = $op_is_reg && ($funct3 == 3'b110) && ($funct7 == 7'b0000000);
         $is_and  = $op_is_reg && ($funct3 == 3'b111) && ($funct7 == 7'b0000000);

         $is_lui = $op_is_lui;

         $is_beq  = $op_is_branch && ($funct3 == 3'b000);
         $is_bne  = $op_is_branch && ($funct3 == 3'b001);
         $is_blt  = $op_is_branch && ($funct3 == 3'b100);
         $is_bge  = $op_is_branch && ($funct3 == 3'b101);
         $is_bltu = $op_is_branch && ($funct3 == 3'b110);
         $is_bgeu = $op_is_branch && ($funct3 == 3'b111);

         $is_jalr = $op_is_jalr;
         $is_jal  = $op_is_jal;

         $is_addiw = $op_is_immw && ($funct3 == 3'b000);
         $is_slliw = $op_is_immw && ($funct3 == 3'b001) && ($funct7 == 7'b0000000);
         $is_srliw = $op_is_immw && ($funct3 == 3'b101) && ($funct7 == 7'b0000000);
         $is_sraiw = $op_is_immw && ($funct3 == 3'b101) && ($funct7 == 7'b0100000);

         $is_addw = $op_is_regw && ($funct3 == 3'b000) && ($funct7 == 7'b0000000);
         $is_subw = $op_is_regw && ($funct3 == 3'b000) && ($funct7 == 7'b0100000);
         $is_sllw = $op_is_regw && ($funct3 == 3'b001) && ($funct7 == 7'b0000000);
         $is_srlw = $op_is_regw && ($funct3 == 3'b101) && ($funct7 == 7'b0000000);
         $is_sraw = $op_is_regw && ($funct3 == 3'b101) && ($funct7 == 7'b0100000);

         $is_fence = $op_is_fence;
         // Decoded but intentionally unused this phase (FENCE is a
         // functional NOP -- no memory-ordering hazards exist in a
         // single-cycle, single-hart core); silences the SandPiper
         // unused-signal warning per the tool's own suggested idiom.
         `BOGUS_USE($is_fence)

         $is_shift_imm  = $is_slli || $is_srli || $is_srai;
         $is_shift_immw = $is_slliw || $is_srliw || $is_sraiw;
         $is_alu_imm    = $is_addi || $is_slti || $is_sltiu || $is_xori || $is_ori || $is_andi || $is_shift_imm;
         $is_alu_reg    = $is_add || $is_sub || $is_sll || $is_slt || $is_sltu || $is_xor || $is_srl || $is_sra || $is_or || $is_and;
         $is_alu_immw   = $is_addiw || $is_shift_immw;
         $is_alu_regw   = $is_addw || $is_subw || $is_sllw || $is_srlw || $is_sraw;
         $is_w_op       = $is_alu_immw || $is_alu_regw;

         $reg_write = $is_load || $is_alu_imm || $is_alu_reg || $is_lui || $is_auipc ||
                      $is_jal || $is_jalr || $is_alu_immw || $is_alu_regw;

         // ─────────────────────────────────────────────────────────
         //  REGISTER FILE (32 x 64-bit), x0 hardwired to 0
         // ─────────────────────────────────────────────────────────
         /xreg[31:0]
            $wr_en = |cpu>>1$reg_write &&
                     (|cpu>>1$rd == #xreg) &&
                     (#xreg != 5'b0);
            $val[63:0] = (|cpu$reset || |cpu>>1$reset) ? 64'b0 :
                         $wr_en ? |cpu>>1$wr_data :
                                  $RETAIN;
         $rs1_data[63:0] = ($rs1 == 5'd0) ? 64'b0 : /xreg[$rs1]$val;
         $rs2_data[63:0] = ($rs2 == 5'd0) ? 64'b0 : /xreg[$rs2]$val;

         // ─────────────────────────────────────────────────────────
         //  IMMEDIATE GENERATION — bit layouts verified against the
         //  RISC-V ISA manual's own immediate-encoding figures.
         // ─────────────────────────────────────────────────────────
         $imm_i[63:0] = {{52{$instr[31]}}, $instr[31:20]};
         $imm_s[63:0] = {{52{$instr[31]}}, $instr[31:25], $instr[11:7]};
         $imm_b[63:0] = {{51{$instr[31]}}, $instr[31], $instr[7], $instr[30:25], $instr[11:8], 1'b0};
         $imm_u[63:0] = {{32{$instr[31]}}, $instr[31:12], 12'b0};
         $imm_j[63:0] = {{43{$instr[31]}}, $instr[31], $instr[19:12], $instr[20], $instr[30:21], 1'b0};

         // ─────────────────────────────────────────────────────────
         //  ALU — full 64-bit op table plus the 32-bit *W path
         //  (compute on the low 32 bits, then sign-extend to 64).
         // ─────────────────────────────────────────────────────────
         $alu_op2[63:0]     = ($is_alu_reg || $is_alu_regw) ? $rs2_data : $imm_i;
         $shift_amt64[5:0]  = ($is_sll || $is_srl || $is_sra) ? $rs2_data[5:0] : $shamt6;
         $shift_amt32[4:0]  = ($is_sllw || $is_srlw || $is_sraw) ? $rs2_data[4:0] : $shamt5;
         // Signed less-than without a `signed` cast (the `$` sigil in
         // "$signed(...)" collides with TL-Verilog's own signal-name
         // syntax and is misparsed as a signal reference): if the sign
         // bits differ, the operand whose sign bit is set is the smaller
         // one; otherwise a plain unsigned compare already gives the
         // correct signed result.
         $lt_signed         = ($rs1_data[63] != $alu_op2[63]) ? $rs1_data[63] : ($rs1_data < $alu_op2);
         $lt_unsigned       = ($rs1_data < $alu_op2);
         // Arithmetic right shift built from sign-bit replication +
         // logical shift, for the same reason (no `$signed()` cast):
         // concatenate the sign bit ahead of the value, logical-shift
         // the widened value, then take the low bits.
         $sra_ext128[127:0]  = {{64{$rs1_data[63]}}, $rs1_data};
         $alu_sra64[63:0]    = ($sra_ext128 >> $shift_amt64);
         $sraw_ext64[63:0]   = {{32{$rs1_data[31]}}, $rs1_data[31:0]};
         $alu_sraw32_wide[63:0] = ($sraw_ext64 >> $shift_amt32);

         $alu_result64[63:0] =
            ($is_add || $is_addi)   ? ($rs1_data + $alu_op2) :
            $is_sub                  ? ($rs1_data - $rs2_data) :
            ($is_sll || $is_slli)    ? ($rs1_data << $shift_amt64) :
            ($is_slt || $is_slti)    ? {63'b0, $lt_signed} :
            ($is_sltu || $is_sltiu)  ? {63'b0, $lt_unsigned} :
            ($is_xor || $is_xori)    ? ($rs1_data ^ $alu_op2) :
            ($is_srl || $is_srli)    ? ($rs1_data >> $shift_amt64) :
            ($is_sra || $is_srai)    ? $alu_sra64 :
            ($is_or || $is_ori)      ? ($rs1_data | $alu_op2) :
            ($is_and || $is_andi)    ? ($rs1_data & $alu_op2) :
                                        64'b0;

         $alu_result32_raw[31:0] =
            ($is_addw || $is_addiw)              ? ($rs1_data[31:0] + $alu_op2[31:0]) :
            $is_subw                               ? ($rs1_data[31:0] - $rs2_data[31:0]) :
            ($is_sllw || $is_slliw)                ? ($rs1_data[31:0] << $shift_amt32) :
            ($is_srlw || $is_srliw)                ? ($rs1_data[31:0] >> $shift_amt32) :
            ($is_sraw || $is_sraiw)                ? $alu_sraw32_wide[31:0] :
                                                       32'b0;
         $alu_result32[63:0] = {{32{$alu_result32_raw[31]}}, $alu_result32_raw};

         $alu_result[63:0] = $is_w_op ? $alu_result32 : $alu_result64;

         // ─────────────────────────────────────────────────────────
         //  BRANCH / JUMP TARGET
         // ─────────────────────────────────────────────────────────
         // Same sign-bit-based technique as $lt_signed above (no
         // $signed() cast, for the same TL-Verilog $-sigil reason).
         $blt_signed = ($rs1_data[63] != $rs2_data[63]) ? $rs1_data[63] : ($rs1_data < $rs2_data);
         $branch_taken =
            ($is_beq  && ($rs1_data == $rs2_data)) ||
            ($is_bne  && ($rs1_data != $rs2_data)) ||
            ($is_blt  && $blt_signed) ||
            ($is_bge  && !$blt_signed) ||
            ($is_bltu && ($rs1_data < $rs2_data)) ||
            ($is_bgeu && ($rs1_data >= $rs2_data));
         $branch_target[63:0] = $pc + $imm_b;
         $jal_target[63:0]    = $pc + $imm_j;
         $jalr_target[63:0]   = ($rs1_data + $imm_i) & ~64'b1;
         $pc_src = $is_jal || $is_jalr || $branch_taken;
         $alt_pc[63:0] = $is_jal ? $jal_target : $is_jalr ? $jalr_target : $branch_target;

         // ─────────────────────────────────────────────────────────
         //  DATA MEMORY — byte-addressable via a doubleword-granular
         //  /dmem array (64 entries, byte addresses 0-511) with
         //  explicit byte-lane shift/mask/merge logic on top, the
         //  standard technique for byte-addressable memory backed by
         //  word-granular storage.
         // ─────────────────────────────────────────────────────────
         $mem_addr[63:0]     = $rs1_data + ($is_store ? $imm_s : $imm_i);
         $mem_word_idx[5:0]  = $mem_addr[8:3];
         $mem_byte_off[2:0]  = $mem_addr[2:0];
         $mem_shift_bits[5:0] = {$mem_byte_off, 3'b0};

         $mem_cur_word[63:0] = /dmem[$mem_word_idx]$val;
         // Milestone C: an 8-byte little-endian read starting at the
         // exact target address, straight from elfmem -- equivalent in
         // shape to $mem_cur_word already shifted so the target byte
         // sits at bit 0, so it slots into the *existing* width-based
         // extraction/sign-extension logic below completely unchanged.
         $mem_bytes_elf[63:0] =
            {elfmem[$mem_addr[31:0]+7], elfmem[$mem_addr[31:0]+6],
             elfmem[$mem_addr[31:0]+5], elfmem[$mem_addr[31:0]+4],
             elfmem[$mem_addr[31:0]+3], elfmem[$mem_addr[31:0]+2],
             elfmem[$mem_addr[31:0]+1], elfmem[$mem_addr[31:0]+0]};
         $mem_shifted[63:0]  = act4_mode ? $mem_bytes_elf : ($mem_cur_word >> $mem_shift_bits);

         $load_data[63:0] =
            $is_lb  ? {{56{$mem_shifted[7]}},  $mem_shifted[7:0]}  :
            $is_lh  ? {{48{$mem_shifted[15]}}, $mem_shifted[15:0]} :
            $is_lw  ? {{32{$mem_shifted[31]}}, $mem_shifted[31:0]} :
            $is_lbu ? {56'b0, $mem_shifted[7:0]}  :
            $is_lhu ? {48'b0, $mem_shifted[15:0]} :
            $is_lwu ? {32'b0, $mem_shifted[31:0]} :
            $is_ld  ? $mem_shifted :
                      64'b0;

         $store_mask_base[63:0] =
            $is_sb ? 64'h00000000000000FF :
            $is_sh ? 64'h000000000000FFFF :
            $is_sw ? 64'h00000000FFFFFFFF :
            $is_sd ? 64'hFFFFFFFFFFFFFFFF :
                     64'b0;
         $store_mask[63:0]     = $store_mask_base << $mem_shift_bits;
         $store_data_sh[63:0]  = ($rs2_data << $mem_shift_bits) & $store_mask;
         $dmem_new_word[63:0]  = ($mem_cur_word & ~$store_mask) | $store_data_sh;

         /dmem[63:0]
            $wr_en = |cpu>>1$is_store &&
                     (|cpu>>1$mem_word_idx == #dmem);
            $val[63:0] = (|cpu$reset || |cpu>>1$reset) ? 64'b0 :
                         $wr_en ? |cpu>>1$dmem_new_word :
                                  $RETAIN;

         // ─────────────────────────────────────────────────────────
         //  WRITEBACK
         // ─────────────────────────────────────────────────────────
         $wr_data[63:0] =
            ($is_jal || $is_jalr) ? ($pc + 64'd4) :
            $is_lui                 ? $imm_u :
            $is_auipc                ? ($pc + $imm_u) :
            $is_load                  ? $load_data :
                                         $alu_result;

         // ═════════════════════════════════════════════════════════
         //  VIZ — RV64I Single-Cycle Datapath status view. Follows
         //  arm_single_cycle.tlv's proven 'sig'.asBigInt/asInt/asBool
         //  signal-reading convention. Added at the end of Milestone B
         //  (per plan Section 4) now that the full 50-encoding datapath
         //  is stable, rather than re-visualizing a moving target
         //  through Milestones A and B.
         \viz_js
            box: {width: 1080, height: 620, fill: "#0d1117", stroke: "#30363d", strokeWidth: 1},
            where: {left: 0, top: 0},
            init() {
               const mkTxt = (x,y,s,size,colorv,boldv) => new fabric.Text(s, {left: x, top: y, fontSize: size || 10, fill: colorv || "#c9d1d9", fontFamily: "monospace", fontWeight: boldv ? 700 : 400, selectable: false, evented: false})
               const mkBox = (x,y,w,h,fillv,strokev) => new fabric.Rect({left: x, top: y, width: w, height: h, fill: fillv || "#161b22", stroke: strokev || "#30363d", strokeWidth: 1, rx: 3, ry: 3, selectable: false, evented: false})

               let hdr_box = mkBox(0, 0, 1080, 36, "#ffffff", "#ffffff")
               let hdr_ttl = new fabric.Text("RVA23 Base Core -- RV64I Single-Cycle CPU (Phase 1)", {left: 300, top: 8, fontSize: 18, fill: "#128BAB", fontWeight: 700, fontFamily: "Gill Sans, Calibri, sans-serif", selectable: false, evented: false})

               // Status strip: PC, raw instruction word, disassembly.
               let status_box = mkBox(10, 46, 1060, 56)
               let status_pc    = mkTxt(20, 54, "PC=0x0", 13, "#0969da", true)
               let status_instr = mkTxt(160, 54, "instr=0x00000000", 12, "#8b949e", false)
               let status_asm   = mkTxt(420, 54, "--", 15, "#3fb950", true)
               let status_line2 = mkTxt(20, 76, "", 11, "#e3b341", false)

               // Datapath activity indicators.
               let dp_box = mkBox(10, 110, 1060, 40)
               const DP_LABELS = ["RegWrite","ALU","Branch","Jump","Load","Store","W-op","Fence"]
               let dpCells = {}
               DP_LABELS.forEach((nm, i) => {
                  let cx = 20 + i * 132
                  dpCells["dp_lbl_" + i] = mkTxt(cx, 118, nm, 10, "#555555", false)
                  dpCells["dp_led_" + i] = new fabric.Circle({left: cx, top: 132, radius: 6, fill: "#30363d", selectable: false, evented: false})
               })

               // Register grid: x0-x31, 8 columns x 4 rows.
               let rg_box = mkBox(10, 160, 1060, 200)
               let rgCells = {}
               for (let i = 0; i < 32; i++) {
                  let col = i % 8, row = Math.floor(i / 8)
                  let cx = 20 + col * 131, cy = 168 + row * 48
                  rgCells["rg_cell_" + i] = mkBox(cx, cy, 125, 42, "#0d1117", "#128BAB")
                  rgCells["rg_lbl_" + i]  = mkTxt(cx + 6, cy + 3, "x" + i, 9, "#128BAB", true)
                  rgCells["rg_val_" + i]  = mkTxt(cx + 6, cy + 18, "0", 10, "#e6edf3", false)
               }

               // Data-memory activity line (address + operation, when active).
               let mem_box = mkBox(10, 370, 1060, 34)
               let mem_txt = mkTxt(20, 380, "mem: --", 11, "#c9d1d9", false)

               // Cycle counter / PASS banner.
               let bottom_box = mkBox(10, 414, 1060, 40)
               let cyc_txt = mkTxt(20, 424, "cyc=0", 11, "#8b949e", false)
               let pass_txt = mkTxt(160, 424, "", 13, "#e3b341", true)

               return Object.assign({
                  hdr_box, hdr_ttl, status_box, status_pc, status_instr, status_asm, status_line2,
                  dp_box, rg_box, mem_box, mem_txt, bottom_box, cyc_txt, pass_txt
               }, dpCells, rgCells)
            },
            render() {
               const h = (v, w) => "0x" + BigInt.asUintN(64, BigInt(v)).toString(16).toUpperCase().padStart(w || 16, "0")

               let pc      = '$pc'.asBigInt(0n)
               let instr   = '$instr'.asInt(0)
               let cyc     = '$cyc_cnt'.asInt(0)
               let reg_write = '$reg_write'.asBool(false)
               let is_load = '$is_load'.asBool(false)
               let is_store= '$is_store'.asBool(false)
               let is_jal  = '$is_jal'.asBool(false)
               let is_jalr = '$is_jalr'.asBool(false)
               let branch_taken = '$branch_taken'.asBool(false)
               let is_w_op = '$is_w_op'.asBool(false)
               let is_fence = '$is_fence'.asBool(false)
               let alu_res = '$alu_result'.asBigInt(0n)
               let mem_addr = '$mem_addr'.asBigInt(0n)

               // Minimal disassembler covering all 50 RV64I encodings,
               // decoded straight from the instruction bits (never a
               // separately hand-maintained mnemonic list).
               const disasm = (w) => {
                  w = w >>> 0
                  let op = w & 0x7F, f3 = (w >>> 12) & 0x7, f7 = (w >>> 25) & 0x7F
                  let rd = (w >>> 7) & 0x1F, rs1 = (w >>> 15) & 0x1F, rs2 = (w >>> 20) & 0x1F
                  const R = (nm) => nm + " x" + rd + ",x" + rs1 + ",x" + rs2
                  const I = (nm) => nm + " x" + rd + ",x" + rs1
                  if (op === 0x33) { // OP
                     if (f3===0 && f7===0) return R("add"); if (f3===0 && f7===0x20) return R("sub")
                     if (f3===1) return R("sll"); if (f3===2) return R("slt"); if (f3===3) return R("sltu")
                     if (f3===4) return R("xor"); if (f3===5 && f7===0) return R("srl"); if (f3===5 && f7===0x20) return R("sra")
                     if (f3===6) return R("or"); if (f3===7) return R("and")
                  }
                  if (op === 0x13) { // OP-IMM
                     if (f3===0) return I("addi"); if (f3===2) return I("slti"); if (f3===3) return I("sltiu")
                     if (f3===4) return I("xori"); if (f3===6) return I("ori"); if (f3===7) return I("andi")
                     if (f3===1) return I("slli"); if (f3===5 && f7===0) return I("srli"); if (f3===5 && f7===0x20) return I("srai")
                  }
                  if (op === 0x63) { // BRANCH
                     const B = (nm) => nm + " x" + rs1 + ",x" + rs2
                     if (f3===0) return B("beq"); if (f3===1) return B("bne"); if (f3===4) return B("blt")
                     if (f3===5) return B("bge"); if (f3===6) return B("bltu"); if (f3===7) return B("bgeu")
                  }
                  if (op === 0x6F) return "jal x" + rd
                  if (op === 0x67) return "jalr x" + rd + ",x" + rs1
                  if (op === 0x37) return "lui x" + rd
                  if (op === 0x17) return "auipc x" + rd
                  if (op === 0x03) { // LOAD
                     if (f3===0) return "lb x"+rd+",(x"+rs1+")"; if (f3===1) return "lh x"+rd+",(x"+rs1+")"
                     if (f3===2) return "lw x"+rd+",(x"+rs1+")"; if (f3===3) return "ld x"+rd+",(x"+rs1+")"
                     if (f3===4) return "lbu x"+rd+",(x"+rs1+")"; if (f3===5) return "lhu x"+rd+",(x"+rs1+")"
                     if (f3===6) return "lwu x"+rd+",(x"+rs1+")"
                  }
                  if (op === 0x23) { // STORE
                     if (f3===0) return "sb x"+rs2+",(x"+rs1+")"; if (f3===1) return "sh x"+rs2+",(x"+rs1+")"
                     if (f3===2) return "sw x"+rs2+",(x"+rs1+")"; if (f3===3) return "sd x"+rs2+",(x"+rs1+")"
                  }
                  if (op === 0x1B) { // OP-IMM-32
                     if (f3===0) return I("addiw"); if (f3===1) return I("slliw")
                     if (f3===5 && f7===0) return I("srliw"); if (f3===5 && f7===0x20) return I("sraiw")
                  }
                  if (op === 0x3B) { // OP-32
                     if (f3===0 && f7===0) return R("addw"); if (f3===0 && f7===0x20) return R("subw")
                     if (f3===1) return R("sllw"); if (f3===5 && f7===0) return R("srlw"); if (f3===5 && f7===0x20) return R("sraw")
                  }
                  if (op === 0x0F) return "fence"
                  return "-- (0x" + w.toString(16) + ")"
               }

               let objs = this.getObjects()

               objs.status_pc.set({text: "PC=" + h(pc, 4)})
               objs.status_instr.set({text: "instr=" + h(instr, 8)})
               objs.status_asm.set({text: disasm(instr)})
               objs.status_line2.set({text: (is_load||is_store) ? ("mem_addr=" + h(mem_addr,4)) :
                                             (is_jal||is_jalr||branch_taken) ? "control transfer" : ""})

               const dpVals = [reg_write, true, branch_taken, (is_jal||is_jalr), is_load, is_store, is_w_op, is_fence]
               for (let i = 0; i < 8; i++) {
                  objs["dp_led_" + i].set({fill: dpVals[i] ? "#3fb950" : "#30363d"})
               }

               // SandPiper's preprocessor scans for /scope[N]$sig syntax
               // even inside JS string literals, so each register must be
               // read via its own literal-index string (matching
               // arm_single_cycle.tlv's proven pattern) -- a dynamically
               // interpolated '/xreg[' + i + ']$val' string is not
               // recognized and breaks the headless transpile.
               let xregs = [0n,
                  '/xreg[1]$val'.asBigInt(0n),  '/xreg[2]$val'.asBigInt(0n),  '/xreg[3]$val'.asBigInt(0n),
                  '/xreg[4]$val'.asBigInt(0n),  '/xreg[5]$val'.asBigInt(0n),  '/xreg[6]$val'.asBigInt(0n),
                  '/xreg[7]$val'.asBigInt(0n),  '/xreg[8]$val'.asBigInt(0n),  '/xreg[9]$val'.asBigInt(0n),
                  '/xreg[10]$val'.asBigInt(0n), '/xreg[11]$val'.asBigInt(0n), '/xreg[12]$val'.asBigInt(0n),
                  '/xreg[13]$val'.asBigInt(0n), '/xreg[14]$val'.asBigInt(0n), '/xreg[15]$val'.asBigInt(0n),
                  '/xreg[16]$val'.asBigInt(0n), '/xreg[17]$val'.asBigInt(0n), '/xreg[18]$val'.asBigInt(0n),
                  '/xreg[19]$val'.asBigInt(0n), '/xreg[20]$val'.asBigInt(0n), '/xreg[21]$val'.asBigInt(0n),
                  '/xreg[22]$val'.asBigInt(0n), '/xreg[23]$val'.asBigInt(0n), '/xreg[24]$val'.asBigInt(0n),
                  '/xreg[25]$val'.asBigInt(0n), '/xreg[26]$val'.asBigInt(0n), '/xreg[27]$val'.asBigInt(0n),
                  '/xreg[28]$val'.asBigInt(0n), '/xreg[29]$val'.asBigInt(0n), '/xreg[30]$val'.asBigInt(0n),
                  '/xreg[31]$val'.asBigInt(0n)]
               for (let i = 0; i < 32; i++) {
                  objs["rg_val_" + i].set({text: xregs[i].toString()})
               }

               // Mirrors *passed's condition (Section "PASS/FAIL" below) using
               // the same register values already read above -- the viz_js
               // signal-string convention only resolves $name/scope[n]$name
               // pipeline signals, not top-level *name assertions, so '*passed'
               // cannot be read directly here (confirmed: attempting to do so
               // throws "Unexpected token '*'" in Makerchip's real VIZ runtime).
               let passed = (xregs[15] === 1n) && (xregs[16] === 1n) &&
                            (xregs[30] === 1n) && (xregs[10] === 20n) &&
                            (cyc > 100)

               objs.mem_txt.set({text: (is_load||is_store) ? ("mem: " + (is_load?"READ":"WRITE") + " @" + h(mem_addr,4) + " alu=" + alu_res) : "mem: --"})
               objs.cyc_txt.set({text: "cyc=" + cyc})
               objs.pass_txt.set({text: passed ? "PASS" : ""})
               objs.pass_txt.set({fill: "#3fb950"})
            }

   // ─────────────────────────────────────────────────────────────
   //  PASS / FAIL — a small, robust set of final-state checks (the
   //  last write to each of these registers happens near the very end
   //  of the program, nothing overwrites them afterward). Full 50-
   //  encoding coverage is verified via manual trace review against
   //  the expected values documented inline in the program above, per
   //  Milestone B's own done criteria.
   // ─────────────────────────────────────────────────────────────
   *passed = (|cpu/xreg[15]>>1$val == 64'd1)  &&   // ROM[77] JALR landing
             (|cpu/xreg[16]>>1$val == 64'd1)  &&   // ROM[79] post-FENCE
             (|cpu/xreg[30]>>1$val == 64'd1)  &&   // ROM[39] JAL landing
             (|cpu/xreg[10]>>1$val == 64'd20) &&   // ROM[72] SLLW result
             (|cpu>>1$cyc_cnt > 32'd100);
   *failed = 1'b0;

   // Milestone C's elfmem store (see trailing \SV block at end of file)
   // references |cpu@0's real mangled SV signal names directly
   // (CPU_is_store_a0, CPU_mem_addr_a0, etc. -- confirmed by inspecting
   // this file's own SandPiper-generated output) rather than bridging
   // through a new *name[N:0] top-level signal: SandPiper generates a
   // bare `assign` for a wide, non-predeclared *name[N:0] without a
   // matching net declaration, which Icarus correctly rejects
   // ("Net ... is not defined in this context") -- confirmed by
   // actually attempting it and reading the real error, not assumed.

\SV
   // Milestone C: performs the actual byte-wise store into elfmem.
   // References |cpu@0's real mangled SV signal names directly (see
   // note above this block's *-driven predecessor, removed after
   // confirming SandPiper doesn't correctly declare a new wide
   // *name[N:0] top-level net). Standard synchronous-write timing
   // (non-blocking assignment => value committed and visible starting
   // next clock edge), matching how /dmem's own $wr_en/$val TLV idiom
   // already behaves.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_is_store_a0) begin
         if (CPU_is_sb_a0) begin
            elfmem[CPU_mem_addr_a0[31:0]+0] <= CPU_rs2_data_a0[7:0];
         end else if (CPU_is_sh_a0) begin
            elfmem[CPU_mem_addr_a0[31:0]+0] <= CPU_rs2_data_a0[7:0];
            elfmem[CPU_mem_addr_a0[31:0]+1] <= CPU_rs2_data_a0[15:8];
         end else if (CPU_is_sw_a0) begin
            elfmem[CPU_mem_addr_a0[31:0]+0] <= CPU_rs2_data_a0[7:0];
            elfmem[CPU_mem_addr_a0[31:0]+1] <= CPU_rs2_data_a0[15:8];
            elfmem[CPU_mem_addr_a0[31:0]+2] <= CPU_rs2_data_a0[23:16];
            elfmem[CPU_mem_addr_a0[31:0]+3] <= CPU_rs2_data_a0[31:24];
         end else if (CPU_is_sd_a0) begin
            elfmem[CPU_mem_addr_a0[31:0]+0] <= CPU_rs2_data_a0[7:0];
            elfmem[CPU_mem_addr_a0[31:0]+1] <= CPU_rs2_data_a0[15:8];
            elfmem[CPU_mem_addr_a0[31:0]+2] <= CPU_rs2_data_a0[23:16];
            elfmem[CPU_mem_addr_a0[31:0]+3] <= CPU_rs2_data_a0[31:24];
            elfmem[CPU_mem_addr_a0[31:0]+4] <= CPU_rs2_data_a0[39:32];
            elfmem[CPU_mem_addr_a0[31:0]+5] <= CPU_rs2_data_a0[47:40];
            elfmem[CPU_mem_addr_a0[31:0]+6] <= CPU_rs2_data_a0[55:48];
            elfmem[CPU_mem_addr_a0[31:0]+7] <= CPU_rs2_data_a0[63:56];
         end
      end
   end
   endmodule
