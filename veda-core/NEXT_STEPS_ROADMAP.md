# Veda-Core — Next Steps: A Rigorous Roadmap

**Date:** 2026-07-23

**Status update, 2026-07-25**: Tier 1 item 1 (`OCL.C`/`OCS.C`, §2.1) is
now **done** in both Sail and RTL — see `MILESTONE_7_RESULTS.md`. Tier 1
item 2 (Sail-side Veda-Atomic/`NMC_ADD.W` test-coverage parity, §2.2) is
also now **done** — see `MILESTONE_V-B_RESULTS.md`'s 2026-07-25 addendum,
16/16 self-check tests passing. Tier 1 item 3 (RTL `Rebind`/`Bind-NoTrap`,
§2.3) is also now **done** — see `rtl/MILESTONE_8_RESULTS.md`; along the
way it closed a real, previously-undetected gap (the bind-mode field was
decoded since RTL Milestone 1 but never actually checked, so every
non-zero mode silently executed as plain `Bind`), and proved `Rebind`'s
own real-relocation property against a real physical address, not just
capability metadata. **Tier 1 is now fully closed.** Tier 2 item 4 (real
RTL trap infrastructure, §2.4) is also now **done** — see
`rtl/MILESTONE_9_RESULTS.md`: a real Zicsr-lite CSR file
(`mtvec`/`mepc`/`mcause`/`mtval`), real `CSRRW`/`CSRRS`/`MRET` (standard
RISC-V encoding), and a real PC redirect wired to every Sail
"use"-family violation, closing the largest remaining Sail/RTL
architectural divergence and finding five real, distinct bugs along the
way (spanning a stale Milestone-1 test assumption, a trap/resume PC
placement mistake repeated across three files, three unrelated tests
broken by the new trap infrastructure exposing their own latent
soft-fail assumptions, a register-naming collision, and a too-tight
cycle budget). Deliberately still deferred within this same item: plain
`Bind`'s own ODT-miss hard-trap, and `ODT-Populate`/`ODT-Destroy`'s own
`Illegal_Instruction` privilege trap (a distinct exception class) — both
real, named, separate follow-ons, not silently folded in. **Tier 2 is
now fully closed.** Tier 3 item 5 (`CInvoke`-equivalent, §2.6) is also
now **done** — see `rtl/MILESTONE_10_RESULTS.md`: `OCInvoke`, term-for-
term adapted from real CHERI's `CInvoke` (CHERI ISA spec p.209), in both
Sail and RTL. `c15` (the last CRF entry) serves as the fixed "IDC"
target, proportional to CHERI's own real `C31` convention (itself just
the last entry in CHERI's 32-register file, not a separate physical
register — a real fact this milestone's own research corrected from an
earlier, vaguer assumption). Deliberately still deferred within this
same item, stated plainly: a real `PCC` register and real
instruction-fetch-time capability enforcement (`OCInvoke` redirects PC
directly to the resolved target address instead, achieving the real
"atomic unseal-and-jump" property without that storage) — this would
require changes to the RVA23 base core's own fetch stage, out of bounds
for `veda_core.tlv`-only work, and remains a distinct, separately-scoped
future item. Tier 3 item 6 (capability-authority-gated
`ODT-Populate`/`ODT-Destroy`, §2.5) is also now **done** — see
`rtl/MILESTONE_11_RESULTS.md`: `OSpecialRW` + the ODA (Object Descriptor
Authority), Veda-Core's own single Special Capability Register,
term-for-term adapted from real CHERI's own `CSpecialRW`/SCR model
(CHERI ISA spec §4.3.6). `ODT-Populate`/`ODT-Destroy` now legal via a
real OR — ordinary privilege (unchanged since Milestone 4) **or** a
live, unsealed, `Permit_Access_System_Registers`-carrying capability
delegated into the ODA — matching CHERI's own layered privilege model
exactly, activating `Permit_Access_System_Registers` for the first time.
Found and honestly worked around a real Sail-side scope limit along the
way: this project's own Sail test config has S/U-mode disabled, so
privilege can never actually drop below Machine there, making a
genuinely privilege-independent proof structurally impossible in Sail
with the existing config — RTL's own independent `veda.droppriv`
supplied the one real, end-to-end proof instead. Zero design/Sail/RTL
bugs found this milestone, a first since Milestone 8. The owner-hart
hardware enforcement piece of Tier 3 item 7 is now **done** — see
`rtl/MILESTONE_12_RESULTS.md`: a real `owner_hart` byte in every ODT
entry, checked and claimed at Bind/Rebind time in both Sail and RTL,
closing `VEDA_CORE_SPEC.md` §4.1's own long-named gap. **The remaining
half of Tier 3 item 7 — real multi-hart RTL architecture and shared-ODT
arbitration between genuinely concurrent harts — stays open**; it was
always the larger, separate undertaking, and owner-hart enforcement was
verified via direct ODT-state injection standing in for a second hart
(neither this project's single-process Sail simulator nor its
single-core RTL can produce one), not genuine concurrent execution.
**Milestone 13** (`rtl/MILESTONE_13_RESULTS.md`) then closed
`MILESTONE_9_RESULTS.md`'s own separately-named, deliberately-deferred
gap: plain `Bind`'s ODT-miss hard-trap (`cause = 0x05`) is now real in
RTL too (Sail already had it). A full grep of the existing test corpus
before writing any RTL found five pre-existing tests relying on plain
`Bind`'s old soft-fail behavior against a never-populated/destroyed
`Object_ID`; each was fixed by switching to `Bind-NoTrap` — the
already-correct instruction for that purpose since Milestone 8 — not a
workaround. Also closed a real, previously-unnoticed Sail-side
test-coverage gap (no self-check test had ever directly asserted this
trap's own `mcause`/`mtval`, despite the Sail behavior itself existing
for many milestones). Two more items were then resolved by research
rather than code: **`ODT-Destroy`'s own owner-hart gating question is
now permanently closed, not deferred** — `VEDA_CORE_SPEC.md` §4.1 was
updated with the real reasoning (CHERI ISA spec §2.3.16's own object-
revocation precedent places that authority with a trusted handler,
independent of current ownership; `ODT-Destroy` was correctly designed
already and should stay privilege/ODA-gated, not owner-gated). **Tier 3
item 5's own long-named "PCC" gap has been rescoped and fully designed**
(`veda-core/PCC_COMPARTMENT_DESIGN.md`) but deliberately not yet
implemented: research found real CHERI's own PCC is a universal,
always-on fetch-time mechanism that doesn't fit Veda-Core's own hybrid,
opt-in architecture at all — the actual, well-scoped gap is narrower,
`OCInvoke`'s own currently-incomplete compartmentalization bound (a
successful `OCInvoke` redirects PC but nothing constrains subsequent
execution to stay within the invoked capability's own bounds). The
design doc verifies real, concrete Sail extension hooks for this
(`ext_fetch_check_pc`/`ext_handle_fetch_check_error`, and new CSR
addresses `0x7C0`-`0x7C3` in the real RISC-V-spec-reserved custom M-mode
range) and a real, non-obvious finding along the way — `xret_callback`
is declared `pure`, so automatic hardware save/restore of compartment
bounds across a trap isn't available the way it is for `mepc`; the
design instead makes restoration an explicit software step, consistent
with `mepc`'s own already-established explicit-advance-before-`mret`
convention. **That design is now implemented and verified on the Sail
side** (`veda-core/MILESTONE_14_RESULTS.md`) — `OCInvoke` genuinely
narrows execution to the invoked compartment's own bounds, fetch outside
them genuinely hard-traps, and the full save/explicit-restore cycle
across a real trap and `mret` is proven end to end, 24/24 Sail tests
passing. Two real, concrete findings surfaced only by actually building
it: a module-ordering conflict (`core` compiles before `Veda`, so the
fetch-check hook's real body had to move to `postlude/step_ext.sail`,
which already requires `Veda_insts`) and a pre-existing Milestone 10
test whose own `Length` fixture needed widening now that the field is
genuinely checked rather than decorative. **The RTL mirror is now also
done** (`veda-core/rtl/MILESTONE_14_RESULTS.md`), the same day: `$instr`
is forced to a real NOP on a PCC violation -- a single, minimal change
that correctly suppresses every downstream write path at the source
rather than auditing each one individually, since this is the one check
in the whole file that's genuinely unconditional rather than gated on a
decoded opcode. Found and fixed two real bugs via an actual
cycle-by-cycle debug trace, neither in the trap mechanism itself (which
worked first try): a second real instance of the Milestone-13-taught
Object_ID-collision class, and two testbenches' own underestimated
cycle budgets. 25/25 RTL tests passing. **Tier 3 item 5 is now fully
closed, in both Sail and RTL.**
This document otherwise remains a point-in-time analysis; the
recommendation below should be re-read in that light, not assumed still
current for every item — Tier 4 items remain exactly as originally
assessed below.

## Why this document exists

Requested explicitly, in these terms: *"complete and rigorous analysis,
research, analytical thinking and logical approach... how much we can
extend it... read complete content... of any research paper or web
content, don't just piece of content or relevant section."* This document
is the output of that pass: (1) a complete re-read of every planning/
results document this project has produced (2,000+ lines, all read in
full, not grepped for fragments), cross-checked against the actual current
RTL/Sail source rather than assumed from memory; (2) fresh external
research, reading complete primary sources — the ratified RVA23 profile
spec, the current live CHERI-RISC-V draft spec, a real CHERI-RISC-V
standardization-status talk, and a full peer-reviewed paper on Arm CCA —
not search-result summaries alone. Findings that overturn or sharpen
earlier assumptions are stated as such, not quietly folded in.

---

## Part 1 — Where we actually are (verified against source, not memory)

### Sail formal model — Milestones V-A/V-B/V-C, all done
Capability struct (`Object_ID`(23)/`Base`(32)/`Length`(16)/`Offset`(16)/
`Perms`(16)/`otype`(16)/`Reserved`(8), 128 bits + out-of-band Tag), 16-entry
CRF, a flat system-wide ODT, **all three** Object-Bind modes (`Bind`/
`Bind-NoTrap`/`Rebind`), `OCL.D`/`OCS.D`, `NMC_ADD.{W,D}`, Veda-Atomic (9
ops, only `AMOXOR.D` independently tested), `OCA`, the 7-instruction query
family, `CSetBounds`/`CSetBoundsExact`, `CSeal`/`CUnseal` with real
hard-trap sealed-capability enforcement, `ODT-Populate`/`ODT-Destroy`
(privilege-gated, not capability-authority-gated — a stated deviation). A
real security gap (generation re-check never actually performed at
dereference time) was found and fixed mid-pass. 14/14 self-checking tests
via `sail_riscv_sim`'s real HTIF/`tohost` support.

### RTL — Milestones 1 through 6, all done, this session
Capability Register File, plain `Bind` only (no `Rebind`/`Bind-NoTrap`),
`OCL.D`/`OCS.D`, `OCA`, `NMC_ADD.{W,D}`, all 9 Veda-Atomic ops (fully
tested as of Milestone 5), the query family, `CSetBounds`/
`CSetBoundsExact`, a minimal one-bit `$priv` privilege gate +
`ODT-Populate`/`ODT-Destroy`, and `CSeal`/`CUnseal` with soft-fail (not
hard-trap — this RTL has no trap infrastructure at all) sealed-capability
enforcement. 12 real test programs, zero regressions, via real Icarus
Verilog simulation. The RVA23 *base* core underneath it (`rv64i_core.tlv`)
is bare RV64I, single-cycle, 51/51 real ACT4 conformance — **and nothing
more**: no CSRs, no privilege modes, no MMU, no vector unit, no other
standard extension.

### Everything above is genuinely real — verified via actual compilation, actual simulation, actual trace output — not asserted from source review alone. That much is a solid foundation. What follows is what it's missing, some of it larger than the project's own docs have previously emphasized.

---

## Part 2 — Real, already-flagged gaps, re-audited and re-prioritized

Cross-checked against `MILESTONE_PLAN.md`, all six `rtl/MILESTONE_*_RESULTS.md`,
`MILESTONE_V-{A,B,C}_RESULTS.md`, and `FORMAL_VERIFICATION_PLAN.md` — every
"not yet built"/"deferred"/"explicitly not decided" line in all ten
documents, consolidated and re-ranked by actual leverage, not just by
which document happened to mention it last.

### 2.1 — Highest leverage, smallest cost: capability-width memory access (`OCL.C`/`OCS.C`)

**Not built in either Sail or RTL.** `VEDA_CORE_SPEC.md`'s own OCL/OCS
width table already names a Capability width; `FORMAL_VERIFICATION_PLAN.md`
§2.2 already identified the real Sail hook for it (`mem_meta`, deliberately
left as `unit` "specifically for an extension to override with real
per-location metadata"). Neither was ever exercised. **Concretely, this
means Veda-Core capabilities cannot currently be stored to memory and
loaded back with their Tag intact.** That is not a peripheral gap — it is
the mechanism that makes a capability system a *system* rather than a
register-only toy: linked data structures of capabilities, a capability
heap, passing a sealed token between two pieces of code via memory (the
exact CSeal/CUnseal use case Milestone 6 just built and verified in
registers) all require it. This is real, tractable, and already has a
designed landing spot in both layers — the highest-leverage-per-effort
item found in this whole pass.

### 2.2 — Sail-side test-coverage parity gap (mirrors what RTL Milestone 5 just closed on the other side)

`MILESTONE_V-B_RESULTS.md`'s own "Not yet built" section: 8 of 9
Veda-Atomic ops beyond `AMOXOR.D`, and every non-D width across every
instruction family, were never independently tested **in Sail** — the
identical class of gap RTL Milestone 5 found and closed for the RTL side.
Mechanical, cheap, closes an honesty gap the same way M5 did.

### 2.3 — RTL/Sail parity: `Rebind`/`Bind-NoTrap`

Sail has all three Object-Bind modes; RTL only decodes plain `Bind`
(`MILESTONE_PLAN.md`'s own stated scope reduction, never revisited).
`Rebind` in particular is the mechanism that makes Veda-Core's headline
design claim ("the MSA can silently relocate an object without the CPU
knowing") actually real — currently only provable in Sail, not RTL.

### 2.4 — Real trap infrastructure in RTL

Every RTL milestone has stated the same honest floor: violations suppress
writes; they do not trap, because this RTL has no privileged/trap
architecture at all. This is the single largest remaining *architectural*
divergence between the two verified layers — Sail's own security model
(hard trap, exact `mcause`/`mtval`) is not actually what the RTL currently
enforces. Building it requires real CSR state (`mcause`/`mtval`/`mtvec`/
`mepc`) and trap-taken control-flow redirect — a genuine, non-trivial RTL
milestone, but a well-understood one (this is exactly `Zicsr` + the
privileged-trap mechanism, both real, standard, already-specified RISC-V
concepts, not novel design).

### 2.5 — Capability-authority-gated `ODT-Populate`/`ODT-Destroy`

Both Sail and RTL currently gate this on ordinary RISC-V privilege level, a
stated, deliberate simplification (no spare R-type operand, no
privileged-capability convention exists yet). Closing this "for real" needs
a privileged-capability model (a `PCC`-adjacent concept) designed first —
not a quick fix, correctly deferred.

### 2.6 — `CInvoke`-equivalent domain transition

Explicitly, repeatedly named and deferred since the spec's own Section 6
item 7: no `PCC`-equivalent register exists for it to unseal into. This is
real, substantial, novel design work — CHERI's own most complex mechanism,
the one that turns sealed capabilities into actual secure cross-domain
calls rather than just opaque tokens.

### 2.7 — Multi-core

`VEDA_CORE_SPEC.md`'s Object-Bind exclusive-ownership policy is
*designed and documented* (grounded in UPMEM's real share-nothing
precedent, `SCALING_BARRIERS_RESEARCH.md` §4) but never actually built or
tested against real multi-core RTL — this project has been single-hart
throughout. A real, if distant, gap between "the policy is right" and "the
policy is implemented and tested."

### 2.8 — `Length`/`Offset` 16-bit cap

A stated, honest, load-bearing limit (65,536-byte object-size cap) —
growing past it needs either a wider capability register or CHERI-
Concentrate-style compressed bounds encoding (real, proven, but a separate
design task, not free).

### 2.9 — Formal-verification maturity gap

`SCALING_BARRIERS_RESEARCH.md` §8's own real, cited finding: the mature
`sail-cheri-riscv` effort is 51.3% Isabelle, 45.9% Rocq/Coq, only 2.6%
executable Sail. Everything built so far (V-A/B/C) is entirely in that
2.6% category. This is not a small remaining gap — it is, by this
project's own honest calibration, the overwhelming majority of what "formal
verification" means at real maturity, essentially entirely unstarted.

---

## Part 3 — Fresh external research: reframing "how far can we extend, and toward what"

### 3.1 — RVA23 is ratified, and its real requirement list is enormous

Read in full from the official ratified spec
([docs.riscv.org/reference/rva23](https://docs.riscv.org/reference/rva23/v1.0/rva23-profiles.html)):
RVA23 was **ratified 2024-10-21**. Its mandatory list for just the
user-mode profile (`RVA23U64`) is ~35 extensions beyond bare RV64I: `M`,
`A`, `F`, `D`, `C`, `B`, `Zicsr`, `Zicntr`, `Zihpm`, `Ziccif`, `Ziccrse`,
`Ziccamoa`, `Zicclsm`, `Za64rs`, `Zihintpause`, `Zic64b`, `Zicbom`,
`Zicbop`, `Zicboz`, `Zfhmin`, `Zkt`, **`V` (the full Vector extension, now
mandatory, was optional in RVA22)**, `Zvfhmin`, `Zvbb`, `Zvkt`,
`Zihintntl`, `Zicond`, `Zimop`, `Zcmop`, `Zcb`, `Zfa`, `Zawrs`, `Supm`. The
supervisor-mode profile (`RVA23S64`) adds a **mandatory Hypervisor
extension** (`Sha`, itself a bundle of 7 sub-extensions), a mandatory
**Sv39 MMU**, mandatory supervisor timers (`Sstc`), counters, and pointer
masking.

**Direct, quantified answer to this project's own earlier question ("what
do we still need to be RISC-V compatible")**: the current core (bare
RV64I, zero privilege architecture, zero MMU, zero vector unit) implements
roughly 1 of ~40 required pieces of `RVA23U64` alone, and zero of
`RVA23S64`'s additional privileged/MMU/hypervisor requirements. This is not
a "few milestones away" gap — it is a categorically different scale of
undertaking than anything built so far, and every one of those ~40 pieces
is **already fully specified, already implemented by multiple real
vendors** (SiFive, Ventana, and others already ship real RVA23-class
silicon). There is close to zero novel research value in re-implementing
them — the entire value would be in the exercise of implementing them, not
in any new idea they'd embody.

### 3.2 — CHERI-RISC-V itself — Veda-Core's real, closest precedent — is still in draft, a year past its own target

Two real, current primary sources, read in full:

- The **live spec repository** ([riscv.github.io/riscv-cheri](https://riscv.github.io/riscv-cheri/)),
  fetched today: version **v0.9.9-draft**, dated **2026-07-21** (two days
  before this document), status **"Stable"** — RISC-V's own maturity model
  defines "Stable" as "assume anything could still change, but limited
  change should be expected," one stage before "Frozen" and two before
  "Ratified."
- A **real conference talk abstract** by Tariq Kurd (Codasip) and Ben
  Laurie (Google), *"Standardizing CHERI-RISC-V,"* RISC-V Summit Europe,
  May 2025, read in full (PDF): the CHERI Task Group was **officially
  formed October 2024**. Its own agreed ratification plan targeted
  **"late summer 2025."** Real industry backing is substantial and named:
  Google chairs the SIG/TG; Microsoft Research built CHERIoT (an embedded
  variant with a hardware garbage collector); Codasip ships an X730 core
  meeting the draft base standard; lowRISC ships the SONATA FPGA dev
  board; ICENI silicon based on open-source CHERIoT was planned for 2025.
  The talk's own words: *"This comes late for existing silicon projects,
  risking a defacto standard forming."*

**Cross-referencing these two sources directly**: the "late summer 2025"
target has now been missed by well over ten months — the spec is still
"Stable"-draft, not ratified, as of this week. **This is the single most
important calibration point this research pass produced**: a RISC-V
Task-Group-chartered effort, backed by Google, Microsoft Research,
Cambridge, and multiple silicon vendors, with a concrete ratification plan
and real committed hardware, has still taken *at minimum* 21 months
(October 2024 → now) without reaching ratification. Veda-Core is a
single-contributor research project pursuing a *more* novel design (fully
address-less and object-table-based, versus CHERI's address-based
tagged-pointer model — `SCALING_BARRIERS_RESEARCH.md` §7 already made this
exact comparison for the software-ecosystem question; it applies equally
here to the standardization-timeline question). This isn't a reason to
stop — it's a real, evidence-based reason not to frame any near-term work
here as "on the path to being a standardized, shippable extension soon."
The honest framing is: this is research-stage work in a space where even
the best-resourced comparable effort is still years from that bar.

### 3.3 — Confidential computing (Arm CCA / Intel TDX / AMD SEV-SNP) is a different problem, not a competitor

Read in full: Bertschi & Shinde (ETH Zürich), *"OpenCCA: An Open Framework
to Enable Arm CCA Research"* (2025, full paper via `arXiv:2506.05129`), plus
a real, current technical comparison search across TDX/SEV-SNP/CCA
sources. **Real, precise technical finding, not assumed**: Arm CCA's
actual mechanism is the Realm Management Extension (RME) — Granule
Protection Checks/Tables at each core, splitting execution into four
*worlds* (Normal, Secure, Realm, Root), with a firmware Realm Management
Monitor managing whole *Confidential VMs*. Intel TDX and AMD SEV-SNP do the
analogous thing via a signed TDX module / per-VM memory encryption+
integrity, respectively. **All three operate at VM/tenant granularity**:
their job is protecting an entire guest VM from an untrusted hypervisor or
cloud host. The paper states plainly, as of its writing: *"no public Arm
CPU supports CCA yet."*

**This is categorically not what CHERI or Veda-Core do.** CHERI/Veda-Core
target *intra-process and inter-process* memory safety and fine-grained
compartmentalization — protecting a program from its own bugs (buffer
overflows, use-after-free) and enabling sub-process sandboxing (Milestone
6's `CSeal`/`CUnseal` sealed-token model is exactly this), a completely
different granularity and threat model than "protect this whole VM from
the hypervisor." **Direct, evidence-based answer to this project's own
earlier question ("compete with whom, on which domain")**: Veda-Core's
real comparison set is CHERI-RISC-V (same problem: deterministic memory
safety/compartmentalization; different mechanism: address-based+compressed-
tag vs. address-less+object-table), not the confidential-computing
vendors, who are solving an adjacent, complementary problem at a different
layer. A real system could plausibly use both together (a CCA/TDX-style
confidential VM, internally memory-safe via a CHERI/Veda-Core-style
capability model) — they are not substitutes.

---

## Part 4 — Recommendation, reasoned, tiered

**Tier 1 — near-term, high leverage, directly strengthens the existing, verified core. Recommended as the actual next milestone.**
1. `OCL.C`/`OCS.C` (capability-width, Tag-preserving memory access) — §2.1.
   The highest leverage-per-effort item found: unlocks capabilities-in-memory,
   the property that makes this a real capability *system*, and both layers
   already have a designed landing spot for it.
2. Sail-side Veda-Atomic/width test-coverage parity — §2.2. Cheap, mirrors
   RTL Milestone 5's already-proven approach exactly.
3. RTL `Rebind`/`Bind-NoTrap` — §2.3. Cheap, closes a real Sail/RTL parity
   gap, makes the project's own headline "transparent relocation" claim
   provable in RTL, not just Sail.

**Tier 2 — medium-term, substantial but well-understood, dual-purpose.**
4. Real RTL trap infrastructure (`Zicsr`-lite + trap-taken control flow) —
   §2.4. The largest remaining Sail/RTL architectural divergence, *and* a
   genuine, if small, real step toward eventual standard-RISC-V alignment
   (unlike the broad RVA23 list below, `Zicsr`/trap delivery is something
   Veda-Core's own security model actually needs regardless of any
   standards-compliance goal).

**Tier 3 — large, novel, deliberately sequenced after a design pass of their own.**
5. `CInvoke`-equivalent + a `PCC`-adjacent control-flow-capability design —
   §2.6. The genuinely novel, highest-differentiation feature remaining;
   needs its own dedicated design pass first, not a quick add.
6. Capability-authority-gated `ODT-Populate`/`ODT-Destroy` — §2.5. Blocked
   on the same `PCC`-adjacent design work as item 5.
7. Real multi-core RTL, finally exercising the already-designed
   exclusive-ownership policy — §2.7.

**Tier 4 — explicitly not recommended as a near/medium-term priority, with reasoning stated plainly rather than left implicit:**
- **Chasing broad RVA23 compliance** (§3.1) — confirmed, quantified this
  pass: ~40 already-fully-specified, already-multiply-implemented standard
  extensions, near-zero novel research value, multi-year scope. Pursuing
  it now would consume all available effort on well-trodden ground while
  contributing nothing to this project's actual differentiated value.
  **Recommendation: do not adopt "become RVA23-compliant" as a goal.**
  Take standard extensions only where they directly serve Veda-Core's own
  needs (Tier 2's `Zicsr` is exactly this kind of targeted, justified
  exception — not a step toward the broader list).
- **Full Isabelle/Rocq-level formal proofs** (§2.9) — real, and eventually
  necessary for anything claiming CHERI-grade assurance, but by this
  project's own honest calibration represents the large majority of real
  verification effort and needs dedicated theorem-proving expertise/time
  disproportionate to pursue casually alongside RTL/ISA work. Flagged as a
  real, distant aspiration, not a near-term milestone.
- **Software/compiler/OS ecosystem** (`SCALING_BARRIERS_RESEARCH.md` §7) —
  CHERI's own real, decade-plus, DARPA-and-UK-government-funded,
  dozen-committer history is the honest floor here. Not a milestone to
  start casually; the single largest real-world adoption barrier of
  anything in this document, correctly left as a distant, named, unstarted
  cost rather than quietly ignored.

## What I decided, in one sentence, and why

Build `OCL.C`/`OCS.C` next (Tier 1, item 1): it is the highest-leverage,
already-designed-for, currently-missing piece that makes Veda-Core's
capability model actually usable as a *system* rather than a register-only
demonstration, in both Sail (closing real parity with the mature CHERI
formal-model precedent) and RTL — and, per Part 3's own research, doing
that is a better use of effort right now than either chasing standard
RISC-V breadth (§3.1, low differentiation) or full theorem-proving rigor
(§2.9, disproportionate at this stage).
