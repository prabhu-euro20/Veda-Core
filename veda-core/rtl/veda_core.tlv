\m4_TLV_version 1d: tl-x.org
\SV
   // ═══════════════════════════════════════════════════════════════════
   //  Veda-Core RTL — Phase 1 Milestone 1 (Capability Register File,
   //  Object-Bind, OCL.D/OCS.D). Seeded from the already-verified RVA23
   //  base core (rtl/rv64i_core.tlv, 51/51 real ACT4 RV64I conformance),
   //  which is untouched below except for the new Veda-Core additions --
   //  see veda-core/rtl/MILESTONE_PLAN.md for the full scope decision and
   //  the three real architectural calls this milestone required (the ODT
   //  is memory-mapped, not a register array; violations suppress writes
   //  rather than trap, since this core has no privileged/trap
   //  infrastructure at all yet; the generation-staleness check is
   //  included from the start rather than reproducing a known, already-
   //  fixed Sail V-A gap).
   //
   //  All 50 RV64I encodings implemented (unchanged from the base core):
   //  the 38 RV32I-equivalent instructions (incl. FENCE and, as of RTL
   //  Milestone 23, ECALL; EBREAK still excl./deferred) plus the 12
   //  RV64-only *W encodings.
   //
   //  Waveform signals to watch (add in Makerchip waveform panel):
   //    |cpu @0  $pc, $instr, $opcode, $funct3, $funct7, $reg_write,
   //             $alu_result, $branch_taken, $pc_src, $wr_data,
   //             $is_load, $is_store, $mem_addr
   //    |cpu @0  $is_veda_bind, $is_veda_ocl, $is_veda_ocs, $veda_violation
   //    /xreg[1..31] $val   — register file values
   //    /dmem[0..63] $val   — data memory (64 doublewords, byte addr 0-511)
   //    /vreg[0..15] $tag, $base, $length, $offset, $perms, $otype — CRF
   // ═══════════════════════════════════════════════════════════════════
   m4_makerchip_module

   // ───────────────────────────────────────────────────────────────────
   //  VEDA-CORE: Object Descriptor Table — memory-mapped, not a register
   //  array (VEDA_CORE_SPEC.md Section 5.1's own design intent, made
   //  concrete for the first time in real RTL — see MILESTONE_PLAN.md
   //  item 1 for the full reasoning). 256 entries this milestone (real
   //  silicon-area scoping, not Sail's own 8.4M-entry ID space), 16 bytes
   //  each: Base(32) + Length(16) + Perms(16) + generation(8) + valid(8,
   //  really 1 bit, byte-aligned for simple addressing) + owner_hart(8,
   //  Milestone 12 addition, byte offset +10, one of the six previously-
   //  spare bytes in this 16-byte window) = 88 bits used of 128
   //  available, same byte-addressable-array convention already used
   //  for elfmem/dmem below, not a new idiom. Milestone 15 (Object_ID hi
   //  bits, +11/+12) and Milestone 16 (retired, 1 bit of +13) each later
   //  consumed one more previously-spare byte. Length widened 16->20
   //  bits, 2026-08-19 (mirrors veda_types.sail's odt_entry.Length) --
   //  the extra 4 bits reuse byte +14's low nibble, the same spare-byte-
   //  reuse idiom; only +15 remains fully spare after this pass.
   // ───────────────────────────────────────────────────────────────────
   localparam bit [31:0] ODT_BASE = 32'h9000_0000;
   localparam int ODT_ENTRIES = 256;
   localparam int ODT_ENTRY_BYTES = 16;
   // MILESTONE 24 (TCM_FAST_PATH_DESIGN.md): the first real DRAM-latency
   // number this core has ever modeled -- every prior milestone's own
   // cycle counts assumed odt_mem[]/elfmem[] access is always 1 cycle,
   // which CRF_ARCHITECTURE_ALIGNMENT_VERDICT.md's own addendum found is
   // only true because no latency was ever modeled, not because it's
   // architecturally free. Swept {0,10,50} in verification
   // (DRAM_TCM_LATENCY_STUDY.md's own real, DDR4-grounded range).
   //
   // Committed default is 0, NOT a nonzero value -- a real, deliberate
   // correction found empirically this milestone, not assumed: every one
   // of the 46 pre-existing RTL smoke tests uses Object-Bind (often
   // several times, for compartment-entry setup), sharing ONE compiled
   // veda_core.sv per run_veda_smoke_test.sh invocation, against fixed
   // repeat(N) testbench cycle budgets as tight as repeat(12) (confirmed
   // by direct grep before deciding this, e.g. tb_veda_smoke.sv:23) --
   // shipping a nonzero default here would silently break most of that
   // corpus via budget exhaustion, not any real logic defect. The stall
   // mechanism itself is fully built and verified working correctly at a
   // nonzero value via a dedicated new test with a properly-sized budget
   // (veda_smoke_m24_latency.S) -- widening the pre-existing 46 tests'
   // own budgets so a nonzero default is safe to ship globally is real,
   // separate, mechanical follow-up work, named honestly as not done in
   // this milestone, not silently assumed away.
   localparam int DRAM_EXTRA_CYCLES = 0;
   // MILESTONE 24 Stage 2 (TCM_FAST_PATH_DESIGN.md Part B): a fixed, LOW
   // Object_ID range that never pays the DRAM-tier stall on Bind/Bind-
   // NoTrap/Rebind. Real, deliberate simplification: odt_mem[] itself
   // does NOT get physically split into a separate array -- the "TCM"
   // property here is purely about latency classification (Object_ID <
   // TCM_ODT_ENTRIES never stalls), not physical placement, since
   // odt_mem[] is already a same-cycle-combinational SystemVerilog array
   // with no memory-technology distinction in simulation. 32 entries =
   // 512 bytes of the real, existing 16-byte ODT_ENTRY_BYTES layout --
   // comfortably inside real Cortex-M/R TCM budgets (4KB-64KB) already
   // cited in DRAM_TCM_LATENCY_STUDY.md. Placement is STATIC and
   // software-declared (whichever Object_ID a program chooses to
   // ODT-Populate below this threshold), never automatically promoted
   // based on observed access frequency -- the real, cited security
   // constraint from TCM_FAST_PATH_DESIGN.md Section 1 (GhostRider,
   // ASPLOS 2015): placement must be independent of secret-correlated
   // runtime data, which a fixed, compile-time-chosen range satisfies by
   // construction. Per-hart-private: safe as a single, unpartitioned
   // range only because MHARTID is fixed at 0 below -- if/when a real
   // multi-hart Veda-Core is ever built, this must be revisited (per-hart
   // banks, or a real static time-partitioned arbiter per Wang/
   // Ferraiuolo/Suh HPCA 2014) before this same code can be trusted for
   // the same security property -- written down, not silently assumed.
   localparam int TCM_ODT_ENTRIES = 32;
   // RTL MILESTONE 12: this single-core RTL's own fixed hart identity --
   // no real MHARTID CSR/concept existed anywhere in this file before
   // now (a genuine new architectural constant, not a repurposed one).
   // Fixed at 0, the real, standard RISC-V single-hart convention
   // (mirrors Sail's own veda_test_sail.json single-hart config, which
   // also fixes mhartid=0) -- extendable to a real per-instance value if
   // this core is ever replicated into an actual multi-hart system
   // (NEXT_STEPS_ROADMAP.md §2.7's own still-open, explicitly deferred
   // item), not attempted here.
   localparam bit [7:0] MHARTID = 8'h00;
   // Sentinel for "no live owner yet" -- matches Sail's own
   // VEDA_OWNER_UNOWNED (veda_types.sail) byte-for-byte, not re-chosen.
   localparam bit [7:0] VEDA_OWNER_UNOWNED = 8'hFF;
   logic [7:0] odt_mem [ODT_BASE : ODT_BASE + (ODT_ENTRIES * ODT_ENTRY_BYTES) - 1];
   initial begin
      // Milestone 1 test scaffold, explicitly temporary -- mirrors Sail
      // Milestone V-A's own veda_test_seed_odt() field-for-field, same
      // real reason: no ODT-Populate instruction exists yet in RTL
      // (deferred to a later RTL milestone, matching the Sail V-A -> V-B
      // sequencing already used and documented in MILESTONE_PLAN.md).
      for (int veda_i = 0; veda_i < (ODT_ENTRIES * ODT_ENTRY_BYTES); veda_i = veda_i + 1)
         odt_mem[ODT_BASE + veda_i] = 8'h00;
      // Object_ID=1 -> byte offset 1*16=16 from ODT_BASE. Base=0x80010000
      // (inside the same ELF-loaded RAM region ACT4/elfmem uses),
      // Length=0x40, Perms=0x100C (Permit_Load|Permit_Store|
      // Permit_NMC_Compute -- the last bit isn't consumed by anything
      // built this milestone, set now so it doesn't need revisiting),
      // generation=0, valid=1.
      {odt_mem[ODT_BASE+16+3], odt_mem[ODT_BASE+16+2], odt_mem[ODT_BASE+16+1], odt_mem[ODT_BASE+16+0]} = 32'h8001_0000;
      {odt_mem[ODT_BASE+16+5], odt_mem[ODT_BASE+16+4]} = 16'h0040;
      {odt_mem[ODT_BASE+16+7], odt_mem[ODT_BASE+16+6]} = 16'h100C;
      odt_mem[ODT_BASE+16+8] = 8'h00;
      odt_mem[ODT_BASE+16+9] = 8'h01;
      // Milestone 12 addition: reset-seeded objects start genuinely
      // unowned (matches Sail's own veda_test_seed_odt() field-for-
      // field), not owned by hart 0 by default -- Bind's own real claim
      // logic (below) is what's actually under test, not a fixture that
      // pre-empts it.
      odt_mem[ODT_BASE+16+10] = VEDA_OWNER_UNOWNED;
      // Milestone 2 addition: a second seeded object, deliberately
      // *without* Permit_NMC_Compute (Perms = 0x000C, Load+Store only),
      // so a real negative-control test can confirm NMC_ADD's own
      // permission gate actually fires -- the identical real reason and
      // identical field values already used for this exact purpose in
      // the Sail test scaffold (veda_regs.sail's own Object_ID=2 entry).
      // Object_ID=2 -> byte offset 2*16=32 from ODT_BASE.
      {odt_mem[ODT_BASE+32+3], odt_mem[ODT_BASE+32+2], odt_mem[ODT_BASE+32+1], odt_mem[ODT_BASE+32+0]} = 32'h8001_0100;
      {odt_mem[ODT_BASE+32+5], odt_mem[ODT_BASE+32+4]} = 16'h0040;
      {odt_mem[ODT_BASE+32+7], odt_mem[ODT_BASE+32+6]} = 16'h000C;
      odt_mem[ODT_BASE+32+8] = 8'h00;
      odt_mem[ODT_BASE+32+9] = 8'h01;
      odt_mem[ODT_BASE+32+10] = VEDA_OWNER_UNOWNED;
      // Milestone 12 addition: Object_ID=60 -> byte offset 60*16=960, a
      // THIRD seeded object, pre-claimed by owner_hart=0x63 (99 decimal)
      // -- a stand-in "other hart," since this single-core RTL testbench
      // has no real second hart to own anything with (mirrors Sail's own
      // identical Milestone 12 fixture, veda_regs.sail's Object_ID=5
      // entry, same real reason: direct ODT-state injection is the only
      // way this project's own single-hart test environments can prove
      // a wrong-owner outcome at all). Object_ID=60 chosen specifically
      // because it's the one value genuinely unused anywhere else in
      // this project's own existing RTL test corpus (confirmed by
      // grepping every veda_smoke_*.S file before picking it -- Object_
      // ID=3 was tried first and found to collide with Milestone 4's own
      // "never seeded at reset" fresh-mint precondition, a real bug
      // caught by that pre-existing test, not a hypothetical one).
      // Base=0x80010200, Length=0x40, Perms=0x000C (Load+Store), so this
      // fixture is also usable as an ordinary-looking object in every
      // respect except ownership.
      {odt_mem[ODT_BASE+960+3], odt_mem[ODT_BASE+960+2], odt_mem[ODT_BASE+960+1], odt_mem[ODT_BASE+960+0]} = 32'h8001_0200;
      {odt_mem[ODT_BASE+960+5], odt_mem[ODT_BASE+960+4]} = 16'h0040;
      {odt_mem[ODT_BASE+960+7], odt_mem[ODT_BASE+960+6]} = 16'h000C;
      odt_mem[ODT_BASE+960+8] = 8'h00;
      odt_mem[ODT_BASE+960+9] = 8'h01;
      odt_mem[ODT_BASE+960+10] = 8'h63;
   end

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

   // ─────────────────────────────────────────────────────────────────
   //  VEDA-CORE RTL MILESTONE 7: real, out-of-band capability Tag store
   //  for OCL.C/OCS.C -- mirrors the real Sail-side implementation
   //  field-for-field (toolchain/sail-riscv/model/core/mem_metadata.sail,
   //  mem_meta redefined from unit to bool): one bit per 16-byte
   //  (128-bit) granule, scoped to exactly the same real, ELF-loadable
   //  RAM region elfmem[] already covers -- the same honest, bounded-
   //  scope discipline already used for the ODT (256 real RTL entries,
   //  not Sail's 8.4M) and now for the tag store too. Only OCL.C/OCS.C
   //  ever touch this array; plain OCL/OCS/NMC_ADD/Atomic accesses to the
   //  same bytes never do, matching CHERI's own real separation between
   //  ordinary data access and capability load/store.
   // ─────────────────────────────────────────────────────────────────
   logic tag_mem [0 : (ELFMEM_SIZE/16) - 1];
   initial begin
      for (int veda_tm_i = 0; veda_tm_i < (ELFMEM_SIZE/16); veda_tm_i = veda_tm_i + 1)
         tag_mem[veda_tm_i] = 1'b0;
   end

   // ─────────────────────────────────────────────────────────────────
   //  MILESTONE 24 Stage 3 (TCM_FAST_PATH_DESIGN.md Part C, "Mechanism
   //  A"): the TCM capability-spill scratch region -- generalizes the
   //  already-decided OCS.C/OCL.C software-managed spill/restore pattern
   //  (already used for the scheduler save-area) into a real, reusable
   //  fast destination, distinct from elfmem[]. A genuinely SEPARATE
   //  physical array (mirroring the real, existing odt_mem[]-vs-elfmem[]
   //  precedent above -- two distinct base-address ranges, not a
   //  carved-out sub-range of an existing array), at a real, deliberately
   //  small, bounded size (4KiB, sized for the scheduler's own real
   //  save_area_0/save_area_1 relocation -- 3 dwords=24 bytes each today
   //  -- plus real headroom for a handful of future Mechanism-A spill
   //  targets, without being large enough to become a second general-
   //  purpose DRAM-equivalent region, which would blur the "small,
   //  deterministic TCM" security framing the whole feature rests on).
   //  tcm_scratch_tag[] mirrors tag_mem[]'s own real, out-of-band-tag
   //  discipline exactly -- only OCL.C/OCS.C ever touch it, plain
   //  OCL.D/OCS.D against a TCM-scratch address are explicitly out of
   //  this milestone's own scope (they would fall outside elfmem[]'s own
   //  declared bounds if ever attempted against 0xA0000000+, the same
   //  natural, pre-existing out-of-range behavior any address outside
   //  elfmem[] already has -- not a new gap this milestone introduces).
   // ─────────────────────────────────────────────────────────────────
   localparam bit [31:0] TCM_SCRATCH_BASE = 32'hA000_0000;
   localparam bit [31:0] TCM_SCRATCH_SIZE = 32'h0000_1000;
   logic [7:0] tcm_scratch [TCM_SCRATCH_BASE : TCM_SCRATCH_BASE + TCM_SCRATCH_SIZE - 1];
   logic tcm_scratch_tag [0 : (TCM_SCRATCH_SIZE/16) - 1];
   initial begin
      for (int veda_ts_i = 0; veda_ts_i < (TCM_SCRATCH_SIZE/16); veda_ts_i = veda_ts_i + 1)
         tcm_scratch_tag[veda_ts_i] = 1'b0;
   end

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
         //  VEDA-CORE RTL MILESTONE 4: minimal real privilege state.
         //  Resets to 1 (privileged), matching real RISC-V's own "harts
         //  reset into the highest privilege level" convention. One-way:
         //  only `veda.droppriv` (decoded below) can clear it; nothing
         //  raises it back (MILESTONE_PLAN.md's own Milestone 4 addendum
         //  has the full reasoning). Same simple stateful-signal idiom
         //  already used for $cyc_cnt above, not a new one.
         // ─────────────────────────────────────────────────────────
         $priv = $reset ? 1'b1 : (>>1$is_veda_droppriv ? 1'b0 : >>1$priv);

         // ─────────────────────────────────────────────────────────
         //  PROGRAM COUNTER — same one-extra-cycle-after-reset handling
         //  as Milestone A / arm_single_cycle.tlv.
         // ─────────────────────────────────────────────────────────
         $reset_just_released = >>1$reset && !$reset;
         // MILESTONE 24: >>1$veda_dram_busy (PREVIOUS cycle's busy state,
         // never this cycle's own combinational value -- see the stall
         // FSM's own header comment above for why this specific ordering
         // matters) takes priority over >>1$pc_src -- a DRAM-tier access
         // that also happens to be the last instruction before a branch
         // must finish its own extra wait before the branch's own
         // redirect is honored; nothing in this core freezes $pc today
         // outside of this new condition (Milestone 14's own PCC-
         // violation check forces $instr to NOP but never freezes $pc --
         // confirmed by direct read before writing this).
         $pc[63:0] =
            ($reset || $reset_just_released) ? (act4_mode ? {32'b0, ELFMEM_BASE} : 64'b0) :
            >>1$veda_dram_busy               ? >>1$pc :
            >>1$pc_src                       ? >>1$alt_pc :
                                                >>1$pc + 64'd4;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 14 (Sail mirror, veda-core/MILESTONE_14_RESULTS.md
         //  / PCC_COMPARTMENT_DESIGN.md): PCC compartment bounding --
         //  bounding execution inside an OCInvoke-entered compartment.
         //  $veda_pcc_base/$veda_pcc_length (defined further below,
         //  alongside $mtvec/$mepc -- SandPiper's own combinational-
         //  elaboration-is-order-independent pattern already used
         //  throughout this file, e.g. $veda_trap_taken referenced here
         //  before its own definition too) hold the currently-active
         //  compartment's own bounds, narrowed away from
         //  VEDA_PCC_UNBOUNDED (20'hFFFFF, the reset/no-compartment
         //  sentinel -- widened from 16'hFFFF alongside capability
         //  Length/Offset, 2026-08-19) only by a successful OCInvoke.
         //  This check is genuinely unconditional, every cycle, against
         //  the CURRENT $pc -- distinct in kind from every other check
         //  in this file, none of which are gated on a decoded opcode;
         //  Sail's own mirror (postlude/step_ext.sail's
         //  ext_fetch_check_pc) is identically unconditional, called
         //  before every fetch.
         // ─────────────────────────────────────────────────────────
         $veda_pcc_violation = ($veda_pcc_length != 20'hFFFFF) &&
                                (($pc[31:0] < $veda_pcc_base) ||
                                 ($pc[31:0] >= ($veda_pcc_base + {12'b0, $veda_pcc_length})));

         // ─────────────────────────────────────────────────────────
         //  INSTRUCTION MEMORY — Milestone A/B hand-assembled ROM[]
         //  (pc[8:2] gives a 7-bit index, 0-127, byte addresses 0-508,
         //  comfortably covering ROM_SIZE=81), or Milestone C's
         //  ELF-loaded elfmem[] (little-endian 4-byte read at $pc, real
         //  absolute address), selected by act4_mode.
         // ─────────────────────────────────────────────────────────
         $instr_rom[31:0]  = ROM[($pc[8:2] >= ROM_SIZE) ? ROM_SIZE - 1 : $pc[8:2]];
         $instr_elf[31:0]  = {elfmem[$pc[31:0]+3], elfmem[$pc[31:0]+2], elfmem[$pc[31:0]+1], elfmem[$pc[31:0]+0]};
         // RTL Milestone 14: on a PCC bounds violation, $instr is forced
         // to a real, standard NOP encoding (0x00000013 = ADDI x0,x0,0)
         // rather than whatever arbitrary bytes happen to live at the
         // out-of-bounds $pc -- the single, minimal change that
         // correctly suppresses every possible downstream GPR/capability
         // -register/memory write path this cycle (a NOP targeting x0
         // triggers no real write anywhere in the file), matching Sail's
         // own real behavior of never reaching decode/execute at all on
         // a failed fetch, without needing to individually audit and
         // gate every one of this file's many independent write paths.
         // The real trap itself (mcause/mepc/mtval/PC-redirect) is still
         // delivered via $veda_pcc_violation joining $veda_trap_taken
         // below, entirely independent of what $instr decodes to.
         //
         // MILESTONE 24: >>1$veda_dram_busy composed alongside the
         // existing PCC-violation term, same literal NOP-substitution
         // idiom -- this is the ONE piece of Milestone 14 that is
         // genuinely reused verbatim here (M14 itself provides no
         // stall/freeze mechanism to reuse, only this literal encoding
         // trick -- see the stall FSM's own header comment above).
         // Using >>1 here (not this cycle's own $veda_dram_busy) is what
         // keeps this acyclic: the triggering instruction's REAL decode
         // this cycle is never touched (>>1busy was 0 the cycle a fresh
         // DRAM-tier access is first attempted), only the SUBSEQUENT
         // DRAM_EXTRA_CYCLES cycles at the same (frozen) $pc are forced
         // to NOP here.
         $instr[31:0] = ($veda_pcc_violation || >>1$veda_dram_busy) ? 32'h00000013 :
                        act4_mode                                   ? $instr_elf :
                                                                       $instr_rom;

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
         $op_is_system = ($opcode == 7'b1110011);

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 9: a minimal, real Zicsr-lite + trap-taken
         //  control flow -- the largest remaining Sail/RTL architectural
         //  divergence named in NEXT_STEPS_ROADMAP.md §2.4 ("Sail's own
         //  security model (hard trap, exact mcause/mtval) is not
         //  actually what the RTL currently enforces"). Real, standard
         //  RISC-V encoding throughout (Zicsr's I-type CSR shape,
         //  SYSTEM opcode), not an invented mechanism.
         //
         //  Deliberate scope reduction, stated plainly rather than
         //  silently narrowed: only CSRRW/CSRRS are decoded this pass
         //  (CSRRC/CSRRWI/CSRRSI/CSRRCI deferred -- this core's own
         //  trap handlers only ever need "install a value" (CSRRW, for
         //  mtvec) and "read a value" (CSRRS with rs1=x0, the real
         //  `csrr` pseudo-instruction's own expansion), matching every
         //  trap-handler pattern already proven in this project's own
         //  Sail-side tests). Only 5 CSR addresses are recognized --
         //  the real, standard RISC-V M-mode addresses for mtvec/mscratch/
         //  mepc/mcause/mtval (0x305/0x340/0x341/0x342/0x343) -- any other
         //  address reads/writes as a hardwired 0, matching real RISC-V's
         //  own WARL convention for an unimplemented CSR rather than
         //  inventing new fault behavior for it. mscratch (RTL Milestone
         //  25 mirror) was added later than the other four, needed by the
         //  full-GPR-context-save scheduler's own mscratch-based trap-
         //  entry bootstrap (sail_tests/vc_scheduler_cooperative_yield.S)
         //  -- a byte-for-byte structural copy of mtvec's own pattern
         //  below, since mscratch shares mtvec's exact profile: nothing
         //  but software CSRRW ever writes it, no hardware-capture logic
         //  needed.
         // ─────────────────────────────────────────────────────────
         $csr_addr[11:0] = $instr[31:20];
         $is_csrrw = $op_is_system && ($funct3 == 3'b001);
         $is_csrrs = $op_is_system && ($funct3 == 3'b010);
         $is_csr_access = $is_csrrw || $is_csrrs;
         $csr_is_mtvec   = ($csr_addr == 12'h305);
         $csr_is_mscratch = ($csr_addr == 12'h340);
         $csr_is_mepc    = ($csr_addr == 12'h341);
         $csr_is_mcause  = ($csr_addr == 12'h342);
         $csr_is_mtval   = ($csr_addr == 12'h343);
         // RTL Milestone 14: four new CSRs, the real, standard RISC-V
         // "Machine-level Custom read/write" address range (riscv-spec.pdf
         // Table 91, p.664, 0x7C0-0x7FF) -- verified against the real
         // spec, the same real range convention already trusted once for
         // mtvec/mscratch/mepc/mcause/mtval above, and the identical four
         // addresses already chosen and verified on the Sail side
         // (veda_regs.sail).
         $csr_is_veda_pcc_base     = ($csr_addr == 12'h7C0);
         $csr_is_veda_pcc_length   = ($csr_addr == 12'h7C1);
         $csr_is_veda_mepcc_base   = ($csr_addr == 12'h7C2);
         $csr_is_veda_mepcc_length = ($csr_addr == 12'h7C3);
         // RTL Milestone 18: reusable Length/Perms template for
         // VEDA_ODT_POPULATE_FAST below -- same real 0x7C0-0x7FF custom
         // range, next free slot after Milestone 14's four, matching the
         // already-verified Sail-side choice (veda_regs.sail).
         $csr_is_veda_attr         = ($csr_addr == 12'h7C4);
         // RTL Milestone 19 (Sail mirror, MILESTONE_19_RESULTS.md /
         // veda-core/rtl/MILESTONE_19_RESULTS.md): veda_mode, bit 0 =
         // veda_purecap. Next free slot after Milestone 18's 0x7C4,
         // matching the already-verified Sail-side choice
         // (veda_regs.sail) -- confirmed collision-free against every
         // $csr_is_veda_* address already decoded above before adopting
         // it.
         $csr_is_veda_mode         = ($csr_addr == 12'h7C5);

         // MRET: the one, fixed 32-bit encoding (funct12=0b001100000010,
         // rs1=rd=0, funct3=0, opcode=SYSTEM) -- matched as a single
         // literal comparison rather than field-by-field decode, the
         // simplest, least-ambiguous way to recognize one specific,
         // fully-fixed instruction word (no operand fields to extract at
         // all, unlike CSRRW/CSRRS). This core has no privilege-level
         // stack to restore (it's always effectively M-mode, matching
         // $priv's own existing one-way-drop model) -- MRET here means
         // exactly "PC = mepc", not a full mstatus.MPP/MPIE restore.
         $is_mret = ($instr == 32'h30200073);

         // RTL MILESTONE 23: ECALL -- the same fixed-literal idiom as
         // MRET above (funct12=0, rs1=rd=0, funct3=0, opcode=SYSTEM;
         // the full 32-bit word is 0x00000073, distinct from EBREAK's
         // 0x00100073 -- differs only in bit 20 -- and from MRET's
         // 0x30200073). Closes a gap this project's own Milestone 21
         // explicitly named and pre-scoped: "if and when a future
         // milestone adds ecall... that work must wire its own new
         // violation signal into the existing $veda_trap_taken
         // OR-chain... Doing so would automatically and correctly get
         // PCC-reset for free, by construction" (MILESTONE_21_RESULTS.md).
         // EBREAK remains deferred -- not added here.
         $is_ecall = ($instr == 32'h00000073);

         // Real-time/safety-critical audit (2026-08-16, REALTIME_SAFETY_
         // CRITICAL_AUDIT_RESULTS.md): WFI (funct12=0x105, rs1=rd=0,
         // funct3=PRIV, opcode=SYSTEM -- full word 0x10500073, distinct
         // from ECALL/MRET/EBREAK by bits 31:20) was previously
         // UNDECODED. Verified this was accidentally, not deliberately,
         // spec-safe: no $is_wfi existed, so WFI matched none of
         // $reg_write/$veda_trap_taken/$pc_src's own explicit OR-lists
         // and fell through to an ordinary pc+4 advance -- externally
         // indistinguishable from the RISC-V spec's own explicitly
         // -permitted "a legal implementation is to simply implement the
         // WFI instruction as a NOP" (ISA manual p.715), but fragile:
         // nothing marked it intentional, so a future hardening pass
         // that adds a catch-all "unrecognized SYSTEM-opcode word ->
         // illegal instruction" trap (a reasonable step, given this core
         // still has no generic illegal-instruction path at all) would
         // silently start faulting WFI, with no TW-bit mechanism behind
         // it to make that legal. This decode makes the NOP intentional
         // and documented, matching every other real instruction in this
         // file -- it is deliberately NOT wired into $reg_write,
         // $veda_trap_taken, or $pc_src; its only job is to exist as a
         // named exclusion any future catch-all must consult.
         $is_wfi = ($instr == 32'h10500073);
         // Deliberately not consumed anywhere else in this file -- see
         // the comment above. Read externally by
         // veda_smoke_wfi_nop.S's own testbench to prove the decode
         // itself fires, not just that execution happens not to crash.
         `BOGUS_USE($is_wfi)

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

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE DECODE — Custom-0 (0001011): Object-Bind (I-type,
         //  funct3=101) vs OCL/OCS (R-type). funct3=101 alone identifies
         //  Bind unambiguously (VEDA_CORE_SPEC.md Section 1: OCL/OCS's
         //  own width table never uses funct3=101, reserved exactly for
         //  this). This milestone only implements OCL.D/OCS.D (funct3=
         //  011, matching Sail V-A's own scope) -- funct7 selects OCL
         //  (0000000) vs OCS (0000001), the R-type case.
         //
         //  Capability-register operand fields are packed into their
         //  5-bit R-type/I-type slots as [0, vcapidx(4)] -- the same
         //  convention already fixed in the Sail model (VEDA_CORE_SPEC.md
         //  Section 3: "future-proofs against growing past 16 capability
         //  registers"), so only the low 4 bits of the relevant field are
         //  real; the top bit is expected to be 0 for a validly-encoded
         //  Veda-Core instruction.
         // ─────────────────────────────────────────────────────────
         $op_is_custom0 = ($opcode == 7'b0001011);
         $is_veda_bind  = $op_is_custom0 && ($funct3 == 3'b101);
         $is_veda_ocl   = $op_is_custom0 && ($funct3 == 3'b011) && ($funct7 == 7'b0000000);
         $is_veda_ocs   = $op_is_custom0 && ($funct3 == 3'b011) && ($funct7 == 7'b0000001);
         // OCL.C/OCS.C -- RTL Milestone 7 (VEDA_CORE_SPEC.md's own
         // "OCL.C/OCS.C semantics" writeup). Same funct7 as OCL/OCS
         // above, differentiated by funct3=100 (the width table's own
         // reserved "C" slot). `rd` here is NOT a GPR -- it reuses
         // $veda_rd_cap (instr[10:7], already extracted below for Bind/
         // OCA/CSetBounds/CSeal/CUnseal) as a Capability Register index,
         // matching real CHERI's own [C]LC/[C]SC precedent (already
         // decided and cited in the spec): a 128-bit capability plus Tag
         // has no meaningful GPR representation.
         $is_veda_ocl_c = $op_is_custom0 && ($funct3 == 3'b100) && ($funct7 == 7'b0000000);
         $is_veda_ocs_c = $op_is_custom0 && ($funct3 == 3'b100) && ($funct7 == 7'b0000001);

         // Bind: mode = instr[21:20] (imm[1:0]), rs1 = instr[19:15]
         // (already extracted as $rs1, an ordinary GPR holding Object_ID
         // -- VEDA_CORE_SPEC.md Section 4's own "not a capability-register
         // reference" choice), rd_cap = instr[10:7] (4-bit capability
         // register index).
         // RTL Milestone 8: the mode field is now actually branched on.
         // A real, previously-undetected gap closed by this milestone:
         // since $veda_bind_mode was decoded but never checked, EVERY
         // mode value (00/01/10/11) silently executed as plain Bind --
         // `veda.rebind` would have wrongly reset Offset to 0 exactly
         // like a fresh Bind, defeating Rebind's entire purpose (Section
         // 4: "Offset preserved across relocation"). Fixed by decoding
         // each mode explicitly below.
         $veda_bind_mode[1:0] = $instr[21:20];
         $is_veda_bind_plain  = $is_veda_bind && ($veda_bind_mode == 2'b00);
         // Bind-NoTrap (mode=01): Sail's own distinction from plain Bind
         // is trap-vs-soft-fail on an ODT miss (veda_bind_insts.sail:
         // VEDA_BIND traps via veda_trap(), VEDA_BIND_NOTRAP instead
         // writes zero_capability+Tag=0). This RTL has no trap
         // infrastructure at all (the same honest floor stated
         // throughout this file) -- plain Bind's own existing soft-fail
         // convention (Tag = $veda_odt_valid, already 0 on a miss) is
         // therefore ALREADY behaviorally identical to Bind-NoTrap.
         // Decoded as its own signal for documentation/test clarity and
         // to keep the door open for real trap infra later (at which
         // point only $is_veda_bind_plain would start trapping), but
         // shares $bind_wr_en's write path unchanged below.
         $is_veda_bind_notrap = $is_veda_bind && ($veda_bind_mode == 2'b01);
         // Rebind (mode=10): the real, new-this-milestone behavior --
         // refreshes Base/Length/Perms/otype/generation from the ODT
         // while leaving the capability register's own Offset field
         // untouched, and reads/writes rd (not rs1) as its own "current
         // capability" input -- distinct enough from Bind/Bind-NoTrap to
         // need its own write path below, not a shared one.
         $is_veda_rebind      = $is_veda_bind && ($veda_bind_mode == 2'b10);

         // ─────────────────────────────────────────────────────────
         //  MILESTONE 24: real DRAM-latency stall FSM (TCM_FAST_PATH_
         //  DESIGN.md Part A). Scope, deliberately narrow (design doc's
         //  own reasoning): only Object-Bind/Bind-NoTrap/Rebind's ODT
         //  access and OCL.C/OCS.C's capability-width memory access --
         //  NOT plain OCL.D/OCS.D, NOT ordinary ld/sd, which would
         //  silently regress ACT4's own cycle-count assumptions for no
         //  benefit this milestone's own scope needs.
         //
         //  Real correctness property, verified by hand-tracing before
         //  writing this (not copied from the design doc's own first-
         //  draft formula, which had a same-cycle combinational-loop
         //  risk: gating $instr on THIS cycle's own $veda_dram_busy,
         //  itself derived from decoding THIS cycle's $instr, is a real
         //  cycle in the dependency graph). The fix: $instr's own NOP-
         //  forcing (below) and $pc's own freeze (below) both gate on
         //  >>1$veda_dram_busy (the PREVIOUS cycle's busy state, a real
         //  register read, never this cycle's own combinational value) --
         //  so the triggering Bind/OCL.C/OCS.C instruction decodes and
         //  executes NORMALLY, unforced, on its own first (only) fetch
         //  cycle -- $bind_wr_en/$oclc_wr_en/OCS.C's own always_ff write
         //  logic below are completely untouched, same 1-cycle write
         //  latency as every prior milestone. The new mechanism purely
         //  holds $pc at the SAME value for DRAM_EXTRA_CYCLES additional
         //  cycles afterward (forcing NOP during those extra cycles only)
         //  before the NEXT instruction is allowed to fetch -- verified
         //  by hand-tracing to add exactly DRAM_EXTRA_CYCLES extra cycles
         //  (not DRAM_EXTRA_CYCLES+1, a real off-by-one the same-cycle-
         //  load-into-stall_cnt formula below specifically avoids).
         //
         //  $veda_dram_stall_req fires exactly once per DRAM-tier access
         //  attempt: real decode this cycle (safe -- $instr is unforced
         //  whenever >>1busy was 0, which is the only time this guard
         //  passes) AND not already mid-stall (>>1busy==0) AND not also a
         //  PCC violation (a faulting fetch must not spuriously start a
         //  stall that would then eat into the trap-handling flow).
         // ─────────────────────────────────────────────────────────
         // MILESTONE 24 Stage 2: the Bind/Bind-NoTrap/Rebind term gains
         // the `&& !$veda_odt_tcm_hit` guard (judged on Object_ID).
         // MILESTONE 24 Stage 3: OCL.C/OCS.C's own term gains the
         // `&& !$veda_capmem_tcm_hit` guard (judged on the resolved
         // memory address, $veda_capmem_tcm_hit defined below alongside
         // $veda_capmem_granule -- SandPiper's own order-independent
         // elaboration within this @0 stage, already relied on
         // throughout this file, makes the forward reference safe).
         //
         // R21 FIX (2026-08-16, found independently on the Linux line's
         // veda-core-sindhu fork of this same Milestone 24 mechanism,
         // confirmed still live here by direct re-derivation of this
         // core's own real trap terms, not copied from that fork's fix
         // text -- this core has no domain/region concepts, so the fix
         // shape differs). The `!$veda_pcc_violation` guard above is
         // FETCH-side only; it was never extended to the DATA-side
         // violations OCL.C/OCS.C and plain Bind can themselves raise.
         // An access that BOTH violates (bad tag/seal/perm/bounds, or a
         // Bind ODT-miss/wrong-owner) AND misses its TCM tier still made
         // `$veda_dram_stall_req` fire, which drives `$veda_dram_busy`,
         // which the `$pc` mux above ranks ABOVE `$pc_src` -- discarding
         // the same-cycle trap redirect to `mtvec` while every trap
         // STATE effect (PCC reset to unbounded, etc.) still fires: a
         // real compartment escape, not just a missed-handler bug.
         // `!$veda_bind_trap` is added to the bind arm (safe for all
         // three bind modes: `$veda_bind_trap` is defined only in terms
         // of `$is_veda_bind_plain`, so it reads a constant 0 for
         // Bind-NoTrap/Rebind, changing nothing for those -- neither
         // ever traps in this core, only plain Bind does, Milestone 13).
         // `!$veda_oclc_violation && !$veda_ocsc_violation` is added to
         // the capability-width arm (mutually exclusive by construction,
         // `$is_veda_ocl_c`/`$is_veda_ocs_c` can't both be the decoded
         // instruction). Strictly monotone, matching the Linux-line
         // fix's own reasoning: this can only ever REMOVE a stall, on a
         // path that traps anyway via `$veda_trap_taken`'s own existing
         // OR-list -- it cannot create a stall that did not exist, so it
         // cannot open a new escape. FIX 2 (the Linux line's own
         // deliberately-deferred correctness fix for stalls swallowing
         // ordinary taken branches/JAL/JALR/OCInvoke/OCReturn/mret, which
         // needs restructuring the `$pc` mux itself) is explicitly NOT
         // attempted in this same pass, for the identical reason that
         // fork gave: it is not monotone and needs its own test.
         $veda_dram_stall_req =
            !$veda_pcc_violation && !(>>1$veda_dram_busy) &&
            ((($is_veda_bind_plain || $is_veda_bind_notrap || $is_veda_rebind) && !$veda_odt_tcm_hit && !$veda_bind_trap) ||
             (($is_veda_ocl_c || $is_veda_ocs_c) && !$veda_capmem_tcm_hit && !$veda_oclc_violation && !$veda_ocsc_violation &&
              // NEW (2026-08-19 widening): the new alignment-violation
              // signals must join this guard for the identical R21 reason
              // the tag/seal/perm/bounds violations already do above --
              // both are only ever true on a path that traps anyway via
              // $veda_trap_taken's own OR-list, so this can only REMOVE a
              // stall, never create one (same strictly-monotone argument
              // the original R21 fix's own comment makes).
              !$veda_oclc_align_violation && !$veda_ocsc_align_violation));
         // Same-cycle load (NOT >>1$veda_dram_stall_req) -- loading on the
         // >>1-delayed request would add one extra spurious cycle before
         // the counter reflects the real remaining wait, the exact
         // off-by-one caught by hand-tracing above.
         $veda_dram_stall_cnt[7:0] =
            $reset                       ? 8'd0 :
            $veda_dram_stall_req         ? DRAM_EXTRA_CYCLES[7:0] :
            (>>1$veda_dram_stall_cnt != 8'd0) ? (>>1$veda_dram_stall_cnt - 8'd1) :
                                                 8'd0;
         // Real bug caught only by actually running the regression (not
         // just hand-tracing the nonzero-E case): $veda_dram_stall_req can
         // fire on any DRAM-tier access attempt REGARDLESS of
         // DRAM_EXTRA_CYCLES's own value (it's a pure decode/idle check,
         // never compared against E). Without the explicit
         // `DRAM_EXTRA_CYCLES != 0` guard here, busy would go true for
         // exactly one spurious cycle even at the E=0 regression floor
         // (stall_cnt loads to 0 that same cycle, but stall_req alone
         // still made busy true), forcing one spurious NOP after every
         // single Bind/OCL.C/OCS.C even with the feature nominally "off"
         // -- confirmed as a real functional regression (Milestone 4 and
         // Milestone 10's own POSITIVE tests genuinely failed) before
         // this fix, not a hypothetical concern.
         $veda_dram_busy = ($veda_dram_stall_cnt != 8'd0) ||
                            ($veda_dram_stall_req && (DRAM_EXTRA_CYCLES != 0));

         // mode=11 (VEDA_BIND_RESERVED, Sail: Illegal_Instruction()) --
         // deliberately produces no write-enable anywhere below, this
         // file's own established floor for "no trap to raise" (matches
         // e.g. an out-of-range funct7 producing no decode match at all).
         $veda_rd_cap[3:0]    = $instr[10:7];

         // OCL/OCS: rs1 is a capability register at instr[18:15] (4
         // bits), rs2 = instr[24:20] (already extracted as $rs2, the
         // fresh per-access GPR offset), rd = instr[11:7] (already
         // extracted as $rd -- OCL's GPR load destination, or OCS's
         // GPR store-value source). Reused as-is below by OCA/NMC_ADD/
         // Veda-Atomic too -- all of Custom-0/2's R-type instructions and
         // Custom-1 share the identical rs1-capability field position, so
         // this one signal (and $rs2/$rd) serves all of them without a
         // per-instruction rename.
         $veda_ocl_ocs_rs1_cap[3:0] = $instr[18:15];

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 2 DECODE — OCA (Custom-2), NMC_ADD.W/D
         //  (Custom-0), Veda-Atomic (Custom-1, its own separate opcode).
         //  Build order matters here and is real, not arbitrary: OCA must
         //  exist before NMC_ADD/Veda-Atomic are usefully testable, since
         //  Milestone 1's Object-Bind always resets a capability's Offset
         //  to 0, and NMC_ADD/Veda-Atomic both operate on the capability's
         //  own *persistent* Offset (VEDA_CORE_SPEC.md Section 1: "OCA is
         //  the missing instruction that lets software position a
         //  capability register at an exact target offset before issuing
         //  an atomic or NMC operation") -- the identical dependency
         //  order already used when this same subset was built in Sail.
         // ─────────────────────────────────────────────────────────
         $op_is_custom2 = ($opcode == 7'b1011011);
         $is_veda_oca   = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0001010);

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 3 DECODE — the Veda-Cap query family
         //  (funct3 = 000, dest-kind = GPR) and CSetBounds/CSetBoundsExact
         //  (funct3 = 001, dest-kind = Capability, same as OCA). No
         //  permission or bounds checks on the query family at all --
         //  deliberately, matching CHERI's own real principle (already
         //  applied once in Sail): capability *metadata* is always
         //  inspectable, even on a sealed or untagged capability.
         // ─────────────────────────────────────────────────────────
         $is_veda_cgetbase   = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000000);
         $is_veda_cgetlen    = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000001);
         $is_veda_cgetperm   = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000010);
         $is_veda_cgettag    = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000011);
         $is_veda_cgettype   = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000100);
         $is_veda_cgetaddr   = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000101);
         $is_veda_cgetoffset = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000110);
         $is_veda_capquery = $is_veda_cgetbase || $is_veda_cgetlen || $is_veda_cgetperm ||
                              $is_veda_cgettag || $is_veda_cgettype || $is_veda_cgetaddr || $is_veda_cgetoffset;

         // Real, honest observation already recorded once in Sail, not
         // re-litigated here: CSetBoundsExact's real distinction from
         // CSetBounds ("traps instead of rounding if not exactly
         // representable") only matters for a *compressed* bounds
         // encoding CHERI has and this design deliberately doesn't
         // (VEDA_CORE_SPEC.md Section 2's `Length` is a plain, uncompressed
         // 16-bit value -- every value is exactly representable). Both
         // decode separately (their real, distinct funct7 slots are kept,
         // matching the spec) but share one identical execute path below.
         $is_veda_csetbounds      = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0001000);
         $is_veda_csetboundsexact = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0001001);
         $is_veda_csetbounds_either = $is_veda_csetbounds || $is_veda_csetboundsexact;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 6: CSeal/CUnseal (VEDA_CORE_SPEC.md
         //  Section 1's already-decided encoding, a direct, unmodified
         //  field-for-field match to CHERI-RISC-V's own real CSeal/
         //  CUnseal shape). funct7=0010000/0010001, same Custom-2
         //  opcode/funct3=001 dest-is-capability-register convention as
         //  OCA/CSetBounds. The first RTL instructions where `rs2` is
         //  ALSO a capability register (the "type-authority" operand),
         //  not a GPR -- a genuinely new operand pattern, decoded below.
         // ─────────────────────────────────────────────────────────
         $is_veda_cseal   = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010000);
         $is_veda_cunseal = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010001);
         // rs2 as a capability register: instr[23:20] (4 bits) -- the
         // same relative position/width as $veda_ocl_ocs_rs1_cap's own
         // instr[18:15] rs1-capability field, just shifted to the rs2
         // slot (instr[24:20]'s low 4 bits), mirroring
         // VEDA_CORE_SPEC.md Section 1's own stated field-position
         // consistency principle.
         $veda_cseal_cunseal_rs2_cap[3:0] = $instr[23:20];

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 4 DECODE — a minimal, real privilege
         //  gate (MILESTONE_PLAN.md's own Milestone 4 addendum has the
         //  full reasoning for why this couldn't be deferred further
         //  once ODT-Populate exists), and ODT-Populate/ODT-Destroy
         //  themselves (VEDA_CORE_SPEC.md Section 5.1's already-decided
         //  encoding). `veda.droppriv` lives in Custom-3 -- explicitly
         //  "Reserved, unallocated" in this file's own ISA summary since
         //  the very first draft, exactly the room this project has
         //  repeatedly reserved for real, later growth rather than
         //  overloading an already-populated opcode.
         // ─────────────────────────────────────────────────────────
         $op_is_custom3 = ($opcode == 7'b1111011);
         // funct7 = 0000000 claims one Custom-3 slot, leaving room for
         // more (the same "reserve, don't exhaust" principle already
         // used for Custom-3 as a whole).
         $is_veda_droppriv = $op_is_custom3 && ($funct7 == 7'b0000000);

         // rs1/rs2/rd here are ordinary GPRs, not capability registers --
         // ODT-Populate/Destroy operate on raw Object_ID/descriptor
         // *values*, not on an already-bound capability (Section 5.1:
         // "rs1 = a GPR holding Object_ID, mirrors Object-Bind's own rs1
         // convention field-for-field"). $rs1/$rs2/$rd are already the
         // right, full 5-bit GPR fields -- no new decode signal needed.
         $is_veda_odt_populate = $op_is_custom0 && ($funct3 == 3'b000) && ($funct7 == 7'b0000011);
         $is_veda_odt_destroy  = $op_is_custom0 && ($funct3 == 3'b001) && ($funct7 == 7'b0000011);
         // RTL Milestone 18 (mirrors Sail's VEDA_ODT_POPULATE_FAST,
         // veda_ocl_insts.sail): same funct3 as plain Populate (grouping
         // with the Populate family), funct7 = 0000100 -- the next free
         // Custom-0 slot, verified free by grepping every existing
         // $is_veda_* decode condition in this file before choosing it.
         // rs2 = Base directly (no packed descriptor); Length/Perms come
         // from $veda_attr (defined further below), not from rs2.
         $is_veda_odt_populate_fast = $op_is_custom0 && ($funct3 == 3'b000) && ($funct7 == 7'b0000100);

         $op_is_custom1   = ($opcode == 7'b0101011);
         // Op-select (funct7[31:27]) reuses real RISC-V Zaamo's own
         // encoding verbatim -- VEDA_CORE_SPEC.md Section 1's own text
         // already names the identical operation set, and this project's
         // established practice throughout is to reuse a real, verified
         // encoding wherever the concept transfers directly, not invent
         // new bit values (the same reasoning already applied when this
         // same op-select table was built once already in Sail
         // Milestone V-B). aq/rl (funct7[26:25]) are real, named signals
         // below, matching Sail's own identical decoded-but-unused
         // treatment (veda_atomic_insts.sail's own `_aq`/`_rl`
         // underscore-prefixed parameters) -- fixed this security-audit
         // pass: an earlier version of this comment claimed they were
         // "decoded" when no RTL signal here actually captured them at
         // all, a real documentation/code mismatch caught by direct
         // inspection, not assumed correct from the comment alone. Left
         // unused deliberately -- this core is genuinely single-hart,
         // in-order, with no reordering of memory operations relative
         // to program order ever possible, so aq/rl are trivially
         // satisfied regardless of their value (RVWMO reduces to
         // program order on one hart), not a silently-ignored real
         // ordering requirement. See ATOMIC_AQRL_SAFETY_ANALYSIS.md for
         // the full reasoning and the explicit, load-bearing warning for
         // whoever eventually builds real multi-hart RTL.
         $veda_atomic_aq = $instr[26];
         $veda_atomic_rl = $instr[25];
         `BOGUS_USE($veda_atomic_aq)
         `BOGUS_USE($veda_atomic_rl)
         $veda_atomic_op[4:0] = $instr[31:27];
         // Width scoped to D (64-bit) only this milestone, matching the
         // established D-only precedent already used for OCL.D/OCS.D and
         // Sail's own Veda-Atomic scope.
         $is_veda_atomic  = $op_is_custom1 && ($funct3 == 3'b011);

         $is_veda_nmc_add_w = $op_is_custom0 && ($funct3 == 3'b010) && ($funct7 == 7'b0000010);
         $is_veda_nmc_add_d = $op_is_custom0 && ($funct3 == 3'b011) && ($funct7 == 7'b0000010);

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: ODT lookup for Object-Bind, by Object_ID read
         //  from the GPR named by $rs1. Milestone 1's 256-entry ODT
         //  (MILESTONE_PLAN.md item 1) indexes on only the low 8 bits of
         //  the real 23-bit Object_ID field -- a real, stated scope
         //  boundary, not silent truncation.
         // ─────────────────────────────────────────────────────────
         $veda_object_id[22:0] = $rs1_data[22:0];
         // MILESTONE 24 Stage 2: judged on the FULL 23-bit Object_ID
         // above, NOT the truncated low-8-bit $veda_odt_idx below -- a
         // TCM-tier placement decision must never be judged on the
         // already-aliased index, or a DRAM-tier object sharing the same
         // low byte as a TCM-tier one could be misclassified, the exact
         // class of bug Milestone 15 (below) already found and fixed for
         // ODT lookups generally. This must not reintroduce a variant of
         // it for latency classification specifically.
         $veda_odt_tcm_hit = ($veda_object_id < {17'b0, TCM_ODT_ENTRIES[5:0]});
         $veda_odt_idx[7:0]    = $veda_object_id[7:0];
         $veda_odt_addr[31:0]  = ODT_BASE + ({24'b0, $veda_odt_idx} * 32'd16);
         $veda_odt_base[31:0]   = {odt_mem[$veda_odt_addr+3], odt_mem[$veda_odt_addr+2], odt_mem[$veda_odt_addr+1], odt_mem[$veda_odt_addr+0]};
         // Length widened 16->20 bits, 2026-08-19 (mirrors veda_types.sail's
         // odt_entry.Length). The extra 4 bits reuse byte +14, previously
         // fully spare -- the same "consume a previously-unused spare byte
         // of this same 16-byte struct" convention Milestone 15 (+11/+12)
         // and Milestone 16 (+13) already established here. 15 of 16
         // bytes are now used; +15 remains spare.
         $veda_odt_length[19:0] = {odt_mem[$veda_odt_addr+14][3:0], odt_mem[$veda_odt_addr+5], odt_mem[$veda_odt_addr+4]};
         $veda_odt_perms[15:0]  = {odt_mem[$veda_odt_addr+7], odt_mem[$veda_odt_addr+6]};
         $veda_odt_gen[7:0]     = odt_mem[$veda_odt_addr+8];
         // RTL MILESTONE 15: the low-8-bit ODT index above aliases any
         // two Object_IDs sharing a low byte onto the same physical
         // slot -- found via a real empirical reproduction
         // (ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 1), not a
         // theoretical concern: Object_ID=100 and Object_ID=356
         // silently overwrote each other's ODT metadata with no trap,
         // no error, no signal to either party. Bytes +11/+12 of the
         // 16-byte entry were real, allocated-but-unused space ("88
         // bits used of 128 available", per this file's own header
         // comment above) -- store the real upper 15 bits of Object_ID
         // there on every Populate (below), and require it to match on
         // every lookup here. A low-byte collision with a DIFFERENT
         // real Object_ID now reads as "not found" (folded into
         // $veda_odt_valid itself, so every existing downstream
         // consumer -- owner_ok, bind_trap, rebind_ok -- inherits the
         // fix with no other change needed) instead of silently
         // returning a different object's metadata.
         $veda_odt_id_hi[14:0] = {odt_mem[$veda_odt_addr+12][6:0], odt_mem[$veda_odt_addr+11]};
         $veda_odt_id_match    = ($veda_odt_id_hi == $veda_object_id[22:8]);
         $veda_odt_valid        = odt_mem[$veda_odt_addr+9][0] && $veda_odt_id_match;
         // Milestone 12: the owner-hart byte, read alongside every other
         // ODT field above -- an object with no live owner yet
         // (VEDA_OWNER_UNOWNED), or one this same hart already owns, is
         // fair game for Bind/Rebind to claim (or re-claim, idempotently)
         // -- mirrors veda_bind_insts.sail's own `owner_ok` boolean
         // field-for-field.
         $veda_odt_owner[7:0]  = odt_mem[$veda_odt_addr+10];
         $veda_owner_ok        = ($veda_odt_owner == VEDA_OWNER_UNOWNED) || ($veda_odt_owner == MHARTID);
         // RTL MILESTONE 16: the 8-bit generation counter, empirically
         // confirmed to wrap after 256 destroy/re-populate cycles on the
         // same slot, creates a real ABA-problem use-after-free false
         // negative (a capability cached before the wrap can pass the
         // staleness check again once the count wraps back to its old
         // value) -- ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 2,
         // reproduced empirically before any fix was designed. Simply
         // saturating the counter at 0xFF instead of wrapping is NOT
         // sufficient by itself -- every future re-populate of the slot
         // would then also land on 0xFF, making every incarnation from
         // that point on indistinguishable from every other, a
         // *permanent* ambiguity instead of a periodic one. The real fix
         // needs a second bit: once generation would wrap, PERMANENTLY
         // retire the slot (refuse any future ODT-Populate against it)
         // instead of reusing 0xFF forever. Uses 1 bit of byte +13, real,
         // allocated-but-unused space after Milestone 15's own use of
         // +11/+12 ("88 bits used of 128 available" plus Milestone 15's
         // 15 more still leaves 3 full spare bytes).
         $veda_odt_retired     = odt_mem[$veda_odt_addr+13][0];
         // Milestone 12: plain Bind's own real, genuine hard-trap --
         // a LIVE object owned by a genuinely different hart, distinct
         // in kind from "object not found" (Milestone 13, below). Joins
         // the combined trap-taken family below. Bind-NoTrap never
         // participates here at all (matches its own established
         // soft-fail-always convention; only plain Bind is gated by
         // $is_veda_bind_plain), mirroring veda_bind_insts.sail's own
         // exact mode split.
         $veda_bind_owner_violation = $is_veda_bind_plain && $veda_odt_valid && !$veda_owner_ok;
         // Milestone 13: plain Bind's own second real hard-trap reason --
         // object-not-found ($veda_odt_valid=0) -- closing the gap
         // Milestone 9 itself named and deliberately deferred
         // (MILESTONE_9_RESULTS.md: "doing so would, for the first time,
         // make RTL's plain Bind and Bind-NoTrap behaviorally different"
         // -- a concern Milestone 12 already made moot, since plain
         // Bind's own owner-violation trap above already created that
         // exact divergence). Mutually exclusive with
         // $veda_bind_owner_violation by construction (one requires
         // $veda_odt_valid, the other requires !$veda_odt_valid) --
         // combined into one umbrella $veda_bind_trap below, mirroring
         // veda_bind_insts.sail's own catch-all else-chain exactly
         // (owner check, THEN object-not-found, mutually exclusive
         // outcomes of the same `e.valid` test).
         $veda_bind_notfound_violation = $is_veda_bind_plain && !$veda_odt_valid;
         $veda_bind_trap = $veda_bind_owner_violation || $veda_bind_notfound_violation;
         $veda_bind_cause[4:0] = $veda_bind_owner_violation ? 5'h06 : 5'h05;

         // ─────────────────────────────────────────────────────────
         //  RTL Milestone 8: Rebind reads its OWN destination register
         //  (rd, not rs1) as its "current capability" input -- needed
         //  to check whether rd is already sealed (veda_types.sail:
         //  isSealedCap(c) = c.otype != 0xFFFF), matching Sail's exact
         //  rule (VEDA_CORE_SPEC.md Section 4/Section 1's manipulate-
         //  vs-use split): a Rebind targeting an already-sealed
         //  capability register soft-fails (Tag cleared, ODT refresh
         //  skipped) rather than trapping, joining OCA/CSetBounds's own
         //  soft-fail family. $veda_object_id/$veda_odt_* above already
         //  serve as Rebind's ODT lookup too (Sail computes `object_id`
         //  and `odt_lookup` identically for every bind mode, branching
         //  only afterward) -- no separate ODT read needed here.
         // ─────────────────────────────────────────────────────────
         $veda_rdcap_otype[15:0] = /vreg[$veda_rd_cap]$otype;
         $veda_rebind_sealed     = ($veda_rdcap_otype != 16'hFFFF);
         // Milestone 12: a wrong-owner ODT entry joins "sealed rd" and
         // "ODT miss" as a THIRD soft-fail reason for Rebind -- Rebind
         // never hard-traps for ANY failure reason (Section 1's
         // manipulate-vs-use split), matching veda_bind_insts.sail's own
         // VEDA_REBIND match arm, which folds all three into the same
         // uniform soft-fail branch.
         $veda_rebind_ok         = !$veda_rebind_sealed && $veda_odt_valid && $veda_owner_ok;
         // Milestone 12: real claim/re-claim write-back, shared by both
         // Bind's and Rebind's own success paths below -- mirrors
         // veda_bind_insts.sail's own `claimed_entry`, written on every
         // successful Bind/Bind-NoTrap/Rebind regardless of whether
         // owner_hart was already MHARTID or VEDA_OWNER_UNOWNED (an
         // idempotent re-claim is still a real write, matching Sail
         // exactly). Deliberately excludes plain Bind's own hard-trap
         // path ($veda_bind_owner_violation, defined further below) --
         // mutually exclusive by construction, since that path requires
         // !$veda_owner_ok while this one requires $veda_owner_ok.
         $veda_bind_claim_en     = ($is_veda_bind_plain || $is_veda_bind_notrap) &&
                                    $veda_odt_valid && $veda_owner_ok;
         $veda_rebind_claim_en   = $is_veda_rebind && $veda_rebind_ok;
         $veda_owner_claim_en    = $veda_bind_claim_en || $veda_rebind_claim_en;
         // Only consumed by the trailing raw \SV always_ff block below,
         // the same real reason $veda_odtpd_new_gen/etc. already needed
         // this (invisible to SandPiper's own TLV-level dependency
         // tracking otherwise).
         `BOGUS_USE($veda_owner_claim_en)

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 4: ODT-Populate/ODT-Destroy
         //  (VEDA_CORE_SPEC.md Section 5.1's real, decided encoding and
         //  data model, mirrored field-for-field from the already-working
         //  Sail implementation, veda_ocl_insts.sail's own
         //  VEDA_ODT_POPULATE/VEDA_ODT_DESTROY). rs1 = Object_ID -- the
         //  exact same GPR-to-index computation Object-Bind's own lookup
         //  above already performs, so $veda_odt_addr/$veda_odt_valid/
         //  $veda_odt_gen/$veda_odt_base/$veda_odt_length/$veda_odt_perms
         //  above ARE this instruction's own "old_entry" read -- reused
         //  directly, not recomputed.
         //
         //  Gated on $priv, not a capability check -- Section 5.1's own
         //  stated, honest deviation (no spare R-type operand for a
         //  capability-authority operand), realized here as
         //  MILESTONE_PLAN.md's Milestone 4 addendum's real $priv gate:
         //  a violation suppresses the odt_mem write below exactly like
         //  every other soft-fail in this file (no trap infrastructure to
         //  raise a real Illegal_Instruction() into, the identical real
         //  constraint Sail itself has none of here either -- Sail's own
         //  version genuinely traps because Sail has real privilege/trap
         //  machinery; this RTL's honest floor is "the write doesn't
         //  happen").
         // ─────────────────────────────────────────────────────────
         // RTL Milestone 11: an OR, not a replacement -- ordinary M-mode
         // privilege still always suffices on its own (unchanged from
         // Milestone 4), and a live, unsealed, PERMIT_ACCESS_SYSTEM_
         // REGISTERS-carrying capability delegated into the ODA (via
         // OSpecialRW, below) is now a second, independent, real
         // authorization path -- closing NEXT_STEPS_ROADMAP.md §2.5's
         // own named gap ("a real capability-permission-gated version
         // would need Veda-Core's own privileged-capability model
         // designed first"). $veda_oda_authorized is defined further
         // below (after $veda_rs1cap_* it depends on) but referenced
         // here -- a real forward reference, the same combinational-
         // elaboration-is-order-independent pattern already used
         // throughout this file (e.g. $veda_trap_taken referencing
         // per-family violation signals defined later in the file).
         // RTL MILESTONE 16 (continued): a retired slot can never be
         // re-populated -- folded into the SAME $veda_odt_populate
         // _violation signal that already gates privilege, so it reuses
         // the established soft-no-op-on-violation write path with no
         // new plumbing.
         // RTL Milestone 18: shares this same violation signal with
         // VEDA_ODT_POPULATE_FAST (identical privilege/retired gate on
         // both, mirroring Sail's own two execute clauses, which each
         // repeat the identical check rather than sharing a helper).
         $veda_odt_populate_violation = ($is_veda_odt_populate || $is_veda_odt_populate_fast) &&
                                          (!($priv || $veda_oda_authorized) || $veda_odt_retired);
         $veda_odt_destroy_violation  = $is_veda_odt_destroy  && !($priv || $veda_oda_authorized);

         // Sail's own real rule: repopulating a still-valid slot bumps
         // generation too, not just Destroy -- a stale capability's
         // cached generation must stop matching regardless of whether
         // software destroyed the old entry first or overwrote it
         // directly. Destroy always bumps (old entry may or may not have
         // been valid; either way the slot's identity changes).
         // RTL MILESTONE 16: once already at 0xFF, freeze instead of
         // wrapping back to 0 -- the retirement write-back below (near
         // odt_mem[...+13]) is what actually stops the slot from ever
         // being reused once this point is reached.
         $veda_odtpd_new_gen[7:0] = ($is_veda_odt_destroy || $veda_odt_valid) ?
                                    (($veda_odt_gen == 8'hFF) ? 8'hFF : ($veda_odt_gen + 8'd1)) : $veda_odt_gen;
         $veda_odtpd_new_retired = $veda_odt_retired ||
                                    (($is_veda_odt_destroy || $veda_odt_valid) && ($veda_odt_gen == 8'hFF));
         // Populate: Base/Length/Perms come from rs2's packed descriptor
         // (Section 5.1: Base[31:0] in bits[63:32], Length[15:0] in
         // bits[31:16], Perms[15:0] in bits[15:0]). Populate-Fast (RTL
         // Milestone 18): Base = rs2 directly (no packing -- the whole
         // real point, a clean 2-instruction `la`/`li` suffices instead
         // of a full 6-instruction `li`), Length/Perms = $veda_attr
         // (defined further below). Destroy: preserved unchanged from
         // old_entry, matching Sail's own VEDA_ODT_DESTROY exactly (only
         // valid/generation actually change).
         $veda_odtpd_new_base[31:0]   = $is_veda_odt_populate      ? $rs2_data[63:32] :
                                          $is_veda_odt_populate_fast ? $rs2_data[31:0]  : $veda_odt_base;
         // Plain Populate's descriptor keeps its existing 16-bit Length
         // slice (descriptor[31:16]), unchanged encoding, still capped at
         // 64KiB by design (NEXT_STEPS_ROADMAP.md "Break 3", mirrors
         // veda_ocl_insts.sail's VEDA_ODT_POPULATE) -- explicitly
         // zero-extended into the new 20-bit field, matching Sail's own
         // zero_extend(descriptor[31..16]). Populate-Fast reads the real
         // 20-bit Length straight from the widened $veda_attr[35:16]
         // (2026-08-19 widening, mirrors veda_attr[35..16] in Sail).
         $veda_odtpd_new_length[19:0] = $is_veda_odt_populate      ? {4'b0, $rs2_data[31:16]} :
                                          $is_veda_odt_populate_fast ? $veda_attr[35:16]        : $veda_odt_length;
         $veda_odtpd_new_perms[15:0]  = $is_veda_odt_populate      ? $rs2_data[15:0]  :
                                          $is_veda_odt_populate_fast ? $veda_attr[15:0]  : $veda_odt_perms;
         // Only consumed by the trailing raw \SV always_ff block below
         // (invisible to SandPiper's own TLV-level dependency tracking,
         // same real reason $veda_ocs_value/$veda_nmc_add_result_d/
         // $veda_atomic_result all needed this).
         `BOGUS_USE($veda_odtpd_new_gen)
         `BOGUS_USE($veda_odtpd_new_base)
         `BOGUS_USE($veda_odtpd_new_length)
         `BOGUS_USE($veda_odtpd_new_perms)

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: Capability Register File (16 x 128-bit-equivalent
         //  fields + 1 Tag bit each), array-of-registers exactly mirroring
         //  /xreg's own real, already-proven convention below -- not a
         //  new idiom. Written only by Object-Bind this milestone (OCA/
         //  CSetBounds/CSeal/Rebind, which partially update individual
         //  fields, don't exist in RTL yet).
         // ─────────────────────────────────────────────────────────
         /vreg[15:0]
            // Two independent write sources this milestone: Bind (full
            // register write, from the ODT) and OCA. A real bug was found
            // and fixed here, caught by the Milestone 2 smoke test, not
            // assumed correct from the source alone: OCA does NOT do a
            // partial Tag+Offset-only update -- CHERI's real semantics
            // (and this project's own already-verified Sail
            // implementation, veda_cap_insts.sail's VEDA_OCA) are "rd =
            // a full copy of rs1's fields, with Offset replaced" -- an
            // *initial* RTL draft only wrote Tag+Offset, wrongly assuming
            // rd's other fields were already correct from some earlier
            // Bind. They aren't, in general (OCA's rd and rs1 are often
            // *different* registers). Fixed: OCA now copies every field
            // from $veda_rs1cap_* (the same rs1 capability already read
            // for the checks above), exactly mirroring Bind's own
            // structure but sourced from rs1 instead of the ODT.
            // RTL Milestone 8: restricted from "any $is_veda_bind" to
            // just the two modes that share this write path (plain
            // Bind + Bind-NoTrap, behaviorally identical on this RTL's
            // no-trap floor -- see the mode-decode comment above). A
            // real gap closed here: previously mode=10/11 fell through
            // to this same path too, silently mis-executing Rebind as
            // plain Bind. Rebind now has its own write path below.
            // Milestone 12/13: plain Bind's own two hard-trap reasons
            // (wrong-owner, object-not-found -- $veda_bind_trap, the
            // combined umbrella) must leave rd COMPLETELY untouched, not
            // even Tag cleared -- matches Sail exactly (veda_trap()
            // diverts control flow before wC()/wCTag() are ever called
            // on either path). Mirrors OCInvoke's own identical
            // `!violation` exclusion already established for this same
            // reason (RTL Milestone 10). Bind-NoTrap can never set
            // $veda_bind_trap (only plain Bind can), so its own two
            // soft-fail reasons below are unaffected by this exclusion.
            $bind_wr_en = (|cpu>>1$is_veda_bind_plain || |cpu>>1$is_veda_bind_notrap) &&
                          !|cpu>>1$veda_bind_trap &&
                          (|cpu>>1$veda_rd_cap == #vreg);
            // Rebind: a genuinely different write shape from every
            // other source in this mux -- on failure (sealed rd, or an
            // ODT miss) only Tag changes (to 0); every other field,
            // INCLUDING Offset even on success, is preserved untouched
            // (VEDA_CORE_SPEC.md Section 4: "Offset preserved across
            // relocation" -- Rebind never resets it, unlike plain
            // Bind). Gated separately per-field below via
            // $veda_rebind_ok, not folded into a single unconditional
            // $rebind_wr_en write like every other source here.
            $rebind_wr_en = |cpu>>1$is_veda_rebind &&
                            (|cpu>>1$veda_rd_cap == #vreg);
            $oca_wr_en  = |cpu>>1$is_veda_oca &&
                          (|cpu>>1$veda_rd_cap == #vreg);
            // Milestone 3 addition: CSetBounds/CSetBoundsExact, a third
            // independent write source, same shared $veda_rd_cap
            // position. Applies the fix already learned from OCA's own
            // real bug: copies every non-overridden field from rs1
            // ($veda_rs1cap_*), not a partial update.
            $csetbounds_wr_en = |cpu>>1$is_veda_csetbounds_either &&
                                (|cpu>>1$veda_rd_cap == #vreg);
            // Milestone 6 addition: CSeal/CUnseal, a 4th/5th independent
            // write source, same shared $veda_rd_cap position. Same
            // copy-cs1-fields-then-override-one-field skeleton already
            // proven for OCA/CSetBounds -- here the one overridden field
            // is otype (cs2.Offset for CSeal, UNSEALED_OTYPE for
            // CUnseal), everything else copies from cs1 ($veda_rs1cap_*)
            // unchanged, mirroring veda_cap_insts.sail's own struct
            // literal field-for-field.
            $cseal_wr_en   = |cpu>>1$is_veda_cseal &&
                              (|cpu>>1$veda_rd_cap == #vreg);
            $cunseal_wr_en = |cpu>>1$is_veda_cunseal &&
                              (|cpu>>1$veda_rd_cap == #vreg);
            // Milestone 7 addition: OCL.C, a 6th independent write
            // source, same shared $veda_rd_cap position -- but a
            // genuinely different KIND of source from every one above:
            // OCA/CSetBounds/CSeal/CUnseal all copy fields from an
            // already-bound rs1 capability register; OCL.C's fields come
            // fresh from memory ($veda_oclc_unpacked_*), unpacked from
            // real bytes a real OCS.C (or nothing at all, if never
            // written) put there -- not from any other capability
            // register.
            // NEW (2026-08-19 widening): !|cpu>>1$veda_oclc_align_violation
            // added -- the identical violation-suppresses-write convention
            // already applied to $veda_oclc_violation just above, now
            // extended to the new 32-byte-alignment violation so a
            // misaligned OCL.C cannot commit whatever bytes happen to sit
            // at the unaligned address (plus whatever the tag store
            // happens to report there) into the destination capability
            // register before the trap redirect takes effect.
            $oclc_wr_en = |cpu>>1$is_veda_ocl_c && !|cpu>>1$veda_oclc_violation &&
                          !|cpu>>1$veda_oclc_align_violation &&
                          (|cpu>>1$veda_rd_cap == #vreg);
            // RTL Milestone 10: OCInvoke's own write source -- a
            // genuinely different KIND of write-enable from every one
            // above: its target is NOT $veda_rd_cap (OCInvoke's own
            // encoding has no destination-capability field at all,
            // matching real CHERI's identical choice -- its outputs are
            // architecturally fixed, not instruction-selectable). Fixed
            // to index 15 (VEDA_IDC_INDEX, the same fixed target already
            // decided and verified in Sail, veda_cap_insts.sail).
            $ocinvoke_wr_en = |cpu>>1$is_veda_ocinvoke && !|cpu>>1$veda_ocinvoke_violation &&
                              (#vreg == 4'd15);
            // RTL Milestone 11: OSpecialRW's own `cd` write -- an
            // ordinary $veda_rd_cap-indexed target (real operand, unlike
            // OCInvoke's fixed index above), receiving the ODA's OWN
            // value from BEFORE this same instruction's write to it
            // (real CHERI's own CSpecialRW semantics: read-then-write,
            // not write-then-read) -- $veda_oda_tag/base/etc. below are
            // already the correct "old" values at this point, since the
            // ODA's own persistent-register update (above) only takes
            // effect on the NEXT cycle.
            $ospecialrw_wr_en = |cpu>>1$is_veda_ospecialrw && !|cpu>>1$veda_ospecialrw_violation &&
                                (|cpu>>1$veda_rd_cap == #vreg);
            // Minimal OS kernel Milestone B: VEDA_CSEALENTRY's own write
            // source -- same shared $veda_rd_cap position, same
            // copy-cs1-fields-then-override-one-field skeleton CSeal
            // already established, but the one overridden field (otype)
            // becomes the fixed 0xFFFE constant rather than a
            // capability-derived value.
            $csealentry_wr_en = |cpu>>1$is_veda_csealentry &&
                                (|cpu>>1$veda_rd_cap == #vreg);
            $tag = (|cpu$reset || |cpu>>1$reset) ? 1'b0 :
                   // Milestone 12: Bind/Bind-NoTrap's own success now
                   // additionally requires owner_ok -- a wrong-owner
                   // live object soft-fails here exactly like an ODT
                   // miss already did (Tag cleared, same as before;
                   // Bind-NoTrap's OTHER fields still carry over from
                   // the wrong object's real ODT entry below, dead
                   // either way once Tag=0 -- the same established,
                   // accepted convention already governing every other
                   // "$bind_wr_en fires unconditionally, only Tag is
                   // gated" soft-fail path in this mux, not a new
                   // concession). Plain Bind's OWN wrong-owner case
                   // never reaches this line at all -- $bind_wr_en
                   // itself is already false then (the exclusion above).
                   $bind_wr_en       ? (|cpu>>1$veda_odt_valid && |cpu>>1$veda_owner_ok) :
                   // Rebind: 1 only on the real success path (rd wasn't
                   // already sealed, AND the ODT entry is valid) --
                   // covers both soft-fail cases (sealed rd; ODT miss)
                   // with the single already-computed $veda_rebind_ok,
                   // matching Sail's own three-way match exactly.
                   $rebind_wr_en     ? |cpu>>1$veda_rebind_ok :
                   $oca_wr_en        ? |cpu>>1$veda_oca_ok :
                   $csetbounds_wr_en ? |cpu>>1$veda_csetbounds_ok :
                   $cseal_wr_en      ? |cpu>>1$veda_cseal_ok :
                   $cunseal_wr_en    ? |cpu>>1$veda_cunseal_ok :
                   // The memory-resident tag, not "load succeeded = 1" --
                   // this is the one real security property Milestone 7
                   // exists to prove (see the load-side comment above).
                   $oclc_wr_en       ? |cpu>>1$veda_oclc_loaded_tag :
                   // OCInvoke: 1 only on the real, already-authorized
                   // success path ($ocinvoke_wr_en itself already
                   // excludes the violation case) -- mirrors Sail's own
                   // unconditional wCTag(VEDA_IDC_INDEX, true) after
                   // every check has passed.
                   $ocinvoke_wr_en   ? 1'b1 :
                   // OSpecialRW's own `cd` = the ODA's Tag from BEFORE
                   // this instruction's own write to it.
                   $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_tag : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_tag : |cpu>>1$veda_oda_tag) :
                   $csealentry_wr_en ? |cpu>>1$veda_csealentry_ok :
                                       $RETAIN;
            $object_id[22:0] = (|cpu$reset || |cpu>>1$reset) ? 23'b0 :
                               $bind_wr_en       ? |cpu>>1$veda_object_id :
                               // Rebind success only -- on failure (sealed
                               // rd / ODT miss), Sail's own execute clause
                               // never calls wC() at all, so every field
                               // below except Tag must fall through to
                               // $RETAIN unchanged, not get overwritten.
                               ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_object_id :
                               ($oca_wr_en || $csetbounds_wr_en || $cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_object_id :
                               $oclc_wr_en       ? |cpu>>1$veda_oclc_unpacked_object_id :
                               // OCInvoke copies cs2's OWN full field set
                               // into c15 (IDC) -- a genuinely different
                               // source capability register from every
                               // other write source above, which all
                               // either come from the ODT or from cs1.
                               $ocinvoke_wr_en   ? |cpu>>1$veda_cs2_object_id :
                               $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_object_id : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_object_id : |cpu>>1$veda_oda_object_id) :
                               $csealentry_wr_en ? |cpu>>1$veda_rs1cap_object_id :
                                                                    $RETAIN;
            $base[31:0] = (|cpu$reset || |cpu>>1$reset) ? 32'b0 :
                          $bind_wr_en       ? |cpu>>1$veda_odt_base :
                          ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_odt_base :
                          $oca_wr_en        ? |cpu>>1$veda_rs1cap_base :
                          $csetbounds_wr_en ? |cpu>>1$veda_csetbounds_new_base :
                          ($cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_base :
                          $oclc_wr_en       ? |cpu>>1$veda_oclc_unpacked_base :
                          $ocinvoke_wr_en   ? |cpu>>1$veda_cs2_base :
                          $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_base : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_base : |cpu>>1$veda_oda_base) :
                          $csealentry_wr_en ? |cpu>>1$veda_rs1cap_base :
                                              $RETAIN;
            // Length widened 16->20 bits, 2026-08-19 (mirrors veda_types.sail's
            // capability.Length: bits(16)->bits(20), NEXT_STEPS_ROADMAP.md
            // "DECIDED, 2026-08-19"). Every RHS source below is independently
            // widened to 20 bits at its own declaration site.
            $length[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                            $bind_wr_en       ? |cpu>>1$veda_odt_length :
                            ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_odt_length :
                            $oca_wr_en        ? |cpu>>1$veda_rs1cap_length :
                            $csetbounds_wr_en ? |cpu>>1$veda_csetbounds_new_length :
                            ($cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_length :
                            $oclc_wr_en       ? |cpu>>1$veda_oclc_unpacked_length :
                            $ocinvoke_wr_en   ? |cpu>>1$veda_cs2_length :
                            $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_length : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_length : |cpu>>1$veda_oda_length) :
                            $csealentry_wr_en ? |cpu>>1$veda_rs1cap_length :
                                                $RETAIN;
            // A fresh Bind always starts at the object's own beginning
            // (VEDA_CORE_SPEC.md Section 4) -- Offset isn't sourced from
            // the ODT at all. OCA is the one instruction that moves it
            // (Section 1) -- the entire reason OCA exists. CSetBounds
            // resets it to 0 too (Section 1: "the narrowed capability's
            // cursor resets to its own new start"). CSeal/CUnseal leave
            // it unchanged (Section 1: "cd.Offset = cs1.Offset" -- sealing
            // is purely a metadata operation, the cursor doesn't move).
            // OCL.C restores whatever Offset a real OCS.C actually
            // stored (the capability's own full state at store time, not
            // reset to 0 -- a capability round-tripped through memory
            // must come back exactly as it was saved).
            // Rebind deliberately has NO branch here at all, success or
            // failure -- this is the one field Rebind never touches
            // (VEDA_CORE_SPEC.md Section 4: "Offset preserved across
            // relocation" -- the entire reason Rebind exists, distinct
            // from plain Bind's own Offset=0 reset above). Falls through
            // to $RETAIN exactly like every cycle $rebind_wr_en is false.
            // OCInvoke copies cs2's OWN Offset unchanged too -- CHERI's
            // own real unsealCap() only ever clears otype, every other
            // field (including the cursor) carries over exactly as it
            // was in the sealed capability.
            // Offset widened 16->20 bits, 2026-08-19 (mirrors veda_types.sail's
            // capability.Offset: bits(16)->bits(20)).
            $offset[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                            $bind_wr_en       ? 20'b0 :
                            $oca_wr_en        ? |cpu>>1$veda_oca_sum[19:0] :
                            $csetbounds_wr_en ? 20'b0 :
                            ($cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_offset :
                            $oclc_wr_en       ? |cpu>>1$veda_oclc_unpacked_offset :
                            $ocinvoke_wr_en   ? |cpu>>1$veda_cs2_offset :
                            $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_offset : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_offset : |cpu>>1$veda_oda_offset) :
                            $csealentry_wr_en ? |cpu>>1$veda_rs1cap_offset :
                                                $RETAIN;
            $perms[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'b0 :
                           $bind_wr_en ? |cpu>>1$veda_odt_perms :
                           ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_odt_perms :
                           ($oca_wr_en || $csetbounds_wr_en || $cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_perms :
                           $oclc_wr_en ? |cpu>>1$veda_oclc_unpacked_perms :
                           $ocinvoke_wr_en ? |cpu>>1$veda_cs2_perms :
                           $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_perms : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_perms : |cpu>>1$veda_oda_perms) :
                           $csealentry_wr_en ? |cpu>>1$veda_rs1cap_perms :
                                                                $RETAIN;
            // A fresh Bind always carries the UNSEALED sentinel (Section
            // 1: "otype always set to 0xFFFF... sealing only ever happens
            // explicitly via CSeal"). OCA/CSetBounds both copy otype from
            // rs1 as-is (Section 1: neither ever seals/unseals; if rs1
            // happened to be sealed, $veda_oca_ok/$veda_csetbounds_ok
            // already clear Tag separately -- the otype *field value*
            // itself still carries over unconditionally, matching
            // CHERI's own real "fields always set, tag conditionally
            // cleared" pattern already used in Sail). CSeal/CUnseal are
            // the one real exception, and the entire reason these two
            // instructions exist: CSeal sets otype = cs2.Offset (the
            // type-authority's own cursor value, the new seal); CUnseal
            // resets it back to 0xFFFF.
            // Rebind's own struct literal (veda_bind_insts.sail) sets
            // otype = UNSEALED_OTYPE unconditionally on success -- same
            // as plain Bind, matching Section 1: "Object-Bind... always
            // populates a freshly-derived capability's otype with
            // 0xFFFF... sealing only ever happens explicitly via CSeal".
            // OCInvoke is the second real "unseal" consumer (after
            // CUnseal) -- unconditionally 0xFFFF on its own success
            // path, matching Sail's own unsealCap() semantics exactly
            // (the entire reason c15/IDC becomes usable again after
            // OCInvoke, not still sealed).
            $otype[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'hFFFF :
                           $bind_wr_en ? 16'hFFFF :
                           ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? 16'hFFFF :
                           ($oca_wr_en || $csetbounds_wr_en) ? |cpu>>1$veda_rs1cap_otype :
                           // WIDENING: |cpu>>1$veda_cs2_offset is now 20 bits;
                           // otype stays 16 bits (veda_types.sail) -- this is
                           // now a real, explicit narrowing slice, mirroring
                           // veda_cap_insts.sail's own VEDA_CSEAL field
                           // literal `otype = cs2.Offset[15..0]`. Written
                           // unconditionally (Tag alone is gated by
                           // $veda_cseal_ok below) -- the same "always write
                           // fields, conditionally clear tag" pattern already
                           // used throughout this mux.
                           $cseal_wr_en   ? |cpu>>1$veda_cs2_offset[15:0] :
                           $cunseal_wr_en ? 16'hFFFF :
                           $oclc_wr_en    ? |cpu>>1$veda_oclc_unpacked_otype :
                           $ocinvoke_wr_en ? 16'hFFFF :
                           // OSpecialRW's own `cd` receives the ODA's
                           // real otype as-is (unlike OCInvoke/CUnseal,
                           // this is a plain read-back, not an unseal --
                           // the ODA's own contents might genuinely be
                           // sealed, and `cd` must show that faithfully).
                           $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_otype : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_otype : |cpu>>1$veda_oda_otype) :
                           // Minimal OS kernel Milestone B: VEDA_CSEALENTRY's
                           // one overridden field -- the fixed 0xFFFE
                           // (VEDA_OTYPE_SENTRY) constant, unconditionally,
                           // mirroring CSeal's own "otype = the new seal"
                           // pattern above but with a fixed value instead of
                           // a capability-derived one.
                           $csealentry_wr_en ? 16'hFFFE :
                                                                $RETAIN;
            // Cached generation, for the staleness re-check below. OCL.C
            // restores the generation a real OCS.C actually stored --
            // matching the Sail model's own veda_cap_unpack exactly
            // (Reserved is packed/unpacked like every other field, not
            // special-cased).
            $reserved[7:0] = (|cpu$reset || |cpu>>1$reset) ? 8'b0 :
                             $bind_wr_en ? |cpu>>1$veda_odt_gen :
                             // Reserved = e.generation on Rebind success --
                             // the entire point of a Rebind refresh: the
                             // capability's cached generation must move
                             // forward to the ODT slot's CURRENT
                             // generation, or the very next dereference's
                             // own staleness re-check ($veda_gen_stale
                             // below) would immediately reject the
                             // freshly-rebound capability as stale.
                             ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_odt_gen :
                             ($oca_wr_en || $csetbounds_wr_en || $cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_reserved :
                             $oclc_wr_en ? |cpu>>1$veda_oclc_unpacked_reserved :
                             $ocinvoke_wr_en ? |cpu>>1$veda_cs2_reserved :
                             $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_reserved : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_reserved : |cpu>>1$veda_oda_reserved) :
                             $csealentry_wr_en ? |cpu>>1$veda_rs1cap_reserved :
                                                                  $RETAIN;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: OCL.D/OCS.D checks. Real hard-trap enforcement
         //  (VEDA_CORE_SPEC.md Section 3's mcause=0x18 convention) has no
         //  RTL infrastructure to land in yet -- this core has no
         //  privileged/trap architecture at all (MILESTONE_PLAN.md item
         //  2). A violation instead suppresses the write: $reg_write is
         //  gated off for OCL, the elfmem write below is gated off for
         //  OCS. $veda_violation is exposed so the real security property
         //  (an illegal access cannot corrupt state) is testable now.
         // ─────────────────────────────────────────────────────────
         $veda_rs1cap_tag           = /vreg[$veda_ocl_ocs_rs1_cap]$tag;
         $veda_rs1cap_base[31:0]    = /vreg[$veda_ocl_ocs_rs1_cap]$base;
         $veda_rs1cap_length[19:0]  = /vreg[$veda_ocl_ocs_rs1_cap]$length;
         $veda_rs1cap_perms[15:0]   = /vreg[$veda_ocl_ocs_rs1_cap]$perms;
         $veda_rs1cap_otype[15:0]   = /vreg[$veda_ocl_ocs_rs1_cap]$otype;
         $veda_rs1cap_object_id[22:0] = /vreg[$veda_ocl_ocs_rs1_cap]$object_id;
         $veda_rs1cap_reserved[7:0] = /vreg[$veda_ocl_ocs_rs1_cap]$reserved;
         // Milestone 2 addition: Offset wasn't read anywhere in Milestone
         // 1 (OCL/OCS use a fresh per-access GPR offset, not the
         // capability's own persistent one), so it never got promoted to
         // a top-level signal at all -- OCA/NMC_ADD/Veda-Atomic all need
         // it, so it's added here.
         $veda_rs1cap_offset[19:0] = /vreg[$veda_ocl_ocs_rs1_cap]$offset;

         // Generation re-check: a fresh, independent ODT lookup by the
         // *capability's own cached* Object_ID (distinct from Bind's own
         // lookup above, which is keyed by whatever the GPR $rs1 holds
         // *now* -- these are two different address computations that
         // happen to share the same odt_mem array). Included from the
         // start this milestone rather than reproducing the real gap
         // found and fixed in Sail Milestone V-B (MILESTONE_PLAN.md item
         // 3) -- not independently testable until a real ODT-Destroy
         // exists in RTL (a later milestone), same real caveat V-A/V-B
         // had in Sail.
         $veda_check_odt_idx[7:0]   = $veda_rs1cap_object_id[7:0];
         $veda_check_odt_addr[31:0] = ODT_BASE + ({24'b0, $veda_check_odt_idx} * 32'd16);
         $veda_check_odt_gen[7:0]   = odt_mem[$veda_check_odt_addr+8];
         // RTL MILESTONE 15 (same fix as the Bind-side lookup above):
         // the dereference-time re-check must also confirm the slot
         // still holds the SAME real Object_ID the capability was bound
         // to -- otherwise a capability for Object_ID=100 could keep
         // successfully dereferencing after Object_ID=356 (a low-byte
         // alias) took over slot 100, since generation/valid alone
         // can't tell the two apart.
         $veda_check_odt_id_hi[14:0] = {odt_mem[$veda_check_odt_addr+12][6:0], odt_mem[$veda_check_odt_addr+11]};
         $veda_check_odt_id_match    = ($veda_check_odt_id_hi == $veda_rs1cap_object_id[22:8]);
         $veda_check_odt_valid      = odt_mem[$veda_check_odt_addr+9][0] && $veda_check_odt_id_match;
         $veda_gen_stale = (!$veda_check_odt_valid) || ($veda_check_odt_gen != $veda_rs1cap_reserved);

         $veda_sealed        = ($veda_rs1cap_otype != 16'hFFFF);
         $veda_perm_load_ok  = $veda_rs1cap_perms[2];
         $veda_perm_store_ok = $veda_rs1cap_perms[3];
         $veda_bounds_ok     = (($rs2_data + 64'd8) <= {44'b0, $veda_rs1cap_length});

         $veda_ocl_violation = $is_veda_ocl && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_load_ok || !$veda_bounds_ok);
         $veda_ocs_violation = $is_veda_ocs && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_store_ok || !$veda_bounds_ok);
         // $veda_violation itself is combined further below, once
         // NMC_ADD/Veda-Atomic's own violation signals are also computed
         // (kept textually after the checks they depend on, matching this
         // file's own established define-before-use style, even though
         // TL-Verilog's combinational elaboration doesn't strictly
         // require it).

         $veda_real_addr[63:0] = {32'b0, $veda_rs1cap_base} + $rs2_data;
         // The GPR holding OCS's store value ($rd is the shared 5-bit
         // GPR-index field at instr[11:7], reused here as the "value
         // source" the same way the base ISA's own store instructions
         // reuse $rs2 for theirs -- OCL/OCS's own R-type shape puts the
         // value/destination in the $rd slot instead, per
         // VEDA_CORE_SPEC.md Section 1).
         $veda_ocs_value[63:0] = /xreg[$rd]$val;
         // Only consumed by the trailing raw \SV always_ff block below via
         // its mangled name (invisible to SandPiper's own TLV-level
         // dependency tracking, same real reason $mem_addr/$rs2_data's
         // trailing-\SV consumption never needed this -- those are *also*
         // used elsewhere in TLV logic, this signal genuinely isn't).
         `BOGUS_USE($veda_ocs_value)

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 7 (widened 2026-08-19, Length/Offset
         //  20-bit mirror): OCL.C/OCS.C checks. Real, own 17-byte
         //  (136-bit) bounds check -- deliberately NOT sharing
         //  $veda_bounds_ok above, which is hardcoded to the 8-byte
         //  D-width. Same real_addr computation as OCL.D/OCS.D
         //  ($veda_real_addr, already computed above: rs1cap.Base +
         //  fresh GPR offset) -- the capability width doesn't change
         //  where the access lands, only how many bytes/whether the tag
         //  store is touched. 16 -> 17 mirrors veda_ocl_insts.sail's own
         //  veda_check_access(capidx, offset, 17, ...) call for both
         //  VEDA_OCL_C/VEDA_OCS_C.
         // ─────────────────────────────────────────────────────────
         $veda_oclc_bounds_ok = (($rs2_data + 64'd17) <= {44'b0, $veda_rs1cap_length});
         $veda_oclc_violation = $is_veda_ocl_c && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_load_ok  || !$veda_oclc_bounds_ok);
         $veda_ocsc_violation = $is_veda_ocs_c && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_store_ok || !$veda_oclc_bounds_ok);

         // ─────────────────────────────────────────────────────────
         //  NEW (2026-08-19 widening): 32-byte alignment requirement,
         //  real Sail/RTL parity with the decided RTL tag-store design
         //  (NEXT_STEPS_ROADMAP.md's own "DECIDED, 2026-08-19"
         //  tag-granule-reversal section) -- the precondition that lets a
         //  17-byte capability-store touch exactly 2 statically-known-
         //  ADJACENT 16-byte tag_mem[]/tcm_scratch_tag[] granules (idx,
         //  idx+1, computed below) with no runtime-variable-span
         //  arithmetic. Checked only when the existing tag/gen/seal/perm/
         //  bounds check above ALREADY passed -- mirrors
         //  veda_ocl_insts.sail's own VEDA_OCL_C/VEDA_OCS_C execute
         //  clauses exactly: alignment is tested only after
         //  veda_check_access already returned Ok(paddr), so a
         //  misaligned-AND-otherwise-invalid access reports its first
         //  real violation, never alignment. Address-only (not load-vs-
         //  store-specific): both OCL.C and OCS.C need the identical
         //  check on the identical $veda_real_addr. Cause =
         //  VEDA_CAUSE_ALIGNMENT_VIOLATION = 5'h08, wired into
         //  $veda_trap_taken/$veda_trap_cause further below.
         // ─────────────────────────────────────────────────────────
         $veda_oclc_ocsc_misaligned = ($veda_real_addr[4:0] != 5'b00000);
         $veda_oclc_align_violation = $is_veda_ocl_c && !$veda_oclc_violation && $veda_oclc_ocsc_misaligned;
         $veda_ocsc_align_violation = $is_veda_ocs_c && !$veda_ocsc_violation && $veda_oclc_ocsc_misaligned;

         // Tag-store granule index: $veda_real_addr is absolute
         // (ELFMEM_BASE-relative), tag_mem[] is declared 0-based
         // (mirroring elfmem[]'s own absolute-vs-tag_mem's own relative
         // indexing choice, both real, deliberate, independent design
         // calls) -- subtract ELFMEM_BASE, then >>4 (real hardware's own
         // natural way to divide by 16, the granule size, since 16 is a
         // power of two -- the same technique already used in the Sail
         // model's own tag-store index computation, byte_off >> 4).
         $veda_capmem_granule[31:0] = ($veda_real_addr[31:0] - ELFMEM_BASE) >> 4;
         // NEW (2026-08-19 widening): the capability's own SECOND
         // granule. A 17-byte OCL.C/OCS.C access, now hard-required to be
         // 32-byte aligned (above), always spans exactly 2 adjacent
         // 16-byte granules (idx, idx+1), never more -- tag granule size
         // stays unchanged at 16 bytes by explicit decision
         // (NEXT_STEPS_ROADMAP.md's "DECIDED, 2026-08-19" reversal), so
         // this is a bare +1, not a runtime-variable-span computation.
         // Mirrors mem_metadata.sail's own __WriteRAM_Meta/__ReadRAM_Meta
         // g0/g1 fix ("the real index of the access's own last byte too").
         $veda_capmem_granule2[31:0] = $veda_capmem_granule + 32'd1;

         // MILESTONE 24 Stage 3: OCL.C/OCS.C's own TCM routing decision --
         // a real, separate address-range check on $veda_real_addr
         // (already computed above), completely independent of Stage 2's
         // Object_ID-based $veda_odt_tcm_hit (OCL.C/OCS.C's rs1 selects a
         // CRF register, never an Object_ID -- these two "_tcm_hit"
         // signals are judged on fundamentally different data and must
         // stay separate). A parallel, TCM-relative granule index is
         // real, load-bearing, not cosmetic: feeding a TCM_SCRATCH_BASE
         // -relative address into tag_mem[]'s own ELFMEM_SIZE-scoped
         // index space would alias or overflow -- the exact "easy-to-
         // miss bug class" flagged before any code was written here, now
         // closed by construction with its own, separate index.
         $veda_capmem_tcm_hit = ($veda_real_addr[31:0] >= TCM_SCRATCH_BASE) &&
                                 ($veda_real_addr[31:0] <  (TCM_SCRATCH_BASE + TCM_SCRATCH_SIZE));
         $veda_capmem_tcm_granule[31:0] = ($veda_real_addr[31:0] - TCM_SCRATCH_BASE) >> 4;
         // NEW (2026-08-19 widening): the TCM-tier's own second granule,
         // same real reason/1-adjacent-granule property as
         // $veda_capmem_granule2 above, kept as its own separate signal
         // (never shared with the elfmem-tier one) for the identical real
         // reason $veda_capmem_tcm_granule itself is already kept
         // separate from $veda_capmem_granule.
         $veda_capmem_tcm_granule2[31:0] = $veda_capmem_tcm_granule + 32'd1;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 7: byte-granular tag invalidation --
         //  real CHERI hardware's own core property, found missing by
         //  this milestone's own negative test (not assumed correct
         //  from the design alone): ANY plain, non-OCS.C write that
         //  touches a 16-byte granule must clear that granule's tag,
         //  because the bytes there may no longer form a valid, intact
         //  capability. Without this, a plain OCS.D could silently
         //  corrupt the low 8 bytes of a previously-stored capability
         //  while tag_mem[] kept reporting it as still genuinely tagged
         //  -- exactly the forgery OCL.C/OCS.C's whole design exists to
         //  prevent. Reused for NMC_ADD/Veda-Atomic's own write address
         //  below (both use $veda_cap_real_addr, distinct from OCL/OCS's
         //  $veda_real_addr above).
         // ─────────────────────────────────────────────────────────
         $veda_capmem_nmc_granule[31:0] = ($veda_cap_real_addr[31:0] - ELFMEM_BASE) >> 4;

         // OCS.C's own store source: rd is a Capability Register here
         // (Section 1's own field-position-reuse idiom, same as every
         // other Custom-0/2 instruction), not a GPR -- pack its 136 data
         // bits (widened from 128, 2026-08-19, Length/Offset 16->20 bits
         // each) in the identical field order the Sail model uses
         // (veda_cap_pack: Object_ID @ Base @ Length @ Offset @ Perms @
         // otype @ Reserved @ 1'b0 padding), so both real, independent
         // implementations of this ISA agree on one real memory layout,
         // not two silently different ones.
         $veda_ocsc_store_cap_object_id[22:0] = /vreg[$veda_rd_cap]$object_id;
         $veda_ocsc_store_cap_base[31:0]      = /vreg[$veda_rd_cap]$base;
         $veda_ocsc_store_cap_length[19:0]    = /vreg[$veda_rd_cap]$length;
         $veda_ocsc_store_cap_offset[19:0]    = /vreg[$veda_rd_cap]$offset;
         $veda_ocsc_store_cap_perms[15:0]     = /vreg[$veda_rd_cap]$perms;
         $veda_ocsc_store_cap_otype[15:0]     = /vreg[$veda_rd_cap]$otype;
         $veda_ocsc_store_cap_reserved[7:0]   = /vreg[$veda_rd_cap]$reserved;
         $veda_ocsc_store_tag                 = /vreg[$veda_rd_cap]$tag;
         $veda_ocsc_packed[135:0] = {$veda_ocsc_store_cap_object_id, $veda_ocsc_store_cap_base,
                                      $veda_ocsc_store_cap_length, $veda_ocsc_store_cap_offset,
                                      $veda_ocsc_store_cap_perms, $veda_ocsc_store_cap_otype,
                                      $veda_ocsc_store_cap_reserved, 1'b0};
         // Only consumed by the trailing raw \SV always_ff block below
         // (invisible to SandPiper's own TLV-level dependency tracking,
         // same real reason $veda_ocs_value needed this).
         `BOGUS_USE($veda_ocsc_packed)
         `BOGUS_USE($veda_ocsc_store_tag)

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: OCA (Object Capability Adjust). Soft-fail (Tag
         //  cleared, no trap) on out-of-bounds or sealed rs1 -- matches
         //  CHERI's own real CIncOffset unconditional-field/conditional-
         //  tag pattern (already used for the /vreg write logic below),
         //  the identical semantics already built and verified in Sail.
         //  No permission gate: OCA is a "manipulate" instruction
         //  (Section 1), not a "use" instruction -- it never dereferences
         //  the object itself.
         // ─────────────────────────────────────────────────────────
         // Ordinary 64-bit two's-complement addition already produces the
         // mathematically-correct signed sum regardless of operand signs
         // (same principle already relied on throughout this file for
         // $alu_result64/$branch_target/etc.) -- checking sum[63] for
         // "negative" needs no $signed() cast, avoiding the real
         // misparse issue already documented and fixed once in this
         // project (the `$` sigil collides with TL-Verilog's own syntax).
         // 2026-08-19 widening: cap.Offset/cap.Length are now 20 bits, so
         // zero-extension to 64 bits needs 44 zero bits, not 48.
         $veda_oca_sum[63:0] = {44'b0, $veda_rs1cap_offset} + $rs2_data;
         $veda_oca_out_of_range = $veda_oca_sum[63] || ($veda_oca_sum >= {44'b0, $veda_rs1cap_length});
         $veda_oca_ok = $veda_rs1cap_tag && !$veda_oca_out_of_range && ($veda_rs1cap_otype == 16'hFFFF);

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: Veda-Cap query family. Pure combinational reads of
         //  the already-fetched $veda_rs1cap_* fields -- no checks, per
         //  the decode comment above.
         // ─────────────────────────────────────────────────────────
         $veda_capquery_result[63:0] =
            $is_veda_cgetbase   ? {32'b0, $veda_rs1cap_base} :
            $is_veda_cgetlen    ? {44'b0, $veda_rs1cap_length} :
            $is_veda_cgetperm   ? {48'b0, $veda_rs1cap_perms} :
            $is_veda_cgettag    ? {63'b0, $veda_rs1cap_tag} :
            $is_veda_cgettype   ? {48'b0, $veda_rs1cap_otype} :
            $is_veda_cgetaddr   ? ({32'b0, $veda_rs1cap_base} + {44'b0, $veda_rs1cap_offset}) :
            $is_veda_cgetoffset ? {44'b0, $veda_rs1cap_offset} :
                                  64'b0;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: CSetBounds/CSetBoundsExact. "cd.Base = cs1.Base +
         //  cs1.Offset (narrows the object window to start at the
         //  capability's current position)... cd.Length = rs2... cd.Offset
         //  = 0" (VEDA_CORE_SPEC.md Section 1) -- soft-fail (Tag cleared,
         //  no trap) if cs1 was sealed or the requested bounds would
         //  exceed cs1's own current window, the same "manipulate" family
         //  convention as OCA above.
         // ─────────────────────────────────────────────────────────
         // 2026-08-19 widening: cap.Offset/cap.Length are 20 bits now, so
         // Base's own zero-extension of cap.Offset needs 12 zero bits
         // (32-20), not 16, and the new-Length slice widens to
         // rs2_data[19:0].
         $veda_csetbounds_new_base[31:0]   = $veda_rs1cap_base + {12'b0, $veda_rs1cap_offset};
         $veda_csetbounds_new_length[19:0] = $rs2_data[19:0];
         // Monotonic narrowing: the new window, starting at the current
         // position, must not extend past cs1's own remaining Length --
         // the same principle already applied for CSetBounds in Sail.
         // REAL PARITY FIX (found auditing this exact line for the
         // 2026-08-19 widening, pre-existing since RTL Milestone 3, not
         // introduced by this pass): Sail's own window_ok (veda_setbounds)
         // compares cap.Offset against the FULL, untruncated new_length
         // (X(rs2), xlenbits) -- only the later struct assignment slices
         // new_length[19..0]. This check must therefore use the full
         // 64-bit $rs2_data directly, NOT $veda_csetbounds_new_length
         // above (already-sliced) -- doing otherwise let an rs2 whose
         // full value was out-of-window but whose low bits happened to
         // alias a small, in-window value wrongly succeed here where
         // Sail soft-fails it. Compared at 65-bit width (not 64) so
         // cap.Offset's own zero-extension can be added to the full
         // 64-bit $rs2_data without truncating a legitimate sum that
         // lands just past 2^64-1.
         $veda_csetbounds_window_ok = ({45'b0, $veda_rs1cap_offset} + {1'b0, $rs2_data}) <= {45'b0, $veda_rs1cap_length};
         $veda_csetbounds_ok = $veda_rs1cap_tag && !$veda_sealed && $veda_csetbounds_window_ok;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 6: CSeal/CUnseal. Mirrors
         //  veda_cap_insts.sail's own VEDA_CSEAL/VEDA_CUNSEAL field-for-
         //  field (already real, working, verified Sail) -- ground truth
         //  re-read directly from that file before writing this, not
         //  re-derived from the CHERI spec summary. cs1 = the already-
         //  extracted $veda_rs1cap_* (this Custom-2 format's own rs1-
         //  capability field, instr[18:15], the exact same field OCA/
         //  CSetBounds/the query family already read). cs2 = the NEW
         //  rs2-capability operand ($veda_cseal_cunseal_rs2_cap,
         //  instr[23:20]) -- a fresh, independent /vreg read, not reused
         //  from anything above.
         // ─────────────────────────────────────────────────────────
         $veda_cs2_tag          = /vreg[$veda_cseal_cunseal_rs2_cap]$tag;
         $veda_cs2_length[19:0] = /vreg[$veda_cseal_cunseal_rs2_cap]$length;
         $veda_cs2_offset[19:0] = /vreg[$veda_cseal_cunseal_rs2_cap]$offset;
         $veda_cs2_perms[15:0]  = /vreg[$veda_cseal_cunseal_rs2_cap]$perms;
         $veda_cs2_otype[15:0]  = /vreg[$veda_cseal_cunseal_rs2_cap]$otype;
         $veda_cs2_sealed       = ($veda_cs2_otype != 16'hFFFF);
         // Object_ID/Base/Reserved: not needed by CSeal/CUnseal above
         // (cs2 there is only ever a type-authority, never copied into
         // cd), but needed by OCInvoke below, which really does copy
         // cs2's own full field set into c15 (IDC) on success.
         $veda_cs2_object_id[22:0] = /vreg[$veda_cseal_cunseal_rs2_cap]$object_id;
         $veda_cs2_base[31:0]      = /vreg[$veda_cseal_cunseal_rs2_cap]$base;
         $veda_cs2_reserved[7:0]   = /vreg[$veda_cseal_cunseal_rs2_cap]$reserved;

         // CSeal: cs2 must be a live, unsealed, Permit_Seal-carrying
         // (Perms bit 8, matching veda_types.sail's PERM_SEAL=8, the
         // same bit-index convention already used for Perms[2]=Load/
         // Perms[3]=Store/Perms[12]=NMC_Compute above) capability whose
         // own Offset (the value about to become cs1's new otype) lies
         // within cs2's own [0,Length) window and isn't the UNSEALED
         // sentinel (0xFFFF) -- using 0xFFFF as a "sealed" otype would
         // silently alias UNSEALED, a real, meaningful check, not a
         // mechanical bound. cs1 itself must be tagged and not already
         // sealed ("if cs1 was already sealed" -- Sail's own comment,
         // reused verbatim).
         // Minimal OS kernel Milestone B (MILESTONE_B_RESULTS.md):
         // `!= 16'hFFFE` added alongside the pre-existing `!= 16'hFFFF`
         // exclusion -- the load-bearing security property for the
         // entire sentry mechanism (VEDA_CSEALENTRY/VEDA_OCRETURN
         // below), mirroring real CHERI's own CSeal `cursor <=
         // cap_max_otype` bound: ordinary, software-directed sealing
         // must never be able to forge the hardware-reserved sentry
         // otype. Without this line, a capability sealed here with
         // otype=0xFFFE would be indistinguishable from a genuine
         // VEDA_CSEALENTRY-minted sentry to VEDA_OCRETURN.
         // WIDENING (2026-08-19): $veda_cs2_offset is now 20 bits; otype
         // stays 16 bits (veda_types.sail). CSeal is the one real MINT
         // site (otype := cs2.Offset[15:0], see the write-mux above) --
         // mirrors veda_cap_insts.sail's own VEDA_CSEAL `authorized` fix:
         // an explicit new precondition that the value about to become
         // otype has no bits set outside otype's own 16-bit range,
         // soft-failed (Tag cleared) via the existing $veda_cseal_ok path
         // exactly like every other CSeal authorization failure -- not a
         // new mechanism. Without this, e.g. cs2.Offset=20'h10005 would
         // authorize a seal whose otype (0x0005) collides with an
         // unrelated authority. The sentinel comparisons now compare the
         // truncated [15:0] slice, safe only because the new conjunct
         // already guarantees the upper 4 bits are zero.
         $veda_cseal_authorized = $veda_cs2_tag && !$veda_cs2_sealed && $veda_cs2_perms[8] &&
                                   ($veda_cs2_offset < $veda_cs2_length) &&
                                   ($veda_cs2_offset[19:16] == 4'b0000) &&
                                   ($veda_cs2_offset[15:0] != 16'hFFFF) && ($veda_cs2_offset[15:0] != 16'hFFFE);
         $veda_cseal_ok = $veda_cseal_authorized && $veda_rs1cap_tag && !$veda_sealed;

         // CUnseal: mirror of CSeal's authorization -- cs2 must be live,
         // unsealed, Permit_Unseal-carrying (Perms bit 9, PERM_UNSEAL),
         // and its Offset must exactly match cs1's current otype (the
         // type-authority proving it's allowed to unseal *this specific*
         // sealed type), within cs2's own bounds. cs1 must actually be
         // sealed and tagged.
         // WIDENING (2026-08-19): CUnseal is a pure COMPARE site -- mirrors
         // veda_cap_insts.sail's own VEDA_CUNSEAL fix: compare the full
         // 20-bit $veda_cs2_offset against cs1's 16-bit otype explicitly
         // zero-extended to 20 bits, rather than truncating
         // $veda_cs2_offset. Mathematically equivalent to CSeal's own
         // explicit gate above (equality can only hold if
         // $veda_cs2_offset's upper 4 bits are already zero) and simpler
         // at this read site.
         $veda_cunseal_authorized = $veda_cs2_tag && !$veda_cs2_sealed && $veda_cs2_perms[9] &&
                                     $veda_sealed && ($veda_cs2_offset == {4'b0, $veda_rs1cap_otype}) &&
                                     ($veda_cs2_offset < $veda_cs2_length);
         $veda_cunseal_ok = $veda_cunseal_authorized && $veda_rs1cap_tag;

         // ─────────────────────────────────────────────────────────
         //  Minimal OS kernel Milestone B (MILESTONE_B_RESULTS.md):
         //  VEDA_CSEALENTRY -- term-for-term adaptation of real CHERI's
         //  own CSealEntry (CHERI ISA spec p.215, read in full before
         //  writing this): cd = cs1 sealed with the fixed 0xFFFE
         //  (VEDA_OTYPE_SENTRY) constant -- no authorizing capability
         //  operand at all, unlike CSeal/CUnseal above (real CHERI's own
         //  text, p.101: "an ambient monotonic action, requiring no
         //  additional permission than to have a capability bearing
         //  Permit_Execute"). Perms (including Permit_Execute) are
         //  carried through unchanged, neither stripped nor added --
         //  VEDA_OCRETURN below is what actually enforces Permit_Execute,
         //  at the point of use, matching real CHERI's own division of
         //  labor between CSealEntry and CJALR exactly (verified against
         //  the Sail model, veda_cap_insts.sail's own VEDA_CSEALENTRY).
         //  funct7 = 0010101, the next genuinely free Custom-2/funct3=001
         //  slot after OCJALR (0010100), verified directly against every
         //  existing funct7==7'b0010... decode line in this file before
         //  picking it. Single source operand, reusing the same shared
         //  rs1-cap field ($veda_ocl_ocs_rs1_cap / $veda_rs1cap_*) every
         //  other Custom-2 instruction already shares -- no new field
         //  extraction needed.
         // ─────────────────────────────────────────────────────────
         $is_veda_csealentry = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010101);
         // Soft-fail only, no hard trap -- mirrors CSeal's own $veda_cseal_ok
         // pattern, minus any cs2/authorization term (CSealEntry takes
         // none): an already-untagged or already-sealed cs1 can't
         // produce a valid sentry, the same "untagged/already-sealed
         // source can't produce a valid result" reasoning CSeal already
         // applies.
         $veda_csealentry_ok = $veda_rs1cap_tag && !$veda_sealed;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 10: OCInvoke -- Veda-Core's own term-for-term
         //  adaptation of real CHERI's CInvoke (CHERI ISA spec p.209,
         //  read in full before writing this, not assumed from a
         //  summary), the protection-domain-transition primitive
         //  VEDA_CORE_SPEC.md Section 6 item 7 named and deferred until
         //  now. cs1 (code) = $veda_rs1cap_* (this format's already-
         //  established rs1-capability field); cs2 (data) =
         //  $veda_cs2_* above (already read for CSeal/CUnseal, reused
         //  unchanged). Real CHERI check order, mirrored exactly (not
         //  re-derived): Tag(cs1) -> Tag(cs2) -> Seal(cs1) -> Seal(cs2)
         //  -> matching otype -> Permit_Invoke(cs1) -> Permit_Invoke
         //  (cs2) -> Permit_Execute(cs1) must hold -> Permit_Execute
         //  (cs2) must NOT hold. cap_idx for mtval is NOT the single
         //  shared rs1-cap signal every other "use" family instruction
         //  could rely on (Milestone 9) -- OCInvoke genuinely involves
         //  two distinct capability registers, so the specific one that
         //  actually failed must be reported, muxed per failing check
         //  below, exactly matching Sail's own per-check
         //  veda_trap(rs1 or rs2, ...) choice.
         // ─────────────────────────────────────────────────────────
         $is_veda_ocinvoke = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010010);
         $veda_ocinvoke_violation = $is_veda_ocinvoke && (
            !$veda_rs1cap_tag || !$veda_cs2_tag ||
            !$veda_sealed || !$veda_cs2_sealed ||
            ($veda_rs1cap_otype != $veda_cs2_otype) ||
            !$veda_rs1cap_perms[10] || !$veda_cs2_perms[10] ||
            !$veda_rs1cap_perms[1] || $veda_cs2_perms[1]);
         $veda_ocinvoke_cause[4:0] =
            !$veda_rs1cap_tag           ? 5'h02 :
            !$veda_cs2_tag              ? 5'h02 :
            !$veda_sealed               ? 5'h03 :
            !$veda_cs2_sealed           ? 5'h03 :
            ($veda_rs1cap_otype != $veda_cs2_otype) ? 5'h04 :
            !$veda_rs1cap_perms[10]     ? 5'h19 :
            !$veda_cs2_perms[10]        ? 5'h19 :
            !$veda_rs1cap_perms[1]      ? 5'h11 :
                                           5'h11; // remaining case: cs2 wrongly executable
         $veda_ocinvoke_cap_idx[3:0] =
            !$veda_rs1cap_tag           ? $veda_ocl_ocs_rs1_cap :
            !$veda_cs2_tag              ? $veda_cseal_cunseal_rs2_cap :
            !$veda_sealed               ? $veda_ocl_ocs_rs1_cap :
            !$veda_cs2_sealed           ? $veda_cseal_cunseal_rs2_cap :
            ($veda_rs1cap_otype != $veda_cs2_otype) ? $veda_ocl_ocs_rs1_cap :
            !$veda_rs1cap_perms[10]     ? $veda_ocl_ocs_rs1_cap :
            !$veda_cs2_perms[10]        ? $veda_cseal_cunseal_rs2_cap :
            !$veda_rs1cap_perms[1]      ? $veda_ocl_ocs_rs1_cap :
                                           $veda_cseal_cunseal_rs2_cap;
         // Real jump target: cs1.Base + cs1.Offset (the same real
         // CGetAddr semantics already established) -- CHERI's own real
         // "clear bit 0 as for RISCV JALR" is a no-op here, since
         // Base/Offset are already byte-address-aligned integers with
         // no such low bit convention to clear.
         $veda_ocinvoke_target[63:0] = {32'b0, $veda_rs1cap_base} + {44'b0, $veda_rs1cap_offset};

         // ─────────────────────────────────────────────────────────
         //  OCJALR (Milestone 17, veda-core/STACK_FRAME_CALL_RETURN_
         //  ANALYSIS.md): closes the real, honest software-discipline
         //  gap that analysis found by testing rather than assuming --
         //  a return-address convention built entirely from already-
         //  existing instructions (OCA+CSeal at the call site, already
         //  proven working) left the return side as a hand-rolled
         //  CUnseal+CGetAddr+JALR sequence with no hardware gate: a
         //  never-sealed or corrupted-to-unsealed capability's own
         //  Base/Offset fields were still readable and jumpable, the
         //  check that made it safe was purely a software habit.
         //  OCJALR merges unseal-verification and jump into one atomic
         //  instruction, so the check cannot be forgotten by
         //  construction -- the same real property real CHERI's own
         //  CJALR provides for its sentry-capability jumps (CHERI ISA
         //  spec p.213, `CapEx_SealViolation` on a sealed-but-wrong
         //  capability, full semantics read before writing this).
         //  funct7 = 0010100, the next genuinely free Custom-2/
         //  funct3=001 slot -- 0010011 was this instruction's own
         //  first-draft value, found (on the Sail side, before any RTL
         //  was written) to collide with OSpecialRW's already-existing
         //  encoding, since OSpecialRW hardwires its own rs2-position
         //  field to all-zero rather than treating it as a real
         //  operand -- a real, narrow encoding bug caught and fixed
         //  before it could reach RTL at all.
         //  rs1 = cs1 (the sealed return-capability being verified and
         //  jumped through, reusing $veda_rs1cap_*, the same rs1-cap
         //  field position every Custom-2 instruction already shares);
         //  rs2 = cs2 (the seal-authority, reusing $veda_cs2_*, the
         //  same field CSeal/CUnseal/OCInvoke already established).
         //  Check order mirrors veda_cap_insts.sail's own VEDA_OCJALR
         //  exactly: Tag(cs1) -> Tag(cs2) -> Seal(cs1) must hold ->
         //  Seal(cs2) must NOT hold -> Permit_Unseal(cs2) ->
         //  cs2.Offset == cs1.otype (the same real type-authority match
         //  CUnseal itself already checks) -> Permit_Execute(cs1).
         //  Deliberately narrower than real CHERI's own general-purpose
         //  CJALR (which also mints a new sentry-sealed return
         //  capability as a side effect of every jump, via a dedicated
         //  reserved otype): this instruction is scoped to exactly the
         //  verify-and-consume half the vulnerability was in, reusing
         //  Milestone 6's existing CSeal/CUnseal type-authority model
         //  rather than inventing a second, parallel sealing mechanism.
         // ─────────────────────────────────────────────────────────
         $is_veda_ocjalr = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010100);
         // WIDENING (2026-08-19): OCJALR is a pure COMPARE site, same fix
         // as CUnseal above and veda_cap_insts.sail's own VEDA_OCJALR:
         // compare against zero_extend(cs1.otype) rather than truncating
         // the now-20-bit $veda_cs2_offset. Applied identically to the
         // violation gate, the cause mux, and the cap_idx mux below --
         // check order unchanged.
         $veda_ocjalr_violation = $is_veda_ocjalr && (
            !$veda_rs1cap_tag || !$veda_cs2_tag ||
            !$veda_sealed || $veda_cs2_sealed ||
            !$veda_cs2_perms[9] ||
            ($veda_cs2_offset != {4'b0, $veda_rs1cap_otype}) ||
            !$veda_rs1cap_perms[1]);
         $veda_ocjalr_cause[4:0] =
            !$veda_rs1cap_tag                       ? 5'h02 :
            !$veda_cs2_tag                          ? 5'h02 :
            !$veda_sealed                           ? 5'h03 :
            $veda_cs2_sealed                        ? 5'h03 :
            !$veda_cs2_perms[9]                     ? 5'h03 :
            ($veda_cs2_offset != {4'b0, $veda_rs1cap_otype}) ? 5'h04 :
                                                        5'h11; // remaining case: cs1 not executable
         $veda_ocjalr_cap_idx[3:0] =
            !$veda_rs1cap_tag                       ? $veda_ocl_ocs_rs1_cap :
            !$veda_cs2_tag                          ? $veda_cseal_cunseal_rs2_cap :
            !$veda_sealed                           ? $veda_ocl_ocs_rs1_cap :
            $veda_cs2_sealed                        ? $veda_cseal_cunseal_rs2_cap :
            !$veda_cs2_perms[9]                     ? $veda_cseal_cunseal_rs2_cap :
            ($veda_cs2_offset != {4'b0, $veda_rs1cap_otype}) ? $veda_ocl_ocs_rs1_cap :
                                                        $veda_ocl_ocs_rs1_cap;
         $veda_ocjalr_target[63:0] = {32'b0, $veda_rs1cap_base} + {44'b0, $veda_rs1cap_offset};

         // ─────────────────────────────────────────────────────────
         //  Minimal OS kernel Milestone B (MILESTONE_B_RESULTS.md):
         //  VEDA_OCRETURN -- the actual cheap, cross-compartment-
         //  boundary-crossing counterpart to OCJALR's own always-two-
         //  operand design above. Deliberately a NEW opcode rather than
         //  a sentry branch folded into OCJALR: OCJALR's own rs2 is a
         //  fixed encoding field (folding a branch in would either still
         //  require rs2 to be supplied unused, defeating the single-
         //  operand premise, or make one static encoding mean two
         //  different things depending on runtime capability contents --
         //  this file's own convention already gives each distinct
         //  security-relevant behavior its own funct7, e.g. OCA/
         //  CSetBounds/CSetBoundsExact). OCJALR itself is completely
         //  unmodified by this addition -- direct, load-bearing
         //  preservation of RTL Milestone 22's own already-shipped,
         //  already-tested "OCJALR cannot cross a compartment boundary"
         //  finding (veda_smoke_m22.S).
         //
         //  cs1 must be a genuine VEDA_CSEALENTRY-minted sentry (otype
         //  == 0xFFFE, a value ordinary CSeal is now hardware-blocked
         //  from ever producing, per the hardened $veda_cseal_authorized
         //  above) -- verified with exactly the same three checks
         //  OCJALR's own cs1-side already performs (tag, seal-validity,
         //  Permit_Execute), reusing the identical cause codes, but with
         //  NO second, type-authority capability operand at all: a
         //  sentry's own otype is self-authenticating, unlike an
         //  arbitrary CSeal otype which always needs an explicit
         //  CUnseal-style authority to vouch for it. Permit_Invoke is
         //  deliberately NOT checked -- matches real CHERI's own sentry/
         //  CJALR mechanism exactly.
         //
         //  On success, narrows $veda_pcc_base/$veda_pcc_length to cs1's
         //  own Base/Length (defined further below, alongside
         //  OCInvoke's own identical assignment) -- the actual
         //  compartment-boundary-crossing side effect. c15 (IDC) is
         //  deliberately left untouched (not cleared): real CJALR never
         //  touches IDC either (only CInvoke does), and OCInvoke's own
         //  write-back mux above already treats "install data-capability
         //  context" and "narrow PCC" as two independently-triggered
         //  effects, so OCRETURN adopting only the PCC half reuses a
         //  split this file already makes internally rather than
         //  inventing a new one.
         //
         //  funct7 = 0010110, the next free Custom-2/funct3=001 slot
         //  after CSealEntry's own 0010101 above (verified by grep
         //  against every existing user of this space before picking
         //  it). Single source operand, reusing the same shared rs1-cap
         //  field every other Custom-2 instruction already shares -- no
         //  new field extraction needed. cap_idx for a trap needs no new
         //  per-family branch in $veda_trap_cap_idx below -- its own
         //  existing default fallback is already $veda_ocl_ocs_rs1_cap,
         //  exactly the single operand OCRETURN has.
         // ─────────────────────────────────────────────────────────
         $is_veda_ocreturn = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010110);
         $veda_ocreturn_violation = $is_veda_ocreturn && (
            !$veda_rs1cap_tag || !$veda_sealed ||
            ($veda_rs1cap_otype != 16'hFFFE) ||
            !$veda_rs1cap_perms[1]);
         $veda_ocreturn_cause[4:0] =
            !$veda_rs1cap_tag                    ? 5'h02 :
            !$veda_sealed                        ? 5'h03 :
            ($veda_rs1cap_otype != 16'hFFFE)     ? 5'h03 :
                                                    5'h11; // remaining case: cs1 not executable
         $veda_ocreturn_target[63:0] = {32'b0, $veda_rs1cap_base} + {44'b0, $veda_rs1cap_offset};

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 11: OSpecialRW + capability-authority-gated
         //  ODT-Populate/ODT-Destroy (NEXT_STEPS_ROADMAP.md §2.5).
         //  Mirrors veda_cap_insts.sail's own VEDA_OSPECIALRW field-for-
         //  field. funct7 = 0010011, the next unused Custom-2 slot after
         //  OCInvoke (0010010). Reads/writes the ODA (Object Descriptor
         //  Authority) -- Veda-Core's own single Special Capability
         //  Register, real CHERI's own CSpecialRW/SCR model (CHERI ISA
         //  spec §4.3.6) adapted to Veda-Core's one-SCR case (no scr-
         //  index operand needed). Real CHERI's own access rule (Table
         //  4.3's "ASR" column) needs PCC.perms to grant
         //  PERMIT_ACCESS_SYSTEM_REGISTERS -- Veda-Core has no PCC
         //  (Milestone 10's own stated scope boundary), so this RTL
         //  gates OSpecialRW itself on ordinary privilege alone
         //  ($priv), the identical, already-established convention
         //  ODT-Populate/ODT-Destroy themselves already use below.
         // ─────────────────────────────────────────────────────────
         $is_veda_ospecialrw = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010011);
         $veda_ospecialrw_violation = $is_veda_ospecialrw && !$priv;

         // RTL mirror of minimal OS kernel Milestone A
         // (MINIMAL_OS_KERNEL_DESIGN.md): the SCR-selector operand
         // veda_cap_insts.sail's own VEDA_OSPECIALRW extension added,
         // read from the FULL 5-bit rs2 register-field position
         // ($instr[24:20]) -- unlike every vcapidx-shaped rs2-capability
         // operand elsewhere in this file (e.g.
         // $veda_cseal_cunseal_rs2_cap[3:0] = $instr[23:20], a 0-spacer
         // + 4-bit split), Sail's own encdec_veda_scr mapping consumes
         // the entire 5-bit field directly, confirmed by re-reading that
         // mapping before writing this, not assumed from the vcap
         // pattern. 5'b00000 = VEDA_SCR_ODA (the pre-existing, only
         // encoding every already-shipped test still uses -- x0 in this
         // position, backward-compatible by construction); 5'b00001 =
         // VEDA_SCR_TSC; 5'b00010 = VEDA_SCR_SSC (SSC milestone --
         // SSC_STACK_SPILL_CAPABILITY_DESIGN.md, mirrors the Sail side's
         // own encdec_veda_scr mapping exactly).
         $veda_ospecialrw_scr_sel[4:0] = $instr[24:20];
         $veda_ospecialrw_scr_is_tsc = ($veda_ospecialrw_scr_sel == 5'b00001);
         $veda_ospecialrw_scr_is_ssc = ($veda_ospecialrw_scr_sel == 5'b00010);

         // The ODA itself: a persistent capability register, structurally
         // identical to a /vreg entry but deliberately kept OUTSIDE the
         // CRF (VEDA_CORE_SPEC.md's own reasoning: it plays a genuinely
         // different architectural role -- a capability-authority
         // context for privileged instructions, not a general-purpose
         // capability register any Object-Bind/OCL/OCS/etc. can target).
         // Same real persistent-signal idiom already proven for
         // $mtvec/$mepc/$mcause/$mtval (Milestone 9), not a new one.
         // Minimal OS kernel Milestone A addition: write now also
         // requires the selector to specifically pick ODA (previously
         // unconditional whenever OSpecialRW fired at all, back when
         // ODA was the only SCR) -- TSC below mirrors this exactly with
         // the opposite selector value, so the two registers are
         // genuinely independent, never aliased.
         $veda_oda_tag = (|cpu$reset || |cpu>>1$reset) ? 1'b0 :
                          (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_tag :
                                                                                        >>1$veda_oda_tag;
         $veda_oda_object_id[22:0] = (|cpu$reset || |cpu>>1$reset) ? 23'b0 :
                                      (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_object_id :
                                                                                                     >>1$veda_oda_object_id;
         $veda_oda_base[31:0] = (|cpu$reset || |cpu>>1$reset) ? 32'b0 :
                                 (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_base :
                                                                                                >>1$veda_oda_base;
         // Length/Offset widened 16->20 bits, 2026-08-19 (mirrors
         // veda_types.sail's capability.Length/.Offset -- ODA stores a
         // full capability's own fields, so it needs the identical
         // widening the main CRF's own $length/$offset already got).
         $veda_oda_length[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_length :
                                                                                                  >>1$veda_oda_length;
         $veda_oda_offset[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_offset :
                                                                                                  >>1$veda_oda_offset;
         $veda_oda_perms[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'b0 :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_perms :
                                                                                                 >>1$veda_oda_perms;
         $veda_oda_otype[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'hFFFF :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_otype :
                                                                                                 >>1$veda_oda_otype;
         $veda_oda_reserved[7:0] = (|cpu$reset || |cpu>>1$reset) ? 8'b0 :
                                    (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_reserved :
                                                                                                   >>1$veda_oda_reserved;

         // The real, load-bearing check every OSpecialRW consumer
         // ultimately depends on -- mirrors Sail's own
         // veda_oda_authorized() exactly: a live, unsealed ODA carrying
         // PERMIT_ACCESS_SYSTEM_REGISTERS (bit 7 -- already reserved in
         // the Perms table since CHERI adoption, never before consumed
         // by any real instruction).
         $veda_oda_sealed = ($veda_oda_otype != 16'hFFFF);
         $veda_oda_authorized = $veda_oda_tag && !$veda_oda_sealed && $veda_oda_perms[7];

         // The TSC (Trusted Stack Capability): minimal OS kernel
         // Milestone A's own second Special Capability Register, term-
         // for-term adapted from real CHERIoT's own `mtdc`
         // (MINIMAL_OS_KERNEL_DESIGN.md). Structurally identical to the
         // ODA's own 8-field persistent-register pattern immediately
         // above, mirrored field-for-field, gated by the opposite
         // selector value so the two registers are never aliased.
         $veda_tsc_tag = (|cpu$reset || |cpu>>1$reset) ? 1'b0 :
                          (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_tag :
                                                                                        >>1$veda_tsc_tag;
         $veda_tsc_object_id[22:0] = (|cpu$reset || |cpu>>1$reset) ? 23'b0 :
                                      (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_object_id :
                                                                                                     >>1$veda_tsc_object_id;
         $veda_tsc_base[31:0] = (|cpu$reset || |cpu>>1$reset) ? 32'b0 :
                                 (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_base :
                                                                                                >>1$veda_tsc_base;
         // Length/Offset widened 16->20 bits, 2026-08-19 (mirrors
         // veda_types.sail's capability.Length/.Offset -- TSC stores a
         // full capability's own fields, so it needs the identical
         // widening the main CRF's own $length/$offset already got).
         $veda_tsc_length[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_length :
                                                                                                  >>1$veda_tsc_length;
         $veda_tsc_offset[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_offset :
                                                                                                  >>1$veda_tsc_offset;
         $veda_tsc_perms[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'b0 :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_perms :
                                                                                                 >>1$veda_tsc_perms;
         $veda_tsc_otype[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'hFFFF :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_otype :
                                                                                                 >>1$veda_tsc_otype;
         $veda_tsc_reserved[7:0] = (|cpu$reset || |cpu>>1$reset) ? 8'b0 :
                                    (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_reserved :
                                                                                                   >>1$veda_tsc_reserved;

         // The SSC (Stack-Spill Capability): SSC_STACK_SPILL_CAPABILITY_
         // DESIGN.md's own third Special Capability Register, added to
         // give ordinary compiled C's ABI-mandated callee-saved-register
         // spills a real, dedicated, capability-checked register to
         // route through instead of raw sd/ld (which Milestone 19's
         // purecap rule unconditionally traps inside a live compartment).
         // Structurally identical to the ODA/TSC 8-field persistent-
         // register pattern above, mirrored field-for-field, gated by
         // its own selector value so all three SCRs stay genuinely
         // independent. Unlike ODA/TSC, this register is ALSO cleared
         // by $is_veda_ocinvoke and $is_veda_ocreturn below (their own
         // violation-gated blocks) -- deliberately NOT persistent-and-
         // -boundary-crossing-transparent like ODA/TSC, per an
         // independent design review's real finding (see the design
         // doc): an SSC following ODA/TSC's own "untouched by OCInvoke"
         // convention would let a callee compartment silently inherit
         // full OCL.D/OCS.D access to the caller's entire stack region.
         $veda_ssc_tag = (|cpu$reset || |cpu>>1$reset) ? 1'b0 :
                          (>>1$is_veda_ocinvoke && !>>1$veda_ocinvoke_violation) ? 1'b0 :
                          (>>1$is_veda_ocreturn && !>>1$veda_ocreturn_violation) ? 1'b0 :
                          (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_tag :
                                                                                        >>1$veda_ssc_tag;
         $veda_ssc_object_id[22:0] = (|cpu$reset || |cpu>>1$reset) ? 23'b0 :
                                      (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_object_id :
                                                                                                     >>1$veda_ssc_object_id;
         $veda_ssc_base[31:0] = (|cpu$reset || |cpu>>1$reset) ? 32'b0 :
                                 (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_base :
                                                                                                >>1$veda_ssc_base;
         // Length/Offset widened 16->20 bits, 2026-08-19 (mirrors
         // veda_types.sail's capability.Length/.Offset -- SSC stores a
         // full capability's own fields, so it needs the identical
         // widening the main CRF's own $length/$offset already got).
         $veda_ssc_length[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_length :
                                                                                                  >>1$veda_ssc_length;
         $veda_ssc_offset[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_offset :
                                                                                                  >>1$veda_ssc_offset;
         $veda_ssc_perms[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'b0 :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_perms :
                                                                                                 >>1$veda_ssc_perms;
         $veda_ssc_otype[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'hFFFF :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_otype :
                                                                                                 >>1$veda_ssc_otype;
         $veda_ssc_reserved[7:0] = (|cpu$reset || |cpu>>1$reset) ? 8'b0 :
                                    (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_reserved :
                                                                                                   >>1$veda_ssc_reserved;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: NMC_ADD.{W,D} and Veda-Atomic share the same
         //  capability-positioned real-address computation and, at
         //  D-width, the same read of the current value -- both operate
         //  on the capability's own *persistent* Offset (Section 1),
         //  unlike OCL/OCS's fresh per-access GPR offset ($veda_real_addr
         //  above). Gated on Permit_NMC_Compute (NMC_ADD, its own
         //  dedicated bit, Section 2) vs. Permit_Load+Permit_Store
         //  (Veda-Atomic, a general RMW, not the dedicated compute-at-
         //  memory dispatch NMC_ADD is) -- the identical permission split
         //  already reasoned through and built in Sail.
         // ─────────────────────────────────────────────────────────
         $veda_cap_real_addr[63:0] = {32'b0, $veda_rs1cap_base} + {44'b0, $veda_rs1cap_offset};
         $veda_cap_old_d[63:0] =
            {elfmem[$veda_cap_real_addr[31:0]+7], elfmem[$veda_cap_real_addr[31:0]+6],
             elfmem[$veda_cap_real_addr[31:0]+5], elfmem[$veda_cap_real_addr[31:0]+4],
             elfmem[$veda_cap_real_addr[31:0]+3], elfmem[$veda_cap_real_addr[31:0]+2],
             elfmem[$veda_cap_real_addr[31:0]+1], elfmem[$veda_cap_real_addr[31:0]+0]};
         $veda_cap_old_w[31:0] =
            {elfmem[$veda_cap_real_addr[31:0]+3], elfmem[$veda_cap_real_addr[31:0]+2],
             elfmem[$veda_cap_real_addr[31:0]+1], elfmem[$veda_cap_real_addr[31:0]+0]};

         $veda_perm_nmc_ok = $veda_rs1cap_perms[12];
         $veda_nmc_bounds_ok_d = (({44'b0, $veda_rs1cap_offset}) + 64'd8) <= {44'b0, $veda_rs1cap_length};
         $veda_nmc_bounds_ok_w = (({44'b0, $veda_rs1cap_offset}) + 64'd4) <= {44'b0, $veda_rs1cap_length};

         // Only consumed by the trailing raw \SV always_ff block below
         // (invisible to SandPiper's own TLV-level dependency tracking,
         // same real reason $veda_ocs_value needed this).
         $veda_nmc_add_result_d[63:0] = $rs2_data + $veda_cap_old_d;
         `BOGUS_USE($veda_nmc_add_result_d)
         $veda_nmc_add_result_w[31:0] = $rs2_data[31:0] + $veda_cap_old_w;
         `BOGUS_USE($veda_nmc_add_result_w)
         // rd receives the *old* value, matching real AMOADD's return
         // convention exactly (Section 1) -- W sign-extends, D doesn't
         // need to (already xlen-wide).
         $veda_nmc_rd_value[63:0] = $is_veda_nmc_add_w ? {{32{$veda_cap_old_w[31]}}, $veda_cap_old_w} : $veda_cap_old_d;

         $veda_nmc_add_w_violation = $is_veda_nmc_add_w && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_nmc_ok || !$veda_nmc_bounds_ok_w);
         $veda_nmc_add_d_violation = $is_veda_nmc_add_d && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_nmc_ok || !$veda_nmc_bounds_ok_d);

         // Veda-Atomic ALU: op-select values reuse real RISC-V Zaamo's
         // own encoding (see decode comment above). Signed MIN/MAX use
         // the same sign-bit-based technique as $lt_signed elsewhere in
         // this file, not $signed().
         $veda_atomic_lt_signed = ($rs2_data[63] != $veda_cap_old_d[63]) ? $rs2_data[63] : ($rs2_data < $veda_cap_old_d);
         $veda_atomic_result[63:0] =
            ($veda_atomic_op == 5'b00001) ? $rs2_data :                                                     // SWAP
            ($veda_atomic_op == 5'b00000) ? ($rs2_data + $veda_cap_old_d) :                                 // ADD
            ($veda_atomic_op == 5'b00100) ? ($rs2_data ^ $veda_cap_old_d) :                                 // XOR
            ($veda_atomic_op == 5'b01100) ? ($rs2_data & $veda_cap_old_d) :                                 // AND
            ($veda_atomic_op == 5'b01000) ? ($rs2_data | $veda_cap_old_d) :                                 // OR
            ($veda_atomic_op == 5'b10000) ? ($veda_atomic_lt_signed ? $rs2_data : $veda_cap_old_d) :        // MIN
            ($veda_atomic_op == 5'b10100) ? ($veda_atomic_lt_signed ? $veda_cap_old_d : $rs2_data) :        // MAX
            ($veda_atomic_op == 5'b11000) ? (($rs2_data < $veda_cap_old_d) ? $rs2_data : $veda_cap_old_d) : // MINU
            ($veda_atomic_op == 5'b11100) ? (($rs2_data > $veda_cap_old_d) ? $rs2_data : $veda_cap_old_d) : // MAXU
                                             64'b0;
         // Only consumed by the trailing raw \SV always_ff block below.
         `BOGUS_USE($veda_atomic_result)
         $veda_atomic_violation = $is_veda_atomic && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_load_ok || !$veda_perm_store_ok || !$veda_nmc_bounds_ok_d);

         $veda_violation = $veda_ocl_violation || $veda_ocs_violation ||
                           $veda_nmc_add_w_violation || $veda_nmc_add_d_violation ||
                           $veda_atomic_violation;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 9: per-family cause codes, mirroring
         //  veda_bind_insts.sail's own VEDA_CAUSE_* constants and
         //  veda_check_access/veda_check_nmc_access's exact if-else
         //  priority order (Tag/generation -> Seal -> Permission ->
         //  Bounds) field-for-field -- not re-derived or approximated.
         //  Only the seven "use" families that actually call
         //  veda_check_access/veda_check_nmc_access in Sail (and
         //  therefore genuinely veda_trap()) get a cause signal here;
         //  OCA/CSetBounds/CSetBoundsExact/CSeal/CUnseal are correctly
         //  absent -- Sail's own execute clauses for those never call
         //  either check function at all, they soft-fail by
         //  unconditional design (see the /vreg comment block below),
         //  not because RTL trap infrastructure was missing until now.
         // ─────────────────────────────────────────────────────────
         $veda_ocl_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_load_ok                    ? 5'h12 :
                                                      5'h01;
         $veda_ocs_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_store_ok                   ? 5'h13 :
                                                      5'h01;
         $veda_oclc_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_load_ok                    ? 5'h12 :
                                                      5'h01;
         $veda_ocsc_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_store_ok                   ? 5'h13 :
                                                      5'h01;
         $veda_nmc_add_w_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_nmc_ok                     ? 5'h1f :
                                                      5'h01;
         $veda_nmc_add_d_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_nmc_ok                     ? 5'h1f :
                                                      5'h01;
         // Atomic reuses veda_check_access with need_load=need_store=
         // true -- Sail checks Permit_Load before Permit_Store in that
         // case (veda_ocl_insts.sail's own if-else chain), so a missing
         // Permit_Load must win the cause code over a missing
         // Permit_Store when both happen to be absent, matching exactly.
         $veda_atomic_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_load_ok                    ? 5'h12 :
            !$veda_perm_store_ok                   ? 5'h13 :
                                                      5'h01;

         // One combined trap-taken signal + cause mux across every real
         // hard-trapping family. cap_idx is NOT muxed per-family -- all
         // seven share the identical rs1-capability field position
         // ($veda_ocl_ocs_rs1_cap, already established and reused
         // throughout this file), so the same signal is correct
         // regardless of which family actually trapped.
         // RTL Milestone 10 addition: OCInvoke joins the same combined
         // trap-taken family. Its own cap_idx is NOT the shared
         // $veda_ocl_ocs_rs1_cap every other family here can rely on
         // (OCInvoke genuinely spans two distinct capability registers)
         // -- $veda_trap_cap_idx below resolves that per-family, falling
         // back to the shared field for every family that only ever
         // involves one capability register.
         // RTL Milestone 12/13 addition: plain Bind's own two hard-trap
         // reasons (owner-violation, object-not-found -- combined into
         // $veda_bind_trap) join the same combined trap-taken family
         // too. Their shared cap_idx is rd (the destination capability
         // register, $veda_rd_cap), NOT rs1 -- mirrors
         // veda_bind_insts.sail's own `veda_trap(rd, ...)` call exactly
         // for both cause codes (every other family here traps on the
         // capability being DEREFERENCED, rs1; Bind's own cap_idx is the
         // capability being WRITTEN, rd).
         // RTL Milestone 14 addition: $veda_pcc_violation joins the same
         // combined trap-taken family -- its own cap_idx (16, the PCC
         // sentinel) and cause (0x01, reused) are both fixed constants,
         // built directly into $mtval's own construction below rather
         // than routed through $veda_trap_cap_idx[3:0] (only 4 bits wide,
         // can't carry the 5-bit sentinel value 16 without a wider,
         // more invasive change to every existing call site) -- the
         // identical "built inline, not through the typed interface"
         // choice already made on the Sail side (veda_bind_insts.sail's
         // veda_trap() vs. the PCC hook's own direct handle_exception()
         // call).
         // RTL Milestone 19 addition: $veda_purecap_violation joins the
         // same combined trap-taken family -- its own cap_idx (17, the
         // "this was purecap enforcement, not a real capability register"
         // sentinel -- the next free value after PCC's own 16) and cause
         // (0x07, VEDA_CORE_SPEC.md's previously-reserved slot, matching
         // the Sail side) are both fixed constants, built directly into
         // $mtval's own construction below, the identical "built inline,
         // not through the typed interface" choice PCC's own cap_idx=16
         // already established (see that comment above) -- 17 doesn't fit
         // $veda_trap_cap_idx[3:0] (4 bits, max 15) either.
         // RTL Milestone 20 addition: $veda_csr_escape_violation joins
         // the same combined trap-taken family -- it needs no special
         // cap_idx/cause handling of its own beyond $mcause's own
         // mcause=0x02 special-case below (see that comment), because
         // the existing, uniform "any trap resets veda_pcc_base/_length
         // to unbounded, saving the pre-trap bounds into
         // veda_mepcc_base/_length" priority (already the highest
         // -priority branch in each of those four CSRs' own definitions)
         // already correctly prevents the attacker-controlled csr_wdata
         // from ever landing, for free, with no extra per-CSR guard
         // needed -- confirmed by direct inspection before relying on
         // it. veda_mode (0x7C5) has no such pre-existing trap-reset
         // branch of its own (unlike the PCC-family CSRs, nothing else
         // ever writes it), so its own write-gating expression below
         // gets an explicit, separate guard instead.
         // Minimal OS kernel Milestone B: $veda_ocreturn_violation joins
         // the same combined trap-taken family -- its own cap_idx needs
         // NO new branch in $veda_trap_cap_idx below (single operand,
         // already the shared $veda_ocl_ocs_rs1_cap position, exactly
         // the existing default fallback).
         // RTL Milestone 23: $is_ecall joins the same combined
         // trap-taken family -- unlike every other term here (all
         // conditional security violations), ecall is unconditional by
         // design: executing it always traps, no separate violation
         // gate needed. No same-cycle collision risk with any other
         // term -- every other term gates on Custom-0/1/2 opcodes or
         // is_load/is_store/CSRRW/CSRRS, all disjoint from SYSTEM
         // opcode; $veda_pcc_violation forces $instr to a NOP before
         // decode, so it's provably mutually exclusive with $is_ecall
         // needing an exact literal match.
         $veda_trap_taken = $veda_ocl_violation || $veda_ocs_violation ||
                             $veda_oclc_violation || $veda_ocsc_violation ||
                             // NEW (2026-08-19 widening): the new 32-byte
                             // alignment violation joins the same combined
                             // trap-taken family -- without this, the check
                             // computed above would be detected but never
                             // acted on (no trap, no PC redirect).
                             $veda_oclc_align_violation || $veda_ocsc_align_violation ||
                             $veda_nmc_add_w_violation || $veda_nmc_add_d_violation ||
                             $veda_atomic_violation || $veda_ocinvoke_violation ||
                             $veda_ocjalr_violation || $veda_ocreturn_violation ||
                             $veda_bind_trap || $veda_pcc_violation ||
                             $veda_purecap_violation || $veda_csr_escape_violation ||
                             $is_ecall;
         $veda_trap_cause[4:0] =
            $veda_ocl_violation       ? $veda_ocl_cause :
            $veda_ocs_violation       ? $veda_ocs_cause :
            $veda_oclc_violation      ? $veda_oclc_cause :
            $veda_ocsc_violation      ? $veda_ocsc_cause :
            // NEW (2026-08-19 widening): VEDA_CAUSE_ALIGNMENT_VIOLATION =
            // 5'h08 (5'b01000) -- a fixed literal, not a per-family
            // *_cause signal, since there is only ever one possible cause
            // value once either alignment signal fires (mirrors this same
            // mux's own sibling $mtval construction below, which already
            // inlines PCC/purecap's own fixed cap_idx/cause pairs directly
            // rather than routing every fixed case through a named signal).
            $veda_oclc_align_violation ? 5'h08 :
            $veda_ocsc_align_violation ? 5'h08 :
            $veda_nmc_add_w_violation ? $veda_nmc_add_w_cause :
            $veda_nmc_add_d_violation ? $veda_nmc_add_d_cause :
            $veda_atomic_violation    ? $veda_atomic_cause :
            $veda_ocinvoke_violation  ? $veda_ocinvoke_cause :
            $veda_ocjalr_violation    ? $veda_ocjalr_cause :
            $veda_ocreturn_violation  ? $veda_ocreturn_cause :
            $veda_bind_trap           ? $veda_bind_cause :
                                        5'b0;
         $veda_trap_cap_idx[3:0] = $veda_ocinvoke_violation ? $veda_ocinvoke_cap_idx :
                                    $veda_ocjalr_violation   ? $veda_ocjalr_cap_idx :
                                    $veda_bind_trap          ? $veda_rd_cap :
                                                                $veda_ocl_ocs_rs1_cap;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 9: real Zicsr-lite CSR state. mtvec and mepc
         //  are both genuinely software-writable (mtvec: software
         //  installs its own trap handler address; mepc: a real trap
         //  handler must be able to advance PAST the faulting
         //  instruction before MRET, or MRET would jump straight back
         //  into the same instruction and re-trap forever -- confirmed
         //  a real, load-bearing need while designing this milestone's
         //  own trap-and-resume test, not a speculative feature added
         //  "to be complete"). mcause/mtval stay hardware-write-only
         //  (CSRRS can read them; CSRRW to them is decoded but its
         //  write silently has no effect, real RISC-V's own WARL
         //  convention for a field software isn't allowed to move) --
         //  no real trap-handler pattern in this project ever needs to
         //  fabricate a cause/value software didn't actually observe.
         // ─────────────────────────────────────────────────────────
         $csr_rdata[63:0] = $csr_is_mtvec  ? $mtvec :
                             $csr_is_mscratch ? $mscratch :
                             $csr_is_mepc   ? $mepc :
                             $csr_is_mcause ? $mcause :
                             $csr_is_mtval  ? $mtval :
                             $csr_is_veda_pcc_base     ? {32'b0, $veda_pcc_base} :
                             $csr_is_veda_pcc_length   ? {44'b0, $veda_pcc_length} :
                             $csr_is_veda_mepcc_base   ? {32'b0, $veda_mepcc_base} :
                             $csr_is_veda_mepcc_length ? {44'b0, $veda_mepcc_length} :
                             $csr_is_veda_attr         ? {28'b0, $veda_attr} :
                             $csr_is_veda_mode         ? {32'b0, $veda_mode} :
                                              64'b0;
         // CSRRS with rs1=x0 must not write the CSR at all (real
         // RISC-V's own rule, VEDA_CORE... no -- the base Zicsr spec
         // itself: "If rs1=x0, then the instruction... shall not write
         // to the CSR"), matching this project's own real trap-handler
         // pattern (`csrr t3, mcause` expands to exactly this form and
         // must never attempt to write mcause).
         $csr_wdata[63:0] = $is_csrrw ? $rs1_data :
                             $is_csrrs ? ($csr_rdata | $rs1_data) :
                                         64'b0;
         $csr_write_en = $is_csr_access && !($is_csrrs && ($rs1 == 5'b0));
         // RTL MILESTONE 20 (Sail mirror, MILESTONE_20_RESULTS.md): the
         // real, empirically-confirmed compartment-state CSR
         // self-escape -- code entered via a real OCInvoke could simply
         // CSRRW its own compartment-state CSRs (veda_pcc_base/_length,
         // veda_mepcc_base/_length, veda_mode) to undo its own bounding,
         // zero trap. A write to any of these five while a compartment
         // is live (veda_pcc_length != UNBOUNDED) is now illegal --
         // matches the Sail side's own real-CHERI-grounded rule
         // ("Reading or writing any CSR requires the
         // Access_System_Registers permission on the PCC"). Read access
         // is deliberately NOT gated (capability metadata is always
         // inspectable, the same principle CGetTag/CGetType already
         // rely on -- code inside a compartment already knows its own
         // bounds, it got there via the capability that defined them).
         // RTL M27-mtvec-gate: $csr_is_mtvec added to this OR-list -- see
         // the real comment at $mtvec's own update logic below for the full
         // reasoning. Reuses 100% of the already-wired mcause=0x02/
         // mtval=raw-instr/veda_trap_taken machinery for free.
         $veda_csr_escape_violation = $csr_write_en &&
            ($csr_is_veda_pcc_base || $csr_is_veda_pcc_length ||
             $csr_is_veda_mepcc_base || $csr_is_veda_mepcc_length ||
             $csr_is_veda_mode || $csr_is_mtvec) &&
            ($veda_pcc_length != 20'hFFFFF);
         `BOGUS_USE($csr_rdata)
         `BOGUS_USE($csr_wdata)

         // RTL M27-mtvec-gate (Sail-parity mirror, MILESTONE_27_MTVEC_CSR_
         // GATE_RESULTS.md): mtvec joins $veda_csr_escape_violation's own
         // CSR list below (the same "same class of gap" that doc's own
         // "Not yet built" section already named) -- a live compartment
         // silently CSRRW-ing its own trap handler out from under itself
         // (installing an attacker-controlled trap target) is now blocked
         // for the identical real reason the pcc_base/_length/mepcc_*/mode
         // family already is. Unlike those, mtvec has no trap-reset branch
         // of its own to piggyback on, so it needs its own explicit guard
         // here -- matching $veda_mode's own already-established pattern.
         $mtvec[63:0] = $reset ? 64'b0 :
                        (>>1$csr_write_en && >>1$csr_is_mtvec && !(>>1$veda_csr_escape_violation)) ? >>1$csr_wdata :
                                                                  >>1$mtvec;
         // RTL Milestone 25 mirror: mscratch, byte-for-byte structural
         // copy of $mtvec's own pattern above -- no hardware-capture
         // logic needed, nothing but software CSRRW ever writes it,
         // exactly mtvec's own situation.
         $mscratch[63:0] = $reset ? 64'b0 :
                            (>>1$csr_write_en && >>1$csr_is_mscratch) ? >>1$csr_wdata :
                                                                         >>1$mscratch;
         $mepc[63:0] = $reset ? 64'b0 :
                       // A real trap-taken event always wins over a
                       // same-cycle software CSRRW to mepc -- the two
                       // can't actually co-occur in practice (a CSRRW
                       // to mepc is never itself a Veda-Core violation),
                       // but ordering it this way keeps the hardware
                       // capture the authoritative source on the one
                       // cycle that matters, matching mcause/mtval's
                       // own precedence below.
                       (>>1$veda_trap_taken) ? >>1$pc :
                       (>>1$csr_write_en && >>1$csr_is_mepc) ? >>1$csr_wdata :
                                                                >>1$mepc;
         $mcause[63:0] = $reset ? 64'b0 :
                         // E_Extension's own fixed top-level code
                         // (VEDA_CORE_SPEC.md Section 3, verified
                         // against core/types_ext.sail's real
                         // ext_exc_type_bits mapping, not assumed) --
                         // every Veda-Core hard trap shares this one
                         // mcause value regardless of which family or
                         // cause sub-code fired; the real detail lives
                         // in mtval below, matching Sail's own
                         // make_sync_exception(E_Extension(()), xtval)
                         // shape exactly.
                         // RTL Milestone 20: a compartment-state CSR
                         // self-escape attempt is a real, standard
                         // RISC-V Illegal_Instruction (mcause=0x02), NOT
                         // Veda-Core's own E_Extension (0x18) every
                         // other family here shares -- matches the Sail
                         // side's own real, idiomatic write_CSR
                         // Err(())=>Illegal_Instruction() mechanism
                         // exactly (a stronger, more consistent response
                         // than a silent no-op, per that milestone's own
                         // reasoning).
                         // RTL Milestone 23: ecall gets the real,
                         // standard RISC-V privileged-spec mcause for
                         // "Environment call from M-mode" (0x0B=11) --
                         // not an invented Veda-specific code, and the
                         // only possible value since this core only
                         // ever runs M-mode.
                         (>>1$veda_trap_taken) ? (>>1$veda_csr_escape_violation ? 64'h02 :
                                                   >>1$is_ecall ? 64'h0B : 64'h18) :
                                                  >>1$mcause;
         $mtval[63:0] = $reset ? 64'b0 :
                        // veda_xtval(cap_idx, cause) = zero_extend(cap_idx5
                        // @ cause) -- cap_idx5 is cap_idx zero-extended
                        // from 4 to 5 bits, verified directly from
                        // veda_bind_insts.sail's own source, the same
                        // encoding already cross-checked once this
                        // session for the Sail-side atomic8 test.
                        // RTL Milestone 14: the PCC-violation case is
                        // special-cased here directly (cap_idx=5'b10000,
                        // cause=5'b00001) rather than going through
                        // $veda_trap_cap_idx[3:0]/$veda_trap_cause[4:0]
                        // (see $veda_trap_taken's own comment above).
                        // RTL Milestone 19: the purecap-violation case is
                        // special-cased identically (cap_idx=5'b10001=17,
                        // cause=5'b00111=0x07) -- checked ahead of the PCC
                        // case in this ternary chain, but the two can
                        // never actually co-occur on the same cycle
                        // ($veda_pcc_violation only ever fires from the
                        // fetch-time check, which forces $instr to a NOP
                        // before decode, so $is_load/$is_store -- and
                        // therefore $veda_purecap_violation -- can never
                        // also be true that same cycle), so the ordering
                        // here is a don't-care, not a real priority
                        // decision.
                        // RTL Milestone 20: mtval for the mcause=0x02
                        // case above holds the real, standard RISC-V
                        // convention for an illegal-instruction trap --
                        // the raw faulting instruction bits (the
                        // offending CSRRW/CSRRS itself) -- rather than a
                        // cap_idx/cause pair, since this is not a
                        // Veda-specific violation family at all.
                        // RTL Milestone 23: mtval=0 for ecall, the real
                        // RISC-V spec convention (no fault-address info
                        // applies) -- the pre-existing default fallback
                        // below is built from $veda_trap_cap_idx/_cause,
                        // which ecall never populates, so it needs its
                        // own explicit branch rather than falling through.
                        (>>1$veda_trap_taken) ? (>>1$veda_csr_escape_violation ? {32'b0, >>1$instr}
                                                  : >>1$veda_purecap_violation ? {54'b0, 5'b10001, 5'b00111}
                                                  : >>1$veda_pcc_violation ? {54'b0, 5'b10000, 5'b00001}
                                                  : >>1$is_ecall ? 64'b0
                                                                         : {55'b0, >>1$veda_trap_cap_idx, >>1$veda_trap_cause}) :
                                                 >>1$mtval;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 14: veda_pcc_base/veda_pcc_length (the live
         //  compartment) and veda_mepcc_base/veda_mepcc_length (the saved
         //  copy across a trap) -- the same real persistent-signal idiom
         //  $mtvec/$mepc already established (Milestone 9), applied to a
         //  new, genuinely different kind of state (a fetch-time bound,
         //  not an ordinary CSR value alone). Reset to
         //  VEDA_PCC_UNBOUNDED (20'hFFFFF, widened from 16'hFFFF
         //  alongside capability Length/Offset, 2026-08-19) -- a real
         //  correctness requirement, not styling: left at 0 by default,
         //  every fetch
         //  would bounds-check against an empty window at address 0 and
         //  hard-trap on the very first cycle (the identical real reason
         //  already named on the Sail side, postlude/step_ext.sail).
         //  Priority order, matching veda_trap()'s own real behavior on
         //  the Sail side field-for-field: (1) a real trap always wins --
         //  save the live bounds into mepcc, reset pcc to unbounded so
         //  the trap handler itself runs in a trusted, unconstrained
         //  context (real CHERI's own "Exception Code Capability"
         //  requirement); (2) a successful OCInvoke narrows pcc to the
         //  invoked code capability's own Base/Length; (3) an explicit
         //  CSRRW/CSRRS to one of the four new addresses -- this
         //  project's own established "software, not hardware, restores
         //  across mret" convention (mepc's own explicit
         //  advance-before-mret since Milestone 9, carried forward here
         //  rather than inventing an automatic mechanism); (4) retain.
         // ─────────────────────────────────────────────────────────
         // Minimal OS kernel Milestone B: a successful VEDA_OCRETURN
         // joins OCInvoke at the same priority tier -- both narrow PCC
         // to cs1's own Base/Length on their own real success path, the
         // actual compartment-boundary-crossing side effect. Structurally
         // identical branches (both read $veda_rs1cap_base/_length, the
         // shared rs1-capability signal every Custom-2 instruction here
         // already reads), just gated by a different instruction/
         // violation pair.
         // RTL M21-restore (Sail-parity mirror, MILESTONE_21_PCC_AUTO_RESTORE_
         // RESULTS.md): automatic PCC restore-on-mret, ported from the Sail
         // side's own veda_pcc_restore_on_xret(). Priority ordering matches
         // that design field-for-field: (1) a real trap always wins (already
         // the top-priority branch, unchanged); (2) a real mret consuming a
         // genuinely-saved mepcc (length != UNBOUNDED, i.e. a real
         // compartment WAS captured there, not just "some trap happened
         // while already unbounded") restores; (3) OCInvoke/OCReturn
         // (unchanged); (4) explicit CSRRW/CSRRS (unchanged, still honored
         // -- software retains full override, this is a default not a
         // forced behavior, matching the Sail side's own explicit-override
         // test property); (5) retain.
         $veda_pcc_base[31:0] = $reset ? 32'b0 :
                                 (>>1$veda_trap_taken) ? 32'b0 :
                                 (>>1$is_mret && (>>1$veda_mepcc_length != 20'hFFFFF)) ? >>1$veda_mepcc_base :
                                 (>>1$is_veda_ocinvoke && !(>>1$veda_ocinvoke_violation)) ? >>1$veda_rs1cap_base :
                                 (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation)) ? >>1$veda_rs1cap_base :
                                 (>>1$csr_write_en && >>1$csr_is_veda_pcc_base) ? >>1$csr_wdata[31:0] :
                                                                                   >>1$veda_pcc_base;
         $veda_pcc_length[19:0] = $reset ? 20'hFFFFF :
                                   (>>1$veda_trap_taken) ? 20'hFFFFF :
                                   (>>1$is_mret && (>>1$veda_mepcc_length != 20'hFFFFF)) ? >>1$veda_mepcc_length :
                                   (>>1$is_veda_ocinvoke && !(>>1$veda_ocinvoke_violation)) ? >>1$veda_rs1cap_length :
                                   (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation)) ? >>1$veda_rs1cap_length :
                                   (>>1$csr_write_en && >>1$csr_is_veda_pcc_length) ? >>1$csr_wdata[19:0] :
                                                                                       >>1$veda_pcc_length;
         // Real bug found (not copied blindly from Sail) while designing
         // this mirror: the pre-existing trap-time capture below was
         // UNCONDITIONAL (captured on every trap, even one that fired while
         // PCC was already unbounded). Harmless while nothing auto-consumed
         // mepcc -- but once mret starts consuming it automatically (above),
         // a second, nested trap between a first trap's save and its own
         // later mret would silently overwrite the first trap's real saved
         // bounds with {don't-care, UNBOUNDED}. Fixed by gating the capture
         // itself on `>>1$veda_pcc_length != 20'hFFFFF` (a compartment was
         // genuinely live at the moment of the trap) -- exactly the Sail
         // side's own already-adversarially-reviewed conditional-capture
         // design (veda_pcc_save_and_reset()'s own guard). Self-consuming:
         // a successful mret-restore immediately resets mepcc back to
         // {0, UNBOUNDED} so a stale value can never be restored twice --
         // the identical self-consuming property the Sail side's own design
         // already proved necessary for the same nested-trap hazard class.
         $veda_mepcc_base[31:0] = $reset ? 32'b0 :
                                   (>>1$veda_trap_taken && (>>1$veda_pcc_length != 20'hFFFFF)) ? >>1$veda_pcc_base :
                                   (>>1$is_mret && (>>1$veda_mepcc_length != 20'hFFFFF)) ? 32'b0 :
                                   (>>1$csr_write_en && >>1$csr_is_veda_mepcc_base) ? >>1$csr_wdata[31:0] :
                                                                                       >>1$veda_mepcc_base;
         $veda_mepcc_length[19:0] = $reset ? 20'hFFFFF :
                                     (>>1$veda_trap_taken && (>>1$veda_pcc_length != 20'hFFFFF)) ? >>1$veda_pcc_length :
                                     (>>1$is_mret && (>>1$veda_mepcc_length != 20'hFFFFF)) ? 20'hFFFFF :
                                     (>>1$csr_write_en && >>1$csr_is_veda_mepcc_length) ? >>1$csr_wdata[19:0] :
                                                                                           >>1$veda_mepcc_length;
         // RTL Milestone 18: plain read/write CSR, no other write source
         // (unlike veda_pcc_base/length, which also get written by a
         // successful OCInvoke/trap) -- mirrors $mtvec's own simple
         // reset/CSRRW-only pattern exactly. Reset to 0 is harmless: an
         // all-zero Length/Perms just makes the first Populate-Fast
         // object real but permission-less until software actually sets
         // this CSR, matching the Sail side's own identical reasoning.
         // 2026-08-19 widening: bits(32)->bits(36) alongside the capability
         // struct's own Length widening (veda_regs.sail:234-239) -- Perms
         // keeps its original position [15:0]; only Length's own span
         // grows, from [31:16] to [35:16].
         $veda_attr[35:0] = $reset ? 36'b0 :
                              (>>1$csr_write_en && >>1$csr_is_veda_attr) ? >>1$csr_wdata[35:0] :
                                                                            >>1$veda_attr;
         // RTL Milestone 19: veda_mode, bit 0 = veda_purecap. Identical
         // simple reset/CSRRW-only pattern as veda_attr directly above --
         // reset to 0 is the real correctness requirement here (not just
         // styling): purecap defaults OFF, so the entire pre-existing
         // 27-test RTL corpus and the 51/51 ACT4 conformance suite, none
         // of which anticipate this feature, see zero behavior change
         // until software explicitly opts in.
         // RTL Milestone 20: !(>>1$veda_csr_escape_violation) added --
         // unlike veda_pcc_base/_length/_mepcc_*, nothing else ever
         // writes veda_mode, so there is no pre-existing higher-priority
         // trap-reset branch to fall back on here; this guard is the
         // only thing preventing an attacker's csr_wdata from landing
         // while a compartment is live.
         $veda_mode[31:0] = $reset ? 32'b0 :
                              (>>1$csr_write_en && >>1$csr_is_veda_mode && !(>>1$veda_csr_escape_violation)) ? >>1$csr_wdata[31:0] :
                                                                            >>1$veda_mode;

         // OCA is deliberately absent here -- its destination (rd) is a
         // Capability Register, not a GPR (VEDA_CORE_SPEC.md Section 1:
         // funct3's dest-kind bit selects Capability Register for OCA),
         // handled entirely by /vreg's own write logic below.
         // CSetBounds/CSetBoundsExact are deliberately absent here too,
         // for the identical reason as OCA -- their destination is a
         // Capability Register (funct3 = 001, Section 1), not a GPR.
         // CSeal/CUnseal (Milestone 6) are absent for the same reason
         // again -- funct3 = 001, destination is a Capability Register.
         // OCL.C (Milestone 7) is absent for the same reason once more --
         // funct3 = 100, destination is a Capability Register (rd reused
         // as $veda_rd_cap, Section 1's own "OCL.C/OCS.C semantics"). OCS.C
         // needs no entry here at all -- its own destination is memory
         // (elfmem[]/tag_mem[], via the trailing \SV block below), not
         // any register, GPR or Capability, matching OCS.D's own absence
         // from this list. OCInvoke (Milestone 10) needs no entry either
         // -- its own destination (c15/IDC) is fixed, not GPR-written,
         // and its real destination effect is the PC redirect, not any
         // register write at all. OSpecialRW (Milestone 11) is absent
         // for the identical reason as OCA/CSetBounds/CSeal/CUnseal --
         // its `cd` is a Capability Register, not a GPR.
         // RTL Milestone 19: $is_load's own term gains
         // !$veda_purecap_violation -- an ordinary load blocked by
         // purecap enforcement must not write $rd with load data (the
         // memory access itself is also suppressed below, at /dmem's
         // read is unaffected since RAM reads have no side effect to
         // block, but the *write-back* of that data into a GPR is the
         // real thing that must never happen on a violation, matching
         // every other family's own $reg_write gating in this list).
         $reg_write = ($is_load && !$veda_purecap_violation) || $is_alu_imm || $is_alu_reg || $is_lui || $is_auipc ||
                      $is_jal || $is_jalr || $is_alu_immw || $is_alu_regw ||
                      ($is_veda_ocl && !$veda_violation) ||
                      ($is_veda_nmc_add_w && !$veda_nmc_add_w_violation) ||
                      ($is_veda_nmc_add_d && !$veda_nmc_add_d_violation) ||
                      ($is_veda_atomic && !$veda_atomic_violation) ||
                      $is_veda_capquery ||
                      ($is_veda_odt_populate && !$veda_odt_populate_violation) ||
                      ($is_veda_odt_populate_fast && !$veda_odt_populate_violation) ||
                      ($is_veda_odt_destroy  && !$veda_odt_destroy_violation) ||
                      // RTL Milestone 9: CSRRW/CSRRS always write rd
                      // with the CSR's OLD value, independent of
                      // $veda_trap_taken -- a CSR read/write is never
                      // itself a Veda-Core violation, and real Zicsr
                      // semantics give rd the pre-write value
                      // unconditionally (matching every prior /xreg
                      // write-gating convention in this file: gate on
                      // "is this instruction real", not on an
                      // unrelated signal).
                      $is_csr_access;

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
         // RTL Milestone 9: a real hard trap now genuinely redirects
         // control flow (PC = mtvec), the same real property Sail has
         // enforced since Milestone V-A/B and RTL has, until now,
         // never actually delivered -- every prior RTL milestone's own
         // "violation suppresses write" floor left PC unaffected,
         // meaning execution silently continued past a blocked access.
         // Checked before MRET (both can't be true from the same
         // instruction -- MRET is its own, unrelated opcode -- but
         // trap takes priority in the mux ordering as the more
         // security-critical of the two, matching this file's own
         // established "most critical condition first" mux style).
         // RTL Milestone 10: OCInvoke's own real jump -- checked after
         // $veda_trap_taken (an OCInvoke that fails its own checks is
         // already routed to $veda_trap_taken above, never reaches
         // here) but the success path is a real, unconditional hardware
         // redirect, the literal "atomic unseal-and-jump" CHERI's own
         // real CInvoke performs (CHERI ISA spec p.209's own
         // `nextPC = newPC` on the success path) -- not a two-
         // instruction unseal-then-JALR software sequence.
         // RTL Milestone 17: OCJALR's own real jump, the same real
         // unconditional-hardware-redirect shape OCInvoke's own jump
         // above already established (a failing OCJALR is already
         // routed to $veda_trap_taken, never reaches here).
         // Minimal OS kernel Milestone B: VEDA_OCRETURN's own real jump
         // joins the same unconditional-hardware-redirect family as
         // OCInvoke/OCJALR above (a failing OCRETURN is already routed
         // to $veda_trap_taken, never reaches here).
         $pc_src = $veda_trap_taken || $is_mret ||
                   ($is_veda_ocinvoke && !$veda_ocinvoke_violation) ||
                   ($is_veda_ocjalr && !$veda_ocjalr_violation) ||
                   ($is_veda_ocreturn && !$veda_ocreturn_violation) ||
                   $is_jal || $is_jalr || $branch_taken;
         $alt_pc[63:0] = $veda_trap_taken ? $mtvec :
                          $is_mret         ? $mepc :
                          ($is_veda_ocinvoke && !$veda_ocinvoke_violation) ? $veda_ocinvoke_target :
                          ($is_veda_ocjalr && !$veda_ocjalr_violation) ? $veda_ocjalr_target :
                          ($is_veda_ocreturn && !$veda_ocreturn_violation) ? $veda_ocreturn_target :
                          $is_jal ? $jal_target : $is_jalr ? $jalr_target : $branch_target;

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
         // RTL MILESTONE 19 (Sail mirror): Veda-Purecap Enforcement --
         // closes the real CGetBase-then-ordinary-load/store bypass
         // (`cgetbase x1,c2` then a plain `ld`/`sd` through x1 completely
         // skips every Veda-Core check). An ordinary base-ISA load/store
         // traps if EITHER veda_mode's own purecap bit is set (a global
         // "no ordinary load/store anywhere" switch) OR the live
         // compartment is narrowed away from VEDA_PCC_UNBOUNDED (code
         // entered via a successful OCInvoke can otherwise still read/
         // write memory directly, undermining the isolation OCInvoke/PCC
         // -bounding is meant to provide) -- both trigger conditions
         // verified directly against MILESTONE_19_RESULTS.md's own Sail
         // design before writing this. Deliberately does NOT touch any
         // Veda-Core instruction's own memory path ($veda_ocl_load_data,
         // OCS.D's write, etc.) -- those already go through their own,
         // separate capability checks entirely (veda_check_access), zero
         // shared code path by construction, matching the Sail side's own
         // "never interferes with a legitimate Veda access" guarantee.
         $veda_purecap_violation = ($is_load || $is_store) &&
                                    ($veda_mode[0] || ($veda_pcc_length != 20'hFFFFF));
         // VEDA-CORE RTL MILESTONE 7: base ISA stores can land inside the
         // same real elfmem[] region Veda-Core objects live in (in
         // act4_mode) -- must clear that granule's tag too (see the byte-
         // granular tag invalidation comment near $veda_capmem_granule
         // above). Real bounds check needed here, unlike the Veda-only
         // granule signals above: an ordinary base-ISA store's address
         // isn't capability-checked, so it can legitimately land outside
         // ELFMEM_BASE/ELFMEM_SIZE (act4_mode is off) or even, in
         // principle, out of range within act4_mode -- guarded rather
         // than assumed in-range.
         $veda_baseisa_store_in_range = ($mem_addr[31:0] >= ELFMEM_BASE) && ($mem_addr[31:0] < (ELFMEM_BASE + ELFMEM_SIZE));
         $veda_baseisa_store_granule[31:0] = ($mem_addr[31:0] - ELFMEM_BASE) >> 4;
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

         // VEDA-CORE: OCL.D's own 8-byte little-endian read, same shape
         // as $mem_bytes_elf above but at $veda_real_addr (the capability-
         // resolved location, Base+offset), not $mem_addr -- a real,
         // separate physical target from the base ISA's own loads, not
         // a reinterpretation of the same address computation.
         $veda_ocl_load_data[63:0] =
            {elfmem[$veda_real_addr[31:0]+7], elfmem[$veda_real_addr[31:0]+6],
             elfmem[$veda_real_addr[31:0]+5], elfmem[$veda_real_addr[31:0]+4],
             elfmem[$veda_real_addr[31:0]+3], elfmem[$veda_real_addr[31:0]+2],
             elfmem[$veda_real_addr[31:0]+1], elfmem[$veda_real_addr[31:0]+0]};

         // OCL.C's own 17-byte little-endian read (Milestone 7, widened
         // 2026-08-19) -- same real shape as OCL.D's 8-byte read directly
         // above, at the identical $veda_real_addr. Feeds /vreg's own new
         // OCL.C write source below, not $load_data/$wr_data (this
         // instruction's destination is a Capability Register, not a
         // GPR -- same reason OCA/CSetBounds/CSeal/CUnseal are absent
         // from $reg_write below).
         // MILESTONE 24 Stage 3: real address-range mux -- a TCM-tier
         // OCL.C reads from tcm_scratch[] (real, separate array, never
         // elfmem[] itself, matching the design's own genuinely-separate
         // -array precedent), a DRAM-tier one reads from elfmem[]
         // exactly as every prior milestone already did.
         $veda_oclc_load_data[135:0] =
            $veda_capmem_tcm_hit ?
            {tcm_scratch[$veda_real_addr[31:0]+16],
             tcm_scratch[$veda_real_addr[31:0]+15], tcm_scratch[$veda_real_addr[31:0]+14],
             tcm_scratch[$veda_real_addr[31:0]+13], tcm_scratch[$veda_real_addr[31:0]+12],
             tcm_scratch[$veda_real_addr[31:0]+11], tcm_scratch[$veda_real_addr[31:0]+10],
             tcm_scratch[$veda_real_addr[31:0]+9],  tcm_scratch[$veda_real_addr[31:0]+8],
             tcm_scratch[$veda_real_addr[31:0]+7],  tcm_scratch[$veda_real_addr[31:0]+6],
             tcm_scratch[$veda_real_addr[31:0]+5],  tcm_scratch[$veda_real_addr[31:0]+4],
             tcm_scratch[$veda_real_addr[31:0]+3],  tcm_scratch[$veda_real_addr[31:0]+2],
             tcm_scratch[$veda_real_addr[31:0]+1],  tcm_scratch[$veda_real_addr[31:0]+0]} :
            {elfmem[$veda_real_addr[31:0]+16],
             elfmem[$veda_real_addr[31:0]+15], elfmem[$veda_real_addr[31:0]+14],
             elfmem[$veda_real_addr[31:0]+13], elfmem[$veda_real_addr[31:0]+12],
             elfmem[$veda_real_addr[31:0]+11], elfmem[$veda_real_addr[31:0]+10],
             elfmem[$veda_real_addr[31:0]+9],  elfmem[$veda_real_addr[31:0]+8],
             elfmem[$veda_real_addr[31:0]+7],  elfmem[$veda_real_addr[31:0]+6],
             elfmem[$veda_real_addr[31:0]+5],  elfmem[$veda_real_addr[31:0]+4],
             elfmem[$veda_real_addr[31:0]+3],  elfmem[$veda_real_addr[31:0]+2],
             elfmem[$veda_real_addr[31:0]+1],  elfmem[$veda_real_addr[31:0]+0]};
         // Field-for-field the inverse of $veda_ocsc_packed's own pack
         // order above (Object_ID @ Base @ Length @ Offset @ Perms @
         // otype @ Reserved @ 1'b0 padding) -- matching the Sail model's
         // veda_cap_unpack exactly. Slice widths/positions are the RTL
         // mirror of veda_types.sail's own 136-bit veda_cap_unpack,
         // widened 2026-08-19.
         $veda_oclc_unpacked_object_id[22:0] = $veda_oclc_load_data[135:113];
         $veda_oclc_unpacked_base[31:0]      = $veda_oclc_load_data[112:81];
         $veda_oclc_unpacked_length[19:0]    = $veda_oclc_load_data[80:61];
         $veda_oclc_unpacked_offset[19:0]    = $veda_oclc_load_data[60:41];
         $veda_oclc_unpacked_perms[15:0]     = $veda_oclc_load_data[40:25];
         $veda_oclc_unpacked_otype[15:0]     = $veda_oclc_load_data[24:9];
         $veda_oclc_unpacked_reserved[7:0]   = $veda_oclc_load_data[8:1];
         // The memory-resident Tag -- a capability loaded from memory is
         // only as trustworthy as what a real OCS.C genuinely stored
         // there (tag_mem[]), never assumed true just because the load
         // itself succeeded (real CHERI's own core tagged-memory
         // property, already the load-bearing reason this milestone
         // exists, restated here at the point it's actually enforced).
         // MILESTONE 24 Stage 3: the SAME tier decision selects the tag
         // source AND its own tier-relative granule index -- reading
         // tag_mem[] with a tcm_scratch-relative granule (or vice versa)
         // is exactly the aliasing/overflow risk flagged before writing
         // this; both index AND array must switch together.
         // NEW (2026-08-19 widening): AND of BOTH granules a 17-byte
         // capability's own real footprint spans (idx and idx+1) --
         // mirrors mem_metadata.sail's own __ReadRAM_Meta fix (t0 & t1):
         // a capability is only genuinely valid if EVERY granule it spans
         // still reads back tagged.
         $veda_oclc_loaded_tag = $veda_capmem_tcm_hit ?
            (tcm_scratch_tag[$veda_capmem_tcm_granule] & tcm_scratch_tag[$veda_capmem_tcm_granule2]) :
            (tag_mem[$veda_capmem_granule] & tag_mem[$veda_capmem_granule2]);

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
            // RTL Milestone 19: !(|cpu>>1$veda_purecap_violation) added,
            // matching the real elfmem write block's own identical gate
            // below -- kept consistent even though every real milestone
            // test exercises the elfmem (act4_mode) path, not this
            // Milestone A/B-era ROM-testing one.
            $wr_en = |cpu>>1$is_store &&
                     !(|cpu>>1$veda_purecap_violation) &&
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
            $is_veda_ocl               ? $veda_ocl_load_data :
            ($is_veda_nmc_add_w || $is_veda_nmc_add_d) ? $veda_nmc_rd_value :
            $is_veda_atomic                              ? $veda_cap_old_d :
            $is_veda_capquery                              ? $veda_capquery_result :
            // rd = 0 on success, matching Sail's own "X(rd) = zeros()"
            // exactly (VEDA_CORE_SPEC.md Section 5.1: "rd unused (written
            // 0 on success)"). Irrelevant when a violation suppresses the
            // write ($reg_write already gates that off above).
            ($is_veda_odt_populate || $is_veda_odt_populate_fast || $is_veda_odt_destroy) ? 64'b0 :
            // RTL Milestone 9: rd = the CSR's value from BEFORE this
            // write (real CSRRW/CSRRS semantics) -- $csr_rdata is read
            // combinationally in the same cycle the write is computed,
            // matching real hardware's own atomic "read-then-write"
            // CSR access.
            $is_csr_access ? $csr_rdata :
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
      // RTL Milestone 19: !CPU_veda_purecap_violation_a0 added -- an
      // ordinary base-ISA store blocked by purecap enforcement must not
      // write elfmem at all (the real, previously-open bypass this
      // milestone closes: a raw address extracted via cgetbase followed
      // by a plain sd used to reach this exact write, completely
      // unchecked).
      if (act4_mode && CPU_is_store_a0 && !CPU_veda_purecap_violation_a0) begin
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
         // Milestone 7: byte-granular tag invalidation -- an ordinary
         // base-ISA store landing inside the same real elfmem[] region a
         // Veda-Core object's tagged capability might occupy must clear
         // that granule's tag, the identical real property every Veda
         // write block below also now enforces. Gated on
         // CPU_veda_baseisa_store_in_range_a0 -- tag_mem[] is a real,
         // bounded array (ELFMEM_SIZE/16 entries), an out-of-range index
         // here would be a real simulation error, not assumed safe.
         if (CPU_veda_baseisa_store_in_range_a0) begin
            tag_mem[CPU_veda_baseisa_store_granule_a0] <= 1'b0;
         end
      end
   end

   // VEDA-CORE: OCS.D's own store into elfmem, a real, separate
   // always_ff block rather than folding into the block above --
   // deliberately kept independent of the base ISA's own $is_store/
   // $mem_addr signals (a different physical-address computation and a
   // different value source, $veda_ocs_value via $rd, not $rs2_data) so
   // this new logic carries zero risk of regressing the base core's own
   // already-verified 51/51 ACT4 RV64I conformance. Gated on
   // !CPU_veda_violation_a0 -- the real security property this
   // milestone can actually enforce without trap infrastructure
   // (MILESTONE_PLAN.md item 2): an illegal OCS.D simply never writes.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_is_veda_ocs_a0 && !CPU_veda_violation_a0) begin
         elfmem[CPU_veda_real_addr_a0[31:0]+0] <= CPU_veda_ocs_value_a0[7:0];
         elfmem[CPU_veda_real_addr_a0[31:0]+1] <= CPU_veda_ocs_value_a0[15:8];
         elfmem[CPU_veda_real_addr_a0[31:0]+2] <= CPU_veda_ocs_value_a0[23:16];
         elfmem[CPU_veda_real_addr_a0[31:0]+3] <= CPU_veda_ocs_value_a0[31:24];
         elfmem[CPU_veda_real_addr_a0[31:0]+4] <= CPU_veda_ocs_value_a0[39:32];
         elfmem[CPU_veda_real_addr_a0[31:0]+5] <= CPU_veda_ocs_value_a0[47:40];
         elfmem[CPU_veda_real_addr_a0[31:0]+6] <= CPU_veda_ocs_value_a0[55:48];
         elfmem[CPU_veda_real_addr_a0[31:0]+7] <= CPU_veda_ocs_value_a0[63:56];
         // Milestone 7: byte-granular tag invalidation -- this is the
         // exact real gap Milestone 7's own negative test caught (not
         // assumed correct from the design alone): an OCS.D that lands
         // in the same granule a real OCS.C previously tagged must clear
         // that tag, or a capability's own raw bytes could be silently
         // corrupted while tag_mem[] kept reporting it as still valid.
         tag_mem[CPU_veda_capmem_granule_a0] <= 1'b0;
      end
   end

   // VEDA-CORE RTL MILESTONE 2: NMC_ADD.{W,D}'s own real-memory
   // read-modify-write. The read half is already combinational
   // ($veda_cap_old_d/_w, consumed both for the ALU result computed in
   // TLV and for rd's writeback), so only the write half needs a real
   // synchronous always_ff -- the identical single-cycle RMW pattern
   // already proven for the base ISA's own stores and for OCS.D above,
   // just with the write DATA now computed from a real ALU operation
   // rather than a passthrough GPR value.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_is_veda_nmc_add_d_a0 && !CPU_veda_nmc_add_d_violation_a0) begin
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+0] <= CPU_veda_nmc_add_result_d_a0[7:0];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+1] <= CPU_veda_nmc_add_result_d_a0[15:8];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+2] <= CPU_veda_nmc_add_result_d_a0[23:16];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+3] <= CPU_veda_nmc_add_result_d_a0[31:24];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+4] <= CPU_veda_nmc_add_result_d_a0[39:32];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+5] <= CPU_veda_nmc_add_result_d_a0[47:40];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+6] <= CPU_veda_nmc_add_result_d_a0[55:48];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+7] <= CPU_veda_nmc_add_result_d_a0[63:56];
      end else if (act4_mode && CPU_is_veda_nmc_add_w_a0 && !CPU_veda_nmc_add_w_violation_a0) begin
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+0] <= CPU_veda_nmc_add_result_w_a0[7:0];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+1] <= CPU_veda_nmc_add_result_w_a0[15:8];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+2] <= CPU_veda_nmc_add_result_w_a0[23:16];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+3] <= CPU_veda_nmc_add_result_w_a0[31:24];
      end
      // Milestone 7: byte-granular tag invalidation, both W and D --
      // real-memory compute-at-memory writes are exactly the kind of
      // plain, non-OCS.C write that must clear a granule's tag if it
      // overlaps one, the same real property every other write block in
      // this file now enforces.
      if (act4_mode && ((CPU_is_veda_nmc_add_d_a0 && !CPU_veda_nmc_add_d_violation_a0) ||
                         (CPU_is_veda_nmc_add_w_a0 && !CPU_veda_nmc_add_w_violation_a0))) begin
         tag_mem[CPU_veda_capmem_nmc_granule_a0] <= 1'b0;
      end
   end

   // VEDA-CORE RTL MILESTONE 2: Veda-Atomic's own real-memory
   // read-modify-write, D-width only this milestone (matching the decode
   // scope above). Same real pattern as NMC_ADD's own write block.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_is_veda_atomic_a0 && !CPU_veda_atomic_violation_a0) begin
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+0] <= CPU_veda_atomic_result_a0[7:0];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+1] <= CPU_veda_atomic_result_a0[15:8];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+2] <= CPU_veda_atomic_result_a0[23:16];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+3] <= CPU_veda_atomic_result_a0[31:24];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+4] <= CPU_veda_atomic_result_a0[39:32];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+5] <= CPU_veda_atomic_result_a0[47:40];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+6] <= CPU_veda_atomic_result_a0[55:48];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+7] <= CPU_veda_atomic_result_a0[63:56];
         // Milestone 7: byte-granular tag invalidation -- same real
         // property, Veda-Atomic's own write.
         tag_mem[CPU_veda_capmem_nmc_granule_a0] <= 1'b0;
      end
   end

   // VEDA-CORE RTL MILESTONE 4: ODT-Populate/ODT-Destroy's own real
   // write into odt_mem[] -- the same real byte-addressable array
   // Object-Bind/OCL/OCS/etc. already read from above, written here for
   // the first time. Gated on !CPU_veda_odt_populate_violation_a0 /
   // !CPU_veda_odt_destroy_violation_a0 -- MILESTONE_PLAN.md's Milestone
   // 4 addendum's real $priv gate, the identical violation-suppresses-
   // write convention already used for every other soft-fail in this
   // file, now closing the one real gap (minting new capability-granting
   // authority from raw values) that convention alone couldn't cover
   // without $priv existing first. act4_mode-gated to match every other
   // Veda-Core write block in this file, even though odt_mem[] itself
   // (unlike elfmem) doesn't actually depend on an ELF load -- kept
   // consistent rather than a one-off exception, since every real
   // Veda-Core instruction test in this project already runs under
   // +elf_hex/act4_mode anyway.
   always_ff @(posedge clk) begin
      if (act4_mode && (CPU_is_veda_odt_populate_a0 || CPU_is_veda_odt_populate_fast_a0) && !CPU_veda_odt_populate_violation_a0) begin
         odt_mem[CPU_veda_odt_addr_a0+0] <= CPU_veda_odtpd_new_base_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+1] <= CPU_veda_odtpd_new_base_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+2] <= CPU_veda_odtpd_new_base_a0[23:16];
         odt_mem[CPU_veda_odt_addr_a0+3] <= CPU_veda_odtpd_new_base_a0[31:24];
         odt_mem[CPU_veda_odt_addr_a0+4] <= CPU_veda_odtpd_new_length_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+5] <= CPU_veda_odtpd_new_length_a0[15:8];
         // Length widened 16->20 bits, 2026-08-19: the new upper nibble
         // lands in byte +14 (previously fully spare), mirroring the read
         // side above -- zero-padded in the top 4 bits of the byte, the
         // same partially-used-byte convention already used for +9's
         // valid bit and +13's retired bit.
         odt_mem[CPU_veda_odt_addr_a0+14] <= {4'b0, CPU_veda_odtpd_new_length_a0[19:16]};
         odt_mem[CPU_veda_odt_addr_a0+6] <= CPU_veda_odtpd_new_perms_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+7] <= CPU_veda_odtpd_new_perms_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+8] <= CPU_veda_odtpd_new_gen_a0;
         odt_mem[CPU_veda_odt_addr_a0+9] <= 8'h01;
         // RTL MILESTONE 15: record the real full Object_ID's upper 15
         // bits in the real, previously-unused bytes +11/+12, so a
         // later low-byte-aliasing lookup can be told apart from the
         // object that genuinely owns this slot (the two new checks
         // above).
         odt_mem[CPU_veda_odt_addr_a0+11] <= CPU_veda_object_id_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+12] <= {1'b0, CPU_veda_object_id_a0[22:16]};
         // RTL MILESTONE 16: commit the retirement bit computed above --
         // once generation would wrap, this slot can never legitimately
         // distinguish a new object from an old one again, so ODT
         // -Populate itself is permanently refused for it from here on
         // ($veda_odt_populate_violation, above).
         odt_mem[CPU_veda_odt_addr_a0+13] <= {7'b0, CPU_veda_odtpd_new_retired_a0};
      end else if (act4_mode && CPU_is_veda_odt_destroy_a0 && !CPU_veda_odt_destroy_violation_a0) begin
         odt_mem[CPU_veda_odt_addr_a0+8] <= CPU_veda_odtpd_new_gen_a0;
         odt_mem[CPU_veda_odt_addr_a0+9] <= 8'h00;
         odt_mem[CPU_veda_odt_addr_a0+13] <= {7'b0, CPU_veda_odtpd_new_retired_a0};
      end
   end

   // VEDA-CORE RTL MILESTONE 12: owner-hart claim/re-claim write-back --
   // the real, first-time consumer of odt_mem[]'s own byte offset +10.
   // Fires on every successful Bind/Bind-NoTrap/Rebind (gated by
   // CPU_veda_owner_claim_en_a0, already mutually exclusive from plain
   // Bind's own hard-trap path by construction -- see the TLV-side
   // comment above), claiming the ODT slot for MHARTID regardless of
   // whether it was already unowned or already owned by this same hart
   // -- mirrors veda_bind_insts.sail's own unconditional `claimed_entry`
   // write on every success path, not just first-time claims.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_veda_owner_claim_en_a0) begin
         odt_mem[CPU_veda_odt_addr_a0+10] <= MHARTID;
      end
   end

   // VEDA-CORE RTL MILESTONE 7: OCS.C's own real store -- 16 bytes of
   // packed capability data into elfmem[] (the identical little-endian
   // byte-write shape OCS.D already uses, doubled in width) PLUS the
   // real, out-of-band Tag into tag_mem[] at the same granule OCL.C's
   // own read side indexes (CPU_veda_capmem_granule_a0). Gated on
   // !CPU_veda_ocsc_violation_a0 -- the identical violation-suppresses-
   // write convention as every other Veda-Core store in this file. An
   // untagged source capability (CPU_veda_ocsc_store_tag_a0 = 0) still
   // stores its real field bits -- matching real CHERI's own behavior
   // (storing an invalid capability is legal; it just cannot be loaded
   // back as valid) -- the tag_mem[] write below correctly records
   // "not a real capability" for those bytes either way, not skipped.
   // MILESTONE 24 Stage 3: the same real address-range decision
   // (CPU_veda_capmem_tcm_hit_a0) selects tcm_scratch[]/tcm_scratch_tag[]
   // (real, separate arrays) instead of elfmem[]/tag_mem[] -- array AND
   // granule index switch together, the same paired discipline the read
   // side above already applies, closing the same aliasing/overflow risk
   // on the write side too.
   always_ff @(posedge clk) begin
      // NEW (2026-08-19 widening): !CPU_veda_ocsc_align_violation_a0 added
      // to both branch gates below -- the identical violation-suppresses
      // -write convention already applied to !CPU_veda_ocsc_violation_a0,
      // now extended to the new 32-byte-alignment violation, so a
      // misaligned-but-otherwise-legal OCS.C cannot commit its bytes/tag
      // to memory before the trap takes effect.
      if (act4_mode && CPU_is_veda_ocs_c_a0 && !CPU_veda_ocsc_violation_a0 && !CPU_veda_ocsc_align_violation_a0 && CPU_veda_capmem_tcm_hit_a0) begin
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+0]  <= CPU_veda_ocsc_packed_a0[7:0];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+1]  <= CPU_veda_ocsc_packed_a0[15:8];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+2]  <= CPU_veda_ocsc_packed_a0[23:16];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+3]  <= CPU_veda_ocsc_packed_a0[31:24];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+4]  <= CPU_veda_ocsc_packed_a0[39:32];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+5]  <= CPU_veda_ocsc_packed_a0[47:40];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+6]  <= CPU_veda_ocsc_packed_a0[55:48];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+7]  <= CPU_veda_ocsc_packed_a0[63:56];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+8]  <= CPU_veda_ocsc_packed_a0[71:64];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+9]  <= CPU_veda_ocsc_packed_a0[79:72];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+10] <= CPU_veda_ocsc_packed_a0[87:80];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+11] <= CPU_veda_ocsc_packed_a0[95:88];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+12] <= CPU_veda_ocsc_packed_a0[103:96];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+13] <= CPU_veda_ocsc_packed_a0[111:104];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+14] <= CPU_veda_ocsc_packed_a0[119:112];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+15] <= CPU_veda_ocsc_packed_a0[127:120];
         // NEW (2026-08-19 widening): 17th byte-lane, the new top byte of
         // the widened 136-bit pack.
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+16] <= CPU_veda_ocsc_packed_a0[135:128];
         // NEW (2026-08-19 widening): 2 adjacent, contiguous granule
         // writes (never a runtime-variable span) -- per the decided
         // design, the tag granule STAYS 16 bytes unchanged, so a 17-byte,
         // 32-byte-aligned capability-store always spans exactly its own
         // start granule and the very next one.
         tcm_scratch_tag[CPU_veda_capmem_tcm_granule_a0]  <= CPU_veda_ocsc_store_tag_a0;
         tcm_scratch_tag[CPU_veda_capmem_tcm_granule2_a0] <= CPU_veda_ocsc_store_tag_a0;
      end else if (act4_mode && CPU_is_veda_ocs_c_a0 && !CPU_veda_ocsc_violation_a0 && !CPU_veda_ocsc_align_violation_a0) begin
         elfmem[CPU_veda_real_addr_a0[31:0]+0]  <= CPU_veda_ocsc_packed_a0[7:0];
         elfmem[CPU_veda_real_addr_a0[31:0]+1]  <= CPU_veda_ocsc_packed_a0[15:8];
         elfmem[CPU_veda_real_addr_a0[31:0]+2]  <= CPU_veda_ocsc_packed_a0[23:16];
         elfmem[CPU_veda_real_addr_a0[31:0]+3]  <= CPU_veda_ocsc_packed_a0[31:24];
         elfmem[CPU_veda_real_addr_a0[31:0]+4]  <= CPU_veda_ocsc_packed_a0[39:32];
         elfmem[CPU_veda_real_addr_a0[31:0]+5]  <= CPU_veda_ocsc_packed_a0[47:40];
         elfmem[CPU_veda_real_addr_a0[31:0]+6]  <= CPU_veda_ocsc_packed_a0[55:48];
         elfmem[CPU_veda_real_addr_a0[31:0]+7]  <= CPU_veda_ocsc_packed_a0[63:56];
         elfmem[CPU_veda_real_addr_a0[31:0]+8]  <= CPU_veda_ocsc_packed_a0[71:64];
         elfmem[CPU_veda_real_addr_a0[31:0]+9]  <= CPU_veda_ocsc_packed_a0[79:72];
         elfmem[CPU_veda_real_addr_a0[31:0]+10] <= CPU_veda_ocsc_packed_a0[87:80];
         elfmem[CPU_veda_real_addr_a0[31:0]+11] <= CPU_veda_ocsc_packed_a0[95:88];
         elfmem[CPU_veda_real_addr_a0[31:0]+12] <= CPU_veda_ocsc_packed_a0[103:96];
         elfmem[CPU_veda_real_addr_a0[31:0]+13] <= CPU_veda_ocsc_packed_a0[111:104];
         elfmem[CPU_veda_real_addr_a0[31:0]+14] <= CPU_veda_ocsc_packed_a0[119:112];
         elfmem[CPU_veda_real_addr_a0[31:0]+15] <= CPU_veda_ocsc_packed_a0[127:120];
         // NEW (2026-08-19 widening): 17th byte-lane, the new top byte of
         // the widened 136-bit pack.
         elfmem[CPU_veda_real_addr_a0[31:0]+16] <= CPU_veda_ocsc_packed_a0[135:128];
         // NEW (2026-08-19 widening): 2 adjacent, contiguous granule
         // writes -- the elfmem-tier's own mirror of the TCM-tier fix
         // above; same real reason (tag granule stays 16 bytes, capability
         // is now 17 bytes, 32-byte alignment guarantees exactly 2
         // adjacent granules).
         tag_mem[CPU_veda_capmem_granule_a0]  <= CPU_veda_ocsc_store_tag_a0;
         tag_mem[CPU_veda_capmem_granule2_a0] <= CPU_veda_ocsc_store_tag_a0;
      end
   end
   endmodule
