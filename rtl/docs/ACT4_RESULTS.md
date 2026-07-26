# ACT4 RV64I Conformance Results — Milestone C/D

**Date:** 2026-07-20
**Core:** `rtl/rv64i_core.tlv` (single-cycle RV64I, 50 encodings)
**Config:** `act4-verify/config/cores/veda/rva23-base-rv64i/`

## Result

**51/51 RV64I `I` extension tests PASS** (`EXTENSIONS=I` build, real self-checking
`elfs/rv64i/I/*.elf` artifacts — see note below on artifact selection).

```
I-add-00 I-addi-00 I-addiw-00 I-addw-00 I-and-00 I-andi-00 I-auipc-00 I-beq-00
I-bge-00 I-bgeu-00 I-blt-00 I-bltu-00 I-bne-00 I-fence-00 I-jal-00 I-jalr-00
I-lb-00 I-lbu-00 I-ld-00 I-lh-00 I-lhu-00 I-lui-00 I-lw-00 I-lwu-00 I-nop-00
I-or-00 I-ori-00 I-sb-00 I-sd-00 I-sh-00 I-sll-00 I-slli-00 I-slliw-00
I-sllw-00 I-slt-00 I-slti-00 I-sltiu-00 I-sltu-00 I-sra-00 I-srai-00
I-sraiw-00 I-sraw-00 I-srl-00 I-srli-00 I-srliw-00 I-srlw-00 I-sub-00
I-subw-00 I-sw-00 I-xor-00 I-xori-00
== all PASS ==
```

No exceptions or UNSPECIFIED-behavior divergences needed — a clean 100%.

## Toolchain versions

- SandPiper: 1.14-2022/10/10-beta-Pro (Redwood EDA)
- Icarus Verilog: 12.0 (stable)
- GCC: riscv64-unknown-elf-gcc (riscv-collab, g6afcc4f6d) 16.1.0
- Sail reference model: sail-riscv @ eefefd4e (2026-07-15)

## Two real bugs found and fixed during this milestone

1. **RTL bug — SLLI/SRLI/SRAI misdecoded for shift amounts >= 32.** The
   discriminator used the full `funct7 = instr[31:25]`, but bit 25 is
   actually `shamt[5]` for these RV64 shift-immediate instructions, not
   part of the opcode discriminator. Fixed by adding a dedicated
   `$funct6 = instr[31:26]` and using it only for SLLI/SRLI/SRAI (the `*W`
   shift-immediate variants correctly keep the full funct7, since their
   5-bit shamt doesn't extend into bit 25). Verified by cross-checking the
   resulting SP/GP register values against Sail's own reference trace for
   the same boot sequence — exact bit-for-bit match.

2. **Testbench protocol bug — naive `tohost != 0` polling.** This ACT4
   DUT config's `rvmodel_macros.h` uses `tohost` for two purposes: the
   real PASS/FAIL halt code (`RVMODEL_HALT_PASS/FAIL`, low word = 1 or 3,
   high word always 0, spins forever) AND character-by-character
   diagnostic string output on the failure-report path
   (`RVMODEL_IO_WRITE_STR`, low word = one ASCII byte, high word =
   `0x01010000`). A single-cycle poll of "low word nonzero" catches the
   first diagnostic character (confirmed: `0x0000000a` = `'\n'`, the first
   byte of `failstr`). Fixed `tb_act4.sv` to require BOTH words match the
   real halt signature (low nonzero, high exactly 0) AND remain stable for
   several cycles (the halt code spins forever; character prints move on
   within 1-2 cycles) before declaring PASS/FAIL.

## One critical process bug found and fixed

3. **Wrong ELF artifact.** `run_act4_tests.sh`'s default `ELF_DIR` pointed
   at `act4-verify/work/rva23-base-rv64i/build/rv64i/I/*.sig.elf` — the
   intermediate, non-self-checking build (compiled with `-DSIGNATURE`,
   used only to generate the golden reference signature via the Sail
   model; it never compares anything at runtime and always halts PASS
   regardless of DUT correctness). Confirmed via a negative-control test:
   a deliberately-broken AND ALU op still reported PASS against `.sig.elf`.
   The real self-checking artifact is `elfs/rv64i/I/*.elf` (`final_elf` in
   `framework/src/act/build_plan.py`), compiled with `-DRVTEST_SELFCHECK`
   and the Sail-derived reference signature baked in. Fixed the script's
   default path. Re-validated: the same broken-AND negative control now
   correctly reports `FAIL (tohost=0x00000003)` against the real artifact.

## Negative control (Milestone C done-criterion #3)

- AND+ANDI both broken (`&` -> `|`): `TIMEOUT` (the diagnostic/failure
  handler itself uses ANDI for register-field extraction, so the failure
  path itself got corrupted -- a hang, not a clean FAIL, but still
  correctly NOT a false PASS).
- AND alone broken, ANDI left correct: clean `FAIL (tohost=0x00000003)` --
  the real `RVMODEL_HALT_FAIL` code, confirming the self-check + testbench
  correctly detect a wrong DUT result end-to-end.
