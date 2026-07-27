# Real Toggle-Activity Study: A First Signal on the Never-Tested Energy-Efficiency Pillar

**Date:** 2026-07-27
**Motivation:** every prior study in this project measured cycles
(performance) or gates (area). "Energy-efficiency," one of Veda-Core's
own two explicitly stated design priorities (`DESIGN_SOUL_AND_UNIQUENESS.md`
— "security and energy efficiency, NOT throughput"), had never been
empirically tested at all until this study.

## Methodology, decided before running anything

No PDK, no real power-characterization data exists for this project (an
honest, already-established limit — `SYNTHESIS_CRITICAL_PATH_STUDY.md`).
A real Joules/Watts number is not achievable here. The real, achievable,
honest proxy: **total real signal-toggle activity from an actual RTL
simulation VCD trace** — a standard, well-established first-order proxy
for relative dynamic switching power (the dominant power component in
real CMOS logic), used throughout real EDA power-estimation methodology
as one of several real inputs. Same N=16 array-sum workload already
established in `OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`, same real,
unmodified, committed cores, same simulator, `$dumpvars(0, dut)` capturing
every signal in the design hierarchy, a real Python parser counting every
value-change event and every individual bit toggled in the VCD's own
value-change section.

## Real results

| | vars | value-change events | bits toggled | cycles |
|---|---|---|---|---|
| traditional | 442 | 5,070 | 60,752 | 84 |
| Veda-Core | 913 | 10,672 | 81,789 | 94 |

Raw ratios: 2.07x more signals exist in Veda-Core's design at all (real,
expected — the capability register file, ODT logic, trap infrastructure
are all real, additional hardware that simply doesn't exist in the
traditional core), 2.10x more raw events, 1.35x more raw bits toggled,
over 1.12x more cycles.

## The real finding, properly normalized — not just the raw ratio

Raw totals conflate two different real effects: "Veda-Core has more
hardware" (an area/static-power question, already studied) and "Veda
-Core's hardware switches more actively" (the real dynamic-power
question this study is about). Normalizing separates them:

**Per-cycle activity** (bits toggled ÷ cycles): traditional 723.2,
Veda-Core 870.1 — **Veda-Core's dynamic activity is ~20% higher per
cycle**, even after accounting for its own longer runtime. This is a
real, honest signal that Veda-Core's real per-cycle dynamic power is not
free.

**Per-signal, per-cycle rate** (events ÷ vars ÷ cycles): traditional
0.1366, Veda-Core 0.1244 — once *both* extra hardware and extra cycles
are accounted for, each individual signal in Veda-Core's design toggles
at a rate comparable to (very slightly *below*) traditional's own
signals. The higher raw and per-cycle totals are explained mostly by
Veda-Core simply having more real hardware present, not by that hardware
being unusually "hyperactive" — no individual mechanism is toggling far
out of proportion to the rest of the design.

## Why the ~20% per-cycle premium is real and explicable, not a modeling artifact

This session's own earlier RTL work already established the real reason:
several of Veda-Core's own checks are genuinely **unconditional every
cycle**, not gated on decoded opcode — `$veda_pcc_violation` (Milestone
14's own real design, explicitly commented as "a genuinely new *kind* of
check, unconditional every cycle rather than gated on a decoded opcode")
is a real, concrete example. This means part of Veda-Core's real
combinational logic re-evaluates and potentially toggles on *every*
cycle, whether or not that cycle's instruction touches the object model
at all — a real, structural reason per-cycle activity is higher even
during the ordinary base-ISA-only portions of a program (the "loop:
add/addi/addi/bnez" instructions this same benchmark also executes,
identically in both versions).

## Honest, real scope limits

- **This is a relative activity proxy, not a real power/energy number.**
  No voltage, capacitance, clock frequency, or real technology data
  exists for this unsynthesized design. A real ASIC/FPGA flow with a real
  PDK could show a meaningfully different — larger or smaller — real
  power gap, for the same structural reasons already stated in every
  other synthesis-adjacent study this session.
- Raw VCD toggle-counting has no clock-gating awareness (a real chip
  would gate unused logic; this simulation-level count cannot distinguish
  "toggled because clock-gated off" from "toggled and doing real work") —
  a real synthesis + gate-level simulation flow would give a more
  accurate number, not attempted here.
- Single workload shape (sequential array-sum), same honest limit as
  every other benchmark this session.

## Reproducing this

`/tmp/claude-.../scratchpad/energy/` (session-scoped, not committed):
`trad_16.S`, `veda_16.S`, `tb_vcd.sv` (adds `$dumpvars(0, dut)` to the
established benchmark testbench pattern), `count_toggles.py` (real VCD
value-change-event parser), `build_and_run.sh`.
