# Veda-Core Toolchain Milestone 5a: LLVM Assembler for the 3 Pure-GPR Instructions

**Date:** 2026-07-31
**Scope:** real LLVM MC-layer (assembler + disassembler) support for
`veda.odt.populate`, `veda.odt.destroy`, `veda.odt.populate.fast` — the only
3 of Custom-0/1's 27 instructions confirmed to use exclusively GPR operands
(a real correction to this initiative's own original milestone split, made
before any TableGen was written — see below).

## A real planning correction, caught before writing code

This plan's own original Toolchain Milestone 5 was scoped as "Custom-0/1
(27 GPR-operand instructions)... deliberately deferring Custom-2's
capability-register operands to Milestone 6." Re-checking the full
Sail-derived instruction-encoding reference (produced earlier this
initiative) against that framing found it **wrong**: `OCL`/`OCS` (all 5
widths), `NMC_ADD.{W,D}`, the Bind family, and all 9 Veda-Atomic ops all use
a capability register in at least one operand position (`rs1` for
OCL/OCS/NMC_ADD/Atomic, `rd` for Bind). Only 3 of the 27 Custom-0/1
instructions are genuinely GPR-only. The plan file was corrected (Milestone
5 split into 5a/5b, the latter merged with the former Milestone 6) before
any code was written for the mis-scoped version.

## What was built

- `RISCVInstrInfoXVeda.td` (new file, `toolchain/llvm-project/llvm/lib/Target/RISCV/`):
  TableGen definitions for the 3 instructions, using the real, already
  -existing `RVInstR` base class (confirmed field-for-field identical to
  Veda-Core's own R-type layout by reading `RISCVInstrFormats.td` in full)
  and the real, already-defined `OPC_CUSTOM_0` constant (`0b0001011`,
  matching Veda-Core's own opcode exactly — no redefinition needed).
  Modeled directly on the real, in-tree `RISCVInstrInfoXVentana.td` vendor
  extension (confirmed present in this exact `release/21.x` checkout, read
  in full before use as the closest genuine simple-GPR-R-type precedent).
- `FeatureVendorXVeda`/`HasVendorXVeda` added to `RISCVFeatures.td`, using
  the real `RISCVExtension<major, minor, desc>` helper class (confirmed,
  by reading its own definition, to auto-derive the `-mattr=+xveda` name
  and the `hasVendorXVeda()` accessor from the def name — not invented).
- `RISCVInstrInfoXVeda.td` wired in via `include` in `RISCVInstrInfo.td`,
  matching every other vendor extension's own real inclusion pattern.

## A real, second bug found and fixed — disassembler registration is not automatic

TableGen's AsmMatcher generation is fully automatic from the `.td`
definitions alone (confirmed: assembly-encoding worked immediately, zero
additional C++). The **disassembler** direction is not: `RISCVDisassembler.cpp`
maintains an explicit, hand-written `DecoderList32` table mapping each
`DecoderNamespace` string to its generated `DecoderTable<Namespace>32`
symbol and gating `FeatureBitset` — a new namespace genuinely needs a new
entry here, confirmed by testing a real, existing, unrelated Custom-0
-based extension (`XAndesPerf`) against the same fresh build: it disassembled
correctly while Veda-Core's own new instructions did not, isolating the gap
to a missing registration, not a general build or opcode-space problem.
Fixed by adding one line to `DecoderList32`. This is a real, genuine gap in
this initiative's own earlier research-based assumption ("assembler support
needs zero C++ changes for standard operand types") — true for encoding,
not for decoding, now corrected and documented rather than glossed over.

## Verification (real, both directions, plus the full existing test suite)

**Independent encoding cross-check** (three-way, matching this project's
own established discipline): a Python script independently computed the
expected R-type bit-packing for 4 test cases from `RISCVInstrFormats.td`'s
own documented field layout; `veda.odt.populate.fast x0, x1, x2`'s computed
value (`0x0820800b`) was additionally cross-checked against
`MILESTONE_18_RESULTS.md`'s own already-verified value for the identical
operands — exact match, a genuine third independent source agreeing.

**Real `llvm-mc`/`llvm-objdump` round-trip**, both directions:
```
$ llvm-mc -mattr=+xveda -show-encoding ...
veda.odt.populate      zero, ra, sp    # encoding: [0x0b,0x80,0x20,0x06]
veda.odt.destroy       zero, ra        # encoding: [0x0b,0x90,0x00,0x06]
veda.odt.populate.fast zero, ra, sp    # encoding: [0x0b,0x80,0x20,0x08]
veda.odt.populate      t0, ra, gp      # encoding: [0x8b,0x82,0x30,0x06]

$ llvm-mc -filetype=obj ... | llvm-objdump --mattr=+xveda -d
0620800b  veda.odt.populate      zero, ra, sp
0600900b  veda.odt.destroy       zero, ra
0820800b  veda.odt.populate.fast zero, ra, sp
0630828b  veda.odt.populate      t0, ra, gp
```
All 4 encode and decode values match the independently-computed expected
bytes exactly, before and after the disassembler-registration fix (encode
passed both times; decode failed before the fix, passed cleanly after).

**Full existing RISC-V MC test suite, real zero-regression check**: the
complete `llvm/test/MC/RISCV/` directory (533 real tests, via `llvm-lit`)
— **533/533 passed, 0 failed**. (8 failures on the first run were diagnosed
individually, not assumed benign: all traced to missing auxiliary test
binaries — `llvm-readelf`, `split-file`, `llvm-dwarfdump` — this session's
scoped build only targeted `llvm-mc`/`llc`/`clang` initially; building
those tools resolved every one of the 8, confirming zero were genuine
regressions from this milestone's own changes.)

## Build environment note

LLVM built from the official `github.com/llvm/llvm-project.git`,
`release/21.x` branch (matching the already-installed system Clang's own
major version), RISCV target + Clang only, `-j4` (deliberately conservative
parallelism — this machine's RAM is genuinely tight, actively used for many
other applications; a full `-j$(nproc)` run risked destabilizing the live
desktop, not just this build).

## What remains open, honestly

- Only these 3 instructions have real LLVM assembler support. The other 33
  (24 Custom-0/1 + 9 Custom-2) all need the capability register class —
  Toolchain Milestone 5b/6, the largest remaining unit of work in this
  initiative.
- No compiler codegen (IR-level lowering to these instructions) exists yet
  — MC-layer (assembler/disassembler) only, matching this milestone's own
  stated scope.

## Reproducing this

`cd toolchain/llvm-project/build && ninja llvm-mc llvm-objdump`. Test:
`llvm/test/MC/RISCV/XVeda-valid.s` (new file, follows the real
`XVentanaCondOps-valid.s` format exactly). Full suite:
`python3 bin/llvm-lit ../llvm/test/MC/RISCV/`.
