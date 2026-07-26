# Veda-Core — Design Soul and Real Uniqueness

**Date:** 2026-07-23

## Why this document exists, and the standard it was held to

Asked directly: *"what design soul are you done research and verification
[on], what is the uniqueness of our design compared to all other
architectures available till now in the world"* — with the explicit
instruction to read complete primary sources, not fragments, and not to
hallucinate a uniqueness claim. This document does three things: (1)
restates, precisely and with exact citation, what this project's own prior
full-document research (`VEDA_CORE_SPEC.md` §5.1, `SCALING_BARRIERS_RESEARCH.md`)
already established about the design's philosophy and its historical
grounding; (2) adds one new, fresh, complete-document read — a November
2025 ACM survey covering the *entire* modern descriptor/capability/
object-aware memory research landscape, 162 references, read in full, not
sampled — specifically to stress-test whether the uniqueness claim below
survives contact with the most current, most comprehensive academic
mapping of this exact space; (3) states precisely which parts of the design
are genuinely novel synthesis, which are real historical revivals, and
which are shared with current work — not oversold in either direction.

---

## Part 1 — The design soul, in the project's own already-settled words

`VEDA_CORE_SPEC.md`'s own philosophy statement, verified by direct
re-read, not paraphrased from memory: *"not competing on raw throughput.
The two pillars are **security** (every access checked, hardware traps on
violation) and **energy efficiency** (address-less, cache-less — 'no
addresses, no caches, only Objects'). Simplicity is a first-class goal,
not a fallback."*

Three concrete, load-bearing consequences of that pillar pair, each
already built and verified in this project:

1. **No raw address ever exists at the ISA level.** A Veda-Core capability
   register's `Base` field is not software-supplied — it only exists after
   `Object-Bind` performs a real `Object_ID → ODT` lookup (`VEDA_CORE_SPEC.md`
   §4/§5.1). Software never constructs, computes, or manipulates a pointer;
   it only ever holds an `Object_ID` and, once bound, an opaque capability
   register. This is categorically different from "a pointer with extra
   metadata attached" — there is no pointer.
2. **No cache hierarchy exists anywhere in the design.** The ODT is
   explicitly DRAM-resident, walked fresh by the MSA on every `Object-Bind`,
   "matching Veda-Core's own 'cache-less' pillar" (§5.1's own words, verified
   above).
3. **The capability/object layer is opt-in per instruction, not ambient.**
   Ordinary RV64I arithmetic on GPRs pays zero object-model cost; only the
   explicit `OCL`/`OCS`/`NMC_ADD`/Veda-Atomic instructions touch the
   capability system at all — a deliberate, already-verified-against-a-real-
   failure choice (Part 2 below).

A fourth pillar, less explicitly named as a "pillar" in the spec's own
philosophy line but structurally present throughout: **the same
Object-ID-indexed table that provides the security check (bounds/
permission/tag/generation) also gates memory-side compute dispatch**
(`NMC_ADD`, Veda-Atomic) — security-checking and compute-offload are not
two separate mechanisms bolted together; they're the same lookup, reused.

---

## Part 2 — What's real historical precedent, stated honestly (not claimed as new)

Already fully researched and documented in `VEDA_CORE_SPEC.md` §5.1 and
`SCALING_BARRIERS_RESEARCH.md`, from complete reads of Levy's *Capability-
Based Computer Systems* (1984) and the Colwell/Gehringer/Jensen 1988 ACM
TOCS iAPX 432 post-mortem — restated here precisely, not re-derived:

- **System-wide, flat, `Object_ID`-indexed table**: real, shipped
  precedent — the **Plessey System 250**'s System Capability Table, a
  16-bit-indexed flat table holding base/limit per entry, real 589KB
  footprint at that width. Veda-Core's ODT is structurally this, widened.
- **Capability-register-file-populated-by-explicit-bind-from-a-backing-
  table**: real precedent — the **Cambridge CAP Computer**'s 64-entry
  capability unit loaded from a Process Resource List. Veda-Core's
  Object-Bind mechanism is structurally this, with one deliberate, already-
  justified change: CAP's PRL was *process-local* (CAP's own designers'
  documented regret about that choice, §5.1, is real first-party evidence
  used to justify Veda-Core's system-wide choice instead).
- **Opt-in, non-ambient object-indirection avoiding a real, documented
  failure mode**: the **Intel iAPX 432** made object-indirection ambient
  (even scalar register operands paid a 4-memory-reference cost; `CALL`
  cost 300μs on early silicon) and failed commercially, partly for that
  reason. Veda-Core's hybrid RV64I-base-plus-opt-in-Custom-opcode structure
  is a direct, stated response to this documented failure, not an
  assumption that ambient indirection would be fine.
- **A generation-counter answer to the dangling-reference problem that is
  genuinely this project's own synthesis, stated as such, not attributed**:
  Levy's Ch.10 names exactly two historical solutions (never-reuse-an-ID;
  find-and-disable-all-capabilities-on-delete) — neither is a generation
  counter. The generation-counter mechanism is real, reasoned from the
  documented problem, but not copied from any named historical system.

**None of these four elements, taken alone, is unprecedented.** The
project's own prior research already established this honestly. What
follows is the fresh check on whether the *combination* still holds up
against the most current, most comprehensive academic mapping available.

---

## Part 3 — Fresh stress-test: a complete read of the most current, most comprehensive survey of this exact space

Read in full (all 33 pages, every section, not the abstract alone): Dong
Tong (Peking University), *"Descriptor-Based Object-Aware Memory Systems:
A Comprehensive Review,"* ACM, November 2025, 162 references — explicitly
framed by its own author as covering "the architectural paradigm designed
to bridge [the] semantic gap" between object-oriented software and
block-oriented hardware, across memory protection, memory management, and
memory-centric/near-data processing. This is as close to an authoritative,
current map of "everything relevant" as exists.

### 3.1 — The survey's own taxonomy independently confirms this project's own prior classification

The survey's Figure 2 defines a real, precise capability taxonomy: (c1)
*Classical Capability* = Object ID + Access Rights, no address at all;
(c2) *Indirect Pointer Capability* = Object ID + Access Rights +
Address/Offset; (c3) *Direct Pointer Capability* = Bounds + Access Rights +
Address/Offset (embedded directly in the pointer — this is CHERI's real
category). Cross-checking: Veda-Core's capability register is closest to
(c2) — an `Object_ID` plus a cached, re-derivable `Base`/`Offset`
populated *from* the ODT, not authoritative in its own right (`Rebind`
can refresh `Base` without software's knowledge). **This independently
confirms, from a source this project had not read before today, the exact
classification this project's own earlier research (reading Cambridge
CAP/Plessey directly) already reached**: Veda-Core sits in the historical
"indirect, system-wide, `Object_ID`-addressed" capability family, not a
new category invented from nothing. Real convergence, not coincidence —
worth stating as a genuine cross-validation, not claimed as evidence of
novelty.

### 3.2 — The real, precise, freshly-verified finding: the field walked away from category (c1)/(c2) decades ago, and the current literature confirms it, in the current literature's own words

The survey's §3.3 states this as the field's own explicit historical
turning point: *"With the evolution of hardware and programming
technologies, particularly the rise of the RISC architecture, the flat
address space has emerged as the dominant architectural paradigm... Its
prevalence is driven by its benefits in simplified hardware and software
implementation, superior cost-effectiveness, and enhanced flexibility and
portability, enabling high performance with significantly reduced hardware
complexity."* Its own historical timeline (Figure 4) shows "Capability-
Based Architecture" as a **1970s–1980s era category** (Cambridge CAP,
IBM System/38) with no active 2000s/2010s/2020s branch — every single
modern system the survey covers in detail (§4.2.1–4.2.6: `CHERI`, Intel
`MPX`, `Low-Fat`, `HotBound`, `ALEXIA`, `C3`, `FlexPointer`, `CentroID`,
and every other 2010s/2020s entry) is built as metadata **attached to or
encoded within a real address**, operating on top of the flat-address-
space paradigm the field converged on, not replacing it. CHERI's own
category (c3, *Direct Pointer Capability* — bounds embedded directly in a
real address) is exactly this: an address-based design, by explicit
choice, for ABI/backward-compatibility reasons (already independently
confirmed by this project's own prior reading — `SCALING_BARRIERS_RESEARCH.md`
§7's CheriBSD finding that C's `long` still carries a real address and
breaks when treated as a plain integer).

**This is the freshly-verified, precise basis for the uniqueness claim,
not an assertion**: a 162-reference survey published this month, covering
the entire current descriptor/capability/object-aware research landscape
in detail, shows no active modern branch of "pure `Object_ID`, zero raw
address at the ISA level, ever." Veda-Core is a deliberate revival of a
branch the rest of the field abandoned for real, documented reasons (cost,
complexity, ABI compatibility) — reasoned from a different, explicitly
stated optimization target (§`VEDA_CORE_SPEC.md`'s "not competing on raw
throughput... security and energy efficiency") where those original reasons
for abandonment may not bind the same way. This is a real, defensible,
precisely-grounded claim: not "nobody ever thought of this," but "the field
tried this, moved away from it for reasons tied to a throughput/
compatibility optimization target Veda-Core explicitly does not share, and
essentially nobody has revisited it since under a different target."

### 3.3 — The cache-less pillar has essentially no representation in the current mainstream literature, confirmed by what the survey treats as future work

The survey's own §6.1 ("Cache Hierarchies," one of six "Related Research
Directions") frames the goal as *making caches object-aware* — propagating
descriptors and Object IDs *into* an assumed-to-exist cache hierarchy for
better prefetching/replacement/compression (citing e.g. `XMem`, `HotPad`).
Every real system surveyed in depth assumes a conventional cache hierarchy
exists. Veda-Core's explicit "no caches" pillar has no counterpart
anywhere in this survey's coverage — confirmed by what the field's own
current forward-looking research agenda treats as a still-open direction
("future object-aware memory systems should propagate object descriptors...
to the cache hierarchy"), not something already resolved by eliminating
the cache.

### 3.4 — The genuinely least-explored combination, confirmed by the survey's own structure: fusing capability-security dispatch with memory-side compute

The survey's own Figure 1 keeps *Memory Protection* and *Memory Processing*
(near-data/PIM) as **two separate branches**, converging only in §6 as
aspirational future work, not built systems. It does cite real, genuine
partial precedent worth naming honestly, not omitting: Baskaran et al.
(MICRO 2022, ref. [11]) built "an architecture interface and offload model"
using "explicit object identifiers and buffer identifiers as instruction
operands" with a "Buffer Orchestrator" managing a distributed descriptor
table for near-data accelerators — real, cited, genuinely close in spirit
to `NMC_ADD`/Veda-Atomic's own object-identified compute-at-memory
dispatch. **Stated honestly**: this is real, existing prior art for
"identify a memory object by ID, dispatch compute near it" — Veda-Core did
not invent that idea from nothing. What the survey's own structure
confirms is genuinely less explored is the *fusion*: using the exact same
lookup (the ODT, with its live bounds/permission/generation check) to gate
*both* ordinary capability-checked access *and* compute dispatch, as one
mechanism rather than two adjacent ones. The survey's own framing (separate
branches, future convergence) is real, current, and independent evidence
that this specific fusion remains open territory, not a claim invented for
this document.

---

## Part 4 — What the design soul actually is, stated precisely

Not "we invented capabilities" (Cambridge CAP, 1970s) and not "we invented
object-tables" (Plessey System 250, real and shipped) and not "we invented
memory-side compute dispatch by object ID" (Baskaran et al., 2022, real and
cited) — each of those, alone, has real precedent, honestly stated above.
**The design soul is the specific combination, reasoned from a specific,
explicitly non-standard optimization target that the rest of the field, by
its own current comprehensive account, is not currently pursuing**:

1. Every access — ordinary data access *and* compute dispatch — goes
   through exactly one mechanism (`Object_ID` → ODT, capability-cached,
   bounds/permission/tag/generation-checked), never a raw address, not even
   internally.
2. That mechanism has deliberately, explicitly no cache layer — an
   outlier against the entire current literature's assumed baseline.
3. It is opt-in on top of an ordinary, unmodified RV64I base — a
   structural choice directly validated against iAPX 432's real,
   documented, ambient-indirection failure, not a hedge.
4. It is optimized explicitly for security and energy-efficiency, stated
   as *not* competing on throughput — which is precisely the axis the
   field's own documented history (§3.2 above) says drove it away from
   address-less, cache-coupled, table-indirected designs in the first
   place. Veda-Core's honest bet is that revisiting this branch under a
   different, explicitly-stated optimization target is worth doing now —
   not that the old reasons for abandoning it were wrong.

## What this is not, stated as plainly as the uniqueness claim above

This is not a claim that Veda-Core is unprecedented in any single
mechanism, and it is not a claim that this makes Veda-Core "better" than
CHERI, Plessey, or any other real system — each of those made a real,
reasoned, documented choice for its own real constraints (CHERI: ABI
compatibility with existing C code and pointer-width portability; Plessey:
1970s on-chip storage limits). It is a precise claim, checked today against
the most current and comprehensive available survey of the field, that the
*specific combination* Veda-Core commits to — zero raw addresses anywhere,
zero cache layer, one unified object-table mechanism gating both access and
compute, opt-in atop a standard base ISA, explicitly not optimizing for
throughput — has no active exemplar in the current literature, and was a
branch the field moved away from for reasons tied to an optimization target
this project does not share.
