# Veda-Core Scaling Barriers — Rigorous Research Pass

**Date:** 2026-07-22

## Why this document exists

During architectural discussion of whether Veda-Core's address-less,
cache-less, object-based design could be extended — incrementally, not by
redesign — toward enterprise/cloud/AI-class workloads, a list of technical
shortfalls was raised as the reason this design does not presently compete
on throughput. Rather than accept that list on the strength of prior
reasoning alone, every item (plus additional barriers not on the original
list) was re-examined against real, primary-source evidence: published
papers read in full, official specifications read in full, and one
first-party retrospective read in full — not excerpts, not summaries, and
not this project's own earlier confident-sounding claims. Two of those
earlier claims turned out to be wrong and are corrected here rather than
quietly dropped.

This is a research/analysis record, not an ISA specification — it does not
change any encoding in `VEDA_CORE_SPEC.md`, with one exception (the
`Object_ID` bit-budget arithmetic in §3, which is a real, actionable,
not-yet-applied proposal). Where a finding is a genuine open problem with no
real resolution, it is recorded as such rather than talked around.

---

## 1. Correction: IBM i / PowerVM does not prove address-less designs replace virtual memory for multi-tenancy

**Earlier claim (wrong):** IBM i's single-level-store, tagged-pointer object
model was cited as live, real-world evidence that an address-less design
can handle enterprise multi-tenant isolation without conventional virtual
memory.

**Real finding:** Verified directly against the primary source — IBM
Redbook SG24-7940-05, *"IBM PowerVM Virtualization Introduction and
Configuration,"* Section 1.3, "The POWER Hypervisor" (pp.15-16). Real,
production multi-tenant (LPAR) isolation on IBM i is performed by the POWER
Hypervisor, a firmware layer with its own hardware-managed radix-tree page
tables, sitting *underneath* and *entirely separate from* IBM i's own
object/tagged-pointer mechanism:

> "The POWER Hypervisor provides the ability to divide physical system
> resources into isolated logical partitions... Enforces partition
> integrity by providing a security layer between logical partitions...
> Provides an abstraction layer between the physical hardware resources and
> the logical partitions."

IBM i's own tagged-pointer model only protects processes *within* one
partition; it plays no role in the actual multi-tenant boundary. Separately,
IBM i user code is always OS-compiled/translated (TIMI/SLIC), never raw
native code — a software trust-boundary component with no equivalent in
Veda-Core's pure-hardware-tag model. **Conclusion: this precedent does not
transfer.** It is not evidence against address-less design generally, but
it cannot be cited as proof multi-tenant isolation "already works" this way
in a shipping system.

---

## 2. Correction: CHERI-Tooba's real area cost is substantial, not a solved problem

**Earlier claim (wrong):** CHERI-Tooba was cited as proof that per-access
capability checking isn't disqualifying for competitive hardware, without
checking its real reported numbers.

**Real finding:** Read in full — Rugg, Woodruff, Joannou, Moore (Cambridge),
*"A Suite of Processors to Explore CHERI-RISC-V Microarchitecture."* Real
numbers: CoreMarks/MHz for the superscalar Toooba core went from 4.6
(baseline) to 5.0 (CHERI) — favorable, though the paper itself calls this a
non-fundamental optimization artifact, not a general result. Fmax dropped
43.8MHz → 38.7MHz (-12%). Critically: **area overhead was 47% LUTs / 26%
FFs for the core.** The paper's own Hypothesis H.3 ("CHERI overhead shrinks
with core complexity") is explicitly rejected by their own data — the much
larger Toooba core showed a similar fractional overhead to the smaller
Flute core, not a smaller one. **Conclusion:** performance can be preserved
or even improved, but the area cost is real, substantial, and does not
shrink with scale the way it would need to for the "grows into it" argument
to be free. A real, quantified cost with real economic consequences (die
size, power, yield, $/chip), not a solved problem.

---

## 3. `Object_ID` bit-budget arithmetic — a real, actionable, not-yet-applied path to widening it

Current capability layout (per `VEDA_CORE_SPEC.md` §2):
`Object_ID(16) + Base(32) + Length(16) + Offset(16) + Perms(16) + otype(16)
+ Reserved(15) = 127, +1 pad = 128`. The 15-bit `Reserved` field is
currently used in full by Milestone V-A's generation counter — the simplest
choice for a first model, not a considered one.

Real precedent: CHERI-D (Wang, Woodruff, Mazzinghi, Rugg, Stark, Joannou,
Watson, Moore; Cambridge; arXiv 2606.19055) uses **8 bits** for exactly this
kind of per-allocation reuse/generation counter, in a real, hardware-
prototyped design. Applying that precedent: right-sizing `generation` from
15→8 bits frees **7 bits**, enough to widen `Object_ID` from 16→23 bits
(8.4M concurrently-live objects — two orders of magnitude over the current
65,536 cap), with no other structural change to the capability layout.

**Honest limit:** genuinely hyperscale-relative object counts (tens of
millions+) would require actual CHERI-Concentrate-style compressed
encoding of `Base`/`Length` (a real, proven technique — see the CapMem
format in the CHERI-Tooba paper's Figure 2), which is a separate, larger
design task, not asserted here as free. **Not yet applied to the spec or
Sail model — a proposal, pending the next spec-editing pass.**

---

## 4. MSA / Atomic serialization under multi-core contention — two real, divergent precedents

Read in full: **LazyPIM** (Boroumand et al., real published PIM-host
coherence mechanism) and the **UPMEM PIM system** (Gómez-Luna et al. 2022,
the only publicly available real-world, commercially-shipping PIM
hardware — not simulated).

**Precedent A — UPMEM's real answer: architect the contention away rather
than solve it generally.** UPMEM's real DPUs have *no direct inter-DPU
communication channel at all*: *"workloads that require inter-DPU
communication do not scale well, since there is no direct communication
channel among DPUs."* Their own official Programming Recommendation #2:
*"split the workload into independent data blocks, which the DPUs operate
on independently."* Real result: for the 13/16 benchmarks not needing
cross-DPU sync, the real hardware beats a modern CPU by 93.0x average;
workloads needing cross-DPU sync pay a documented, large penalty routed
through the host CPU. **This maps directly onto Veda-Core's own
Object-Bind**, which already gives explicit, software-visible ownership —
treating binding as exclusive-by-default (sharing as the deliberate, rare,
explicit path) is a real, low-risk, already-half-built answer, requiring no
new hardware.

**Precedent B — LazyPIM's real answer for when sharing genuinely is
needed:** speculative execution + 2Kbit Bloom-filter compressed coherence
signatures per core + rollback-on-conflict, measured within **9.8% of a
zero-overhead ideal**, at **512B/core** real storage cost (16-core system).
Credible, quantified, but requires genuinely new microarchitecture
(checkpoint/rollback) not yet in the spec — flagged as real future work, not
"just an implementation detail."

**Real, documented warning against the naive fix:** LazyPIM's own
measurements show a single coarse-grained lock blocks **87.9%** of
processor-core memory accesses in one real workload and performs *worse
than no-PIM-at-all* — a direct, first-party warning against a single global
ODT/Object-Bind lock as the "easy" answer.

---

## 5. Capability-checked vector/SIMD access — real precedent from CHERI's own official spec

Read in full: the official **RISC-V Specification for CHERI Extensions**
(v9.0.0, 2024-10-04 draft), Chapter 9, "Integrating Zcheripurecap and
Zcherihybrid with the Vector Extension."

Real design: vector *data* registers stay plain integer/float, never
capability-typed. The bounds check happens **once per instruction against a
single scalar authority capability** (the address operand), exactly like an
ordinary scalar load/store — not per-element hardware. Masked/inactive
elements are exempt entirely; fault-only-first loads degrade `vl`
gracefully. This means **unit-stride vector access integrates cheaply**
with a capability model, needing no new checking hardware beyond what
`OCL.D`/`OCS.D` already implement — real evidence this shortfall is less
severe than assumed for the common case.

**Real, honest open problem, unsolved even by CHERI itself:** for indexed
(gather/scatter) loads, the spec flags its own unresolved tension —
*"Indexed loads in Capability Pointer Mode check the bounds of every access
against the authority capability in cs1... the approach of having a zero
base register and treating every element as an absolute address may not
work well in this mode."* The spec adds: *"Not all RISC-V extensions have
been checked against CHERI."* Gather/scatter under one capability's bounds
is a genuinely open, industry-wide problem, not a Veda-Core-specific gap.

---

## 6. CHERI-D's inline-ID technique — conceptually applicable, mechanistically does not transfer as-is

Two separate questions:

**Does the *concept* transfer?** Yes — CHERI-D's per-allocation ID and
Veda-Core's ODT `generation` field serve the identical purpose: detecting
staleness after reuse/rebind.

**Does the *mechanism* transfer?** No. CHERI-D's "truly free" ID lookup is
predicated on a cache hierarchy: the ID is free only because it rides along
on the cache-line fetch the data access needs anyway. Veda-Core's Milestone
V-A model deliberately has no cache layer (`read_ram`/`write_ram` only) —
the mechanism CHERI-D exploits doesn't exist here. **Good news:** Veda-Core's
existing design already achieves the same goal a different way —
`generation` already lives in the same `odt_entry` as `Base`/`Length`/
`Offset`/`Perms`, so one ODT lookup returns everything. This validates an
already-made design choice rather than exposing a gap.

**Honest open item:** CHERI-D's real 8-bit choice was empirically derived
from real C/C++ allocator reuse-frequency traces — a workload context
Veda-Core has no equivalent of, since no software stack or allocator exists
yet for its novel object model. Using 8 bits (§3 above) is a reasonable
cross-check starting point, not a proven-correct number for Veda-Core's
eventual real workloads.

**Cross-link to §4:** because Veda-Core has no cache to piggyback coherence
on, keeping the ODT's `generation` field consistent across concurrent cores
is exactly the shared-mutable-state contention problem examined in §4 —
reinforcing exclusive-by-default Object-Bind as the right lever.

---

## 7. Software/compiler/OS ecosystem cost — real, dated, quantified precedent from CHERI's own decade-plus effort

Read in full: Brooks Davis (CheriBSD lead), *"A Dozen Years of CheriBSD,"*
FreeBSD Journal, May/June 2023 — a first-party retrospective, not a
marketing summary.

Real timeline: CHERI project started October 2010. First CheriBSD boot May
2012 (~19 months). Pure-capability userland (CheriABI) working September
2015 (~5 years). Porting the *already-proven* capability model to RISC-V
started merging January 2016, didn't reach CheriBSD-on-RISC-V until August
2020 (~4.5 more years, retargeting an existing design to a new base ISA).
As of the 2023 article — 13 years in — a CheriABI port of Chromium was
still "in progress."

Real scale: 1,800+ FreeBSD commits, over 1.5% of all non-contrib FreeBSD
commits since 2011, from over a dozen committers, several full-time,
funded across three DARPA programs plus a £190m UK government program.
10,000+ packages eventually ported, but only via a full LLVM/Clang fork and
a full OS fork sustained for over a decade.

**The single most concrete, transferable finding**, in the authors' own
words — they call it *"fortuitous"* that they chose FreeBSD over Linux,
because *"extensive use of `long` in the Linux kernel for both integers and
pointers... cause[s] capabilities to be invalidated... the use of `long` is
a major stumbling block."* A single, narrow, unrelated integer-width
convention independently gated an entire OS port for years — and CHERI's
model is still address-based, explicitly designed as a drop-in C pointer
replacement. **Veda-Core's model is address-less and object-based, a
strictly larger departure from the C pointer model than CHERI's own.**
Calibrating off CHERI's real decade-plus, multi-million-pound effort — for
a *less* radical change — is an honest floor on this shortfall's real cost,
not a vague worry.

---

## 8. Formal-verification scalability — real, current limitations, and a self-correction along the way

While researching this item, a WebFetch summary of a paper ("Modular SAIL:
dream or reality?," Kourzanov & Anmol, imec, RISC-V Summit Europe, May
2025) made claims about the paper's content that turned out to be
inaccurate on direct reading of the primary source — caught and corrected
before being recorded here, consistent with this project's standing
practice of not trusting summarized secondary readings of primary sources.

**Real finding from the actual paper:** the standard, unmodified
`sail-riscv` toolchain — the same one Milestone V-A was built on — produces
*"a single whole-program-processed emulator"*: adding or changing any
extension requires a full model rebuild, with no incremental or dynamic
module compilation. This was hit directly and repeatedly during Milestone
V-A's own debug cycles; the paper confirms it as a known, general,
currently-unsolved limitation of the wider ecosystem (their own proposed
fix is explicitly "first steps," not production-ready), not a Veda-Core-
specific inefficiency.

**Real, quantified calibration point on what "formal verification" costs at
maturity:** the real `sail-cheri-riscv` repository's own language
breakdown (checked directly against the repository) is **51.3% Isabelle,
45.9% Rocq/Coq, and only 2.6% Sail**. For the most mature real capability-
ISA formal effort in existence, the *executable* Sail model — which is all
Milestone V-A has built — is a small fraction of the total verification
investment. The overwhelming majority of real engineering effort goes into
interactive theorem-proving of actual security properties, a phase
Veda-Core's own formal-verification work has not yet started. This is an
honest, unscoped gap, not a solved problem: Milestone V-A's "PASS" is a
real, meaningful result (§ `MILESTONE_V-A_RESULTS.md`), but it is a small
fraction of what "formally verified" means at the maturity level of the
project it is being compared against.

---

## Synthesis

Two earlier claims made in this project were wrong and are corrected above
(§1, §2) rather than left standing. Of the remaining six items, three have
real, precedented, actionable answers requiring no new invention
(§3 Object_ID widening, §4 exclusive-by-default Object-Bind, §6 generation-
in-ODT-entry validation); one has a real answer for the common case with an
honestly-flagged, industry-wide-unsolved edge case (§5 vector/gather-
scatter); and two are real, substantial, currently-unscoped costs with no
shortcut found — a decade-plus, well-funded ecosystem-porting effort (§7)
and a formal-verification maturity gap where the executable model is a
small fraction of what real verification rigor eventually requires (§8).

None of this changes the project's direction. It replaces confident
assertion with cited, verified grounding — including where that grounding
contradicts what was claimed earlier in this same project.
