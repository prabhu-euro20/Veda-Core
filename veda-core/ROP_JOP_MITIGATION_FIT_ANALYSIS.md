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

## Honest next step, if pursued

Design a `csp`-equivalent convention for Veda-Core (which capability
register is the protected stack pointer, how prologue/epilogue code uses
it, whether this is opt-in per-function or a fixed ABI rule) — a real,
scoped design task, analogous in size to the PCC compartment-bounding work
already completed (Milestone 14), before any ROP/JOP mitigation claim for
Veda-Core specifically could be tested the way the bounds-overflow claim
already was.

## Sources

- [A Hybrid Capability Architecture (CHERI, Cambridge)](https://www.cl.cam.ac.uk/research/security/ctsrd/cheri/workshops/pdfs/20160423-cheri-architecture.pdf)
- [CHERI: A Hybrid Capability-System Architecture for Scalable Software Compartmentalization (Oakland 2015)](https://www.cl.cam.ac.uk/research/security/ctsrd/pdfs/201505-oakland2015-cheri-compartmentalization.pdf)
- [What's the Difference Between Conventional Memory Protection and CHERI? (Codasip/Electronic Design)](https://www.electronicdesign.com/technologies/embedded/article/21284056/codasip-whats-the-difference-between-conventional-memory-protection-and-cheri)
