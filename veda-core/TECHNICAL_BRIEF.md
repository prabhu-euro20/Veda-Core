# Veda-Core: An Object-Centric, Capability-Based, Deterministic RISC-V Extension Core

**A technical brief for researchers working on capability-based and hardware-security architectures.**

## One-line summary

Veda-Core is a RISC-V custom extension that replaces address-based
memory access with object-handle-based access: every memory reference
goes through a 128-bit capability register bound to a flat, system-wide
Object Descriptor Table (ODT) entry, checked and out-of-band-tagged in
hardware on every use. Design pillars: **Object-Centric, Address-less,
Capability-based, Deterministic, Single Address Space.**

## What is actually different from CHERI

CHERI extends *pointers* with bounds/permissions/tag metadata, while
keeping the underlying flat address space and page-table-based
protection domains. Veda-Core removes the address as the primary
handle entirely: software holds an `Object_ID` (currently 23 bits,
8,388,608-entry space) that is *bound* into a capability register
before use, not an address that already points somewhere. Two concrete
consequences we have measured, not just designed for:

- **No PCC in the traditional sense.** Compartment bounding
  (`OCInvoke`) narrows the live fetch window to the invoked object's
  own `Base`/`Length` directly from the ODT, not from a
  separately-maintained code-capability chain.
- **A single, flat, system-wide ODT** rather than a per-process or
  per-domain capability table — the same real address-uniformity
  property Mungi (Heiser et al., SASOS literature) and IBM i's
  single-level store demonstrate for intra-partition object addressing,
  applied here to a capability architecture rather than an OS.

## Real, measured results (not projected)

All numbers below are read directly from real Icarus Verilog
simulations of the actual, unmodified RTL (`veda_core.tlv`, single-cycle,
50/50 RV64I base + Custom-0/1/2/3 Veda-Core extension), or from a real
Sail formal executable model. Every row is reproducible; none are
estimates.

| Result | Measurement |
|---|---|
| Deterministic tag check vs. probabilistic hardware tagging (Arm MTE, 4-bit) | Veda-Core: `P(bypass) = 0`, always. MTE: `P(success after k attempts) = 1 − (15/16)^k` → 6.25% at k=1, 96.03% at k=50 |
| Compartment-crossing cost (`OCInvoke`) vs. cheapest real software-gated call | `38 + 3N` vs. `1 + 9N` cycles — Veda-Core wins outright (incl. one-time setup) at N≥7; steady-state 3 vs. 9 cycles/crossing |
| Protected-return-jump cost (`OCJALR`, new instruction) vs. naive software-checked sequence | 7 vs. 10 cycles/call (**−30%**) — merging Tag/Seal/Type/Permit checks into the jump itself removes a branch and a query instruction, not just the software gap they left open |
| Object-descriptor construction cost (`POPULATE_FAST` + reusable CSR, new instruction) vs. packed-descriptor `ODT-Populate` | `6N+3` vs. `10N` cycles (**−32.5% at N=4, converging to −40%**) — closes a real RV64I 12-bit-immediate tax a software-only fix (`la`-relative addressing) only closed by ~5% |
| Critical path, full capability-check chain vs. plain load | 95 vs. 114 logic-gate levels (Yosys synthesis, generic cell library) — the checked path is *shorter*, not longer |
| Capability-register working-set pressure (k live objects vs. 16 physical registers) | 1.186–1.187× at k≤16 (at capacity), 1.561× worst-measured case at k=32 (full 2× oversubscription) |
| Per-cycle dynamic energy proxy (VCD toggle count, synthesis-based) | +20% vs. traditional RV64I — real, and the one place our own stated goals (security *and* efficiency) are not both currently met |

## Five real attack demonstrations, traditional vs. Veda-Core

Each run against both the real traditional RV64I core and Veda-Core,
same bug shape, same RTL simulator, real register/trap values (not
theoretical): out-of-bounds read, out-of-bounds write, stack-smashing
return-address hijack, use-after-free, and arbitrary-pointer forgery.
In all five, the traditional core's memory corruption/leak succeeds
silently; Veda-Core hard-traps with the specific, correct cause code
(Bounds/Tag/Type Violation), verified at the exact faulting
instruction.

## Verification methodology

- **Formal executable model**: a Sail specification of the full
  Veda-Core ISA (18 milestones), built on the official `sail-riscv`
  RV64I base. 30/30 self-checking positive/negative tests pass.
- **RTL implementation**: TL-Verilog (SandPiper → SystemVerilog →
  Icarus Verilog), independently implementing the same semantics.
  27/27 milestone regression tests pass.
- **Base-ISA conformance**: the *same* RTL file, run against
  RISC-V International's official ACT4 conformance suite (RV64I),
  Sail as the reference model. 51/51 pass, zero regressions from any
  Veda-Core addition.

## Honest limitations

- No FPGA or silicon exists yet — all results are RTL simulation,
  the same evidentiary tier real capability-architecture research
  (including CHERI's own early publications) used before silicon.
- Energy overhead (+20%) is real and not yet closed.
- The single-hart Sail/RTL test environment cannot yet exercise
  genuinely concurrent multi-hart scenarios (owner-hart enforcement is
  tested via direct state injection, not a real second hart).
- No compiler or toolchain ecosystem exists — every test program is
  hand-assembled. CHERI's own ecosystem took 13 years and 1,800+
  commits to reach its current maturity; we do not claim to have
  replicated that effort, only to have built the first, smallest
  slice of it (formal model + RTL + conformance).
- Sealing/unsealing and several newer instructions (`OCJALR`,
  `POPULATE_FAST`) close real gaps found by *testing* the design, not
  anticipated in advance — we consider this a feature of the
  methodology (build → attack → fix → re-verify), not a hidden defect
  count, but it means the instruction set is still evolving.

## What we are looking for

Technical feedback from researchers with direct CHERI/capability-
architecture experience: places where our threat model or measurement
methodology is weaker than we believe it is, related work we may be
unaware of, and whether the single-address-space/object-centric
framing offers anything genuinely new relative to CHERI's own
pointer-based model beyond what we have measured so far. This is a
research conversation.

## A note on how this was built

This project's RTL, Sail model, tests, and this document were built
with AI-assisted tooling (Claude, Anthropic) under close, iterative
human direction — every design decision, encoding choice, and
measured result was independently reviewed and re-verified before
being included here, and the discipline throughout has been to reject
any claim that could not be backed by a real, reproducible run. We
state this plainly because verifiability, not authorship method, is
what should determine whether any of the above is worth your time —
every number in this document can be independently reproduced.

