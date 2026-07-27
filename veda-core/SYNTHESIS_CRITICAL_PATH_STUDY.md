# Real Synthesis-Based Critical-Path/Area Study: Traditional Load vs Veda-Core OCL.D Check Chain

**Date:** 2026-07-26
**Motivation:** every performance study in this project ran on the single
-cycle RTL, where "cycles" is really "instruction count" — none could say
anything about whether Veda-Core's 5-check combinational chain (Tag,
generation-staleness, Seal, Permission, Bounds) would cost real max-clock
-frequency (Fmax) on a pipelined design, the single largest unanswered
question flagged in `NEXT_STEPS_ROADMAP.md` and this session's own prior
analysis. This study gets a first real signal using Yosys (installed this
session via the official conda-forge channel — no PDK/liberty file exists
in this environment, so this is a technology-independent, generic-gate
analysis, not an absolute-picosecond one).

## Methodology

No PDK exists, so no absolute delay number is possible or claimed. Instead:
two small Verilog modules, each a **faithful, direct transcription** of
real expressions from `rtl/veda_core.tlv` (not approximated):

- `trad_addr.v`: the ordinary RV64I load's own effective-address
  computation, `rs1_data + imm` — confirmed as the real path via
  `veda_core.tlv` line 2149 (`$alu_result`, reused by `$op_is_load`).
- `veda_check_chain.v`: `OCL.D`'s full real check chain, transcribed
  directly from `veda_core.tlv` lines 1389-1433 — Tag check, a real
  256-entry ODT read (matching `ODT_ENTRIES=256`) for the generation
  -staleness re-check, Seal check, Permission check, Bounds check, and the
  final `Base+Offset` address computation, all as unconditional
  combinational logic exactly as the real RTL has it (the ODT read's own
  address-decode/mux depth is included as real internal memory, not
  abstracted away as a free input — abstracting it away would have
  understated Veda-Core's real cost, which this study must not do).

Both synthesized identically: `proc; opt; techmap; opt; abc; stat; ltp`.
Yosys's own `ltp` (longest topological path) command reports real
technology-independent logic depth; `abc`'s own cell-mapping report gives
a real gate-count area proxy. Cross-checked with two different ABC
mapping strategies (a forced generic gate set, and ABC's own default
internal mapping) — both gave **identical** depth numbers, ruling out the
result being an artifact of one specific mapping choice.

## Real results

| | Longest topological path (gate levels) | Total mapped cells |
|---|---|---|
| `trad_addr` (plain RV64I load address) | **114** | **351** |
| `veda_check_chain` (OCL.D full check + address) | **95** | **233** |

## The real, somewhat counter-intuitive finding, and the real reason for it

Veda-Core's isolated check-and-address path is **not deeper or larger**
than the traditional core's plain address computation in this analysis —
it is smaller on both axes. Two real, verified reasons, not a modeling
error:

1. **The checks run in parallel with the address computation, not in
   series before it.** `veda_core.tlv`'s own `$veda_real_addr` is an
   *unconditional* assignment — it is computed every cycle regardless of
   whether `$veda_ocl_violation` is true, with the actual blocking
   happening downstream (the trap/NOP-forcing mechanism), not by gating
   the address computation itself. This means the check logic (Tag/gen
   /Seal/Perm/Bounds, each individually shallower than a 64-bit add) does
   not sit *in front of* the address adder on the critical path — it sits
   *beside* it, so the overall depth is `max(checks, address-calc)`, not
   their sum.
2. **A capability's `Base` field is genuinely 32 bits, not 64.** Per
   `VEDA_CORE_SPEC.md`'s own capability layout, `Base` is a 32-bit field
   (zero-extended before the add), while the traditional core's `rs1_data`
   is a full, generic 64-bit value. A real synthesis tool exploits the
   constant-zero upper half, meaningfully shrinking that half of the
   adder — a real, architecture-level saving (narrower base address than a
   raw pointer), not a simulation artifact.

## Honest, real caveats — this is a first signal, not a final answer

- **No PDK/standard-cell library exists in this environment.** This is a
  generic, technology-independent gate-level analysis (AND/OR/NAND/NOR
  /XOR/MUX primitives). Absolute picosecond delay, real fan-out loading,
  wire delay, and placement effects are not modeled at all — a real ASIC
  or FPGA flow with a real PDK/architecture file could shift these numbers
  meaningfully in either direction.
- **ABC's mapping is a heuristic, not a proven depth-optimum**, though the
  cross-check with two different mapping strategies giving identical
  numbers is real evidence against this being a one-off fluke.
- **Only the single per-access `OCL.D` check-and-address path was
  isolated** — this is the right scope for the Fmax question this study
  set out to answer (what must complete within one cycle on a critical,
  frequently-executed path), but it says nothing about the area of the
  rest of `veda_core.tlv` (the full capability register file, Object-Bind,
  ODT-Populate, trap infrastructure, PCC bounding, etc.), which was never
  measured here and is expected to be real, additional area cost on top
  of this.
- **A real ripple-carry-style adder was used for both** (no
  carry-lookahead/carry-select optimization was specifically invoked) —
  a real backend targeting a specific PDK would likely produce a
  meaningfully shallower adder for *both* designs, likely narrowing the
  absolute gap further, though the *relative* finding (checks run parallel
  to, not serial with, the address calc) would still hold structurally
  regardless of adder implementation.

## What this real result changes about the earlier open question

The single largest previously-unanswered risk — "does the capability
-check logic threaten Fmax on a pipelined design" — now has a real, if
early and generic, signal pointing the *opposite* direction from the
worst-case assumption: the check logic does not appear to be the deeper
path. This does not close the question (no PDK, no full-core synthesis,
no place-and-route), but it meaningfully de-risks it compared to having no
signal at all, which was this project's real status before this study.

## Reproducing this

`/tmp/claude-.../scratchpad/synth/` (session-scoped, not committed):
`trad_addr.v`, `veda_check_chain.v`. Yosys 0.58 installed via
`conda install -c conda-forge yosys` (the official YosysHQ-maintained
channel). Command: `yosys -p "read_verilog <file>; hierarchy -check -top
<module>; proc; [memory;] opt; techmap; opt; abc -g
AND,OR,NAND,NOR,XOR,MUX; stat; ltp -noff"`.
