# Why Not a "Frame-Object" in Place of SP? Real Research, a Rejected Design, a Working Alternative, and a Real Gap Found by Testing It

**Date:** 2026-07-27
**Question asked:** "Why till now we are not used Frame-object call/return
in place of SP here?" — evaluated as a real design decision, not answered
from the drafted spec alone. This directly closes the "honest next step"
`ROP_JOP_MITIGATION_FIT_ANALYSIS.md` already flagged and left open: "Design
a `csp`-equivalent convention for Veda-Core... a real, scoped design task...
before any ROP/JOP mitigation claim for Veda-Core specifically could be
tested."

## The literal idea, taken seriously first: every call frame is a fresh ODT object

The most direct reading of "Frame-object in place of SP": on every function
call, `veda.odt.populate` a fresh object sized to the new frame, `veda.bind`
a capability register to it, address all locals/spills through it, then
`veda.odt.destroy` it on return — replacing `sp`'s raw integer arithmetic
with the same object-lifecycle primitives already used for data objects
elsewhere in this design.

**Rejected, on three independent, quantified grounds — not a style
preference:**

1. **Real historical precedent, already in this project's own research,
   for exactly this failure mode.** `DESIGN_SOUL_AND_UNIQUENESS.md` and
   `VEDA_CORE_SPEC.md` §5.1 already document (from a full read of Levy's
   *Capability-Based Computer Systems*) that the **Intel iAPX 432** made
   object-indirection ambient and paid for it directly in its own `CALL`
   instruction: *"300 microseconds on early prototypes, reduced to under
   100 microseconds only after significant architectural rework
   (preallocated context objects, local-stack storage resources)"*. iAPX
   432's `CALL` **was** a frame-as-object mechanism, and the fix that got
   it merely 3x faster (not fast) was to stop minting a fresh object per
   call and partially retreat back toward ordinary local-stack storage.
   This is not a loose analogy — it is the same mechanism, already
   identified in this project as the cautionary tale its own opt-in
   design was built to avoid.
2. **A real, quantified instruction-count argument, using this project's
   own already-measured numbers.** `OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`
   measured object-centric access's one-time setup (construct a
   descriptor, `veda.odt.populate`, `veda.bind`) at **14 instructions**,
   and found this cost amortizes toward zero specifically *because* it is
   paid once and the object is reused many times. A frame-per-call design
   inverts this: the setup cost would be paid on **every single call**,
   never amortized, for an operation (function calls) that in real
   programs vastly outnumbers large-N array traversals. This is the
   opposite of the access pattern that made the original benchmark's
   result favorable.
3. **RTL Milestone 16 (this session, already fixed and committed) makes
   the heavy design actively worse, not just expensive.** The generation
   -wraparound-retirement fix means any single ODT slot can now only be
   destroyed-and-repopulated **255 times before permanent retirement**
   (`rtl/MILESTONE_16_RESULTS.md`). A hot or recursive function called
   more than 255 times over a slot's lifetime would permanently exhaust
   that physical slot — catastrophic for any real, long-running program,
   and a direct, mechanical consequence of a real bug fix this project
   just made for good, independent reasons.

## What real precedent actually does instead — verified, not assumed

Live-verified via WebSearch, not recalled from training:

- **CHERI**: the stack pointer (`csp`) is a capability, but real CHERI
  does **not** mint a fresh object/table entry per call. Return addresses
  are represented as capabilities; a **sentry** capability (a reserved
  `otype` sentinel) can be jumped to but not otherwise used, and jumping
  to it **atomically unseals it in hardware** — a corrupted return value
  fails the tag/seal check before it can redirect control flow, with zero
  extra software-visible check. ([Sentries for control-flow integrity, CHERIoT](https://cheriot.org/isa/ibex/2024/06/26/sentries-cfi.html))
- **RISC-V Zicfiss**: a real, **ratified** RISC-V extension (confirmed
  live against `docs.riscv.org`'s own Ratified Specifications Library,
  not a draft), purpose-built for exactly the return-address-integrity
  slice of this problem: a second, hardware-protected shadow stack,
  `sspush`/`sspop`/`sspchk` instructions, orthogonal to any
  capability/object model. ([RISC-V CFI, docs.riscv.org](https://docs.riscv.org/reference/isa/v20260120/unpriv/unpriv-cfi.html))

Neither real system re-derives a frame's protection from the general
object-allocation mechanism on every call. Both keep the per-call cost
O(1) and independent of the object table.

## What this project already has, unused for this purpose

Milestones already built and verified, checked directly for reuse before
proposing anything new:

- **`CSetBounds`/`CSetBoundsExact`** (RTL Milestone 3) — narrow an
  existing capability's window, no ODT involvement, single cycle.
- **`OCA`** (RTL Milestone 2) — add an offset to an existing capability's
  `Offset` field, no ODT involvement, single cycle. This is Veda-Core's
  own `CIncOffset`-equivalent, already built.
- **`CSeal`/`CUnseal`** (RTL Milestone 6) — seal/unseal a capability
  under a type-authority; sealed-capability enforcement already wired
  into every "use" instruction since Milestone 1.
- **`OCL.C`/`OCS.C`** (RTL Milestone 7) — capability-width (128-bit)
  memory access with real, verified tag-clearing on any ordinary
  non-`OCS.C` write to the same memory (already exercised by
  `veda_smoke_m7.S`'s own committed negative test).
- **`OCInvoke`** (Milestone 10) — proves this project already knows how
  to build a real, hardware-atomic "unseal-and-check-and-jump, hard-trap
  on failure" instruction. Its own "Not yet built" section already named
  the missing piece explicitly: *"sentry capabilities and
  `CSealEntry`/`CJALR`-style fast unsealing-jump... still out of scope."*

**The honest conclusion from this inventory: nearly everything needed for
a real, CHERI-style protected return-address convention already exists
and is already verified.** No heavy new mechanism was missing — only the
willingness to compose the existing pieces for this specific purpose, and
one real, identified gap (below).

## The experiment: three real programs, on the real, unmodified, committed `veda_core.tlv`

Built and run directly against the current RTL (not a modified copy —
this uses only instructions that already exist and are already
committed), matching this project's own "prove it, don't assert it"
standard for every prior claim:

1. **`trad_hijack`** — the plain RV64I convention: `sd ra,-8(sp)` /
   `ld ra,-8(sp)` / `jalr ra`, with a simulated stack-buffer-overflow bug
   overwriting the saved `ra` with a fully attacker-chosen address before
   the epilogue reloads it.
2. **`prot_caught`** — an object-centric protected convention built
   entirely from existing instructions: a *long-lived* return-slot object
   and a seal-authority object are minted **once** (not per call); each
   call derives a return-capability from a long-lived code-region
   capability via `OCA` (no `ODT-Populate` per call), seals it via
   `CSeal`, and stores it via `OCS.C`. The epilogue reloads via `OCL.C`,
   **explicitly checks `CGetTag`**, and only then `CUnseal`s + `CGetAddr`s
   + jumps. The identical stack corruption bug from test 1 is applied to
   the same 16 bytes.
3. **`prot_gap`** — identical to test 2, except the explicit `CGetTag`
   check is **omitted** before use — testing whether the capability
   mechanism protects automatically, or only when explicitly checked.

### Real results (marker register `x30`, sampled after a fixed 400-cycle budget, with the real cycle at which `x30` first changed from its reset value captured via a second, change-detecting testbench run)

| Test | Final `x30` | Cycle `x30` first changes | Outcome |
|---|---|---|---|
| `trad_hijack` | `0xbad1` | **10** | **Hijacked** — jumped to the attacker-chosen `EVIL` label, exactly as a real ROP-style stack-smash predicts. Trivially fast: no setup exists in the traditional convention, so the whole attack completes in 10 cycles. |
| `prot_caught` | `0xca11` | **56** | **Corruption caught** — `CGetTag` read 0 post-corruption (the same real tag-clearing-on-plain-write mechanism `veda_smoke_m7.S` already verifies), branched to `ABORT` before ever computing or jumping to an address. The higher cycle count versus `trad_hijack` reflects the one-time object-setup cost (minting and binding the return-slot/authority/code-region objects), paid once, not a per-check cost. |
| `prot_gap` | never defined (X) | **56** (this is when `x30` first *diverged* from its reset baseline, into an undefined value — not a real completion) | **Neither hijacked to a chosen target nor safely caught.** `CGetAddr` computed `Base+Offset` from the corrupted (untagged) capability's bit pattern regardless of its Tag — confirmed directly against the RTL's own `CGetAddr` logic (`veda_core.tlv:1605`, `{Base}+{Offset}`, no Tag term at all) — producing a wildly out-of-range address; the resulting instruction fetch indexed outside `elfmem[]`'s real bounds, and both `$pc` and `x30` X-propagated from that cycle onward. |

`prot_caught` and `prot_gap` reach the identical cycle (56) at the point
of divergence, confirming both run the exact same real setup and
corruption path — they differ only in the one instruction pair
(`CGetTag`+`beqz`) that comes after, isolating the causal effect of that
one check as cleanly as this experiment can.

### What this proves, stated precisely

- The traditional convention is trivially, cleanly hijackable to an
  **attacker-fully-chosen** address — the textbook ROP primitive.
- The object-centric convention, **used correctly (with an explicit Tag
  check)**, closes this specific attack completely, using only
  already-built, already-verified instructions, at real, modest,
  per-call cost (below) — not the 300μs-per-call iAPX 432 fate, and not
  gated on Milestone 16's new 255-reuse ODT limit, since the long-lived
  objects are bound once, not per call.
- **The object-centric convention, used *without* the explicit check,
  does not reproduce a clean hijack — but it does not reach the correct
  return site either.** This is the real, honest, structural finding:
  Veda-Core's capability system does not *automatically* prevent misuse
  of a corrupted-but-untagged capability the way CHERI's own sentry
  mechanism or a hard-trapping instruction would. `CGetAddr`, `CUnseal`,
  and ordinary `JALR` all compose without any built-in gate — protection
  here is a **software discipline**, not yet a **hardware guarantee**,
  for ordinary (non-`OCInvoke`) control transfers.

**Honest scope limit on the `prot_gap` result specifically**: this
experiment corrupted the capability's backing bytes with a simple,
undifferentiated pattern (`0x4141...`, the same one `veda_smoke_m7.S`
already uses to demonstrate tag-clearing), which happened to produce an
out-of-range address, not an attacker-chosen one. A more sophisticated
attacker who additionally knows Veda-Core's own capability memory-packing
layout (`veda_core.tlv:2320-2326`, a real, Kerckhoffs-principle-compliant
assumption, not security-by-obscurity) could in principle engineer the
corrupted bytes so `Base+Offset` equals **any address they choose** — a
strictly stronger, not-yet-constructed version of this same attack. This
experiment demonstrates the *structural* gap (an untagged capability's
address is fully readable and usable without restriction) without
claiming to have built the maximally adversarial byte pattern.

### Real, measured cycle cost — not estimated, a second experiment built specifically to answer this

The numbers above answer "does it work." A separate real experiment
answers "what does it cost": a loop repeating the save/restore pair `N`
times (traditional: `sd ra`/`ld ra`; protected: `OCA`+`CSeal`+`OCS.C`+
`OCL.C`+`CGetTag`+`CUnseal`+`CGetAddr`, with the one-time `Populate`
/`Bind`/offset-derivation setup hoisted outside the loop, matching how a
real compiler would treat a loop-invariant call site), run at
`N`=1,2,4,8,16 against the same real, unmodified `veda_core.tlv`, each
point independently assembled and simulated (completion detected via the
same "3 consecutive identical PC" terminal-loop signal
`OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md` already established):

| N | Traditional (cycles) | Protected (cycles) | Overhead |
|---|---|---|---|
| 1 | 8 | 45 | +37 |
| 2 | 12 | 55 | +43 |
| 4 | 20 | 75 | +55 |
| 8 | 36 | 115 | +79 |
| 16 | 68 | 195 | +127 |

Exact closed form, matching every row: **`trad_cycles = 4 + 4N`**,
**`prot_cycles = 35 + 10N`**. 35 is the one-time setup (three
`Populate`+`Bind` pairs plus the offset derivation), paid once per
program, not per call — but **unlike the original data-object benchmark,
the per-call overhead itself does not amortize toward zero**: each call
genuinely costs 10 cycles here versus the traditional convention's 4,
a real, sustained **+6 cycles every single call**, because protecting a
return address requires its own `Seal`+store+reload+`Unseal` work each
time, unlike a data object which is bound once and then read for free.
This is the honest, load-bearing difference from the earlier "amortizes
to under 1%" finding — that result was specific to repeated *reads of
one already-bound object*, and does not transfer to a mechanism that must
re-derive and re-verify a fresh capability on every call.

### Full cost comparison, cycles now real where measured

| Convention | Per-call cost | Protects against |
|---|---|---|
| Traditional (`sd`/`ld`) | **4 cycles/call, measured** | Nothing |
| Object-centric protected (this experiment, `CGetTag`-checked) | **10 cycles/call, measured** (+35 one-time) | Return-address integrity, capability-typed |
| Zicfiss (ratified RISC-V standard) | Not built or measured here — real RTL work, not yet attempted | Return-address integrity only |
| Heavy Frame-object (`ODT-Populate`+`Bind`+...+`Destroy` per call, rejected above) | Not built — rejected on the iAPX 432 + instruction-count + 255-reuse-ceiling grounds before reaching a cycle-count stage | Same, at understood-to-be-far-higher cost |

## Decision

**Reject** the literal "Frame-object per call" design — the iAPX 432
precedent, the instruction-count math, and Milestone 16's own new
255-reuse ceiling independently rule it out.

**For return-address integrity specifically**, if the goal is the
cheapest real protection: adopt **Zicfiss** at the RVA23 base-core level.
It is a ratified standard, costs about as much as the traditional
convention, requires no capability machinery, and was purpose-built for
exactly this problem. This is a real, separate, smaller piece of future
work (base-core RTL, not Veda-Core-specific).

**For a genuinely object-centric answer** — because the question was
about this project's own design philosophy, not just the cheapest fix —
the real, working answer demonstrated above is: **one long-lived stack
-region object and one long-lived seal-authority object, bound once per
program (not per call), with each call deriving and sealing a
return-capability via already-built `OCA`+`CSeal`, and each return
verifying it via `OCL.C`+`CGetTag`+`CUnseal`+`CGetAddr`.** This is real,
it works (`prot_caught`), it uses zero new instructions, and it stays
independent of the ODT-generation-retirement ceiling since no
`ODT-Populate`/`Destroy` happens per call.

**The one real gap this experiment surfaced, honestly, by testing rather
than assuming**: this protection was, when this section was first
written, a **software discipline** (an explicit `CGetTag` check the
programmer/compiler must remember to emit), not a **hardware guarantee**
— `prot_gap` proved the check's absence is not automatically caught.

**Update — now closed, RTL Milestone 17** (`rtl/MILESTONE_17_RESULTS.md`):
`OCJALR`, a lighter sibling of `OCInvoke` (single capability operand pair,
no `c15` side effect, atomic unseal-check-and-jump, **hard-trap** — not
soft-fail — on a Tag or Seal mismatch), was designed, implemented in both
Sail and RTL, and verified (28/28 Sail self-check, 31/31 RTL smoke tests,
51/51 ACT4, zero regressions in either layer). A real, concrete
before/after: `prot_gap`'s own exact corruption scenario, re-run with the
vulnerable `CUnseal`+`CGetAddr`+`JALR` tail replaced by a single `ocjalr`
and **no explicit software Tag check written anywhere in the file**, now
lands in a real, controlled hard-trap (`x30=0xca11`) instead of an
undefined jump (`x30`/`PC` both X-propagated, the original `prot_gap`
result). The gap is closed structurally, not by discipline.

## Reproducing this

`/tmp/claude-.../scratchpad/stackframe/` (session-scoped, not committed):
`enc.py` (instruction encoder, self-checked against every known-good
`.word` encoding already used in `veda_smoke_m6.S`/`veda_smoke_m7.S`),
`gen_tests.py` (generates the three security `.S` files), `tb_marker.sv`/
`tb_marker2.sv` (shared testbench; the `2` variant adds real
change-detection cycle capture), `build_and_run.sh` (transpiles the real,
unmodified `veda_core.tlv` once, builds and runs all three programs),
`gen_loop.py` (generates the `trad_loop_N`/`prot_loop_N` cycle-cost
programs at N=1,2,4,8,16), `tb_bench_loop.sv` (completion-detecting
testbench, same "3 consecutive identical PC" signal as
`OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`).

## Sources

- [Sentries for control-flow integrity, CHERIoT Platform](https://cheriot.org/isa/ibex/2024/06/26/sentries-cfi.html)
- [Capability Hardware Enhanced RISC Instructions: CHERI User's Guide](https://murdoch.is/papers/cl14cheriug.pdf)
- [33.1. Control-flow Integrity (CFI), RISC-V Ratified Specifications Library](https://docs.riscv.org/reference/isa/v20260120/unpriv/unpriv-cfi.html)
