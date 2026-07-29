# Veda-Core -- Object‑Centric + Capability-Based Address-Less RISC‑V Extension Core

This repository subproject implements Veda‑Core: an object‑centric,
address‑less, capability‑based RISC‑V extension designed for deterministic
hardware‑enforced compartmentalization and secure memory access.

Highlights
- Object‑centric ISA: software holds `Object_ID`s; every memory access
  is performed through a bound 128‑bit capability register and a flat,
  system‑wide Object Descriptor Table (ODT).
- Address‑less at the ISA level: no raw software addresses are used for
  memory safety semantics.
- Deterministic enforcement: checks are hardware‑local and designed to
  minimize jitter (WCET focus).

Real measured results (from committed Sail + RTL simulations)
- Deterministic tag checks: `P(bypass) = 0` (vs. Arm MTE's probabilistic tags).
- OCInvoke (compartment crossing): `38 + 3N` cycles vs. software `1 + 9N`.
- OCJALR (protected‑return‑jump): `7 cycles` vs. naive `10 cycles` (≈−30%).
- Object‑descriptor construction (`POPULATE_FAST`): `6N+3` vs `10N` (−32.5% @ N=4).
- Critical check chain shorter than plain loads: `95 vs 114` logic‑gate levels.
- Fixed object‑bind overhead measured at `+10 cycles` (amortizes to <2% by N=64).
- Five real attack demos where traditional RV64I fails silently and
  see `EVIDENCE_INDEX.md`and `ATTACK_DEMO_PORTFOLIO.md` for reproduction notes and which runs were re-executed.

Verification status
- Sail formal model: 30/30 self‑checking tests (re-run during this audit;
  see `EVIDENCE_INDEX.md` for the exact commands and outputs).
- RTL implementation (TL‑Verilog → SystemVerilog): milestone
  regressions pass; per-milestone results live in `veda-core/rtl/`.
- RISC‑V ACT4 RV64I conformance: 51/51, zero regressions (run
  directly against `veda_core.tlv`; see `veda-core/rtl/ACT4_CONFORMANCE_RESULTS.md`).

Where to find the authoritative docs and evidence
- Technical brief: `veda-core/TECHNICAL_BRIEF.md`
- Architecture spec: `veda-core/VEDA_CORE_SPEC.md`
- Benchmarks: `veda-core/OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`
- Evidence index: `veda-core/EVIDENCE_INDEX.md`
- Attack demos and analysis: `veda-core/ATTACK_DEMO_PORTFOLIO.md`
- Roadmap and next steps: `veda-core/NEXT_STEPS_ROADMAP.md`
- Formal verification plan: `veda-core/FORMAL_VERIFICATION_PLAN.md`
- Milestone results (Sail + RTL): `veda-core/MILESTONE_V-A_RESULTS.md`, `veda-core/MILESTONE_V-B_RESULTS.md`, `veda-core/MILESTONE_14_RESULTS.md`, `veda-core/rtl/ACT4_CONFORMANCE_RESULTS.md`
 

Quick reproduction notes
- The RTL and Sail models are in `veda-core/rtl/` and `toolchain/sail-riscv/`.
- Primary reproduction scripts live under `veda-core/` and
   `veda-core/rtl/` (for example `verification.sh`, `rtl/run_act4_tests.sh`).
- Results reported above come from Icarus Verilog simulations and the
   Sail executable model; no FPGA/ASIC is claimed.

Limitations & honest caveats
- All hardware results are from RTL simulation or Sail execution; there
  is no silicon or FPGA bitstream in this repo yet.
- Energy overhead is real (≈+20% dynamic toggle proxy); see
  `ENERGY_TOGGLE_ACTIVITY_STUDY.md` for methodology and numbers.
- Memory-latency effects were explored via a parameterized TCM/DRAM
  latency sweep; results are in `DRAM_TCM_LATENCY_STUDY.md` (TCM helps
  only when objects are repeatedly re-bound, not for bind-once reuse).
- The toolchain ecosystem (compiler support) is not available — tests are
  hand‑assembled or run in the Sail model.

