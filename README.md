# Veda-Core — Object‑Centric Capability Extension for RISC‑V

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
- A real LLVM-based toolchain now exists (assembler, disassembler, a
  GDB stub with live capability-register visibility, and a SoftBound
  -style compiler pass that transparently retrofits ordinary C pointer
  code into capability-checked accesses) — see "Toolchain: full setup,
  from a fresh clone to a debugged demo" below. It compiles a real,
  verified positive+negative demo, not synthetic examples; general
  C/C++ compatibility and library/ABI interop are explicitly **not**
  yet established (see the toolchain results docs for the honest scope).

---

## Toolchain: full setup, from a fresh clone to a debugged demo

Three real, public repos make up the full toolchain (following CHERI's
own real approach: public forks of upstream LLVM and the Sail RISC-V
model, tracking upstream, with Veda-Core's own extension layered on top
as real, reviewable commits — not a from-scratch reinvention):

| Component | Repo | What it adds |
|---|---|---|
| This repo | `github.com/prabhu-euro20/Veda-Core` | Sail formal-model spec source (via the sail-riscv fork below), TL-Verilog RTL, docs, tests, the compiler pass + runtime + demo programs |
| LLVM/Clang fork | `github.com/prabhu-euro20/Veda-Core-LLVM` (branch `veda-core`) | Capability register class + all 36 Veda-Core instructions + disassembler + MC tests, layered on official `llvm/llvm-project` `release/21.x` |
| Sail RISC-V fork | `github.com/prabhu-euro20/Veda-Core-sail-riscv` (branch `veda-core`) | The full Veda-Core formal model (Milestones 1-22) + a GDB Remote Serial Protocol stub with live capability-register visibility, layered on official `riscv/sail-riscv` |

### One-command setup

```bash
git clone git@github.com:prabhu-euro20/Veda-Core.git rva23-core
cd rva23-core
./toolchain/setup.sh          # clones the two forks above, builds everything,
                               # compiles + runs the real end-to-end demo
```

`./toolchain/setup.sh` is idempotent (safe to re-run — it checks each
component's real build output before redoing multi-minute work, never a
separate bookkeeping file that could go stale) and supports `--dry-run`
to preview, `--force` to rebuild, and individual named targets
(`./toolchain/setup.sh --help` lists them: `deps`, `gnu-toolchain`,
`sail-riscv`, `llvm`, `demo`, `debug`). This follows the real
architectural approach of CHERI's own `cheribuild.py`
(github.com/CTSRD-CHERI/cheribuild) — not its content — sized for this
project's own current, much smaller scope.

### What each step does, if you want to run them by hand

```bash
# 1. System prerequisites (Ubuntu/Debian; verified on this exact
#    combination — see TOOLCHAIN_MILESTONE_2_RESULTS.md for the real,
#    checked package versions)
sudo apt-get install -y clang llvm-dev cmake ninja-build build-essential opam
opam init -y && opam install -y sail

# 2. The real, official riscv64-unknown-elf-{gcc,as,ld,gdb} toolchain --
#    prebuilt, unmodified (`.insn` pseudo-ops already assemble every
#    real Veda-Core encoding with zero patches needed)
wget https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2026.07.15/riscv64-elf-ubuntu-24.04-gcc.tar.xz
mkdir -p toolchain/riscv-collab-gcc
tar xf riscv64-elf-ubuntu-24.04-gcc.tar.xz -C toolchain/riscv-collab-gcc
# real binaries land at toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-*

# 3. Sail RISC-V simulator (the Veda-Core formal model + GDB stub)
git clone --branch veda-core https://github.com/prabhu-euro20/Veda-Core-sail-riscv.git toolchain/sail-riscv
cd toolchain/sail-riscv && mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo -DDOWNLOAD_GMP=FALSE -DENABLE_RISCV_TESTS=TRUE ..
make -j4 && cd ../../..

# 4. LLVM/Clang (the compiler that understands Veda-Core assembly)
git clone --branch veda-core https://github.com/prabhu-euro20/Veda-Core-LLVM.git toolchain/llvm-project
cd toolchain/llvm-project && mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang \
      -DLLVM_TARGETS_TO_BUILD=RISCV -DLLVM_PARALLEL_LINK_JOBS=1 -G Ninja ../llvm
ninja -j4 && cd ../../..

# 5. Compile + run the real, end-to-end demo (ordinary C, no Veda-Core
#    instructions written by hand -- the compiler pass does that)
bash veda-core/compiler/run_veda_demo_tests.sh
```

### Debugging with real capability-register visibility

```bash
SIM=toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
GDB=toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-gdb
CFG=veda-core/sail_tests/veda_test_sail.json

$SIM --config $CFG --gdbstub 9998 /tmp/veda_demo_linked_list.elf &
$GDB -ex "target remote :9998"
```

Inside `gdb`, ordinary commands work (`break`, `continue`, `step`,
`info registers`) plus Veda-Core's own 16 capability registers are
directly visible: `info registers c0 c0_tag` shows the real, live
128-bit packed capability and its out-of-band tag bit, verified against
an independent second read path (`cgetbase`/`cgetlen`/`cgetperm`/
`cgettag`) matching byte-for-byte.

Full detail on every step above, including two real bugs found and
fixed during original development (not glossed over): `TOOLCHAIN_MILESTONE_{2,3,4,9}_RESULTS.md`.

