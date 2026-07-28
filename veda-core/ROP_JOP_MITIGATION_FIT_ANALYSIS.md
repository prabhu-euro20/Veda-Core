# Domain 2 Analysis: ROP/JOP Mitigation for High-Value Software Targets

**Date:** 2026-07-27
**Scope:** second of four "out-of-the-box" directions — real, WebSearch
-verified research into how real CHERI achieves its own published ROP/JOP
mitigation, then critically checked against Veda-Core's own actual,
current design (not assumed to transfer automatically).

## What real CHERI's ROP/JOP mitigation actually depends on — verified, not assumed

Live research confirms real CHERI-RISC-V's mechanism precisely: pointers
— "conventional data pointers, arrays, function pointers, stack and heap
allocations, and return addresses" — are represented as capabilities, and
critically, **the stack pointer itself is a capability (`csp`)**, not an
ordinary register. This means *every* stack access, including a function's
own saved return address, is capability-checked by construction, as part
of the standard CHERI calling convention — this is what actually stops a
ROP chain: a corrupted return address fails a real capability check
(Tag/Bounds) before it can be used, because it was never a legitimate
capability to begin with.

## The real, honest finding this analysis produces: the mechanism exists, but the specific application does not — yet

This session's own earlier work already verified Veda-Core's own explicit
design pillar (`DESIGN_SOUL_AND_UNIQUENESS.md`): the capability layer is
**opt-in per instruction, not ambient** — a deliberate choice made to
avoid a real, documented historical failure (the Intel iAPX 432's ambient
object-indirection made even scalar operations pay a real, catastrophic
cost — 300μs per `CALL` on early silicon — and this was a real,
documented factor in its commercial failure).

Checking this reasoning carefully against real CHERI's own actual scope
(not just Veda-Core's framing of it): **CHERI does not tax scalar
operations either.** Its own "opt-in" boundary is drawn in the same place
Veda-Core's is — ordinary integer arithmetic stays cheap in both designs.
The real, load-bearing difference is narrower and more specific: CHERI
draws its ABI convention so that the **stack pointer itself** is always a
capability, while Veda-Core's current instruction set has **no equivalent
convention at all** — the ordinary RISC-V stack pointer (`sp`, `x2`) and
plain `LD`/`SD` instructions are exactly what a standard prologue/epilogue
uses to save and restore a return address, and neither is
capability-checked in Veda-Core today. A corrupted return address on the
standard stack would be read and used by an ordinary `JALR`, completely
outside the capability system's field of view.

**This is not a conflict with the iAPX 432-avoidance reasoning** — a
protected-stack convention (using a dedicated capability register as `sp`,
routing prologue/epilogue through `OCL.D`/`OCS.D` instead of plain
`LD`/`SD`) would still leave ordinary scalar arithmetic untouched, exactly
matching real CHERI's own actual scope. It is real, additional,
**not-yet-made** design work — not something already implied or covered
by anything built in this project's fourteen milestones to date.

## Verdict

Real, well-grounded potential (the underlying Tag/Bounds check mechanism
is proven, verified this session against exactly this kind of corrupted
-value attack in `SECURITY_COMPARISON_STUDY.md`), but **not yet a real
Veda-Core property** — it requires a specific, undesigned architectural
decision (a capability-protected stack pointer convention) that is a
distinct, real next step, not a free consequence of what already exists.
Overselling this domain today, without that design step, would be exactly
the kind of hallucinated claim this analysis is required to avoid.

## Update — this honest next step is now done, tested, and resolved

`STACK_FRAME_CALL_RETURN_ANALYSIS.md` does exactly the scoped design task
named below, then goes further: builds and runs three real programs
against the actual, unmodified, committed `veda_core.tlv` to test it, not
just design it. Real result: a `csp`-equivalent convention built entirely
from already-existing, already-verified instructions (`OCA`+`CSeal` to
derive and seal a return-capability once per call from a long-lived
stack-region capability, `OCL.C`+`CGetTag`+`CUnseal`+`CGetAddr` to verify
and use it on return) **does stop the exact stack-smash hijack this
document describes** — confirmed by reproducing the real attack against
both the unprotected convention (`0xbad1`, hijacked) and the protected one
(`0xca11`, caught). A genuinely new, heavier "Frame-object per call"
design (using `ODT-Populate`/`Destroy` instead of the lighter
`OCA`/`CSeal` derivation) was considered and rejected, grounded in this
project's own iAPX 432 research and Milestone 16's new generation
-retirement ceiling. One real, honest gap was also found by testing
rather than assuming: the protection above is currently a software
discipline (an explicit Tag check), not a hardware guarantee — a third
test (`prot_gap`) proves omitting that check does not fail safely. Closing
that gap needs one new, small, well-precedented instruction (a
single-operand, hard-trapping sibling of `OCInvoke`, i.e. a real sentry
-capability jump) — scoped but not yet built, see the full doc for why it
was deliberately not implemented in the same pass as the design decision.

## Sources

- [A Hybrid Capability Architecture (CHERI, Cambridge)](https://www.cl.cam.ac.uk/research/security/ctsrd/cheri/workshops/pdfs/20160423-cheri-architecture.pdf)
- [CHERI: A Hybrid Capability-System Architecture for Scalable Software Compartmentalization (Oakland 2015)](https://www.cl.cam.ac.uk/research/security/ctsrd/pdfs/201505-oakland2015-cheri-compartmentalization.pdf)
- [What's the Difference Between Conventional Memory Protection and CHERI? (Codasip/Electronic Design)](https://www.electronicdesign.com/technologies/embedded/article/21284056/codasip-whats-the-difference-between-conventional-memory-protection-and-cheri)
