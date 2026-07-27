# Real Cycle-Count Study: Would On-Chip SRAM (TCM) for "System-Critical" Objects Reduce Access Latency?

**Date:** 2026-07-26
**Question asked:** "Why don't we use SRAM for system critical objects to store... would it reduce the clock cycles required for accessing those objects? Is it right or not?"

## Why this needed a new experiment, not just a re-read of the prior one

`OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md` already measured Veda-Core's real
object-centric overhead (a fixed +10 cycles, one-time, regardless of N) — but
that experiment ran on the current RTL's `odt_mem[]`/`elfmem[]`, which are
plain, always-1-cycle-combinational SystemVerilog arrays with **no DRAM
latency modeled at all** (confirmed by re-reading `veda_core.tlv` directly:
no wait-state/stall/latency logic exists anywhere in the file). So that
result could not, by itself, answer a question about DRAM-vs-SRAM latency —
the simulation didn't distinguish the two. This experiment adds the missing
piece: a real, parameterized latency model, built specifically to test the
SRAM/TCM hypothesis on real, measured cycle counts rather than argue it in
the abstract.

## Real grounding for the latency numbers used

No synthesis or clock frequency exists for this core yet, so no single
"real" cycle-latency number can be asserted without false precision.
Instead: DDR4's real random-access latency (row-miss case: `tRP + tRCD +
CL`, each typically ~10-15 ns) is **~30-45 ns**, confirmed via a live search
(sources below) rather than assumed from memory. Converting that into
cycles depends on clock frequency, which spans a wide plausible range for
an unsynthesized, embedded-class core (~4 cycles at 100 MHz up to ~70+
cycles at 2 GHz). Rather than pick one number, the experiment sweeps
**`DRAM_EXTRA_CYCLES` ∈ {0, 10, 50}** — 0 as the regression floor (must
match the unmodified core exactly), 10 and 50 as representative points
spanning that real range.

## What was built (scratchpad-only — the real, committed `veda_core.tlv` was not touched)

A copy of `veda_core.tlv` (`/tmp/.../scratchpad/benchmark/latency/veda_core_latency.tlv`,
session-scoped, not committed — this is exploratory research on a modified
core, deliberately kept separate from the milestone-tracked RTL) gained:

- `TCM_ENTRIES` (=4): Object_IDs `[0, 4)` are "TCM-tier" — always 1 cycle,
  never stalled, matching CV32RT's own real "single-cycle, zero-wait-state
  SRAM" precedent already cited in this project's own
  `EMERGENCY_HANDLING_DESIGN_REVIEW.md`.
- `DRAM_EXTRA_CYCLES`: extra cycles a **DRAM-tier** (`Object_ID >= 4`)
  Object-Bind/Bind-NoTrap takes, on top of the baseline 1. The wait applies
  to the ODT read itself, not gated on whether the entry turns out valid
  (a real DRAM access must be walked to learn that).
- A stall mechanism reusing Milestone 14's own established idiom (force
  `$instr` to a real NOP, `32'h00000013`) rather than auditing every write
  path individually — `$pc` freezes for the extra cycles, `$instr` is
  forced to NOP for the intermediate cycles, and the original Bind
  instruction (still sitting at the frozen `$pc`) genuinely executes and
  completes on the final cycle. At `DRAM_EXTRA_CYCLES=0` the trigger
  condition never fires, so the core is provably unchanged from today —
  this was verified directly, not assumed (below), not just designed to be
  true.
- Rebind is deliberately out of scope for this experiment (kept minimal;
  plain Bind/Bind-NoTrap already exercise the access pattern being tested).

## Regression safety, verified before trusting any sweep result

- At `DRAM_EXTRA_CYCLES=0`, the modified core's N=16 array-sum benchmark
  produced **byte-identical** results to the unmodified `veda_core.tlv`
  (94 cycles, sum=136, both runs).
- The full real ACT4 RV64I conformance suite (the same 51-test corpus
  already run against the real `veda_core.tlv` in
  `ACT4_CONFORMANCE_RESULTS.md`) was re-run against the modified core at
  `DRAM_EXTRA_CYCLES=0`: **51/51 passed, 0 failed, 0 timeout** — confirms
  the added stall logic doesn't silently disturb anything else when
  disabled, not just the one benchmark program.
- A real bug was found and fixed during this work, not glossed over: the
  reused `tb_bench.sv`'s "3 consecutive identical PC = terminal loop"
  heuristic false-triggered on the new, legitimate multi-cycle stall
  itself (a DRAM-tier Bind now also holds `$pc` steady for several
  cycles). Fixed in a new `tb_bench_latency.sv` by requiring the DUT's own
  `veda_dram_busy` signal to be low *and* raising the stability threshold
  well above the largest `DRAM_EXTRA_CYCLES` tested — verified by tracing
  the actual signal values cycle-by-cycle (a debug testbench dump), not
  by guessing at a fix.

## Two access patterns, because the answer genuinely differs between them

**`bindonce`**: bind once, then access the same bound object N times (same
shape as the original benchmark). **`rebind`**: re-bind the *same* object
on *every* one of N iterations, one access each — the case where a
"critical object" is repeatedly re-acquired rather than bound once and
reused.

### Results — real numbers, every row's sum independently checked correct

**Bind-once (setup cost only paid once):**

| N | TCM cycles | DRAM cycles (E=10) | Diff | DRAM cycles (E=50) | Diff |
|---|---|---|---|---|---|
| 4 | 34 | 44 | +10 | 84 | +50 |
| 16 | 94 | 104 | +10 | 144 | +50 |
| 32 | 174 | 184 | +10 | 224 | +50 |

Difference = exactly `DRAM_EXTRA_CYCLES`, **fixed, regardless of N** — the
same amortization shape `OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md` already
found. Even with real DRAM latency now modeled, binding once and reusing
many times still pays the extra cost exactly once.

**Rebind (setup cost paid every iteration):**

| N | TCM cycles | DRAM cycles (E=10) | Diff | DRAM cycles (E=50) | Diff |
|---|---|---|---|---|---|
| 1 | 18 | 28 | +10 | 68 | +50 |
| 2 | 25 | 45 | +20 | 125 | +100 |
| 4 | 39 | 79 | +40 | 239 | +200 |
| 8 | 67 | 147 | +80 | 467 | +400 |

Exact closed form (derived from the assembled instruction counts, checked
against every row): **`tcm_cycles = 11 + 7N`**, **`dram_cycles = 11 + (7 +
E)N`**, i.e. the difference is **`E × N`** — growing *linearly* with N, not
fixed.

## Direct verdict

**Yes — but only for one of the two access patterns, and that distinction
is the real answer, not a footnote.**

1. For an object **bound once and reused many times** (the pattern the
   original benchmark already validated as Veda-Core's own strength — a
   fixed setup cost amortized toward zero): moving it to SRAM/TCM would
   **not** meaningfully help. The extra DRAM cost is paid once regardless
   of tier; TCM only removes a fixed constant that's already being
   amortized away by reuse.
2. For an object **repeatedly re-acquired** (re-bound on every access,
   e.g. because there are more "critical" objects than the 16 capability
   registers can hold bound simultaneously, or because the access pattern
   genuinely re-binds by design): TCM/SRAM placement removes a **real,
   linearly-scaling cost** — `E` cycles saved on *every single* iteration,
   confirmed exactly in the table above. This is the scenario the
   instinct behind the question is actually describing, and here it is
   quantitatively correct.

Architecturally, this is not a "cache" in the sense the project's own
cache-less pillar (`DESIGN_SOUL_AND_UNIQUENESS.md`) forbids — no eviction,
no coherence, no automatic replacement. It matches a real, precedented
pattern instead: **Tightly-Coupled Memory (TCM)**, the same real ARM
Cortex-M/R mechanism already cited via CV32RT in this project's own
`EMERGENCY_HANDLING_DESIGN_REVIEW.md`, chosen there specifically for
deterministic, bounded-latency access — the same "small, provable,
worst-case-bounded cycle count" goal already established as this project's
own target over "zero-latency."

## What this does and does not show

**Does show**: on identical single-cycle RTL microarchitecture, with a real
DRAM-latency range grounded in a live-verified DDR4 timing source, TCM
placement for frequently-re-bound "critical" objects saves real, linearly
-scaling cycles; for bind-once-reuse-many objects it does not, because that
cost is already a fixed one-time constant.

**Does not show**:
- Real silicon numbers — no synthesis, no clock frequency, no ASIC/FPGA
  exists for this core; `DRAM_EXTRA_CYCLES` is a swept parameter grounded
  in a plausible range, not a measured value for this specific design.
- A design for *how* an ODT would actually be split into TCM/DRAM tiers in
  real hardware (addressing, what marks an `Object_ID` "critical", capacity
  limits) — that is real, unstarted design work, not claimed as solved
  here.
- Anything about Rebind, OCInvoke, or any instruction besides plain
  Bind/Bind-NoTrap — deliberately out of scope for this experiment.
- Behavior under a pipelined/superscalar/OoO microarchitecture — same
  single-cycle-only caveat as the original benchmark.

## Reproducing this

`/tmp/claude-.../scratchpad/benchmark/latency/` (session-scoped, not
committed): `veda_core_latency.tlv` (modified core), `gen_latency.py`
(program generator), `run_sweep.sh` (full E×pattern×tier×N driver,
regenerates `results.csv`), `sim/tb_bench_latency.sv` (corrected
completion-detection testbench).

Sources for the DDR4 latency figures: [DDR Timing Parameters Explained: CL, tRCD, tRP and tRAS](https://medium.com/@sidjain1805/ddr-timing-parameters-explained-cl-trcd-trp-and-tras-b048fa90be4f), [RAM Timings: CAS, RAS, tRCD, tRP, tRAS Explained](https://appuals.com/ram-timings-cas-ras-trcd-trp-tras-explained/)
