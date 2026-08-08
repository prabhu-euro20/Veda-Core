# CRF Architecture-Alignment Verdict: Should Veda-Core's 16-Entry Separate CRF Be Reconsidered Against Real CHERI-RISC-V?

## 0. Scope and what changed since Milestone 13's point-fix

This document supersedes the register-file-architecture *reasoning* in
`TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md` (rejection of CHERI-merged alignment, lines 37-44
of that doc) with a full architectural review, per direct project-owner instruction that the CRF's
16-entry, GPR-separate design itself — not just the one-register spill/restore conflict — needed to be
checked against the real, standardized CHERI-RISC-V convention before any further point-fixing.

Three independent research tracks (`cheri-merged-rf-mechanics`, `veda-core-founding-rationale`,
`capability-width-compatibility`) were cross-checked against each other and against direct rereads of
`VEDA_CORE_SPEC.md` §2, `TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md`,
`veda_types.sail:19-30`, and `veda_core.tlv:28,1214,1522-1528`. All three tracks agree on the
load-bearing facts; none contradict each other on any cited number. Where they differ is only in
emphasis (founding-rationale focuses on the *absence* of a decision record; mechanics and
width-compatibility focus on the *cost* of each alternative). That agreement is itself informative —
this is not a case where the evidence is ambiguous.

## 1. Was the 16-entry, separate CRF a reasoned departure or an unexamined default?

**Unexamined default. Stated plainly, not softened.**

Direct evidence, read in full, not fragments:

- `VEDA_CORE_SPEC.md:149` — Section 2 opens with "16 registers (`c0`-`c15`)..." as a bare given. Every
  *other* number in that same section carries a cited rationale — `Object_ID` widened to 23 bits with a
  named source (`SCALING_BARRIERS_RESEARCH.md` §3), `Reserved` right-sized to 8 bits against CHERI-D's
  own arXiv paper, `Length`/`Offset` split argued from the 128-bit budget and Plessey System 250
  precedent (`VEDA_CORE_SPEC.md:162`). The register *count* and the *separate-from-GPR* structural
  choice get no equivalent treatment anywhere in the document.
- `SCALING_BARRIERS_RESEARCH.md` — grepped and read in full. Zero hits for "16-entry," "merged
  register," "split register," "CHERI-MIPS." Its actual scope (confirmed by its own section list) is
  `Object_ID` width, MSA/ODT contention, CHERI-D generation-counter width, vector precedent — never CRF
  organization.
- `MILESTONE_V-A/B/C_RESULTS.md` — the three documents that first built the CRF in Sail. V-A states its
  own scope as "16-register Capability Register File" as a target to hit, not a question to resolve.
  Zero comparison to CHERI's real convention in any of the three files.
- `TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md:37-44` is the *first and only* document in the
  entire corpus that names CHERI's real merged convention and Veda-Core's CHERI-MIPS-like split
  lineage explicitly — and it does so eleven milestones after the CRF was fixed at 16 entries,
  reactively, under exhaustion pressure, and rejects merging on proportionality grounds relative to a
  *single*-register conflict, not on the architectural merits.

This is precisely the shape of finding the project's own standing discipline ("verify before deciding,"
"weigh on standards compliance, not sunk cost") exists to catch. The honest conclusion is that 16/separate
was inherited from CHERI-MIPS's shape (or simply chosen as "smaller, seems fine") without the founding
documents ever putting it next to the real, standardized alternative. That the current exhaustion wall
now forces the comparison does not retroactively make the original choice reasoned — it makes it a
default that got lucky for eleven milestones before hitting its limit.

## 2. The verdict on register-file organization: **(c)**, keep 16 entries and keep the CRF separate — with the newly-articulated justification the tracks actually surfaced, not the one the founding docs never wrote.

This is not a re-endorsement of the *unexamined* original choice. It is an independent architectural
conclusion, reached by actually running the comparison the founding docs skipped, using the real
numbers the tracks found. The reasoning:

**The real CHERI merged file (option a) is causally tied to a compression precondition Veda-Core does
not meet — and lack of it makes literal merging a materially larger, differently-shaped hardware
change than the CRF's own current cost.** CHERI's spec is explicit that the switch from CHERI-MIPS's
split file to merged-only was enabled by CHERI Concentrate compressing the architectural capability to
exactly `2×XLEN` (128 bits for RV64) — "With register tags and 128-bit compressed capabilities,
extending existing general-purpose registers to support capabilities became a feasible approach, as
register size doubled rather than quadrupled" (`chap-rationale.tex`, CTSRD-CHERI/cheri-specification,
"Capability Register File" section, per the `cheri-merged-rf-mechanics` track's direct citation).
Veda-Core's own capability is 128 bits **uncompressed** — confirmed directly from
`veda_types.sail`'s struct (`Object_ID`(23)+`Base`(32)+`Length`(16)+`Offset`(16)+`Perms`(16)+`otype`
(16)+`Reserved`(8) = 127, +1 pad = 128, per `VEDA_CORE_SPEC.md:162`) with a full 32-bit `Base` and
16-bit `Length` carried in the clear, not a CHERI-Concentrate-style floating-point relative-bounds
encoding. Folding that into RVA23's own 32-entry, 64-bit GPR file means every GPR — including ones
holding plain integers — becomes ≥128 bits, all the time. That is a full-width doubling-plus of the
base integer register file's storage and every read/write port, project-wide, with no compression to
offset it. It is a strictly larger change than the CRF's current 16-entry cost, not a simplification.

**Widening the CRF to 32 entries while keeping it separate (option b) has no CHERI precedent to invoke,
so it cannot be justified as "aligning with the standard" — and it is not free either.** The
`cheri-merged-rf-mechanics` track confirms directly from the official spec: CHERI-RISC-V was originally
co-specified with *both* merged and split ("This second approach mirrored the approach used on
CHERI-MIPS") register-file options, but "in practice, only variants of CHERI-RISC-V using a 'merged'
register file were implemented in emulators, soft cores, toolchains, and operating systems"
(`chap-cheri-riscv.tex`, "Separate Capability Register File" section). A 32-entry *separate* file is
not a documented, ever-built CHERI variant — it would be a Veda-Core-original point with no standards
weight behind it. Its real cost, confirmed against source: `vcapidx` is a hard `bits(4)` newtype
(`veda_types.sail:24`, verified directly this session) referenced across roughly 18-19 distinct Sail
union-clause instruction forms and ~33 LLVM CRF-touching instructions
(`RISCVInstrInfoXVeda.td:63`, per the `capability-width-compatibility` track); RTL's `/vreg[15:0]`
array (`veda_core.tlv:1214`, verified directly this session) would need every consuming index width
widened from 4 to 5 bits. This is the *same class* of encoding-wide change Milestone 13's own design
doc already ruled out disproportionate for a single extra slot (`TOOLCHAIN_MILESTONE_13_DESIGN.md:
136-138`, cited in the point-fix doc) — scaled to 16 more slots, not one.

**What legitimately makes 16 sufficient, once understood correctly, is Object_ID-indirection changing
what "register pressure" means here.** This is the one place the tracks surface a real, structural,
citable difference rather than just a cost comparison. Real CHERI capability registers must each hold
a complete, self-contained, already-resolved bounds-and-permissions value — there is no cheap way to
"re-derive" one, so a CHERI program needs enough live registers to avoid constant reconstruction, and
CHERI inherits RISC-V's full 32-register ABI/allocator specifically to have that headroom (confirmed:
CHERI capability-register ABI role names — `cra`/`csp`/`cgp`/`ctp`/`ct0-6`/`cs0-11`/`ca0-7` — are the
*same* 32-register pool with a `c` prefix, per the official psABI, `cheri-elf-psabi/riscv.md`, "Capability
Register Convention" table). Veda-Core's `Bind` is architecturally a single ODT-lookup-and-cache, not a
from-scratch bounds computation (`VEDA_CORE_SPEC.md:229`: "ODT lookup by `Object_ID`; on success...,
populate `rd`'s Tag/Base/Length/Perms/otype fields from the ODT entry"). Re-deriving a Veda-Core
capability is cheap; re-deriving a CHERI capability from a raw pointer is not (CHERI capabilities carry
no indirection to re-resolve from). CRF pressure in Veda-Core is therefore a "how many live object-handles
am I juggling right now" question, not a "how many raw pointers am I threading through this function"
question — a different, generally smaller, kind of pressure than what CHERI's 32-per-GPR convention was
sized to solve. This is a real architectural distinction, grounded in the spec's own text, not
after-the-fact rationalization — but it is being written down for the first time *now*, in this
document, not retroactively credited to the founding docs (see §1: they never made this argument).

**The actual, evidenced root cause of the current exhaustion is a software convention, not a hardware
capacity shortfall — and it is the opposite of real CHERI-derived practice.**
`TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md:8-14` shows the wall is created by treating several
CRF registers (`C4`/`C5`, `C6`-`C9`, `C13`) as *permanently* bound for the program's life or
switch-surviving, never spilled — not by there being too few physical registers for the live working
set at any one instant. The same document already cites the real, official counter-precedent: CHERIoT's
switcher "spills the ENTIRE live capability-register set to a per-thread trusted-stack register-save
area... rather than reserving any register as a permanently-live, switch-surviving binding"
(CHERIoT-Platform/cheriot-rtos, `docs/architecture.md`). Real CHERI-derived practice treats every live
capability register as spillable; Veda-Core's own scheduler currently does the opposite for several
registers. That is the actual defect, and it is a convention bug, independent of register count.

## 3. Why each rejected option was rejected — specific, cited, not "seems like a lot of work"

**(a) Literal CHERI merge (fold capability metadata into all 32 GPRs) — rejected.**
Requires collapsing three independently-built, independently-verified subsystems into the GPR datapath:
Sail's `cr0`-`cr15` (`veda_regs.sail:9-24`, structurally separate from `core/regs.sail`'s base `X`
vector), RTL's `/vreg[15:0]` array (`veda_core.tlv:1214`, structurally separate from `/xreg[1..31]` at
line 26), and LLVM's `CRF` register class (`RISCVRegisterInfoXVeda.td:28-63`, explicitly commented as "a
genuinely disjoint register file, unrelated to GPR/FPR/vector registers"). Every one of the 53 Sail
self-check tests, 41 RTL smoke tests, and 51 ACT4 conformance tests currently passing
(`MILESTONE_C_RESULTS.md:125,128`; `rtl/MILESTONE_C_RESULTS.md:72`) touches the GPR path in some form and
would need re-verification, not extension. It also reintroduces exactly the ambient-cost failure mode
Veda-Core's own research already flags as a documented historical dead end — Intel iAPX 432's
ambient-object-indirection cost on every ordinary operation (`SCALING_BARRIERS_RESEARCH.md` §5.1, per
the `capability-width-compatibility` track) — which the opt-in Custom-0/1/2 opcode design was built
specifically to avoid paying on every RV64I instruction. And per §2 above, it is not even a
compression-compatible move given Veda-Core's uncompressed 128-bit format: it would double-plus the
entire base GPR file's width with no CHERI-Concentrate-style offset. This is a larger, more diffuse
change than the CRF-exhaustion problem it would ostensibly fix.

**(b) 32-entry, still-separate CRF — rejected.**
Not standards-compliant in any citable sense (no ever-built CHERI precedent for "wide but separate," per
§2), and its real cost — 4→5 bit `vcapidx` widening touching ~18-19 Sail instruction forms and ~33 LLVM
CRF-consuming instructions, plus RTL's `/vreg` index width — is the same *class* of encoding-wide sweep
Milestone 13's own design doc already assessed as disproportionate for one extra slot
(`TOOLCHAIN_MILESTONE_13_DESIGN.md:136-138`). Scaling that assessment to sixteen additional slots does
not make it more proportionate; it makes it a larger version of an already-rejected-scale change,
undertaken to solve a problem (§2, "root cause") that is not actually a register-count problem.

**(d), other options** — none of the three tracks surfaced a fourth real architectural option beyond
(a)/(b)/(c) that wasn't already covered in Milestone 13's own decision doc (the 4th-SCR "GDC" idea,
rejected there on per-access-cost/privilege-gate grounds, `TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md:46-55`,
not revisited here since this review's scope was specifically the register-file organization question).

## 4. Effect on the prior point-fix decision: **(i) — still valid as the interim/tactical fix, now on firmer ground, not superseded.**

The scheduler save-area extension (spill/restore the table-base capability, per
`TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md`'s chosen mechanism) is not merely *unaffected* by
this review — this review's §2/§3 findings make it the *architecturally correct* fix, not just the
cheapest one. §2's root-cause finding is that the exhaustion wall is caused by permanently-bound
registers that were never made spillable, which is exactly the defect the save-area extension corrects,
and it does so by adopting the real, cited CHERI-derived practice (CHERIoT: spill everything, exempt
nothing) rather than by working around the symptom. Register-file organization (16 vs 32 vs merged) is
orthogonal to this fix and does not gate it. The point-fix should proceed exactly as already scoped
(four new instructions in `runtime/veda_sched_asm.S`, symmetric with the existing PC/base/length spill
pattern) once its own stated trigger is met (a real test needing both globals-protection and the
scheduler together, or Milestone 13's own register-choice grep-audit finalized) — this review adds no
new blocking dependency and finds no defect in that decision's own reasoning. What this review *does*
retract is the *quality* of the one-line architectural dismissal at
`TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md:37-44` — it reached the right conclusion (don't widen
the CRF) but for an incomplete reason (only proportionality-to-one-register), not the fuller,
now-established reason (§2: no compression precondition for merge, no precedent for separate-32, and a
real architectural reason 16 is adequate once indirection-based pressure is understood).

## 5. Should any architecture change be built, and when?

No architecture change is recommended by this verdict — see §2/§3. Options (a) and (b) are both
rejected, not deferred; there is no "build later" milestone to schedule for either, because neither is
the right target, not merely an early one. This resolves the tension the task named between "don't build
ahead of a real need" and "prioritize standards compliance over sunk cost": there is no real tension to
resolve here, because the standards-compliance analysis itself (§2) concludes the standard's own
precondition (Concentrate-style compression) doesn't transfer, so "compliance" does not actually point
toward (a) or (b) in the first place. Sunk-cost avoidance was never invoked to reach this conclusion —
the same analysis would apply to a CRF built yesterday with zero existing consumers.

One real, concrete follow-up action *is* justified by §1's finding, independent of the register-file
verdict: `VEDA_CORE_SPEC.md` §2 should be edited to state the architectural reason for 16/separate
explicitly (the indirection-pressure argument in §2 of this document), so the next engineer who reaches
this question does not find another unexamined default. This is a documentation fix, not a hardware
milestone — proportionate to what was actually found wrong (a missing rationale, not a wrong number).

## 6. Open risks, stated honestly

- The indirection-pressure argument in §2 (Bind-as-cheap-lookup making 16 registers architecturally
  sufficient) is a real, source-grounded structural argument, but it is **not backed by a quantitative
  study**. No document in the corpus measures actual live-register counts for representative Veda-Core
  workloads against CHERI's own typical register pressure under matched programs. The `capability-width-compatibility`
  track flags this directly: the project's own k=8/16/17/32 pressure experiment (task #93) measured
  Veda-Core's own scaling behavior in isolation, not a CHERI-vs-Veda-Core comparative study. If a future
  workload shape turns out to need materially more simultaneously-live object-handles than the current
  corpus exercises, this verdict's §2 conclusion should be revisited against real data, not just the
  structural argument.
- Arm Morello's register-file organization was not independently verified from a primary Arm source in
  any track — the "merged everywhere" claim for Morello rests on the CHERI spec's own characterization
  ("a model similar to CHERI-RISC-V and Morello"), not a direct read of Morello's own architecture
  reference manual. This does not change the verdict (CHERI-RISC-V's own primary-source evidence is
  sufficient on its own) but should not be cited as independently confirmed.
- The exact sub-field bit arithmetic of CHERI Concentrate's 128-bit format was not independently
  re-derived from the full Concentrate paper (only from the spec's own summary sentence) — the causal
  claim that compression enabled merging is solid (directly quoted from the spec's rationale chapter),
  but the precise bit-diagram was not independently checked field-by-field.
- This review did not audit whether RTL's `/vreg` array or Sail's `cr0`-`cr15` declarations have any
  further hidden 16-entry-specific assumptions beyond the declaration sites themselves (decode mux
  sizing, ODT-index-width coupling) that would affect a future option-(b)-style change if one were ever
  triggered by new evidence under the risk above.

---

## Addendum (2026-08-08): "Object-Bind is cheap" correction, rigorously re-verified

The project owner directly challenged §2's own claim — *"Object-Bind is architecturally a cheap
ODT-lookup-and-cache operation"* — used above to justify why 16 CRF registers are architecturally
sufficient: *"that object-bind operation on every new object is not going to be the overhead or
performance bottleneck"* was flagged as an assertion needing real verification, not an accepted fact.
It was right to flag it. A full re-investigation — re-reading Veda-Core's own existing empirical studies
in full, then researching real CHERI's own equivalent cost from primary sources — found the original
claim **correct as a mechanism description, overstated as a performance claim**.

### The correction

Veda-Core's own real, prior empirical work already contains the answer, not previously connected
together: `OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`'s "Object-Bind is free" result (fixed +10-cycle
one-time cost, zero marginal per-access cost) was measured on a `veda_core.tlv` with **no DRAM latency
modeled at all** — confirmed directly in that document's own text, not a new finding. Once
`DRAM_TCM_LATENCY_STUDY.md` added a real, DDR4-grounded latency term `E` per DRAM-tier ODT access, the
honest cost of a **repeated-rebind** pattern (the actual shape of register-pressure-driven Bind churn,
not the bind-once-reuse-many pattern the original benchmark tested) is:

```
dram_cycles = 11 + (7 + E) × N
```

— growing **linearly** with `N`, the number of rebinds. This is not free, and `DESIGN_SOUL_AND_UNIQUENESS.md`
confirms the ODT is **deliberately, permanently DRAM-resident with no cache layer anywhere** — "no
addresses, no caches, only Objects" is a stated design pillar, not an oversight — so there is no
free cache-hit ride absent the not-yet-built TCM tiering (`DRAM_TCM_LATENCY_STUDY.md`'s own real,
unstarted follow-on). §2's own sentence above should be read with this correction: the *mechanism* (an
ODT lookup, not a from-scratch computation) is genuinely cheap in instruction-count terms in every case;
the *cycle cost* is genuinely near-free only for the bind-once-reuse-many pattern, and genuinely,
linearly non-free for a sustained rebind pattern — the exact scenario CRF register pressure produces.

### The CHERI-side comparison, now verified from primary sources (previously absent)

Two real, separate findings, both directly relevant and neither favoring an easy answer:

**1. Real CHERI's own literature never isolates a register-pressure/spill cost as a measured, named
overhead source.** The most rigorous real (FPGA, not simulated) CHERI performance study available —
CTSRD-CHERI's "Early Performance Results from the Prototype Morello Microarchitecture" — decomposes its
entire pure-capability overhead (30.48% down to 2.2–3.2% after fixes) into four named causes:
unpredicted PCC-bounds checks on capability jumps, a data-dependent exception check, store-queue sizing,
and the essential memory-footprint cost of 128-bit pointers. Capability-register spill/reload is not
named anywhere in that breakdown, nor in the ISCA 2014 CHERI-MIPS paper, nor in CHERI Concentrate (TC
2019). The CHERI FAQ's own answer to "why 32 registers" is MIPS-ISA congruence, not a performance
figure. This absence is suggestive, not proof of near-zero cost — but a report thorough enough to isolate
effects down to fractions of a percent, and never lists register-pressure spill/reload, is real evidence.

**2. The reason it was never isolated: real CHERI's capability spill/reload traffic (CSC/CLC) — data
*and* its tag bit — rides the ordinary cache hierarchy by CHERI's own explicit, documented design
choice.** Confirmed directly from the current canonical CHERI ISA specification
(`chap-microarchitecture.tex`, "Tagged Memory"/"Tag Controller with Cache") and the CHERI-authored
"Efficient Tagged Memory" paper (ICCD 2017): CHERI adopted a **"merged-cache hierarchy"** — capability
data and its tag are cached together in ordinary L1/D$/L2, exactly like any other memory access ("tags...
are maintained with cache lines, and obey normal cache-coherency rules" — CHERI FAQ, "Why tagged
memory?"). Only a genuine miss through the *entire* cache hierarchy falls through to a dedicated
tag-table cache "next to the DRAM controller," functionally equivalent to an ordinary DRAM tier, not a
bypass path. **This means real CHERI's own register-pressure cost, in a real deployment, is very
plausibly cache-hit-cheap (1–4 cycles) for the common case — while Veda-Core's own Object-Bind cost, on
its own deliberately cache-less ODT, pays near-full DRAM-tier latency by design.** This is a real,
honest, structural disadvantage for Veda-Core specifically in the register-pressure-driven-rebind
scenario, and should be stated as one, not argued away.

**3. But CHERI's own authors explicitly, directly admit CHERI does not solve — and real implementations
are documented as actually vulnerable to — the side-channel class this cache dependency opens.** Unlike
temporal safety (where the CHERI FAQ gives a clean "no current plans" out-of-scope statement), CHERI's
side-channel scope is not phrased as a clean disclaimer — it is a direct, repeated admission. The
canonical CHERI ISA specification (`chap-model.tex`, "Protection Against Microarchitectural
Side-Channels") states CHERI was designed as an *architectural*, not microarchitectural, security
mechanism, and that "protective effects rely, of course, on appropriate implementation in the
microarchitecture." The dedicated CHERI technical report **UCAM-CL-TR-916**, "CHERI: Notes on the
Meltdown and Spectre Attacks" (Watson, Woodruff, Roe, Moore, Neumann, 2018), states plainly in its own
conclusion: *"Microarchitectural side-channel attacks have long been known... epitomized by
**cache-timing side-channel attacks** on cryptography dating to the early 2000s... As an architectural
security feature, CHERI is dependent on correct and secure implementation in the microarchitecture,
especially with respect to side channels."* Its abstract states directly: *"CHERI remains vulnerable to
side-channel leakage arising from speculative execution across compartment boundaries."* The current
ISA spec's own microarchitecture chapter goes further, naming a real, currently-deployed open-source
CHERI implementation as actually exposed: *"It is believed that all open-source CHERI implementations
may currently forward unsafe values for these instructions, and the Toooba microarchitecture is likely
vulnerable to speculative execution attacks through this vector."*

### The honest, complete verdict

This is a real, two-sided trade-off, verified on both sides, not a win for either architecture
unconditionally:

- **Performance**: for a workload that genuinely exceeds 16 simultaneously-hot objects and must
  repeatedly re-Bind, Veda-Core pays a real, linearly-scaling, DRAM-tier cost by design that real
  CHERI's own cache-backed equivalent very plausibly does not pay in the common case. This is a real,
  admitted structural disadvantage, not a solved problem — the not-yet-built TCM/DRAM ODT-tiering
  mechanism (`DRAM_TCM_LATENCY_STUDY.md`) is the correct, already-designed answer for genuinely "hot,
  critical" objects, and this finding raises the real stakes of building it once a real triggering
  workload exists — it does not yet justify building it ahead of one, per this project's own standing
  discipline.
- **Security**: the cache-less design closes the specific cache-hit/cache-miss timing differential that
  is the root mechanism of cache-timing side-channel attacks against the ODT/capability-lookup path —
  and CHERI's own authors, in CHERI's own official technical report, admit this exact attack class
  (cache-timing side channels, and separately, cross-compartment speculative-execution leakage) is real,
  unsolved by CHERI's architecture alone, and actually present in at least one real, current open-source
  CHERI implementation. This is a real, sourced, legitimate security property — scoped precisely to the
  ODT/capability-lookup path this comparison concerns, not asserted as a blanket "Veda-Core is
  side-channel-immune" claim, which would need its own separate, dedicated verification project-wide.

**The 16-register-sufficiency argument in §2 above should now be read as resting on three legs, not
one**: the mechanism-cheapness argument (still valid, restated precisely above), the absence of any
official CHERI number to be measurably worse than (§2 above, now independently confirmed by primary
source rather than inferred), and — new, and the most defensible framing for any future outward-facing
comparison — a stated, verified security/performance trade-off, not a free performance win. Any future
Veda-Core document citing "Object-Bind is cheap" without this qualification should be corrected to match
this addendum.

## Addendum 2 (2026-08-08): the "real, admitted structural disadvantage" above, closed for realistic
working sets by Milestone 24 (TCM Fast-Path) — real, composed number, not a re-estimate

The addendum above named a concrete, honest gap: Veda-Core pays real, linearly-scaling DRAM-tier
latency on repeated rebinds that real CHERI's cache-backed spill path very plausibly does not pay, and
said the correct, already-designed answer (`DRAM_TCM_LATENCY_STUDY.md`'s own TCM/DRAM ODT-tiering) "does
not yet justify building it ahead of" a real triggering workload. The project owner then supplied exactly
that trigger, asking directly how to eliminate the overhead without giving up the cache-timing-immune
security property the DRAM-latency finding is the price of. Milestone 24 was designed and built in
response (`TCM_FAST_PATH_DESIGN.md`; real, peer-reviewed grounding for the mechanism from GhostRider,
ASPLOS 2015, and a real cross-hart-contention caveat from Wrisley et al., NordSec 2025) and is now real,
committed RTL: a genuine DRAM-latency stall FSM (Stage 1, mutation-tested), a low, fixed Object_ID range
(`TCM_ODT_ENTRIES=32`) that never pays the stall (Stage 2, mutation-tested), and a genuinely separate
TCM capability-spill scratch region for OCL.C/OCS.C (Stage 3, mutation-tested) — 49/49 RTL smoke, 51/51
ACT4, zero regressions throughout.

### Composition methodology: two independently-verified real quantities, not a fresh estimate

Rather than re-running the full k-sweep's own 4-round round-robin RTL simulation under 8 new
configurations (4 k-values × TCM-on/off), the real, already-verified per-`k` **bind-count** data from
`CAPABILITY_REGISTER_PRESSURE_STUDY.md` (a pure function of the round-robin schedule and 16-register
capacity, unaffected by any timing change) was composed with Stage 1/2's own real, mutation-tested
**per-bind cost** model (`DRAM_EXTRA_CYCLES` extra cycles for a DRAM-tier triggering bind, zero for a
TCM-tier one — provably non-overlapping since the stall FSM freezes `$pc` for the stall's own duration,
so back-to-back triggering binds cannot pipeline). This composition was not trusted from the formula
alone: a real, additional RTL spot-check (8 sequential Binds, Object_ID 3-10, against a scratch
`veda_core.tlv` copy — never the committed file — with `DRAM_EXTRA_CYCLES` temporarily set to 10) directly
confirmed both halves before the full table was computed:

- **TCM disabled** (`TCM_ODT_ENTRIES=0`, forcing all 8 binds DRAM-tier): 170 cycles vs. a 90-cycle
  baseline at `DRAM_EXTRA_CYCLES=0` — a **+80-cycle delta, exactly** `8 binds × 10 cycles`.
- **TCM enabled** (`TCM_ODT_ENTRIES=32`, the real shipped value, same 8 binds now TCM-tier since their
  IDs are all `<32`) at the same `DRAM_EXTRA_CYCLES=10`: **90 cycles — identical to the `E=0` baseline**,
  confirming a TCM-tier bind is a true, exact no-op regardless of `E`.

Both halves matching exactly (not approximately) is what licenses composing the two pre-existing,
independently-verified datasets analytically for the remaining points, rather than re-simulating all
eight.

### The real, composed table (`E=10`, the low end of the DDR4-grounded range this project already
established; Object_IDs numbered from 3 upward, i.e. immediately after the two pre-seeded fixtures at
1/2, so a `k`-object working set occupies IDs `3..(k+2)`)

| k | traditional | old veda (no latency model) | **TCM-on, E=10** | **TCM-off, E=10** | DRAM-tier binds (on / off) |
|---|---|---|---|---|---|
| 8  | 129 | 153 | **153** (ratio 1.186, unchanged) | 233 (ratio 1.806) | 0 / 8 |
| 16 | 257 | 305 | **305** (ratio 1.187, unchanged) | 465 (ratio 1.810) | 0 / 16 |
| 17 | 273 | 336 | **336** (ratio 1.231, unchanged) | 566 (ratio 2.073) | 0 / 23 |
| 32 | 513 | 801 | **921** (ratio 1.795) | 2081 (ratio 4.057) | 12 / 128 |

(`k=32`'s 32-object working set, IDs 3..34, has 29 objects `<32` — TCM-tier — and 3 objects `>=32` —
DRAM-tier; at 100% real-bind rate uniform round-robin puts exactly `3/32 × 128 = 12` of the 128 real
binds on the DRAM-tier objects.)

### The honest verdict: closed for the realistic case, honestly partial for the case that was always
going to be partial

For any working set of **up to 17 simultaneously-hot objects** — i.e. everything at or modestly past the
real 16-register CRF capacity, the actual scenario register pressure produces — Milestone 24's TCM tier
makes the new, real DRAM-latency cost **exactly zero**, so long as those objects' `Object_ID`s are
allocated in the low, TCM-eligible range (a real, stated software contract, not automatic — matching the
same static/compile-time-declared placement discipline the design's own security property already
requires). The ratio at these `k` is **identical to the pre-latency-model baseline** — the "real, admitted
structural disadvantage" the prior addendum named is fully closed for this range, not just mitigated.

Past the 32-entry TCM-ODT budget (`k=32` here), the disadvantage **does** partially reappear — 1.795×
vs. the old no-latency 1.561×, a real, honest regression versus the pre-latency baseline — but the TCM
tier still cuts what an undefended core would show (4.057×) by more than half. This is graceful
degradation proportional to how far a working set exceeds the TCM budget, the same qualitative shape
`CAPABILITY_REGISTER_PRESSURE_STUDY.md`'s own original finding described for register aliasing itself —
now shown to hold for the composed DRAM-latency-plus-TCM picture too, not asserted by analogy.

**Net effect on the two-sided trade-off stated in Addendum 1**: the performance leg is no longer an open,
unmitigated disadvantage for realistic working sets — it is closed by a real, mutation-tested mechanism
whose own security property (a fixed, small, statically-declared TCM range, never history-adaptive) was
independently verified against the primary literature *before* being built. The security leg (cache-timing
immunity CHERI's own report admits it lacks) is unchanged and un-traded-away: the TCM tier is still fully
cache-less by the same GhostRider-grounded static-placement argument, so this is a real performance win
purchased with additional verified engineering, not a quiet reversion to a cached, timing-observable path.
