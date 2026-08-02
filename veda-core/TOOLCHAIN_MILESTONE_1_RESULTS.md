# Veda-Core Toolchain Milestone 1: `.insn`-Based Hex Elimination

**Date:** 2026-07-31
**Scope:** the first, lowest-risk step of the new Veda-Core toolchain initiative
(assembler, debugger, compiler, software models — triggered by Simon Moore's real
cl-cheri-discuss question about toolchain maturity). Every existing test program in
this project encoded Veda-Core's custom instructions as raw `.word 0xHEXVALUE  #
comment` — this milestone eliminates that entirely, using only the real, official,
already-installed `riscv64-unknown-elf-as` (GNU Binutils 2.46) and its `.insn`
pseudo-op, which was verified this session to already work, unpatched, on this exact
toolchain.

## What changed

A mechanical, semantics-free Python converter (scratchpad, not committed) scanned
every `.S` file under `veda-core/` for `.word 0xHEX # comment` / `.word 0xHEX //
comment` lines, decoded each raw 32-bit value using only the standard, architecture
-invariant RISC-V R-type/I-type bit-field layout (`funct7[31:25] rs2[24:20]
rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]` for R-type; `imm[31:20] rs1[19:15]
funct3[14:12] rd[11:7] opcode[6:0]` for I-type), and re-emitted the identical
encoding as `.insn r opcode, funct3, funct7, rd, rs1, rs2` or `.insn i opcode,
funct3, rd, rs1, imm`. The only discriminator needed between R-type and I-type is
real and already spec-confirmed: within Custom-0 (`opcode=0x0B`) specifically,
`funct3=0x5` (101) is the Object-Bind family's own I-type marker; every other
`(opcode, funct3)` combination among the three Veda-Core custom opcodes (`0x0B`,
`0x2B`, `0x5B`) is R-type.

**76 files, 599 instructions converted.** Two comment styles were present in the
existing test corpus (`#` and `//`) — the first converter draft only matched `#`,
silently missing 30 lines; caught by comparing the converter's own line count
against a plain `grep` count of every `.word 0x` line before trusting the result,
not assumed correct on the first pass.

Example, before/after (`veda_smoke_m18_neg.S`):
```
.word 0x0820800b        # veda.odt.populate.fast x0, x1, x2
.insn r 0x0b, 0x0, 0x04, x0, x1, x2  // veda.odt.populate.fast x0, x1, x2
```

## Why this is safe — verified, not assumed

Register operands in `.insn`'s syntax (`x0`-`x31`) are pure 5-bit field-value
selectors, not semantic register-file references — writing `x3` in an `.insn` line
tells the assembler "place the value 3 in this bit position," regardless of whether
that position conventionally means a GPR or (per Veda-Core's own real semantics for
Custom-2) a capability register index. This makes the conversion a genuine, safe,
value-preserving bit-field round trip requiring zero Sail-semantic knowledge — only
the RISC-V ISA manual's own standard format diagrams, already read in full earlier
in this project.

## Verification (real, not "should work")

1. **Byte-for-byte re-encoding check**: every one of the 599 converted `.insn` lines
   was assembled in a single combined file via the real, unmodified
   `riscv64-unknown-elf-as`, `objdump -d`'d, and its resulting raw machine code
   compared word-for-word, in order, against the original `.word` value it replaced.
   **599/599 identical, zero mismatches.**
2. **Full regression, zero tolerance for behavior change**: all three existing test
   suites re-run unchanged against the converted files:
   - Sail self-check suite (`sail_tests/run_veda_selfcheck_tests.sh`): **30/30 PASS**
     (unchanged from pre-conversion).
   - RTL smoke test suite (`rtl/run_veda_smoke_test.sh`): **27/27 `TEST PASSED`, 0
     `TEST FAILED`** (unchanged).
   - Real ACT4 RV64I conformance suite (`rtl/run_act4_tests.sh`, run against the
     real, unmodified `veda_core.tlv` — unaffected by this milestone's own test-file
     changes, re-run anyway per the plan's own stated discipline): **51/51 passed, 0
     failed, 0 timed out** (unchanged).

No `.word 0x` lines remain anywhere under `veda-core/` (`grep -rl` returns zero
matches, confirmed after conversion).

## What this does and does not close

Closes: the single biggest practical error-surface in this project's own test
authoring — a wrong hand-computed hex value previously failed silently as "some
other, unintended instruction," with no assembler-level check at all. `.insn` lines
are still far from real, named mnemonics (`ocl.d c0, x3, x4`) — a future test author
still has to compute `(opcode, funct3, funct7)` numerically, just no longer as one
opaque 8-hex-digit blob. Real named-mnemonic support is deliberately deferred to
Toolchain Milestones 5-6 (LLVM-based assembler work), which is a substantially
larger, separate engineering effort — this milestone's own honest scope is
hex-elimination only, not full assembler support.

## Reproducing this

The converter and verifier are scratchpad scripts (session-scoped, not committed),
built specifically to answer "does this conversion preserve exact encoding" via a
real, independent, byte-for-byte cross-check — matching this project's own
established "never trust one source" discipline, the same reasoning already applied
via Sail-vs-RTL cross-checks and the ACT4 conformance suite itself.
