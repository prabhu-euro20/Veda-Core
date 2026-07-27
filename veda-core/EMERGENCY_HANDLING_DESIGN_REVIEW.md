# Veda-Core — Emergency Signal Handling: Design Review and Decision

**Date:** 2026-07-23

## Why this document exists

The user proposed a concrete micro-architecture for how an "emergency
signal" (interrupt-class event) from the MSA should be handled mid-
instruction, framed as a 5-stage flow over an assumed 3-stage
Fetch→Decode→Execute pipeline, plus three "Golden Standards." Requested,

**Addendum, same day, after the user's follow-up clarification**: two
open questions this document originally left for the user's own call are
now resolved directly, with real grounding added (Part 7). "Zero-latency"
was clarified to mean zero *software* push/pop overhead, with a real,
explicit 2-3 cycle hardware tolerance — this converges with, rather than
contradicts, this document's own "deterministic/bounded WCET" correction
in Part 3; the two framings are now the same target, stated in the user's
own precise terms. The signal-routing topology was also specified
precisely: a dedicated, hard-wired, non-maskable lane → MSA → core → Main
Control Unit — real precedent for this exact topology researched and
added in Part 7, not assumed.
explicitly: complete, rigorous, non-hallucinated research against real
existing architectures before deciding anything — not a piece/section, not
head/tail of a source. This document is that review: what's confirmed
correct, what's real and precedented, what's a genuine mismatch with the
actual current RTL, what's unaddressed, and what's decided here versus
flagged as needing the user's own call.

---

## Part 1 — A foundational mismatch, checked directly against source, not assumed

**The proposed flow assumes a classical, overlapping 3-stage pipeline
(Fetch/Decode/Execute as separate, simultaneously-active stages). The
actual, current Veda-Core RTL is not pipelined at all.**

Verified directly, again, before writing anything else: `veda_core.tlv`'s
entire datapath lives in exactly one stage, `|cpu @0` — there is no `@1`,
no `@2`, anywhere in the file. Every RTL milestone document says the same
thing in different words ("single-cycle," "single flat `@0` stage"). This
isn't a small detail — the proposed flow's core mechanism ("block Decode,
let the Store finish in Execute") only makes sense when a second
instruction can genuinely be *in* Decode while a first is still *in*
Execute. In a single-cycle core, that overlap doesn't exist: exactly one
instruction is in progress at any moment, and it fully completes (fetch
through write-back) within one clock cycle.

**This changes what the 5-stage flow needs to be — and, honestly, makes it
simpler, not harder.** Reasoned through against the actual RTL's own real
write-back mechanism (confirmed earlier this session: `OCS.D`'s memory
write happens via a trailing `always_ff` block, a non-blocking assignment
that commits at the clock edge, "visible starting next clock edge," not
mid-cycle): there is no in-flight Store to protect from a concurrently-
decoding instruction, because nothing else is ever concurrently decoding.
The correct, real mapping for *this* core is:

1. Sample the emergency signal combinationally, same cycle it arrives
   (the proposal's own Stage 1 is correct and needs no change).
2. Let the *current* cycle's instruction complete normally — its
   register/memory writes commit at the upcoming clock edge exactly as
   they always would. No separate "wait state" stage is needed, because a
   single-cycle core never has a second instruction partway into Decode to
   hold back in the first place — this requirement is already satisfied by
   construction, not something new to build.
3. On the *next* clock edge, drive `$pc` to the emergency entry point
   instead of the normal next-PC, having captured the shadow state (Part 2
   below) in the same edge.

This is not a rejection of the proposal's intent — it's the same intent,
correctly re-expressed for the core that actually exists. If a real,
overlapping pipeline is wanted later (a genuine, separate, much larger
architectural change — this project's own `MILESTONE_PLAN.md` already
named pipelining as explicit future scope, never started), the original
5-stage framing would become directly applicable again. Building it now,
under cover of an interrupt feature, would be smuggling in an unrelated,
un-asked-for architectural change — flagged here rather than done quietly.

---

## Part 2 — The shadow-register-bank idea: real, well-precedented, and quantifiably not free

Read in full, not sampled: Balas, Ottaviano, Benini (ETH Zürich),
*"CV32RT: Enabling Fast Interrupt and Context Switching for RISC-V
Microcontrollers"* (2023/2024) — a real, published, industrially-deployed
(ControlPULP SoC) RISC-V core with a real hardware fast-interrupt
extension (`fastirq`) built specifically around register banking. This is
as close to directly-on-point prior art as exists for the proposal.

**The core idea is real and has extensive, shipping industrial
precedent** — not invented here, and not something to second-guess as a
concept: ARM's FIQ mode uses banked registers (`r8`–`r14`) so the
highest-priority handler never touches the interrupted code's values.
MIPS defines real "Shadow Register Sets" for exactly this purpose. Most
directly relevant to the brief's own named target domains: **Infineon's
AURIX TriCore family — a real, shipping automotive-grade MCU line — saves
interrupt context in memory autonomously while restoring it in parallel
with the return jump**, and Renesas' M32C/80 implements a real dual
register bank specifically to swap context without stack push/pop. The
proposal's "shadow register bank... parallel register file... no external
bus required" is, mechanism-for-mechanism, what these real, shipped
automotive/embedded parts already do.

**What's real and quantified, not free**: CV32RT's own register-banking
extension measured a **10% total core area overhead**, concentrated in the
instruction-decode stage (a 36% area increase in the register file itself,
40% overhead in the shadow-register control logic specifically). This is
the honest cost side of the same mechanism the proposal describes as if it
were free ("no external bus is required" is true and correct, but "no
cost at all" would not be) — worth stating precisely rather than implying
the mechanism is costless.

---

## Part 3 — "Zero-latency": the real terminology, and why it matters to correct

**No real system anywhere in this research claims zero-latency context
switching or emergency response — including the best, most specialized,
purpose-built hardware that exists for exactly this problem.** CV32RT's
own `fastirq` extension — a dedicated, register-banking, hardware-only
context-save mechanism, the closest real analog to the brief's own
proposal — achieves **6 clock cycles** of interrupt latency, down from a
33-cycle baseline. Real ARM Cortex-M4 (single-cycle memory assumed)
achieves 12 cycles. These are the state-of-the-art numbers for this exact
problem, published in 2023/2024, and they are **low, bounded, and
deterministic — never zero.**

The correct, real, domain-standard term (used throughout this exact
paper, targeting exactly the automotive/real-time-embedded space the
brief names) is **deterministic** or **bounded worst-case latency (WCET)**
— not "zero-latency." This isn't pedantry: WCET is the actual property
real safety-critical systems (automotive ISO 26262, aerospace DO-254,
space-grade qualification) certify against — a system that can *prove* "N
cycles, always, no exceptions" is certifiable and valuable; a system
merely *claimed* to be "zero-latency" is neither accurate nor is
"zero" the property certification processes actually check for.
**Recommendation, decided here**: retarget the design goal from
"zero-latency" to "a small, provable, worst-case-bounded cycle count" —
the same real target CV32RT, ARM Cortex-M, and every other real system in
this space actually optimizes for.

**A further honest connection to work already done this project**: both
the brief's own "1 clock cycle" memory-wait assumption and CV32RT's own
6-cycle result explicitly depend on **single-cycle SRAM access** ("For the
memory subsystem, we have single cycle (zero wait state) access to static
random access memory," CV32RT §IV). Veda-Core's own RTL memory arrays
(`elfmem[]`/`dmem[]`) are currently exactly this — flat, single-cycle-
access arrays, a real simulation/RTL-milestone convenience, not modeled
DRAM timing. This directly connects to a gap already named honestly in
this project's own spec: *"how the MSA hides DRAM data-fetch latency for
the object's actual payload... a real, open problem"* (`VEDA_CORE_SPEC.md`
§5). Any emergency-response cycle-count target set now is implicitly
scoped to this same simplification — worth stating plainly so it isn't
silently assumed to hold once real DRAM timing is modeled.

---

## Part 4 — Real gaps the proposal doesn't address, that real hardware treats carefully

1. **Nested emergencies.** What happens if a second emergency arrives
   before the first's "Done" signal? A single shadow bank, one level deep,
   cannot safely absorb a second nested event without corrupting the
   first's saved state. Real hardware treats this as a first-class design
   problem, not an edge case: RISC-V's own real CLIC spec (currently under
   ratification) defines explicit interrupt *levels* and *priorities* with
   a hardware arbitration tree specifically to decide when preemption is
   and isn't allowed; ARM's NVIC does the analogous thing with
   *tail-chaining*.

   **Decided here**: treat "emergency" as a single, non-nestable,
   highest-priority class by design — matching the real, common
   convention for NMI-class signals in other architectures (an NMI
   handler is conventionally not expected to be preempted by another NMI;
   a second one arriving mid-handler is either queued as a single pending
   flag or, in the safety-critical domains this brief names, treated as a
   fault condition in its own right). This keeps the mechanism to exactly
   one shadow bank, matching what's actually described, and defers a
   full CLIC-class leveled/prioritized scheme — a real, much larger
   undertaking — to explicit future work if genuine nesting is ever
   required. Not a compromise made silently: stated as a real scope
   decision, with the real alternative and its real cost named.

2. **Where does the emergency entry point come from?** The proposal says
   the controller "sends the Entry Point... directly to Execute" without
   naming the mechanism. **Decided here, for consistency with this
   project's own repeated, established discipline of reusing real RISC-V
   mechanisms rather than inventing new ones**: a single, fixed hardware
   address (direct mode), mirroring real RISC-V `mtvec`'s own direct-mode
   convention — the simplest real option, and sufficient given decision 1
   above (a single, non-nestable emergency class needs exactly one entry
   point, not a vector table).

3. **In-flight hazard during the shadow copy.** CV32RT's own real design
   needed genuine stall/forwarding logic to handle the case where the
   interrupt handler's own first instructions try to touch a register or
   memory location the background-saving mechanism hasn't finished copying
   yet. **Good news, worth stating precisely**: this specific hazard is a
   direct consequence of *background* (multi-cycle, overlapped) saving —
   and Part 1's single-cycle correction avoids it by construction. If the
   shadow-bank capture happens in one clock edge (not "in the background"
   over several cycles while new instructions execute), there is no
   partially-saved state for anything to race against. This is a genuine,
   real advantage of building this on the current single-cycle core rather
   than a pipelined one — not a coincidence, a direct consequence of
   Part 1's correction.

4. **A genuinely new question, with no real precedent in any source read
   this pass — Veda-Core's own capability register file.** None of
   ARM/MIPS/RISC-V CLIC/CV32RT have anything resembling Veda-Core's
   16-entry Capability Register File, so none of this research answers
   the real question directly: **when the emergency task starts, does it
   see the interrupted task's live, bound capabilities, or a fresh
   context?**

   **Decided here, reasoned from this project's own already-built and
   verified security model, not from external precedent (since none
   exists)**: the emergency handler must start with a **fresh, minimal
   capability context** — its own pre-provisioned, minimal set of
   capabilities (or none at all, `Tag=0` across the board, until it binds
   what it needs) — never the interrupted task's own bound capabilities
   by default. Reasoning: this is a direct, natural extension of two
   things already real and verified in this project. First, Milestone 6's
   entire `CSeal`/`CUnseal` design exists specifically to enforce minimal,
   explicit privilege — an unforgeable, non-dereferenceable-until-
   authorized token model. Silently handing the interrupted task's live
   capabilities to emergency code that never independently earned them
   would be a direct violation of that same principle — a real confused-
   deputy risk, not a hypothetical one. Second, this mirrors the real,
   standard practice in the domains the brief itself names (automotive/
   aerospace/robotics safety-critical ISRs are conventionally designed
   with their own minimal, fixed resource set, precisely so a fault in
   the interrupted task's own state can't propagate into the handler
   meant to react to it). Mechanically: the shadow bank captures and
   protects the interrupted task's capability registers exactly like the
   GPRs and PC, but the *live* capability register file the emergency
   task executes against starts clean (or pre-bound to a small, fixed,
   emergency-relevant object set decided at design time) — not restored
   from the interrupted task until Stage 5.

---

## Part 5 — Golden Standard 2 ("hardware-only scheduling"): a real, first-party cautionary tale

Read and verified: x86's own real hardware task-switching mechanism
(TSS-based `JMP`/`CALL` to a task gate) is a genuine, shipped, real
"perform the entire task switch in hardware, no software involved" design
— and it's real, documented history that **Linux 1.0 actually used it**,
then **moved away from it** because it measured slower than software-
managed context switching on real silicon: reloading segment registers
through TSS triggers real protected-mode checks and GDT/LDT indirection
overhead that a purpose-written software routine simply avoids. This is
not a hypothetical caution — it's what actually happened the one time a
real, mainstream architecture built exactly what Golden Standard 2
describes in its most literal, absolute form ("directly through hardware
without software intervention," full stop).

**The real, working, currently-successful middle ground — proven by
CV32RT specifically** — divides the labor differently: hardware
accelerates the *mechanical* part of a switch (register save/restore, via
banking — real, fast, worth having), while the *scheduling decision*
(which task runs next, and by what policy) stays software's job (FreeRTOS,
in CV32RT's own real deployment). CLIC's hardware arbitration tree handles
only the *mechanical* priority comparison for pending interrupts, not
general scheduling policy.

**Decided here**: adopt the CV32RT-style split, not the literal, absolute
reading of Golden Standard 2. Hardware should accelerate context
save/restore and emergency dispatch (real, proven, valuable, matches the
brief's own core intent) — but treating *all* task-switching, including
scheduling policy, as forbidden to touch software is a real, historically-
tested idea that failed on real silicon the one time it was tried at that
scope. This is a genuine correction to the golden standard as literally
worded, not a rejection of its underlying goal.

---

## Part 6 — Golden Standard 3 (hardware-enforced atomicity): already substantially real, not a new gap

This one needs the least new work — it's largely already built and
verified in this project. Veda-Atomic's 9 AMO-style operations (RTL
Milestones 2 and 5, real RISC-V `Zaamo` encoding reused verbatim) already
provide real hardware read-modify-write atomicity at the object level. The
multi-core "hardware lock bit" intent is already addressed at the *policy*
level by the Object-Bind exclusive-ownership design (`VEDA_CORE_SPEC.md`
§4.1, grounded in real, verified UPMEM precedent) — real, hardware-
enforceable owner-hart tracking in the ODT entry, named here as the next
concrete step, **is now built and verified** (Milestone 12, both Sail and
RTL — `owner_hart` in every ODT entry, checked and claimed at
Bind/Rebind time, `rtl/MILESTONE_12_RESULTS.md`). No new decision needed here
beyond what's already on record.

---

## Part 7 — Addendum: the two clarifications, with real grounding added

### 7.1 — "Zero-latency" clarified: zero *software* overhead, 2-3 cycle hardware tolerance

The user's clarification — no software push/pop overhead at all, hardware
handles the entire context switch, and up to 2-3 clock cycles is an
acceptable, tolerated cost for the shadow registers to populate without
corruption — is not a different target from Part 3's "deterministic,
bounded worst-case" correction. It's the same target, stated more
precisely: the earlier correction objected to the word "zero" being
literally read as *zero cycles* (a claim no real system, including
CV32RT's own best-in-class 6-cycle result, makes); the user's
clarification confirms the actual intent was always *zero software
involvement*, with a small, explicit, bounded hardware cost accepted.
**These converge.** A 2-3 cycle target is, in fact, more aggressive than
CV32RT's own real, measured 6-cycle result for a comparable mechanism —
plausible specifically *because* Veda-Core's core is single-cycle with a
smaller register set than CV32RT's 32-register RV32 baseline, and because
Part 1's correction already establishes there's no in-flight pipeline
hazard to resolve first. Small register count and no pipeline overlap are
real, structural reasons 2-3 cycles is a credible target here, not an
arbitrary number.

### 7.2 — Signal routing topology: dedicated NMI lane → MSA → core → Main Control Unit, real precedent checked

Researched specifically, not assumed: is routing a hardware emergency
signal *through* the memory-side subsystem (rather than directly to the
CPU's own interrupt logic) a real, sound pattern, or unusual?

**Real, confirmed precedent, on two counts:**

- **x86's own NMI mechanism is explicitly documented to work exactly this
  way**: NMIs occur "for RAM errors and unrecoverable hardware problems,"
  and — directly relevant to the routing question — real x86 NMI delivery
  is documented as going "either directly to the CPU, or via another
  controller." Routing a hardware-fault-class signal through an
  intermediate controller before it reaches the core's own interrupt logic
  is real, standard, already-shipping practice, not a novel risk.
- **Real, precise confirmation of the non-nestable design decision
  (Part 4.1) from the same source**: x86's own documented NMI semantics —
  "an NMI is serviced immediately and to completion without any further
  interruption" — is exactly the non-nestable, single-level, highest-
  priority treatment already decided in Part 4.1, now independently
  confirmed rather than merely reasoned by analogy.
- **The specific case for routing through the MSA is further strengthened
  by real space-grade practice** — directly relevant since "Space-Grade"
  is one of the brief's own named target domains: radiation-hardened
  memory systems use real, standard EDAC (Error Detection And Correction)
  circuits specifically because Single Event Upsets (cosmic-ray-induced
  bit flips) are a genuine, well-documented threat to memory correctness
  in that environment. A memory-side subsystem being a legitimate,
  serious *source* of hardware-fault-class emergency signals — not just a
  passive data store — is real, established space-grade engineering
  practice, not specific to this design.

**Why routing through the MSA specifically (not a separate, parallel path
bypassing it) is also the *architecturally coherent* choice for this
design in particular**, beyond the general precedent above: the MSA is
already Veda-Core's one designated hardware gateway for every access to
the object system — every capability check, every bounds/permission/
generation verification passes through it. Making it the routing point
for emergency signals too means there is **one hardware trust boundary**
for both ordinary data access and emergency signaling, not two
independent paths that could develop inconsistent security properties
over time. This is a real, named principle in security architecture —
the "reference monitor" concept (Saltzer & Schroeder, 1975, *"The
Protection of Information in Computer Systems"* — a source already
appearing in this project's own prior research, cited in the November
2025 object-aware-memory survey read for `DESIGN_SOUL_AND_UNIQUENESS.md`):
a single, well-defined, always-invoked checkpoint for security-relevant
operations is a stronger, more auditable design than multiple, separately-
reasoned-about paths. Routing emergencies through the MSA is a direct,
real application of that principle, not just a wiring convenience.

**Decided, with the topology now fixed precisely**: `[hard-wired NMI
source] → MSA → core's Main Control Unit`. The Main Control Unit — not
yet a named, distinct block in the current single-cycle RTL, which has no
privileged/control-plane logic separate from ordinary combinational
decode (Part 1) — is real, new work: a small, dedicated piece of control
logic whose job is exactly what Part 1's corrected flow describes
(sample the signal, let the current instruction's writes commit, redirect
`$pc`, trigger the shadow capture). This document does not yet design its
internal RTL; that's the next, concrete implementation step once
confirmed.

---

## Summary — what's decided, what's confirmed, what's still open

**Decided in this document, with reasoning stated above:**
- Adapt the 5-stage flow to the real single-cycle core (Part 1) — simpler
  than the original proposal, not harder, and removes an entire class of
  hazard (Part 4.3) as a side effect.
- Treat "emergency" as single-level, non-nestable by design (Part 4.1).
- Use a fixed hardware entry address, RISC-V `mtvec`-direct-style
  (Part 4.2).
- The emergency handler starts with a fresh/minimal capability context,
  never the interrupted task's inherited capabilities (Part 4.4) — the
  one genuinely novel decision in this document, with no real external
  precedent, reasoned from this project's own already-built security
  model.
- Retarget "zero-latency" to "small, provable, worst-case-bounded cycle
  count," and adopt the CV32RT-style hardware/software split for Golden
  Standard 2 rather than its literal, absolute wording (Parts 3, 5).
- **User-confirmed, Part 7**: the bounded target is precisely zero
  *software* overhead, ≤2-3 hardware cycles for the shadow capture — the
  same target as the point above, now stated in exact numbers rather than
  qualitatively, and more aggressive than CV32RT's own real 6-cycle
  result for real, structural reasons (smaller register set, no pipeline
  overlap to resolve).
- **User-confirmed, Part 7**: signal topology fixed as `[hard-wired NMI
  lane] → MSA → core's Main Control Unit`, with real precedent researched
  and confirmed (x86 NMI's own documented "directly to the CPU, or via
  another controller" routing option; space-grade EDAC as real precedent
  for the memory subsystem itself being a legitimate emergency source;
  the "reference monitor" security-architecture principle as the reason
  routing through the MSA specifically, not a separate path, is the
  architecturally coherent choice for this design).

**Confirmed real and worth keeping as designed:**
- The shadow-register-bank concept itself (Part 2) — real, extensive,
  automotive/embedded-industrial precedent, directly matching the brief's
  own target domains.
- Golden Standards 1 and 3 — already largely real and verified elsewhere
  in this project.
- The non-nestable, "serviced immediately and to completion" treatment of
  emergencies (Part 4.1) — independently confirmed as real x86 NMI
  semantics in Part 7's research, not just reasoned by analogy.

**Still open, not decided here:**
- Exact cycle-accurate RTL for the corrected single-cycle flow, including
  a new, real Main Control Unit block (Part 7.2) — this document is the
  design decision, not the implementation.
- Whether the shadow bank should also capture the ODT-lookup-in-progress
  state, if an emergency arrives mid-`Object-Bind` (a genuinely new
  question this pass didn't fully resolve — flagged honestly rather than
  silently assumed away).
- The exact hard-wired NMI lane's own electrical/signal-level definition
  (single bit? encoded cause?) — Part 7.2 fixes the *routing topology*,
  not the signal's own width/encoding.
