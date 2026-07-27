# Veda-Core RTL — Full ACT4 RV64I Conformance Results (against `veda_core.tlv` itself)

**Date:** 2026-07-26
**Scope:** closes a real, previously-unchecked verification gap, found while auditing the project's own docs for staleness and considering what genuinely valuable, well-bounded work remained after fourteen RTL milestones and two remaining, deliberately-deferred large items (`OSpecialRW`'s own capability-gating, real multi-hart RTL).

## The real gap this closes

The base RVA23 core's own real ACT4 RV64I conformance result (51/51, `rtl/docs/ACT4_RESULTS.md`) has always been run against `rv64i_core.tlv` — a separate, deliberately untouched file. Every one of Veda-Core's own fourteen RTL milestones checked base-ISA regression only via a much smaller, hand-assembled 81-instruction smoke test (the `run_veda_smoke_test.sh` suite's own final step), never the full, real ACT4 conformance corpus, and never against `veda_core.tlv` — the actual file that carries every one of the fourteen milestones' own real additions (new decode paths sharing opcode space, new persistent CSR/trap state, the Milestone 14 `$instr`-forcing-to-NOP mechanism touching the fetch path itself). A base-ISA regression in `veda_core.tlv` specifically was a real, live risk that had genuinely never been checked.

## What was verified, and how

`rtl/sim/tb_act4.sv` (the real ACT4 conformance testbench, confirmed interface-compatible with `veda_core.tlv` before copying it — both files use the identical top-level module signature and the identical `elfmem[]` array, same `ELFMEM_BASE`/`ELFMEM_SIZE`, checked directly against both files' own `localparam` declarations, not assumed) was copied verbatim into `veda-core/rtl/sim/`, requiring zero adaptation. A new `veda-core/rtl/run_act4_tests.sh`, mirroring `rtl/run_act4_tests.sh`'s own proven structure exactly, transpiles and compiles `veda_core.tlv` once, then re-runs the same compiled simulation against every one of the real ACT4-generated RV64I ELFs (`act4-verify/work/rva23-base-rv64i/elfs/rv64i/I/*.elf` — the same 51-file corpus the base core's own 51/51 result already used).

## Result

**51/51 passed, 0 failed, 0 timed out** — `veda_core.tlv` genuinely, currently passes the exact same real ACT4 RV64I conformance suite the untouched `rv64i_core.tlv` does. Fourteen RTL milestones of Veda-Core additions — new Custom-0/1/2/3 decode logic sharing the base ISA's own opcode-space boundaries, a from-scratch Zicsr-lite CSR/trap subsystem, and (Milestone 14) a genuinely new every-cycle check that forces `$instr` itself to a substitute value under a specific condition — have not regressed base RV64I correctness in any of the 51 real, ratified test cases covering every RV64I instruction.

This is a real, additional confidence result, not a formality: Milestone 14 in particular modifies the `$instr` assignment directly (the single most central, highest-blast-radius signal in the whole file, read by literally every other decode signal) — this run is the first real evidence, beyond the project's own smaller smoke tests, that this change is genuinely side-effect-free for the base ISA across a broad, independently-authored, reference-signature-checked test corpus.

## Not a new milestone in the ISA sense — no new instruction or design decision

This work adds no new Veda-Core capability, closes no named spec gap, and required no design decision — it is purely a verification-coverage improvement, real and valuable in its own right (per this project's own repeated emphasis on rigorous, non-hallucinated verification), but categorized here separately from the numbered Sail/RTL milestone sequence rather than claimed as one.
