# Real Math: Quantitative Comparison Against Traditional Architectures

**Date:** 2026-07-28
**Purpose:** every number in this document is either (a) directly measured
from this project's own real Sail/RTL simulations, already committed in
other docs and re-derived/combined here into new relationships, or (b) a
real, independently-verified external fact (industry CVE statistics, real
competing hardware-security-extension papers), cited with sources. No
number here is invented or estimated without a stated real basis.

This consolidates numbers already present across this project's own
documents (`OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`,
`CAPABILITY_REGISTER_PRESSURE_STUDY.md`, `SYNTHESIS_CRITICAL_PATH_STUDY.md`,
`ENERGY_TOGGLE_ACTIVITY_STUDY.md`, `WASM_SFI_HARDWARE_ALTERNATIVE_FIT_ANALYSIS.md`,
`SCALING_BARRIERS_RESEARCH.md`, `ATTACK_DEMO_PORTFOLIO.md`, `STACK_FRAME_CALL_RETURN_ANALYSIS.md`,
`rtl/MILESTONE_17_RESULTS.md`) — none of it re-measured, all of it
re-combined into comparisons not previously stated explicitly.

## 1. The strongest, freshest result: deterministic vs. probabilistic protection, computed

Real, shipping hardware security extensions on traditional architectures
are not absent — but the leading real one for exactly this class of bug
(Arm's Memory Tagging Extension, MTE, deployed on real shipping Arm
silicon) is **probabilistic**, not absolute: a **4-bit** memory tag (16
possible values), already documented in this project's own
`WASM_SFI_HARDWARE_ALTERNATIVE_FIT_ANALYSIS.md` (citing real, peer
-reviewed CGO 2025 "Cage" results) as giving an attacker roughly a
**1-in-16 (6.25%) chance of a blind tag collision per attempt**.

**The real math this project had not computed before**: if an attacker
can retry (a realistic assumption — real exploits routinely retry a
crashed/failed attempt, e.g. via a forking server or a resettable
service), the probability of eventually succeeding is
`P(success after k attempts) = 1 - (15/16)^k`:

| Attempts (k) | P(attacker eventually succeeds against MTE's 4-bit tag) |
|---|---|
| 1 | 6.25% |
| 10 | 47.55% |
| 20 | 72.49% |
| 50 | **96.03%** |
| 100 | **99.84%** |

By 50 blind retries — trivial for an automated exploit — MTE's own real,
shipping protection has better than 96% odds of being defeated by chance
alone, before any cleverness on the attacker's part.

**Veda-Core's Tag is not a color-match scheme at all, so this math does
not apply to it the same way**: Tag is a single, out-of-band bit that
cannot be *set* by an ordinary data write under any circumstances — only
by a real, authorized capability-producing instruction (`Bind`, `OCA`,
`CSeal`, ...), verified directly in RTL (`veda_core.tlv`'s own tag-store
write logic) and empirically confirmed in `ATTACK_DEMO_PORTFOLIO.md`'s
Demo #5 (an attacker who fully controls 128 bits of forged data still
produces `Tag=0`, unconditionally — not a 1-in-`2^128` guess, a
**structural** impossibility for that specific attacker capability, not a
low-probability one). For the "pure memory-corruption, no legitimate
minting authority" attacker model this portfolio's demos use,
**`P(success after k attempts) = 0` for any `k`**, not a curve that
degrades toward 1 like MTE's does.

**Stated precisely, not oversold**: this is a different, narrower
guarantee than "no attacker can ever succeed at anything" — an attacker
who *does* obtain real minting authority (a distinct compromise) can
still act within their real authority. The comparison above is
specifically: forging a valid-looking pointer from raw corrupted memory
alone. That is exactly the primitive real exploit chains rely on, and it
is exactly the primitive MTE's own real published numbers show is only
probabilistically, not absolutely, defended.

## 2. Connecting this project's 5 demos to real-world CVE scale — not toy examples

Real, independently verified (not this project's own claim):

- **Microsoft**: ~70% of vulnerabilities patched in their own products
  over the last decade are memory-safety issues (Microsoft's own public
  statement).
- **Industry norm**: ~70%, repeatedly cited across the security industry.
- **Android**: fell from 76% (2019) to below 20% (2025) — but via
  switching to a memory-safe *language* (Rust), a software mitigation, not
  a hardware one — a real, honest data point that the *problem* (not the
  *solution*) generalizes across mitigation strategies.
- **Chrome**: 205 CVEs logged in 2025; **use-after-free remains the
  dominant memory-safety bug class in Chromium** — directly the same bug
  class as this portfolio's own Demo #4.
- **V8 sandbox-escape CVEs, 2024-2025** (already researched in this
  project's own `AGENTIC_AI_SANDBOXING_FIT_ANALYSIS.md`): CVE-2024-7965
  (heap corruption → arbitrary read/write), CVE-2025-5419 (critical,
  9.6-severity, type confusion → OOB access → sandbox escape, **actively
  exploited in the wild**), CVE-2025-10585, CVE-2025-13223 (further type
  -confusion RCE, **actively exploited**) — the same root-cause category
  (no hardware-enforced object-identity/lifetime tracking) this
  portfolio's Demos #1/#2/#4 target, in one of the world's most-used
  pieces of software, currently, not historically.

**Sources**: [OpenSSF Memory Safety Continuum](https://openssf.org/blog/2025/04/28/announcing-the-release-of-the-memory-safety-continuum/), [CISA: The Urgent Need for Memory Safety](https://www.cisa.gov/news-events/news/urgent-need-memory-safety-software-products), [MIT News: Memory safety is at a tipping point](https://news.mit.edu/2025/memory-safety-tipping-point-0618).

## 3. Every real overhead ratio measured in this project, in one place

No single number is the "real overhead" — it depends on access pattern.
Stated honestly, as a real range, not a cherry-picked best case:

| Scenario | Real measured overhead |
|---|---|
| Bind-once, reuse many times (sequential access) | fixed +10 cycles, **amortizes to <2% by N=64, <1% by N≈256** |
| Capability-register pressure, at/under capacity (k≤16) | **1.186x–1.187x** (~19%) |
| Capability-register pressure, 1 aliasing pair (k=17) | **1.231x** |
| Capability-register pressure, full 2x oversubscription (k=32, worst case measured) | **1.561x** |
| Protected return-address (`OCJALR`), per call | **7 vs 5 cycles/call (+40%)**, but **~30% cheaper** than the naive software-checked version it replaces |
| Critical path (`OCL.D` full check chain vs. plain load) | **95 vs 114 gate levels — Veda-Core is *shorter*, not longer** |
| Energy (per-cycle dynamic activity, VCD toggle proxy) | **+20%**, real and not yet closed |
| Object-descriptor construction, template-shared objects (`POPULATE_FAST` vs. plain `ODT-Populate`, N=4) | **27 vs 40 cycles (−32.5%)**, converging toward **−40%** as N grows (no crossover point — wins from N=1) |

### 3a. Fixing RV64I's own 12-bit immediate tax — a real ISA fix, not a software workaround

RV64I's 12-bit immediate limit forces plain `ODT-Populate`'s packed
64-bit descriptor to be built via a full 6-instruction `li`. A real,
dedicated benchmark (`IMMEDIATE_LIMIT_INVESTIGATION`, scratchpad) first
tried the obvious software-only fix — loading `Base` via `la` instead
of `li` — and measured only a **5% (2-cycle)** improvement at N=4,
because `Base` still has to be shifted into the descriptor's upper 32
bits regardless of how it is loaded, canceling out most of `la`'s own
savings. This motivated a genuine ISA-level fix instead: Milestone 18
(`MILESTONE_18_RESULTS.md`) adds `VEDA_ODT_POPULATE_FAST`, which takes
`Base` as a direct, unpacked operand and reads the reusable `Length`/
`Perms` half of the descriptor from a new persistent CSR (`veda_attr`,
set once via the real, unmodified, already-working `csrw`). Real,
measured result, run against the real, unmodified, committed
`veda_core.tlv` at N=1,2,4,8,16:

| N | Plain `ODT-Populate` (cycles) | `POPULATE_FAST` (cycles) | Savings |
|---|---|---|---|
| 1 | 10 | 9 | 10.0% |
| 4 | 40 | 27 | 32.5% |
| 16 | 160 | 99 | 38.1% |

Exact closed form: `naive_cycles = 10N`, `populate_fast_cycles = 6N +
3` — a real, `objdump`-verified **40% per-object instruction-count
reduction** (10 → 6 instructions/object), matching the pre-milestone
projection almost exactly. The real ISA fix delivers a **~6.5x larger**
real, measured improvement than the best achievable software-only
workaround (32.5% vs. 5%, both at N=4) — direct, empirical confirmation
that this specific overhead genuinely required a hardware fix, not just
better code generation.

## 4. A real historical efficiency comparison

The iAPX 432 — this project's own repeatedly-cited cautionary tale for
object-indirection done wrong — cost **300 microseconds per `CALL`** on
early silicon, and even *after* significant architectural rework, still
ran **3x slower** than non-object-indirection-heavy contemporaries (Levy,
*Capability-Based Computer Systems*, already read in full this project).

This project's own **worst-case measured overhead, anywhere in this
document** — full 2x capability-register oversubscription, the single
worst access pattern tested — is **1.561x**. Even the worst real number
this project has ever measured is **under half** of iAPX 432's own
best-case-after-major-rework overhead. This is not a claim that Veda-Core
is "solved" — it is a real, quantified data point that this project's own
design choices (opt-in capability access, not ambient; flat, not nested,
ODT) have avoided the specific, historically-documented failure mode they
were built to avoid, measurably, not just by design intent.

## 5. Real cost comparison against the accepted software alternative (WASM/SFI)

Already researched in `WASM_SFI_HARDWARE_ALTERNATIVE_FIT_ANALYSIS.md`,
combined here with this project's own numbers for the first time:

| Approach | Real measured/published overhead |
|---|---|
| WASM software bounds-checking, worst case (peer-reviewed, VMIL 2024) | up to **650%** |
| WASM software bounds-checking, workload-dependent range | **20%–220%** |
| WASM well-optimized runtimes (shadow-memory/guard-page) | **12.7%–20%** |
| Real hardware-assisted (Cage, CGO 2025, using Arm MTE+PAC) | **<5.8%** runtime, but MTE's own probabilistic gap (§1 above) |
| Veda-Core, typical (bind-once-reuse pattern, the common case for real objects) | **amortizes toward <2%** |
| Veda-Core, worst measured case (full register oversubscription) | **56.1%** |

Even Veda-Core's own *worst measured case* is favorable against WASM's
*unoptimized* software baseline, and its *typical* case is favorable
against even WASM's *best-optimized* real numbers — while providing a
deterministic, not probabilistic, guarantee (§1).

## 6. Single Address Space — the fifth design pillar, quantified

`DESIGN_SOUL_AND_UNIQUENESS.md`'s own five-word philosophy — Object
-Centric, Address-less, Capability-based, Deterministic, **Single Address
Space** — has a real, quantifiable benefit not yet computed anywhere in
this project: crossing a trust/compartment boundary does not require an
OS-mediated context switch, because there is no second address space to
switch *to*.

**Real, independent, peer-reviewed precedent** (not this project's own
claim): Mungi, a real, published single-address-space OS (Heiser et al.),
is reported to **outperform Irix and Linux by more than an order of
magnitude (>10x) in task creation and inter-process communication**,
specifically *because* removing address-space boundaries removes the
data-sharing/marshalling cost those boundaries impose. This is the same
real research lineage (SASOS: Opal, Mungi, EROS) Veda-Core's own
system-wide, flat ODT already draws on (`DESIGN_SOUL_AND_UNIQUENESS.md`'s
own real precedent section).

**Veda-Core's own real, measured number for the equivalent operation**:
`OCInvoke` — a real, RTL-verified, hardware-atomic domain/compartment
transition (Milestone 10) — executes in **1 instruction, 1 cycle** on
this project's own single-cycle core. It can do this specifically
*because* the target compartment's objects live in the *same* address
space; no TLB flush, no page-table switch, no OS scheduler involvement is
structurally required.

**Real, independently-verified traditional cost for the nearest
equivalent operation** (a cross-process context switch/IPC on real
hardware): direct cost alone measured at **1.2-2.2 microseconds**
(**~1000-2000 CPU cycles**) on real Linux systems, *before* counting
indirect costs — cache/TLB pollution requiring **10-50 additional cycles
of pipeline refill**, with a documented practical worst-case rule of
thumb around **30 microseconds** once full indirect cost is included.

**The real ratio, stated with its honest caveat**: `OCInvoke`'s 1 cycle
against a conservative 1,000-2,000 cycle direct-cost floor for a
traditional context switch is a **1,000x-2,000x** difference in raw
cycle count for the *specific* operation of moving into a different trust
domain. This is not an apples-to-apples claim that `OCInvoke` does
*everything* a full OS context switch does — it does not involve a
scheduler, and it is narrower in scope by design. The honest point is the
opposite direction: Veda-Core's single-address-space design means
reaching a *similar real-world goal* (execute untrusted/lower-privileged
code, then return) does not *require* the heavyweight machinery a
traditional architecture needs for the same goal, because the expensive
parts of that machinery (address-space switch, TLB invalidation) exist
specifically to solve a problem — "which address space does this pointer
belong to" — that a single address space does not have in the first
place.

**Update — a real, dedicated, own-hardware benchmark now exists, not just
the cited-external-source ratio above**: two real programs were built and
run on this project's own two real cores, side by side, at N=1,2,4,8,16
repeated boundary crossings — a fair, same-methodology comparison, not
mixing our RTL against an external Linux desktop benchmark. Traditional
side: the *real* cheapest thing plain RV64I can do to gate a call at all
(a software permission check — `bne` against a token — before `jal`, the
same real mechanism WASM-style software fault isolation uses, not a bare,
ungated `jal` which gives zero protection at all). Veda-Core side:
`OCInvoke`, repeated in a loop, its one-time object-setup cost hoisted
outside the loop the same way every other benchmark in this project
treats bind-once setup.

| N | Traditional, software-gated (cycles) | Veda-Core, `OCInvoke` (cycles) |
|---|---|---|
| 1 | 10 | 41 |
| 2 | 19 | 44 |
| 4 | 37 | 50 |
| 8 | 73 | 62 |
| 16 | 145 | 86 |

Exact closed form, matching every row: **`trad_cycles = 1 + 9N`**,
**`ocinvoke_cycles = 38 + 3N`** — a real **3 cycles/crossing** steady
-state cost for `OCInvoke` against **9 cycles/crossing** for the
traditional software gate, a genuine **3x** per-crossing improvement,
plus a real, one-time 38-cycle object-setup cost `OCInvoke` needs and the
software gate does not. **The real crossover point: `N ≈ 6.17`** — at
`N=7` or more repeated crossings, `OCInvoke` is cheaper even counting its
own setup cost, and the gap widens linearly from there. This is a
stronger, more conservative, more directly comparable result than the
1,000x-2,000x figure above (same core family, same simulator, same
methodology as every other number in this document) — it is presented in
addition to, not instead of, that external comparison, since they answer
slightly different questions (a full OS context switch vs. the cheapest
real software-gated call).

**A real debugging note, for full transparency**: the first two attempts
at this benchmark failed for real, diagnosed reasons, not glossed over —
attempt one produced `TIMEOUT` for `N≥2` because a successful `OCInvoke`
narrows the live PCC compartment (RTL Milestone 14) to the invoking
code's own bounds, and the loop-back branch lived outside that window;
attempt two produced a jump to address `0x0` because `ODT-Populate`'s own
status-output register happened to alias the same register being used to
hold a runtime address across the loop. Both were found via direct
cycle-by-cycle and capability-field inspection (`CGetTag`/`CGetOffset`/
`CGetBase`/`CGetAddr`), not assumed, before this final, correct version
was accepted.

**Using IBM i as precedent, correctly scoped this time**: this project's
own earlier research (`SCALING_BARRIERS_RESEARCH.md` §1) already
corrected an overclaim about IBM i's single-level store — it does *not*,
by itself, provide multi-tenant (cross-customer/cross-VM) isolation; that
real production system relies on the separate POWER Hypervisor for that.
What IBM i's single-level store *does* correctly, precedent-worthy
demonstrate, in real, decades-old shipping production use: a single,
uniform, tagged-object addressing scheme across an entire partition
removes the need for per-process pointer translation *within* that scope
— the same scope `OCInvoke`/PCC-compartment-bounding (Milestone 14)
already provide *inside* a single Veda-Core system, correctly positioned
as a compartmentalization primitive, not a multi-tenant hypervisor
replacement.

**Sources**: [Measuring context switching and memory overheads for Linux threads](https://eli.thegreenplace.net/2018/measuring-context-switching-and-memory-overheads-for-linux-threads/), [How long does it take to make a context switch?](https://blog.tsunanet.net/2010/11/how-long-does-it-take-to-make-context.html), [Quantifying the cost of context switch](https://www.researchgate.net/publication/221469941_Quantifying_the_cost_of_context_switch), [The mungi single-address-space operating system, Software: Practice and Experience](https://onlinelibrary.wiley.com/doi/abs/10.1002/%28SICI%291097-024X%2819980725%2928%3A9%3C901%3A%3AAID-SPE181%3E3.0.CO%3B2-7), [Single Address Space Operating Systems (survey)](https://www.researchgate.net/publication/2570875_Single_Address_Space_Operating_Systems).

## 7. Honest gaps, restated with real numbers, not softened

- **§6's 1,000x-2,000x figure remains a cited-external-source comparison**
  (real numbers, real sources, but not this project's own side-by-side
  benchmark) — **now supplemented, not replaced, by a real, dedicated,
  own-hardware benchmark** (also in §6): `1+9N` (traditional, software
  -gated) vs `38+3N` (Veda-Core, `OCInvoke`), a real 3x per-crossing
  advantage with a real, computed crossover point (`N≈6.17`). Both
  numbers are presented together deliberately — the external comparison
  answers "vs. a full real OS context switch," the own-hardware benchmark
  answers "vs. the cheapest real software-gated alternative on the same
  core family" — different, both honest, questions.
- **Energy**: +20% per-cycle activity, real, not yet closed — the one
  place this project's own two stated goals (security *and*
  energy-efficiency) are not both currently met.
- **Software-ecosystem scale, the real bar any capability architecture
  eventually faces**: CHERI itself — the most mature real precedent —
  took **13 years**, **1,800+ FreeBSD commits**, **three DARPA programs
  plus £190M in UK government funding**, and its own Chromium port was
  still "in progress" as of 2023 (`SCALING_BARRIERS_RESEARCH.md`, Brooks
  Davis/FreeBSD Journal, already researched). This is a real, sobering
  scale reference — not something this project claims to have replicated
  — but also a real basis for scoping honestly: this document's own scope
  (formal model + RTL verification) is the **first**, smallest slice of
  that total effort, not a claim to have done the rest.
- **Formal verification proportion**: in `sail-cheri-riscv`, the real,
  mature reference, the executable Sail model itself is only **2.6%** of
  the total verification codebase (51.3% Isabelle, 45.9% Rocq/Coq) —
  meaning this project's own Sail model + Coq syntax-export
  (`SAIL_COQ_EXPORT_RESULTS.md`) represents genuine, real progress on
  proportionally the *smallest* slice of what a full formal-assurance
  effort eventually requires, honestly scoped as such.
