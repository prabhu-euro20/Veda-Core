# VEDA_TRAP_QUARANTINE: hardware-native containment of the repeated-trap DoS class

## The gap, and why it's real for Veda-Core specifically

CHERIoT RTOS (Amar, Chen, Chisnall, Filardo, Laurie, Lefeuvre, Liu, Moore, Norton-Wright,
Seltzer, Tao, Watson, Xia, ACM SOSP '25 -- official, cross-industry-authored paper, read
in full) names, in its own §5.1.2 "Repeat attacks", a real, explicitly NOT-prevented-by-
capabilities residual risk, quoted verbatim:

> "However this cannot prevent DoS with a strong attacker that can repeatedly trigger
> traps to force a victim compartment to spend all its cycles micro-rebooting. This is
> fundamental to micro-reboots [Candea et al., OSDI'04], not to CHERIoT. Gecko's shadow
> compartments [Li, Wang, Zhang, USENIX Security 2025] could easily be implemented to
> address this."

This project's own compartment/trap model (Milestone 14's PCC bounding, Milestone 21's
universal PCC-reset-on-trap) has never been analyzed against this specific attack class.
This document closes that gap: real research into the two cited mitigations, an empirical
confirmation that Veda-Core is in fact exposed today, and a genuinely hardware-native
design -- not a copy of either cited precedent, both of which turn out to be software
mechanisms -- consistent with this project's own "hardware gets priority whenever it can
solve a security problem" standing philosophy.

## Research: what the two cited mitigations actually are (read in full, not summarized)

**Gecko** (Li, Wang, Zhang, "Software Availability Protection in Cyber-Physical Systems,"
USENIX Security 2025) is a **software** attack-recovery framework for embedded CPS, built
from LLVM/SVF static analysis plus linker-script sectioning on top of the ACES
compartmentalization project -- not hardware-capability-based; isolation is software
fault isolation (register-masking sandboxing via compile-time-inserted trampoline
"reference monitor" code). On attack detection it: (1) traces the malicious input back to
the compartment(s) it flowed through, using recorded inter-compartment dependency data;
(2) disables that compartment's entry point; (3) swaps in a pre-built **shadow
compartment** -- a simpler fallback module, either replaying the last known-good return
value or a hand-written Simplex-style safety fallback -- to answer future calls in its
place; (4) rolls back corrupted memory to an init-time checkpoint. Gecko never refuses
repeated traps -- it permanently reduces functionality by routing around the exploited
input path, so repeated attacks keep hitting the harmless shadow. This is real, published,
and a genuinely different value proposition (graceful degradation, not containment) from
what this document builds.

**Simpler, well-precedented alternatives** (read from their own official docs):
`systemd` (`man systemd.unit`, `StartLimitIntervalSec=`/`StartLimitBurst=`) and
Erlang/OTP's supervisor (`erlang.org`, default `MaxR`=1/`MaxT`=5s) both implement the
identical shape: a restart counter within a decaying time window; exceeding it refuses
further restarts (systemd) or escalates to the parent (Erlang) until explicitly reset.
Both are OS-scheduler/language-runtime patterns, not hardware.

**Real RISC-V hardware precedent, checked directly**: the ratified `Ssdbltrp`/`Smdbltrp`
"Double Trap" extension (docs.riscv.org, Aug 2024) proves hardware trap logic *can* react
to a repeated/nested-trap condition -- a sticky `mstatus.MDT` flag escalates a trap that
arrives while a handler is still active to the next privilege level or an RNMI state. This
is real, official, and load-bearing precedent that reactive trap-state hardware is a sound
category of mechanism -- but it is depth/re-entrancy-based (is a trap arriving *during*
another trap's handler?), not rate-based (has this compartment faulted N times?) -- a
different problem from the one this document addresses.

**Honest conclusion, stated directly**: none of the three real sources implement a raw
hardware counter+backoff for trap-triggered compartment re-entry. What follows is a
genuinely novel synthesis -- the rate-limit-then-refuse *pattern* common to systemd and
Erlang, realized in hardware instead of an OS scheduler, informed by (not copying) Gecko's
framing of the problem and Ssdbltrp's proof that reactive hardware trap-state tracking is
a sound category. It is explicitly **not** a Gecko-equivalent: it provides fail-stop
containment (bound the wasted cycles, refuse further entry), not Gecko's graceful
degradation (swap in a working fallback). That richer property remains a real, named,
future possibility at the software/scheduler layer this project's own Minimal OS Kernel
already has a natural home for -- not built here, not silently dropped either.

## Empirical confirmation (verify before deciding, not assumed)

Built `sail_tests/vc_repeated_trap_dos_probe.S`: an OCInvoke-entered, Length=0x0004
(one-instruction) compartment that hard-traps the instant it fetches its own second
instruction (the identical fault shape `vc_pcc_bounds_neg.S` already established and
verified); its trap handler unconditionally re-derives the sealed CODE/DATA pair and
re-invokes the SAME compartment again, 20 times, before taking a legitimate escape.
Result, traced instruction-by-instruction: all 20 trap-then-immediate-reinvoke round
trips completed with **zero** hardware interference -- no refusal, no slowdown, no
signal of any kind that this compartment had just faulted the exact same way 19 times in
a row. This is the real, confirmed baseline this design closes.

## Design

**New register: `veda_pcc_otype : bits(16)`.** Mirrors `veda_pcc_base`/`veda_pcc_length`'s
own existing role exactly -- the live compartment's identity, not just its bounds. Set to
`cs1.otype` on every successful `VEDA_OCINVOKE`/`VEDA_OCRETURN` (alongside the existing
`veda_pcc_base`/`veda_pcc_length` assignment); reset to `UNSEALED_OTYPE` (the same
existing "no compartment" sentinel `isSealedCap` already uses) wherever PCC itself resets
to unbounded (`veda_pcc_save_and_reset()`, and the exit-to-unbounded OCInvoke/OCRETURN
case, which naturally sets it to `UNSEALED_OTYPE` since that is `cs1.otype` in that case).

**New small hardware table: `veda_trap_tracker[TRAP_TRACKER_ENTRIES]`** (8 entries -- a
real, deliberate simplification matching this project's own established small-fixed-table
precedent, e.g. `TCM_ODT_ENTRIES=32` in the RTL). Each entry: `{otype: bits(16), count:
bits(4), valid: bool}`. A small associative (linear-scan) structure, not indexed directly
by the 16-bit otype -- the same real category of structure a small victim-cache or TLB
already is, appropriate at this scale (a handful of live/recently-faulted compartments in
a single-hart system, not tens of thousands).

**On every trap where a compartment was live** (`veda_pcc_length != VEDA_PCC_UNBOUNDED`):
look up `veda_pcc_otype` in the tracker; increment its count (saturating at 15) if found,
allocate a fresh entry (evicting the lowest-count entry if the table is full) if not.
**Real correction found during implementation, not assumed correct after writing it**:
the first version wired this into `handle_trap_extension` (Milestone 21's own universal
-reset chokepoint) alone, on the reasoning that it was "the" shared trap path. A fresh
negative test (`vc_repeated_trap_dos_neg.S`) empirically caught this as wrong: the
fetch-bounds-violation path this whole milestone's own repeated-trap probe exercises
(`ext_handle_fetch_check_error`, `postlude/step_ext.sail`) calls
`veda_pcc_save_and_reset()` *directly*, bypassing `handle_trap_extension` entirely --
confirmed by reading `ext_handle_fetch_check_error` and `ext_handle_data_check_error`
(the purecap data-access path) directly, both of which share this same real property.
`veda_pcc_save_and_reset()` itself -- not `handle_trap_extension` -- is the one true
chokepoint all three real trap-while-bounded paths share (this file's own pre-existing
header comment on `veda_pcc_save_and_reset()` already said so, in different words, before
this milestone ever touched it). Fixed by moving the record-fault call into
`veda_pcc_save_and_reset()` itself.
If the count reaches `VEDA_TRAP_QUARANTINE_THRESHOLD` (fixed at 3 for this milestone --
deliberately small, auditable, and exhaustively testable; a configurable-threshold CSR is
a natural, separately-scoped future step, not built here, mirroring how `veda_attr`'s own
configurability was added only after ODT-Populate's simpler fixed-descriptor form shipped
first), mark the entry `quarantined = true`.

**On every `VEDA_OCINVOKE`/`VEDA_OCRETURN`**, add one new check (after the existing
tag/seal/otype-match/perm chain, before the success path): if `cs1.otype`'s tracker entry
exists and is quarantined, hard-trap with a new cause code,
`VEDA_CAUSE_COMPARTMENT_QUARANTINED = 0b01001 // 0x09` (the next free slot, grep-verified
against every existing `VEDA_CAUSE_*` in `veda_bind_insts.sail` before picking it, this
project's own established convention) -- refusing entry outright, regardless of what the
calling software (a naive or compromised scheduler) attempts.

**Decay on clean forward progress, not a wall-clock window.** This project's own Sail/RTL
has no CLINT/timer wiring (confirmed, prior research), so a systemd/Erlang-style
time-window decay is not directly available -- and is not needed. A cleaner, fully
event-based rule falls out of the hardware's own real semantics: reaching ANY successful
`VEDA_OCINVOKE`/`VEDA_OCRETURN` from inside a live compartment is only possible if that
compartment did NOT fault since its last entry (a fault would have already forced
`veda_pcc_save_and_reset()` and redirected to the trap handler instead of reaching this
code path at all). So: at the *start* of `VEDA_OCINVOKE`/`VEDA_OCRETURN`'s own success
path, if a compartment was live (`veda_pcc_length != VEDA_PCC_UNBOUNDED`), reset the
*current* (pre-transition) `veda_pcc_otype`'s tracker count to 0 -- whether this
transition is a nested call into a new compartment or a return to unbounded, both are
"the old compartment behaved well enough to make real forward progress." This is simpler
than a timer, needs no new hardware clock, and directly answers systemd/Erlang's own
real "good behavior earns forgiveness" property with a mechanism this ISA already has all
the pieces for.

**Privileged clear, for genuine operator recovery**: a new CSR, `veda_trap_quarantine_clear`
(write-only; write an otype value to explicitly clear that entry's quarantine and count),
gated by the identical `veda_oda_authorized()` check ODT-Populate/Destroy already use
(Milestone 11) -- not a new authorization mechanism, reuse of an established one.

## Explicit, honest scope limits

- **Found while implementing, not assumed at design time**: the quarantine
  *check* is scoped to `VEDA_OCINVOKE` only, not `VEDA_OCRETURN`. OCInvoke's
  `cs1.otype`/`cs2.otype` is CSeal's own real per-compartment type-authority
  identity -- the correct key. OCRETURN's `cs1.otype` is always the fixed
  `VEDA_OTYPE_SENTRY` sentinel (shared by every sentry in the system, checked
  as part of OCRETURN's own existing validity check) -- reusing it as a
  quarantine key would have wrongly quarantined every distinct return target
  together the instant any single one faulted enough times, a real bug this
  document does not ship. OCRETURN's own destination has no otype-paired
  identity to track at all (often literally "return to the
  uncompartmentalized caller"). OCRETURN still correctly decays the
  compartment being LEFT, and resets `veda_pcc_otype` to `UNSEALED_OTYPE`
  (not `cs1.otype`) so a later fault is never misattributed to the shared
  sentry sentinel. A real per-destination-address quarantine key for
  OCRETURN is a plausible, separately-scoped future extension, not built
  here.
- This is fail-stop containment (bound the wasted cycles, refuse further entry after
  real, hardware-observed bad behavior), not Gecko's fail-operational graceful
  degradation (swap in a working fallback). Naming this distinction plainly, not
  overselling the mechanism's real reach.
- The quarantine threshold (3) and table size (8) are fixed constants for this milestone,
  not yet configurable -- a real, stated, deliberately-deferred future step.
- Multi-hart interaction is out of scope by the same construction every other Veda-Core
  mechanism in this line already is (`§2.7` -- this line is confirmed single-hart).
- This closes the specific "same compartment, repeatedly re-invoked after repeatedly
  faulting" pattern the CHERIoT paper names. It does not attempt a general theory of
  compartment misbehavior detection.
- **Found by adversarial RTL-mirror review, not the original design pass -- two real
  gaps, both fixed, see `TRAP_QUARANTINE_RESULTS.md` for full verification**:
  1. The original tracker-table eviction policy (plain global-minimum-count victim)
     let an attacker who controls several OTHER otypes drive them all to the
     threshold (count==3, itself already "quarantined") and force the table's next
     fresh fault to evict a genuinely quarantined VICTIM entry, silently
     un-quarantining it. Fixed on both Sail and RTL: a quarantined entry (count >=
     threshold) is never evicted in preference to a non-quarantined one. **One
     residual edge case remains, named explicitly rather than claimed closed**: if
     literally all 8 tracked entries are simultaneously quarantined (a strictly
     harder, much noisier attack -- it requires driving 7 OTHER distinct
     compartments to full quarantine too, not just occupying free slots), a fresh
     fault against a 9th, never-before-seen otype is simply left untracked for that
     one instance rather than evicting anyone. This does not weaken any EXISTING
     quarantine (the 8 already-tracked entries stay fully protected either way) --
     it only means the 9th otype's own fault-history isn't recorded while the table
     is in this extreme, already-loudly-visible state.
  2. `write_CSR(0x7C6, ...)` (the privileged quarantine-clear CSR) originally
     checked `cur_privilege == Machine` only, contradicting its own source comment
     (and this design doc's own original text) which said it should match
     ODT-Populate/Destroy's real `Machine | veda_oda_authorized()` pattern -- a
     genuine omission in the Sail reference, not a deliberate narrower choice
     (confirmed by grepping every other ODA-gated write in the project, all of
     which already use the OR-form). RTL's own independent implementation had
     already been built correctly against the documented intent; Sail was fixed to
     match it, restoring real parity.

## Verification plan

Sail-first (this project's own established sequencing), then RTL mirror. Positive: the
DoS probe (`vc_repeated_trap_dos_probe.S`, retargeted from a 20-iteration unmitigated
demonstration into a real negative test -- the loop must now be refused at iteration 3,
not silently permitted to 20) and a companion "good behavior earns forgiveness" positive
test (a compartment that faults twice, then makes real forward progress via a clean
return, then faults twice more -- must NOT be quarantined, proving the decay rule is
real, not merely present). Mutation tests: drop the quarantine check at OCInvoke (confirm
the DoS probe reverts to unmitigated), drop the decay-on-clean-progress reset (confirm
the good-behavior test now wrongly quarantines). Full regression required, zero new
failures, matching this project's own standing discipline throughout.
