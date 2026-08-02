# Veda-Core Toolchain Milestone 5b/6: LLVM Assembler for the 33 Capability-Register-Touching Instructions

**Date:** 2026-07-31
**Scope:** real LLVM MC-layer (assembler + disassembler) support for all 33
remaining Veda-Core instructions that touch the 16-entry, 128-bit capability
register file (CRF) — completing the instruction set begun in
[TOOLCHAIN_MILESTONE_5a_RESULTS.md](TOOLCHAIN_MILESTONE_5a_RESULTS.md)'s 3
pure-GPR instructions. Combined, this closes out the full, real 36-instruction
Veda-Core encoding.

## A second real correction, caught before writing code

Milestone 5a's own results doc already recorded one planning correction (the
GPR-vs-CRF operand split). Starting this milestone's TableGen work required
re-deriving the exact per-family operand/width breakdown directly from Sail's
`union clause instruction = ...` and `mapping clause encdec = ...`
declarations (not from an earlier summarized reference table used during
planning). That re-derivation found a second, real error in the earlier
summary: it implied OCL/OCS had 5 width variants each (`.B/.H/.W/.D/.C`),
matching `VEDA_CORE_SPEC.md`'s own aspirational width table. Grepping all four
Sail instruction files (`veda_ocl_insts.sail`, `veda_bind_insts.sail`,
`veda_cap_insts.sail`, `veda_atomic_insts.sail`) for every real
`union clause instruction = VEDA_...` found the *actual, implemented* model
only has `.d` and `.c` widths — 4 real OCL/OCS-family instructions, not 10.
The total instruction count (36) was independently re-derived and reconfirmed
correct (9 atomic + 7 capquery + 3 bind + 4 ocl/ocs + 2 nmc_add + 3
odt-done-in-5a + 8 cap-singles = 36), but the internal per-family breakdown
used for the actual TableGen work was corrected to match the real Sail source
directly.

## What was built

- **`RISCVRegisterInfoXVeda.td`** (new file): a 16-entry `CRF` register class
  (`c0`-`c15`), each register a plain `RISCVReg` (not `RISCVRegWithSubRegs` —
  every capability register is always exactly 128 bits, unlike FPR's
  multi-width composition, so no sub-register scheme is needed). Included
  from `RISCV.td` immediately after the real `RISCVRegisterInfo.td`.
- **`RISCVInstrInfoXVeda.td`** (extended): TableGen definitions for all 33
  instructions across 5 real Sail-defined families — OCL/OCS/NMC_ADD (mixed
  GPR+CRF R-type), OCL.C/OCS.C (all-CRF-plus-GPR R-type), the Bind family
  (I-type with a 2-bit mode field replacing the immediate), the 9-op
  Veda-Atomic family (AMO-shaped R-type), and the 9-instruction Custom-2
  capability-manipulation group (queries, OCA, CSetBounds(Exact),
  CSeal/CUnseal, OCInvoke/OCJALR, OSpecialRW). Every mnemonic, operand order,
  and bit field was read directly from the corresponding Sail
  `mapping clause assembly` / `mapping clause encdec` clause, not inferred.
- 33 new `def`s added to the existing `let Predicates = [HasVendorXVeda], ...`
  block established in Milestone 5a.

## Two real bugs found and fixed, both before any instruction logic was added

**1. `i128` as the CRF register class's value type crashes `llvm-tblgen`'s
GlobalISel emitter.** Tested the register class alone, before adding any
instructions, and hit a real assertion failure (`Could not infer all types in
pattern!`) inside an existing, unrelated `anyext` pattern in `RISCVGISel.td` —
introducing a 3rd legal scalar integer width (alongside RISC-V's existing
i32/i64) broke that pattern's own type inference. Isolated by testing the
register class in isolation first, confirming the crash was unrelated to any
instruction definition. Fixed using `[untyped]` (a real, standard LLVM
`ValueType`) with an explicit `let Size = 128;` override — the identical
mechanism real, upstream AArch64 uses for its own 128-bit+ `QQ`/`QQQ`/`QQQQ`
register-pair classes (confirmed by reading AArch64's own definitions before
adopting the pattern).

**2. `DecodeCRFRegisterClass` undeclared.** After the register class and all
33 instructions compiled cleanly through TableGen (confirming syntactic
correctness of both new files), the C++ build failed:
`error: 'DecodeCRFRegisterClass' was not declared in this scope`. This is the
same real, hand-written-decoder-function gap already understood from
Milestone 5a's `DecoderList32` bug, but at a different layer: TableGen's
disassembler-table emitter generates *calls* to `Decode<RegClass>RegisterClass()`
for every register class used in a decoded operand, but never generates the
function *body* — every existing register class (`GPR`, `FPR32`, `FPR64`,
etc.) has one hand-written in `RISCVDisassembler.cpp`. Fixed by writing
`DecodeCRFRegisterClass` following the real, already-read `DecodeGPRRegisterClass`
template exactly: bounds-check `RegNo >= 16` (vs. GPR's `>= 32`, no RVE-style
narrower sub-case needed since CRF has no analogous restricted mode), map to
`RISCV::C0 + RegNo`.

## Verification

**Independent three-way cross-check, all 33 instructions.** A from-scratch
Python script (`gen_m5b_verify.py`) computed every expected 32-bit encoding
directly from Sail's own `encdec` bit-field formulas (read fresh from the
four `.sail` files, not from the TableGen file under test), covering every
distinct bit-layout family: mixed GPR/CRF R-type, all-CRF R-type, the Bind
family's non-standard I-type-with-mode layout, the AMO-shaped atomic family,
and the funct7-selector capquery family. Every one of the 33 independently
computed values matched `llvm-mc -show-encoding`'s real output exactly, byte
for byte — zero mismatches. Beyond the scripted check, four representative
instructions (one from each of the four distinct bit-layout shapes: `CSEAL`,
`VEDA_AMOSWAP_D`, `OCL_D`, `VEDA_BIND`, `OCA`) were hand-decoded bit-by-bit
against their Sail `encdec` clause during this session as an additional,
independent manual confirmation of the automated check's correctness.

**Real `llvm-mc`/`llvm-objdump` round-trip**, all 33 instructions, both
directions — encode via `llvm-mc -show-encoding`, re-encode to an object file
and disassemble via `llvm-objdump`, confirmed identical mnemonics and register
operands recovered for every instruction (e.g. `cseal c1, c2, c3`,
`veda.amoswap.d ra, c2, gp`, `ocinvoke c2, c3`).

**Combined 36-instruction gate** (explicit plan requirement — one named,
standalone artifact, not folded into the per-milestone checks above):
`combined_36_gate.py` assembles all 36 known Veda-Core instructions (the 3
from Milestone 5a plus all 33 from this milestone) in a single `llvm-mc`
invocation and diffs every encoded word against an independently computed
expected value.
```
36/36 instructions match byte-for-byte, 0 mismatches
```

**Register-class disjointness test** (explicit plan requirement — proving GPR
and CRF are genuinely separate, not aliased): a new lit test,
`XVeda-invalid.s`, asserts the assembler rejects a capability register in a
GPR-only operand position and a GPR in a CRF-only position:
```
error: invalid operand for instruction
veda.odt.populate c0, x1, x2      <- CRF operand where GPR is required
error: invalid operand for instruction
ocl.d x1, x2, x3                  <- GPR operand where CRF is required (rs1)
error: invalid operand for instruction
cseal c1, x2, c3                  <- GPR operand where CRF is required (rs1)
```
All three real, both directions covered (GPR-in-CRF-slot and CRF-in-GPR-slot).

**New lit test file**: `XVeda-cap-valid.s` (33 instructions, following the
exact `XVeda-valid.s`/`XVentanaCondOps-valid.s` format — assemble with
`-show-encoding`, then re-disassemble and `FileCheck` both directions).

**Full existing RISC-V MC test suite, real zero-regression check**: the
complete `llvm/test/MC/RISCV/` directory via `llvm-lit -j4`:
```
Total Discovered Tests: 535
Passed: 535 (100.00%)
```
(535 = the 533 confirmed passing in Milestone 5a + the 2 new files added this
milestone, `XVeda-cap-valid.s` and `XVeda-invalid.s`.)

## What remains open, honestly

- All 36 real Veda-Core instructions now have real LLVM MC-layer (assembler +
  disassembler) support. No compiler codegen (IR-level lowering to these
  instructions from C/C++ source) exists yet — that is Toolchain Milestones
  8/9's explicit scope, not this one's.
- The CRF register class has no `DwarfRegNum` assignment (no ratified DWARF
  register-number convention exists yet for Veda-Core's capability registers)
  — left unassigned until real debug-info/codegen work in a later milestone
  actually needs it, rather than inventing an unverified number now.
- No calling-convention or register-allocator integration exists for CRF —
  out of scope for an MC-layer-only milestone; will be needed once Milestone
  8/9's compiler pass starts generating code that crosses function
  boundaries.

## Reproducing this

```
cd toolchain/llvm-project/build && ninja llvm-mc llvm-objdump
python3 bin/llvm-lit ../llvm/test/MC/RISCV/ -j4
```
New/changed files: `llvm/lib/Target/RISCV/RISCVRegisterInfoXVeda.td`,
`RISCVInstrInfoXVeda.td` (extended), `Disassembler/RISCVDisassembler.cpp`
(added `DecodeCRFRegisterClass`), `RISCV.td` (added the new register-info
include), `llvm/test/MC/RISCV/XVeda-cap-valid.s`, `XVeda-invalid.s` (both
new).
