# Veda-Core — Object-Centric, Address-Less, Capability-Based RISC-V Extension

Veda-Core is a RISC-V processor extension that closes one of the oldest,
most persistent security holes in computing: programs using raw memory
addresses that can be guessed, forged, or reused after being freed. Instead of addresses, software
works with `Object_ID`s that the hardware checks on every single memory
access — enforcing **memory safety** automatically, and keeping different
parts of a program isolated from each other in hardware
(**compartmentalization**), deterministically, every time.

## What is Veda-Core

Traditional processor architectures treat memory as flat bytes at raw
addresses: a raw load/store instruction — `SD` on RISC-V, `MOV [addr], reg`
on x86, `STR` on Arm — has no bounds check, no tag check, no
use-after-free detection built into the instruction itself, on any
mainstream architecture's own base ISA. Veda-Core replaces that contract
at the ISA level, built on five design pillars:

- **Object-centric**: memory is not "bytes at addresses," it is Objects.
  Software holds an `Object_ID`, never a raw address, for memory-safety
  purposes.
- **Address-less**: no raw software address is used in ISA/ABI-visible
  memory-safety semantics — software works only with an `Object_ID` and a
  relative `Offset`. Because of that, an object can physically move in
  memory (`Rebind`) without software changing a single bit: RTL
  Milestone 8 relocated a real object to a new physical address, and the
  capability register's own untouched `Offset` correctly followed it
  there on the very next access (`veda-core/rtl/MILESTONE_8_RESULTS.md`).
- **Capability-based**: software's `Object_ID` is looked up in a flat,
  system-wide Object Descriptor Table (ODT) — hardware's own directory of
  every object's location and size — and loaded into a 128-bit capability
  register: a tamper-proof access pass combining where the object is
  (`Base`), how big it is (`Length`), where within it the program is
  currently pointing (`Offset`), a hidden validity marker (`Tag`), and a
  version number that catches stale references (generation counter). Like
  a key only a locksmith can cut, a capability can only be produced by
  real, authorized hardware operations (`Object-Bind`, `OCA` [Object
  Capability Adjust], ...) — software can never fabricate one by writing
  arbitrary bits into the register (see the arbitrary-pointer-forgery
  result below).
- **Deterministic**: every access is checked in hardware, every time, with
  zero software-visible probability of bypass (`P(bypass) = 0` — not just
  rare, it cannot happen at all — vs. Arm MTE's probabilistic tag
  matching, where a narrow 4-bit tag can coincidentally collide).
- **Single, global object namespace**: the ODT is one flat, system-wide
  table, not partitioned per process — an `Object_ID` means the same thing
  everywhere in the system.

None of this is a brand-new idea invented from scratch — flat, system-wide,
ID-indexed capability tables were explored by real 1970s-80s hardware (the
Plessey System 250, the Cambridge CAP computer) before the field moved on,
for throughput and cost reasons specific to that era. Veda-Core is a
deliberate revival of that design branch, built for today's transistor
budgets and today's security threat landscape.

See `veda-core/VEDA_CORE_SPEC.md` for the full architecture and
`veda-core/TECHNICAL_BRIEF.md` for a guided walkthrough.

## Micro Architecture Visualization



https://github.com/user-attachments/assets/a46c9a61-ef68-4ae5-8912-edf02b897364


## Compartmentalization Visualization



https://github.com/user-attachments/assets/a454737e-e342-45c1-81d3-4bb3c8d80044



## Real measured results

(from committed Sail + RTL simulations)
- Deterministic tag checks: `P(bypass) = 0` (vs. Arm MTE's probabilistic
  tags) — see `veda-core/REAL_MATH_QUANTITATIVE_COMPARISON.md`.
- OCInvoke (compartment crossing): `38 + 3N` cycles vs. software `1 + 9N`,
  where `N` is the number of crossings — Veda-Core pays a larger one-time
  setup cost (38) but a 3x cheaper cost per crossing (3 vs 9), winning
  outright past N≈6 — see `veda-core/REAL_MATH_QUANTITATIVE_COMPARISON.md`.
- OCJALR (protected-return-jump): `7 cycles` vs. naive `10 cycles`
  (≈−30%) — "naive" means hand-writing the check as 4 separate
  instructions (`CGetTag`+`beqz`+`CUnseal`+`CGetAddr`), which a
  programmer can forget to include; `OCJALR` collapses all of it into
  one atomic, hardware-enforced instruction — see
  `veda-core/rtl/MILESTONE_17_RESULTS.md`.
- Object-descriptor construction (`POPULATE_FAST`): `6N+3` vs `10N`
  (−32.5% @ N=4) — here `N` is the number of objects populated from the
  same Length/Permissions template; the old way rebuilds a packed 64-bit
  descriptor per object (10 instructions), `POPULATE_FAST` sets
  Length/Perms once in a CSR and only loads Base fresh per object (6
  instructions) — see `veda-core/rtl/MILESTONE_18_RESULTS.md`.
- Critical check chain shorter than plain loads: `95 vs 114` logic-gate
  levels — a gate-level synthesis measurement of the longest
  combinational path (Yosys), not cycle count. Despite running 5
  security checks (Tag, staleness, Seal, Permission, Bounds), Veda-Core's
  `OCL.D` path is shorter because the checks run in parallel with the
  address computation, not in series before it — see
  `veda-core/SYNTHESIS_CRITICAL_PATH_STUDY.md`.
- Fixed object-bind overhead measured at `+10 cycles` (amortizes to <2%
  by N=64) — see `veda-core/OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`.
- Five real attack-demo classes, each run on both traditional RV64I and
  Veda-Core in real Icarus Verilog simulation, real register/trap values
  read directly from the run, not theoretical:
  - **Out-of-bounds read**: secret value leaked into a GPR vs. blocked
    (`mcause=0x18`, Bounds Violation).
  - **Out-of-bounds write**: an adjacent canary corrupted vs. untouched.
  - **Stack-smashing / return-address hijack**: control flow fully
    attacker-hijacked vs. caught structurally by `OCJALR` — and ~30%
    *cheaper* than a naive software-checked equivalent (7 vs. 10 cycles).
  - **Use-after-free**: a stale reference silently returns a reused
    object's data (traditional "free" is a software-only convention,
    hardware doesn't know) vs. a generation-counter Tag Violation trap
    (Veda-Core's `ODT-Destroy` bumps a real generation counter; a stale
    capability's old generation no longer matches).
  - **Arbitrary-pointer forgery**: a hand-crafted bit pattern used as a
    pointer succeeds unconditionally on traditional hardware (the most
    powerful exploitation primitive — arbitrary read/write) vs.
    `CGetTag = 0` and a hard trap (an ordinary store can write the bits,
    but never the out-of-band Tag — only real hardware mint operations
    can).

  See `veda-core/ATTACK_DEMO_PORTFOLIO.md` for the exact register/trap
  values per demo and `veda-core/EVIDENCE_INDEX.md` for the verification
  ledger (which claims were re-run this session vs. file-committed vs.
  externally cited) — note demos #4/#5 are session-scoped test programs,
  not yet part of the permanent, committed regression corpus.

## Verification status
- Sail formal model: 30/30 self‑checking tests (re-run during this audit;
  see `EVIDENCE_INDEX.md` for the exact commands and outputs).
- RTL implementation (TL‑Verilog → SystemVerilog): milestone
  regressions pass; per-milestone results live in `veda-core/rtl/`.
- RISC‑V ACT4 RV64I conformance: 51/51, zero regressions (run
  directly against `veda_core.tlv`; see `veda-core/rtl/ACT4_CONFORMANCE_RESULTS.md`).

## Where to find the authoritative docs and evidence
- Technical brief: `veda-core/TECHNICAL_BRIEF.md`
- Architecture spec: `veda-core/VEDA_CORE_SPEC.md`
- Benchmarks: `veda-core/OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`
- Evidence index: `veda-core/EVIDENCE_INDEX.md`
- Attack demos and analysis: `veda-core/ATTACK_DEMO_PORTFOLIO.md`
- Roadmap and next steps: `veda-core/NEXT_STEPS_ROADMAP.md`
- Formal verification plan: `veda-core/FORMAL_VERIFICATION_PLAN.md`
- Milestone results (Sail + RTL): `veda-core/MILESTONE_V-A_RESULTS.md`, `veda-core/MILESTONE_V-B_RESULTS.md`, `veda-core/MILESTONE_14_RESULTS.md`, `veda-core/rtl/ACT4_CONFORMANCE_RESULTS.md`
 

## Quick reproduction notes
- The RTL and Sail models are in `veda-core/rtl/` and `toolchain/sail-riscv/`.
- Primary reproduction scripts live under `veda-core/` and
   `veda-core/rtl/` (for example `verification.sh`, `rtl/run_act4_tests.sh`).
- Results reported above come from Icarus Verilog simulations and the
   Sail executable model; no FPGA/ASIC is claimed.

## Limitations & honest caveats
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
`sail-riscv`, `llvm`, `demo`, `debug`).

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

