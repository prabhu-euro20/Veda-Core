# Domain 4 Analysis: Hardware Alternative to WASM / Software Fault Isolation

**Date:** 2026-07-27
**Scope:** fourth of four "out-of-the-box" directions — real, WebSearch
-verified research, including a search specifically for whether this idea
already has real prior art (it does — represented honestly below, not
glossed over to preserve a novelty claim).

## Real, published WASM bounds-checking overhead — the baseline this domain compares against

Peer-reviewed measurements (IEEE, ACM SIGPLAN VMIL 2024) give real,
wide-ranging numbers: worst-case software bounds checking can cost up to
**650%**; application-dependent overhead ranges **20% (Cholesky) to 220%
(gemm)**; well-optimized runtimes get within **12.7%–20% of native** using
shadow-memory/guard-page techniques. This is the real cost WASM's software
-only safety model pays today, and the real baseline any "hardware
alternative" claim must be measured against.

## Real prior art already exists — this is not unclaimed territory, and this analysis says so directly

A live search for exactly this idea found **Cage: Hardware-Accelerated
Safe WebAssembly** (CGO 2025, a top-tier compiler/architecture venue,
real and current). Cage uses **Arm's Memory Tagging Extension (MTE)** and
**Pointer Authentication (PAC)** — both real, already-shipping ARM
hardware features, not a novel ISA — to add memory safety to WASM's own
sandboxing, with real, published results: **under 5.8% runtime overhead,
under 3.7% memory overhead, and up to a 5.1% speedup** of WASM's own
sandboxing mechanism in some cases. This directly, materially weakens any
claim that "hardware-accelerated WASM safety" is itself a novel idea —
real, shipping silicon already does a version of it, with excellent,
published numbers.

## The real, honest, remaining differentiation — not a performance claim, a mechanism-type claim

Cage's own real limitation, not Veda-Core's invention: **ARM MTE is a
probabilistic mechanism.** MTE tags are 4 bits wide (16 possible colors)
— a use-after-free or heap-overflow is caught only if the stale/adjacent
tag happens not to match, which a real attacker can defeat with
roughly 1-in-16 odds per attempt (well-documented, widely-discussed
property of MTE's own design, not specific to Cage). This is a real,
useful *mitigation* that raises attacker cost — not a hard guarantee.

Veda-Core's `Length`-field bounds check, by contrast, is **deterministic**
— confirmed this session, on real RTL, against a real out-of-bounds
attack, with a 100% catch rate across every case tested
(`SECURITY_COMPARISON_STUDY.md`), not a probabilistic one. This is the
real, honest, remaining differentiation this analysis can defend: not
"faster than Cage" (no comparable measurement exists — Cage's numbers are
from real, synthesized ARM silicon at real clock speed; Veda-Core's own
numbers this session are single-cycle-model instruction counts, a
different kind of measurement entirely, and claiming a performance
comparison between them would be exactly the kind of unfounded claim this
analysis must avoid) but **"deterministic guarantee vs. probabilistic
mitigation,"** a real, qualitative, defensible distinction.

## Verdict

A real, legitimate niche remains — deterministic (not probabilistic)
memory safety for untrusted/sandboxed code execution — but the framing
must change from "no one has done hardware-accelerated WASM safety" (false
— Cage already has, well) to "Veda-Core's specific guarantee is stronger
in kind, not necessarily in measured cost, than the best existing real
alternative." This is a narrower, more defensible claim than this
domain's original framing implied, discovered specifically by doing the
literature check rather than assuming the space was open.

## Honest gaps

- No Veda-Core-to-WASM compilation target or ABI exists — this would be
  large, real, unstarted toolchain work (Cage's own real advantage is
  that it works with *unmodified* WASM binaries and existing LLVM/wasmtime
  infrastructure; Veda-Core has no such ecosystem yet).
- No real silicon exists to make any actual performance claim against
  Cage's own real, published, silicon-measured numbers.
- MTE ships today, in real ARM chips, at scale; Veda-Core does not exist
  in silicon at all — the practical deployment gap between these two
  approaches is enormous and should not be understated.

## Sources

- [Leaps and bounds: Analyzing WebAssembly's performance with a focus on bounds checking (IEEE)](https://ieeexplore.ieee.org/document/9975418/)
- [Performant Bounds Checking for 64-Bit WebAssembly (ACM SIGPLAN VMIL 2024)](https://dl.acm.org/doi/10.1145/3689490.3690400)
- [Cage: Hardware-Accelerated Safe WebAssembly (arXiv / CGO 2025)](https://arxiv.org/abs/2408.11456)
- [Cage: Hardware-Accelerated Safe WebAssembly (ACM/IEEE CGO 2025 proceedings)](https://dl.acm.org/doi/10.1145/3696443.3708920)
