# CRF Register-Exhaustion Wall: Design Decision (globals-protection + scheduler collision)

> **Update**: this document's own register-file-organization reasoning (below, "option 1") was a
> one-line dismissal reached under single-register-conflict pressure, not a full architectural review.
> `CRF_ARCHITECTURE_ALIGNMENT_VERDICT.md` runs that full review (was the 16-entry, separate CRF a
> reasoned departure from real CHERI-RISC-V's own merged-register-file convention, or an unexamined
> default?) and reaches the same conclusion — don't widen/merge — but for a fuller, now-primary-source
> -grounded reason: literal CHERI merging is causally tied to CHERI Concentrate compression, a
> precondition Veda-Core's uncompressed 128-bit capability format does not meet. The chosen mechanism
> below (scheduler save-area spill/restore) is **confirmed, not superseded** by that review — it is
> independently the architecturally correct fix regardless of the register-file-organization question.
> Read `CRF_ARCHITECTURE_ALIGNMENT_VERDICT.md` for the full reasoning; this document's own "option 1"
> reasoning below should be read as superseded by it.

## The problem, restated precisely

Milestone 13's own register audit (`TOOLCHAIN_MILESTONE_13_RESULTS.md`, "Register plan") found every
one of the 16 CRF registers already has a real, load-bearing use in this project's own `.S` corpus.
Direct re-confirmation against `runtime/veda_sched_asm.S` this session shows exactly which registers
the scheduler consumes and how: `C4`/`C5` hold the sealed CODE/DATA capabilities for the SCHEDULER
compartment (established once, live for the program's life); `C6`/`C7` are the two threads' own
save-area capabilities, explicitly bound once and never rebound (`:99,109`, "permanent bind"); `C8` is
the thread-index capability (`:119`, also permanent); `C9` is the return-sentry source (`:129`); `C11`
is rebound fresh on **every single resume** (`:268,277`, `veda.bind c11, a0` — a genuinely transient,
per-switch register, not a stable one); `C12` is the OSpecialRW discard target during TSC re-priming at
every resume (`:262,271`); `C13` is the type-authority register at scheduler init only. Milestone 13
reused `C11` for its persistent table-base register — safe only because Milestone 13's own test never
invokes the scheduler. Any real program combining both mechanisms breaks the instant the scheduler
resumes a thread: `veda.bind c11, a0` at `:268`/`:277` silently overwrites the table-base capability
with a fresh per-thread CODE capability, and every subsequent `ocl.c` against the (now wrong)
table-base register either dereferences garbage or trips a tag/bounds violation on the next global
access.

## Chosen mechanism: extend the scheduler's per-thread save-area to spill/restore the table-base capability at every switch — software only, no new Sail/RTL

**Decision**: treat the table-base capability exactly as CHERIoT treats every live capability register
at a context switch — nothing is permanently exempt from the switcher's own save/restore cycle. Add one
more 16-byte slot to each thread's save-area (`save_area_0`/`save_area_1`, currently three `.dword`s —
saved PC, saved base, saved length, `:294-303`) for the table-base capability, and have the switcher's
own save/restore blocks (`yielding_0`/`1`, `:219-233`; `resume_0`/`1`, `:261-278`) `ocs.c`/`ocl.c` it
alongside the fields already spilled there. This is the literal instantiation of the CHERIoT precedent
the cheri-crf-precedent track found: "the switcher spills the ENTIRE live capability-register set to a
per-thread trusted-stack register-save area... rather than reserving any register as a permanently-live,
switch-surviving binding" (CHERIoT-Platform/cheriot-rtos, `docs/architecture.md`) — the opposite of what
Milestone 13's C11 reuse currently and unsafely assumes.

**Why this, not the other two real options the tracks surfaced:**

1. **Widen the CRF to real CHERI's merged-register-file convention (32 registers, one per GPR)** —
   rejected outright. CHERI's merged file is a full ISA change (capability metadata folded into every
   GPR); Veda-Core's separate 16-entry CRF is architecturally closer to CHERI-MIPS's abandoned split
   file. Widening `vcapidx` past its hard 4-bit field (`veda_types.sail:24-25`) touches every
   CRF-referencing instruction's encoding — Object-Bind, OCL/OCS.C/.D, OCA, CSetBounds(Exact),
   OSpecialRW, CSeal/CUnseal, OCInvoke/OCRETURN — the same scale of change Milestone 13's own DESIGN doc
   already ruled out for a mere 17th slot (`TOOLCHAIN_MILESTONE_13_DESIGN.md:136-138`). Not proportionate
   to a one-register conflict.

2. **A 4th SCR ("GDC")** — mechanically clean in isolation (zero CRF cost; 29 of 32 `veda_scr` encodings
   free; a new arm can carry zero crossing-side-effects, since SSC's OCInvoke/OCRETURN clear is
   hardcoded per-SCR, not a generic sweep, per own-scr-semantics) — but its real cost lands where this
   collision needs a fix least: **every** global access site would pay +1 instruction
   (`ospecialrw <scratch>, gdc, x0`) before every existing `ocl.c`, for the program's entire life, versus
   the spill/restore cost, paid only at thread-switch boundaries (already a heavier trap round-trip
   through `OCInvoke`/`OCRETURN`). own-scr-semantics also flags OSpecialRW's `cur_privilege == Machine`
   gate (`veda_cap_insts.sail:700`) as an unresolved cost for GDC — every compartment-body access would
   need M-mode or a carve-out, untested anywhere in the corpus, possibly unverifiable given the
   S/U-mode-disabled Sail config. The spill/restore approach touches no privilege boundary at all.

3. **Defer, unfixed** — rejected: this is not speculative. Milestone 13's own results doc already names
   it "a real, concrete resource-exhaustion wall for the next milestone that needs to combine the two,
   not a hypothetical concern" (`TOOLCHAIN_MILESTONE_13_RESULTS.md:167`).

## Scope of the fix

Purely a software/convention change. No Sail file, no RTL file, no new instruction — `OCL.C`/`OCS.C`
(Milestone 7) already exist and are already load-bearing in the switcher for the PC/base/length spill.

- **`runtime/veda_sched_asm.S`**: extend `save_area_0`/`save_area_1` to reserve one 16-byte capability
  slot for the table-base register. Add one `ocs.c`/`ocl.c` pair to each of the four switch-path blocks
  that already touch the save area (`yielding_0`/`1` on save, `resume_0`/`1` on restore) — four new
  instructions total, symmetric with the existing PC/base/length pattern.
- **`veda-core/compiler/VedaShadowPropagation.cpp`** / runtime helper chain: unchanged — the table-base
  register is still `OCL.C`'d directly at every access site exactly as Milestone 13 already does.
- **Register choice**: this decision does not itself pick which physical register (`C11` or a freshly
  audited alternative) holds the table-base capability — it makes whichever register is chosen safe
  under the scheduler by making it spillable, the same way `C6`/`C7` are already safe. A fresh grep
  audit (the discipline Milestones 11/12/13 each did before committing to `C15`/`C13`/`C11`) is still
  required before implementation.
- **Follow-on**: `Object_ID`s 165/166's own `Length` (`veda_sched_asm.S:94,104`) must grow to cover the
  new slot.

This is smaller in scope than either rejected alternative: no privilege-gate question (unlike GDC), no
encoding change (unlike CRF widening) — in the same size class as Milestone 13's own `OCL.C`/`OCS.C`
reuse.

## Verdict: mechanism decided now; implementation waits for a real verification target

This project's discipline is not to build ahead of a real, concrete test scenario, and no test program
in the corpus yet needs both globals-protection and the scheduler together — so this fix currently has
no verification target of its own, and per that same discipline (already held to across Milestones
11/12/13) it should not be implemented yet: a hand-written `.S` change to `veda_sched_asm.S` with no
test exercising the new spill/restore path is exactly the kind of unverified addition this project has
consistently refused to make. What changes today is that the register-exhaustion problem stops being an
open, unresolved question — the mechanism is chosen, cited, and ready to implement the moment a real
trigger exists. Three things argue for treating it as a live, near-term addendum rather than a distant
"someday" risk:

1. The wall is demonstrated and already documented (`TOOLCHAIN_MILESTONE_13_RESULTS.md:163-167`), not a
   "might need this someday" concern.
2. The fix is genuinely small — four instructions in one file, symmetric with an existing pattern —
   smaller than either rejected alternative's real cost (GDC's privilege-gate question; CRF widening's
   full-encoding sweep).
3. Leaving it unfixed means the next milestone that needs both mechanisms inherits a silent correctness
   bug (C11 corruption) rather than an already-closed gap — the same unchecked-assumption failure mode
   Milestone 12's own alloca-region-collision bug already demonstrated is real, not theoretical, for a
   structurally similar reason.

**Recommendation**: build the save-area extension as a small, standalone addendum (not a full new
milestone) the next time either (a) a scheduler-combined-with-globals test program is actually needed,
or (b) Milestone 13's own register choice is grep-audited and finalized — whichever comes first. Do not
defer it silently past that point: it is cheap enough that "small addendum now" dominates "named risk
plus a larger fire-drill later." This fix falls below this project's own bar for "needs a concrete test
scenario to justify building," not above it.

## Open risks, stated honestly

- **RESOLVED (`TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md`): the table-base register is `c11`,
  finalized.** The fresh grep audit this document called for found `c11`'s own dual role (persistent
  table-base vs. the switcher's transient resume-jump scratch) was the real conflict — closed by moving
  the *transient* resume-jump role onto `c12` (a provably dead `OSpecialRW` discard-sink already in this
  file, not `c10` as first tried — `c10` turned out to also be claimed by Milestone 13's own per-access
  helpers). `c11` is now exclusively the persistent register.
- **RESOLVED: the save-area `Object_ID`s' own `Length` update is specified and implemented** —
  `0x0020`→`0x0030` (32→48 bytes), see Milestone 14's own results doc for the exact byte layout.
- **Only two threads are modeled** — the scheduler's current round-robin scope (`Object_ID`s 160/161) is
  inherited unchanged, not extended. Still true, unchanged by Milestone 14.
- **RESOLVED: verified by a real combined test**
  (`compiler/veda_sched_global_combo_entry.S`/`_threads.S`/`_demo.c`) — thread A mints/uses a shared
  table-base capability, yields, thread B runs, thread A resumes and the table-base capability is
  confirmed intact via a real checkable value, exactly the test shape this document called for. Full
  regression, mutation-tested; see `TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md` for complete results.
- **New, unplanned finding surfaced during implementation**: `save_area_0`/`save_area_1` had to move
  back out of `.tcm_scratch` into ordinary `.data` — Sail cannot round-trip a capability's tag through
  `TCM_SCRATCH_BASE` (a real, empirically-confirmed Sail/RTL asymmetry, since Sail has no TCM concept at
  all). Recorded in full in Milestone 14's own results doc and in `sail_tests/vc_ocsc_bind_spill_restore_roundtrip.S`.
- **The tracks' own gaps carry forward.** cheri-crf-precedent could not find any official CHERI source
  discussing a persistent, program-lifetime capability deliberately exempt from a scheduler's own
  spill/restore cycle — the shape Milestone 13's C11 reuse currently assumes. This decision resolves that
  by *not* exempting it, converging on the one documented precedent (CHERIoT: spill everything) rather
  than inventing a new persistence category. own-scr-semantics' finding that a 4th SCR is mechanically
  viable is not disputed — it is weighed and set aside here on a cited per-access-cost/privilege-gate
  basis. If a future workload is dominated by extremely hot-loop global access with infrequent thread
  switching, that tradeoff should be revisited: own-scr-semantics' own analysis (GDC pays its tax per
  access, spill/restore pays per switch) would favor the opposite conclusion under that access pattern.
  This recommendation is conditioned on typical access/switch-frequency shape, not proven optimal for
  every workload.
