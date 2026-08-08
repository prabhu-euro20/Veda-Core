# TCM Fast-Path Design: Eliminating Object-Bind Repeated-Rebind Overhead Without Reopening the Cache-Timing Side Channel

## 0. What this closes

`CRF_ARCHITECTURE_ALIGNMENT_VERDICT.md`'s own addendum (2026-08-08) established, rigorously: under a
real DRAM-latency model, a repeated-rebind access pattern (the shape CRF register pressure produces)
costs `11 + (7+E)×N` cycles — real, linearly-scaling, not free — while real CHERI's own equivalent cost
(CSC/CLC capability spill/reload) very plausibly rides an ordinary, cache-hit-cheap path, because CHERI's
own "merged-cache hierarchy" caches capability data and tags together. Veda-Core's own ODT is
deliberately, permanently cache-less by design (`DESIGN_SOUL_AND_UNIQUENESS.md`), which is *why* CHERI's
own literature admits its cached path is not immune to cache-timing side-channel attacks
(`UCAM-CL-TR-916`) while Veda-Core's is. The project owner has now asked, explicitly: eliminate the
performance gap **without** giving up the security property that gap is the price of.

This document designs the real, buildable mechanism. Two complementary pieces, both grounded in
already-proven Veda-Core primitives (no new instruction semantics needed for either), plus a real,
rigorously-researched security constraint that governs both.

## 1. Research grounding for the security constraint (new this pass, primary sources)

Before designing anything, the load-bearing question was verified, not assumed: is a small,
deterministic on-chip SRAM (TCM) genuinely immune to the cache-timing side-channel class real CHERI
admits it doesn't solve — and what does it take to keep that property once actually built?

- **Yes, and this is a real, peer-reviewed, directly-on-point precedent, not an inference**: Liu, Harris,
  Maas, Hicks, Tiwari, Shi, "GhostRider: A Hardware-Software System for Memory Trace Oblivious
  Computation," ASPLOS 2015 — a real secure-processor architecture that explicitly turns off caching and
  substitutes a software-directed scratchpad *for exactly this reason*: "cache hit and miss behavior can
  lead to differences in the observable memory traces. To prevent such cache-channel information leakage,
  the GhostRider architecture turns off implicit caching, and instead offers software-directed
  scratchpads." Structurally: a cache has a tag array + comparators + a runtime hit/miss decision
  (Banakar/Steinke/Marwedel, CODES 2002); a scratchpad has none of these — there is no runtime decision
  being made about placement, and therefore nothing analogous to a "hit" or "miss" event to time.
- **The precise property, more exact than "static placement" alone**: GhostRider's own formal security
  property (Memory Trace Obliviousness) requires that the *placement/eviction decision itself* be
  independent of secret-correlated runtime data — "the indices of array a... are deterministic; they do
  not depend on any secret input... it is safe to use the scratchpad to cache array a's accesses." A
  scratchpad whose *contents* are swapped based on secret-correlated behavior would reintroduce the
  channel even though it is not a hardware cache. Veda-Core's own constraint (placement decided at
  Object-creation/compile time, never by observing runtime access frequency) satisfies this directly,
  since a compile-time decision necessarily precedes and cannot depend on runtime secret data.
- **A real, serious caveat that materially shapes this design, confirmed on real RISC-V hardware**:
  Wrisley, Guanciale, Nadjm-Tehrani, Söderquist (Linköping/KTH/Saab AB), "Timing Interference in
  Multi-core RISC-V Systems," NordSec 2025 — directly measured, on real RISC-V (FPGA) hardware, a working
  covert channel from **shared on-chip resource contention alone** (multiple harts arbitrating for one
  finite-bandwidth resource), independent of cache hit/miss: "68 kbps" channel capacity at L2, "19.5 kbps"
  even for pure DRAM-level contention with no cache involved. Their conclusion: "covert channels cannot be
  completely eliminated without significant performance trade-offs" for a *shared* resource — the real,
  peer-reviewed fix is not "use a scratchpad" but "statically time-partition the shared arbiter" (Wang/
  Ferraiuolo/Suh, "Timing Channel Protection for a Shared Memory Controller," HPCA 2014, Cornell) — a
  materially stronger and costlier requirement than static placement alone.
- **Directly, favorably applicable to Veda-Core's own real, current state**: this risk applies only to a
  TCM *shared across multiple harts*. Veda-Core's committed RTL is single-hart today (`MHARTID=0` fixed,
  confirmed Milestone 12) — a per-hart-private TCM is therefore automatically, trivially safe from this
  channel class right now, not by careful design but by the honest fact that there is only one hart to
  share it with. **This must be stated as an explicit, forward-declared constraint, not a silent
  assumption**: if/when Veda-Core ever gets a real multi-hart implementation (already named elsewhere as
  deferred, unattempted work), the TCM must either stay strictly per-hart-private (N separate banks, one
  per hart) or gain a real, statically time-partitioned arbiter before being trusted for this security
  property again.
- **Honest scope limit, not claimed as solved**: Deutsch et al., "DAGguise," ASPLOS 2022, explicitly
  scopes out program-level/early-termination timing variance as a separate, unclosed problem no
  memory-architecture fix addresses. This design closes the ODT/capability-lookup memory-timing channel
  specifically — it is not, and should never be represented as, a blanket "Veda-Core is fully
  side-channel-immune" claim.

## 2. Mechanism A (primary, build first): generalize the already-proven OCS.C/OCL.C spill pattern

**What it is**: the CRF-exhaustion point-fix (`TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md`)
already chose this exact pattern for one specific case (the scheduler's per-thread save-area) — spill a
live capability's exact, already-resolved bits via `OCS.C` to a fast, software-managed memory region, and
restore via `OCL.C` later, skipping the ODT walk entirely. `ARCHITECTURE_IMPROVEMENT_FINDINGS.md`
(Finding 3) already measured this is cheaper in instruction count than a fresh `Bind` (3 vs 4
instructions) and explicitly flagged that "the real payoff would be much larger once combined with [a]
DRAM-latency model — `OCL.C` restore would skip the ODT walk (and its `E`-cycle DRAM-tier cost) entirely,
while a fresh `Bind` would still pay it every time." This design generalizes that pattern from
one hand-picked use site into a real, reusable architectural convention.

**Why this first**: zero new instruction semantics (`OCL.C`/`OCS.C` have existed and been verified since
Milestone 7). The only genuinely new piece is a real, dedicated fast memory region to spill into — today,
`veda_core.tlv` has no latency model or memory-tier distinction at all (confirmed this session: `elfmem[]`
is a single, flat, always-1-cycle array; `DRAM_TCM_LATENCY_STUDY.md`'s own tiering logic only ever
existed in a scratchpad, uncommitted core copy). Building this real TCM region is therefore a genuine
prerequisite for the whole design, not optional scaffolding.

**Mechanism**: a new, small, fixed-address, per-hart-private memory region (`TCM_BASE`..`TCM_BASE +
TCM_BYTES-1`), always 1-cycle/zero-wait-state regardless of the new DRAM-latency model applied to the
rest of `elfmem[]`/`odt_mem[]`. Software (hand-written `.S`, or a future compiler-pass convention) spills
a capability register there via `OCS.C` when register pressure requires evicting it, and restores via
`OCL.C` later — the *exact* mechanism already chosen for the scheduler save-area, now with a real,
dedicated fast destination instead of ordinary `.data`.

**Connects to and closes a related gap**: `runtime/veda_sched_asm.S`'s own `save_area_0`/`save_area_1`
are currently placed in plain `.section .data` — confirmed this session, no tier distinction exists in
the committed RTL at all today. Once this design's own latency model is added to the committed core (§4
below), those save areas would silently regress under realistic memory timing unless explicitly
relocated into the new TCM region. **This design's own implementation must move `save_area_0`/
`save_area_1` into the new TCM region as part of the same change**, not as a separate, later fix — the
scheduler already relies on this being fast, it just never had a real latency model to be wrong against
before.

## 3. Mechanism B (secondary, for genuinely first-touch objects): real ODT TCM-tiering

**What it covers that Mechanism A cannot**: `OCS.C`/`OCL.C` spill/restore only helps an object that was
*already* bound at least once — there is nothing to restore for a genuinely first-ever `Bind` of an
object. For a small, known set of "critical" objects that are bound for the first time in a hot path
(the globals capability table from Toolchain Milestone 13 is a real, concrete example), the ODT lookup
itself needs to be fast, not just the *second* access onward.

**Mechanism**: extend the ODT with a small number of TCM-resident entries, exactly as
`DRAM_TCM_LATENCY_STUDY.md` already prototyped (`TCM_ENTRIES`, `Object_ID < TCM_ENTRIES` routes to a
1-cycle path; everything else pays the new, real `DRAM_EXTRA_CYCLES` latency) — but this time built into
the real, committed core, and with the placement policy made an explicit, software/compile-time-declared
choice (a specific, low, reserved `Object_ID` range dedicated to TCM-tier objects, chosen at
`ODT-Populate` time — **never** automatically promoted based on observed access frequency, which would
reintroduce exactly the secret-correlated-placement channel §1 identifies as the real risk). Real sizing:
the current ODT entry is 16 bytes (`ODT_ENTRY_BYTES`, confirmed `rtl/veda_core.tlv`), 256 entries total
(4KB) — a TCM tier of even 16-32 entries is 256-512 bytes of dedicated SRAM, comfortably inside real
Cortex-M/R TCM budgets (typically 4KB-64KB) cited elsewhere in this project's own prior research.

## 4. Staged build plan

1. **Bring a real DRAM-latency model into the committed `veda_core.tlv` for the first time.** This is a
   genuine prerequisite, not scaffolding — today the committed core has zero latency modeling at all, so
   there is nothing yet to eliminate overhead *against*. Reuses the already-validated stall idiom from
   `DRAM_TCM_LATENCY_STUDY.md`'s own scratchpad prototype (force `$instr` to NOP for the wait cycles,
   Milestone 14's own established pattern) and the regression-safety discipline already proven there
   (byte-identical results at `DRAM_EXTRA_CYCLES=0`, full ACT4 re-run).
2. **Add the real, per-hart-private TCM region + a real ODT TCM-tier** (Mechanism B), sized per §3,
   routing on a static `Object_ID` range check.
3. **Extend `OCS.C`/`OCL.C` spill/restore into a real, reusable convention** (Mechanism A) targeting the
   new TCM region, and relocate `save_area_0`/`save_area_1` into it in the same change.
4. **Compose the two previously-separate real numbers this project already has** — `CAPABILITY_REGISTER_PRESSURE_STUDY.md`'s
   own k=8/16/17/32 miss-rate data and `DRAM_TCM_LATENCY_STUDY.md`'s own `E×N` formula were run
   independently on the same no-latency RTL and were never multiplied together (already flagged as the
   single most valuable next step in this project's own prior addendum). Re-run the same k-sweep against
   the new, real latency-modeled core, with and without the new TCM fast path, to get the real, composed,
   honest before/after number.
5. **Verification**: positive/negative tests, mutation-tested (this project's own standing discipline),
   full Sail self-check + RTL smoke + ACT4 regression, zero-regression bar matching every prior milestone.

## 5. What this does not claim

Matching §1's own honest scope limit: this closes the ODT/capability-lookup memory-timing channel
specifically, for a per-hart-private TCM, with statically-declared (never runtime-adaptive) placement.
It does not claim blanket side-channel immunity for Veda-Core as a whole, and it explicitly names its own
real, forward-looking constraint: if Veda-Core ever becomes a real multi-hart design, this TCM mechanism
must be revisited (per-hart-private banks, or a real static time-partitioned arbiter) before the security
property can still be trusted.
