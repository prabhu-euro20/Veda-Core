# Veda-Core RTL Milestone 24 Results — TCM Fast-Path (Eliminating Object-Bind's Real DRAM-Latency Cost)

**Date:** 2026-08-08
**Scope:** close the real, admitted performance gap `CRF_ARCHITECTURE_ALIGNMENT_VERDICT.md`'s own
Addendum 1 named — a repeated-rebind access pattern (the shape 16-register CRF pressure produces)
pays real, linearly-scaling DRAM-tier latency Veda-Core's own cache-less-by-design ODT was never
going to avoid on its own — **without** giving up the cache-timing-immunity security property that
gap is the price of. Directly requested by the project owner after reviewing the two-sided
trade-off Addendum 1 documented: *"eliminate the performance bottleneck [while] we stick with
[the] inclination to robust and secure hardware-native security enforcement."*

## Why this exists

`DRAM_TCM_LATENCY_STUDY.md` (earlier session) established the real cost formula for a repeated
rebind: `11 + (7+E)×N` cycles, growing linearly with `N`. `CAPABILITY_REGISTER_PRESSURE_STUDY.md`
showed this is exactly the pattern real 16-register pressure produces once a program's working set
exceeds capacity. `CRF_ARCHITECTURE_ALIGNMENT_VERDICT.md`'s Addendum 1 then found real CHERI's own
equivalent cost (CSC/CLC spill/reload) very plausibly rides an ordinary cache hierarchy by CHERI's
own documented design choice — while also finding CHERI's own official technical report
(UCAM-CL-TR-916) admits that cached path is *not* immune to cache-timing side-channel attacks,
something Veda-Core's cache-less ODT structurally is. `TCM_FAST_PATH_DESIGN.md` (this session)
researched a mechanism that keeps that immunity while removing the latency: a real, peer-reviewed
precedent (GhostRider, ASPLOS 2015) for a statically-declared, non-adaptive scratchpad as a
formal-security-preserving alternative to a cache, plus a real, serious caveat confirmed on actual
RISC-V hardware (Wrisley et al., NordSec 2025: shared-TCM cross-hart contention is itself a real
covert channel, up to 68 kbps) — scoped as an explicit, forward-declared constraint for any future
multi-hart Veda-Core (this core is single-hart, `MHARTID=0` fixed, today).

## What was built — five stages, verify-before-layering

### Stage 1 — the real DRAM-latency stall FSM

New state in `veda_core.tlv`: `DRAM_EXTRA_CYCLES` localparam (line 71, shipped default **0** —
see "the E=0 default" below), `$veda_dram_stall_req` (line 980), `$veda_dram_stall_cnt[7:0]` (line
988), `$veda_dram_busy` (line 1006). Applies to exactly three access classes, matching the
design's own deliberately narrow scope: Object-Bind/Bind-NoTrap/Rebind's ODT access, and OCL.C/
OCS.C's capability-width memory access — explicitly **not** plain OCL.D/OCS.D, ordinary `ld`/`sd`,
NMC_ADD, or Veda-Atomic, which would have been a much larger, riskier change than this milestone
needed. `$pc` gains one new leading freeze condition (`>>1$veda_dram_busy ? >>1$pc : ...`) and
`$instr` composes the same literal-NOP idiom Milestone 14 already established for
`$veda_pcc_violation`, reusing it precisely rather than inventing a second mechanism.

**A real combinational-loop risk was caught by hand-tracing before any RTL was written**: gating
`$instr`'s NOP-forcing on the *same* cycle's own `$veda_dram_busy` (itself decoded from that same
cycle's `$instr`) would have been a genuine cycle. Fixed by keying the freeze on `>>1$veda_dram_busy`
(the previous cycle's registered value) throughout, letting the triggering instruction decode and
execute normally on its own first cycle.

**A real functional regression was found only by running the existing suite, not by hand-tracing
alone**: at `DRAM_EXTRA_CYCLES=0`, `$veda_dram_busy` was still spuriously asserted for one cycle
after every Bind/OCL.C/OCS.C, because `$veda_dram_stall_req` itself fires unconditionally regardless
of `E`. This broke two pre-existing positive tests (Milestones 4 and 10) — a real, caught
regression, not a hypothetical one. Fixed by adding a compile-time `(DRAM_EXTRA_CYCLES != 0)` guard
to `$veda_dram_busy`'s own formula, making it a provable no-op at `E=0`. Re-ran the full 46-test
suite after the fix: 0 failures.

New test: `veda_smoke_m24_latency.S` — two Binds, one OCS.C, one OCL.C, `cgettag`; asserts real
capability round-trip correctness plus `busy_cycles==0` at the shipped default. The *other* half of
this feature — that `busy_cycles` becomes exactly `N×E` at a real nonzero `E` — was verified
separately by temporarily building at `E=4` (`busy_cycles=16=4×4`, exact match) and mutation-tested
(forcing `CPU_veda_dram_busy_a0` to always 0 correctly flips the temporary build's own check to
FAILED); not re-asserted in the committed suite since it always builds at the shipped default.

**The `tb_act4.sv` stability-window risk the original design doc flagged did not materialize**:
built at a temporarily nonzero `E=5` and ran the full 51-test ACT4 suite — 51/51, zero interference,
because ACT4's own RV64I-only corpus never issues a Custom-0 opcode, so `$veda_dram_stall_req` never
fires regardless of `E`. `tb_act4.sv` itself was deliberately **not** modified — a real, honest
finding that the theoretical risk didn't apply to the actual, existing corpus, not a "fix" for a
problem that didn't exist.

### Stage 2 — TCM ODT tier (Object_ID-based)

`TCM_ODT_ENTRIES=32` (line 95) and `$veda_odt_tcm_hit = ($veda_object_id < TCM_ODT_ENTRIES)` (line
1182) — checked against the **full** Object_ID, not the truncated low-8-bit ODT index, deliberately
avoiding a variant of the Milestone 15 aliasing bug. No new array: `odt_mem[]` is unchanged; this is
a pure latency-classification gate on the existing stall FSM's own `$veda_dram_stall_req` term.
32 entries chosen as a real, small, auditable budget — GhostRider's own Memory Trace Obliviousness
property requires this placement be static and independent of runtime/secret-correlated data, never
history-adaptive, so the range is a fixed compile-time constant, not a cache that could be probed or
warmed.

New test: `veda_smoke_m24_odt_tcm.S` — Binds a low Object_ID (TCM-tier, pre-seeded fixture) and a
freshly-populated high Object_ID (DRAM-tier), asserting `busy_cycles==0` for both at the shipped
default (the real, valid regression check for the tier classification's own non-interference).
Mutation-tested by inverting the `$veda_odt_tcm_hit` comparison in generated Verilog and confirming
the check now fails.

### Stage 3 — TCM capability-spill scratch (address-based) + OCL.C/OCS.C routing + save-area
relocation

A genuinely separate array (mirroring the project's own `odt_mem[]`-vs-`elfmem[]` precedent, not a
carved-out sub-range): `TCM_SCRATCH_BASE=0xA0000000`, `TCM_SCRATCH_SIZE=4KiB` (line 545),
`tcm_scratch[]`/`tcm_scratch_tag[]`, zero-initialized in the same `initial` block pattern
`tag_mem[]` already used. `$veda_capmem_tcm_hit` (line 1815, address-range check on
`$veda_real_addr`) and `$veda_capmem_tcm_granule` gate a real mux in OCL.C's combinational
16-byte read, OCL.C's tag read, and OCS.C's synchronous 16-byte write plus tag write — each
correctly switching between `tcm_scratch[]`/`tcm_scratch_tag[]` and `elfmem[]`/`tag_mem[]` based on
whether the real target address falls in the new TCM range.

**Object_ID-based tiering (Stage 2, `$veda_odt_tcm_hit`) and address-based tiering (Stage 3,
`$veda_capmem_tcm_hit`) are deliberately two separate signals, not one shared classification** —
because OCL.C/OCS.C's own `.insn` encoding repurposes `rs1` as a CRF-register *index* (not a raw
Object_ID value the way Bind's `rs1` is), so an Object_ID-based check is architecturally
inapplicable to them; only the real memory address they resolve to is meaningful.

**Explicit, deliberate scope boundary, discovered and closed off by design rather than by code**:
while implementing this stage, plain OCS.D's, NMC_ADD's, and Veda-Atomic's own granular
tag-invalidation write-backs were found to compute an ELFMEM-relative granule/address
*unconditionally*, with no TCM awareness — meaning if any of those (out-of-scope-for-this-milestone)
instructions ever targeted a TCM-scratch address, the resulting `tag_mem[]`/`elfmem[]` index would
be wildly out of the arrays' own declared bounds (a real alias/overflow, the exact class the design
doc's own comments predicted). Rather than widen this milestone's own scope to fix four additional
write blocks (each needing its own new test), the TCM-scratch region's own declaration comment in
`veda_core.tlv` (lines 522-543) states plainly: **TCM-scratch access is OCL.C/OCS.C only in this
milestone** — the identical natural, pre-existing out-of-range behavior any address outside
`elfmem[]`'s own declared range already had for these instructions, not a new gap this milestone
introduces. `runtime/veda_sched_asm.S`'s own new comment (§ below) states the same contract at its
own point of use.

**Linker-script relocation** (`runtime/veda_rt.ld`): new `.tcm_scratch` output section at
`TCM_SCRATCH_BASE`, `__tcm_scratch_start`/`__tcm_scratch_end` symbols matching the file's own
existing `__bss_start`-style convention. `runtime/veda_sched_asm.S`'s `save_area_0`/`save_area_1`
(the cooperative scheduler's own yield/resume spill target) moved from `.data` into `.tcm_scratch`;
the other five symbols in the same file (`thread_index`/`yield_count`/`yield_limit`/`saved_ra`/
`saved_sp`) are not on this hot path and stay in ordinary `.data`. Verified via `nm` on a real
linked ELF: `save_area_0`/`save_area_1` land at `0xA0000010`/`0xA0000018` exactly, and
`__tcm_scratch_start`/`_end` bound `0xA0000000`/`0xA0000030` correctly.

**Honest caveat, verified before writing it down, not assumed**: `save_area_0`/`save_area_1` are
accessed in `veda_sched_asm.S` exclusively via `ocl.d`/`ocs.d` (plain doubleword, `funct3=0x3`), not
`ocl.c`/`ocs.c` — and Stage 1's own scope deliberately excludes OCL.D/OCS.D from the DRAM-latency
model entirely. So this specific relocation currently changes **zero** stall cycles on the
scheduler's real yield/resume path; those accesses never stalled regardless of backing address. What
it *does* establish: the real linker convention this milestone's own new RTL test exercises via
OCL.C/OCS.C, and automatic inheritance of the fast path for any future capability-width save or any
future low-numbered TCM-ODT object — recorded honestly here rather than claimed as a measured
scheduler speedup.

New test: `veda_smoke_m24_ocsc_tcm.S` — a real, tagged donor capability round-trips through **both**
the new `tcm_scratch[]` path (Object_ID=201, exercising the mux's TCM arm) and ordinary `elfmem[]`
(Object_ID=202, exercising the mux's other arm) in the same run, plus a negative check per region
(an offset never written reads back untagged) confirming `tcm_scratch_tag[]`'s own zero-init took
effect and neither region's tag store leaks into the other's. Mutation-tested by forcing
`CPU_veda_capmem_tcm_hit_a0` to always 0 in generated Verilog: the TCM-path reads correctly become
`X` (an out-of-bounds `elfmem[]`/`tag_mem[]` index under the mutated, wrong classification) and the
test correctly reports FAILED.

**Zero-regression gate for the relocation**: `veda_smoke_m23_scheduler.S` (RTL, its own independent
`save_area_a`/`save_area_b` symbols, unaffected by the linker change) re-run unmodified within the
full suite — still passes. The real, affected consumer — the compiled-C toolchain path
(`compiler/run_veda_sched_demo_test.sh`, `veda_sched_asm.S` + the now-changed `veda_rt.ld` linked
and executed under `sail_riscv_sim`) — re-run and still passes end-to-end (both thread counters
reach 2 after 4 real yields), confirming the relocation changed only physical backing, not
scheduler behavior.

### Stage 4 — composing the k-sweep with the real latency model

`CAPABILITY_REGISTER_PRESSURE_STUDY.md`'s own real, executed bind-count data (a pure function of the
round-robin schedule and 16-register capacity, unaffected by any timing change) was composed with
Stage 1/2's own mutation-tested per-bind cost model (`E` extra cycles per DRAM-tier triggering bind,
zero for TCM-tier), rather than re-simulating all eight `k`×TCM-config combinations from scratch.
**The composition itself was spot-checked against real RTL before being trusted**: 8 sequential
Binds (Object_ID 3-10) against a scratch `veda_core.tlv` copy (never the committed file) at a
temporary `DRAM_EXTRA_CYCLES=10` measured **exactly** a +80-cycle delta with TCM disabled (`8×10`,
exact) and **exactly** a 0-cycle delta with TCM enabled (identical to the `E=0` baseline) — both
halves of the formula confirmed to the cycle, not approximately.

Composed result at `E=10` (the DDR4-grounded low end this project already established), Object_IDs
numbered from 3 (immediately after the two pre-seeded fixtures):

| k | traditional | old veda (no latency model) | TCM-on, E=10 | TCM-off, E=10 |
|---|---|---|---|---|
| 8  | 129 | 153 | **153** (ratio 1.186, unchanged) | 233 (ratio 1.806) |
| 16 | 257 | 305 | **305** (ratio 1.187, unchanged) | 465 (ratio 1.810) |
| 17 | 273 | 336 | **336** (ratio 1.231, unchanged) | 566 (ratio 2.073) |
| 32 | 513 | 801 | **921** (ratio 1.795) | 2081 (ratio 4.057) |

For any working set up to 17 simultaneously-hot objects — the realistic register-pressure scenario —
the TCM tier makes the new DRAM-latency cost **exactly zero**, so long as those objects' Object_IDs
are allocated in the low, TCM-eligible range (a real, stated software contract, not automatic).
Past the 32-entry TCM-ODT budget (`k=32`), the disadvantage partially reappears (1.795× vs. the
pre-latency-model 1.561×) but the TCM tier still more than halves what an undefended core would show
(4.057×) — graceful degradation proportional to how far the working set exceeds the budget, not a
cliff. Full derivation and the two-sided-trade-off reasoning written up in
`CRF_ARCHITECTURE_ALIGNMENT_VERDICT.md`'s own Addendum 2.

### Stage 5 — final verification

## Verification

```
$ cd sail_tests && bash run_veda_selfcheck_tests.sh
...
58/58 passed
```
Sail model itself was never touched this milestone (confirmed: zero timing/cycle/latency concept
anywhere under `toolchain/sail-riscv/model/extensions/Veda/`) — a true no-op regression check,
including `vc_scheduler_cooperative_yield` specifically, the Sail-side scheduler self-check named as
this milestone's own mandatory zero-regression gate.

```
$ cd rtl && bash run_veda_smoke_test.sh
...
49/49 passed (46 pre-existing + 3 new: m24_latency, m24_odt_tcm, m24_ocsc_tcm), 0 failed
```

```
$ cd rtl && bash run_act4_tests.sh
...
Summary: 51/51 passed, 0 failed, 0 timed out
```

Zero regressions across all three independent verification suites.

## The `E=0` shipped default — a deliberate, verified choice, not an oversight

`DRAM_EXTRA_CYCLES` ships as **0**, not the design doc's originally-proposed 10, discovered *before*
committing to a nonzero default by checking the existing suite's own cycle budgets (`repeat(12)` in
`tb_veda_smoke.sv:23` and similarly tight budgets elsewhere): all 46 pre-existing RTL smoke tests
share one compiled core and use Object-Bind extensively against fixed, tight budgets — a nonzero
global default would have caused real budget-exhaustion failures across the corpus, not logic bugs.
The stall FSM's own correctness at a real nonzero `E` was verified separately (Stages 1 and 4 above,
temporary builds, mutation-tested) rather than shipped as the global default. This mirrors this
project's own established "verify before deciding" discipline applied to a build configuration
choice, not just to RTL logic.

## What this milestone does not show

- **No physically-separate SRAM bank was built.** "TCM" here is a real latency-classification
  distinction (Stage 2, `$veda_odt_tcm_hit`) plus a genuinely separate *array* for the scratch
  region (Stage 3, `tcm_scratch[]`), but neither claims a distinct memory-technology implementation
  — matching this project's own single-cycle-microarchitecture caveat carried since the very first
  benchmark study.
- **TCM-scratch access is OCL.C/OCS.C only.** Plain OCL.D/OCS.D, NMC_ADD, and Veda-Atomic against a
  TCM-scratch-backed object are explicitly out of this milestone's scope and unsafe to use (§ Stage
  3 above) — a real, stated software contract, not yet enforced by any hardware trap.
  A future milestone extending TCM coverage to these instructions, or adding a real bounds trap for
  a misuse, is a legitimate next step, not built here.
- **Multi-hart TCM contention is out of scope by construction, not solved.** This core is
  single-hart (`MHARTID=0` fixed); the real, measured cross-hart TCM-contention covert channel
  (Wrisley et al., NordSec 2025, up to 68 kbps) is a forward-declared constraint for any future
  multi-hart Veda-Core, requiring per-hart-private banks or a real static time-partitioned arbiter
  (Wang/Ferraiuolo/Suh, HPCA 2014) before this security property could be trusted again in that
  setting.
- **Stage 4's composed table is a real, spot-check-validated composition of two independently
  measured quantities, not a fresh full re-simulation of all eight configurations.** The spot-check
  matched to the exact cycle on both halves of the formula, which is why this is treated as a real
  result rather than an estimate — but a full independent re-simulation of all eight points was not
  performed as a second, redundant confirmation.
- **Object_ID allocation within the TCM-eligible range is a software convention, not yet enforced or
  automated.** No compiler backend or runtime allocator exists yet that automatically places
  "hot" objects' IDs below `TCM_ODT_ENTRIES` — this is a manual discipline today, the same honest
  limitation `CAPABILITY_REGISTER_PRESSURE_STUDY.md` already carried for register allocation itself.
