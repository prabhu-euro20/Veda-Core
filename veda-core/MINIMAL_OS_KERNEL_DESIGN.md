# Veda-Core Minimal OS Kernel — Milestone A: the Switcher Pattern

**Status**: Sail-side Milestone A implemented and verified (44/44 self-check regression, zero
regressions on the pre-existing 42-test corpus, both new switcher-specific tests passing).
**Sail-side Milestone B (the real, cheap asymmetric exit) is also now implemented and verified —
see `MILESTONE_B_RESULTS.md`**: the reserved-otype sentry mechanism (`VEDA_OTYPE_SENTRY`,
`CSealEntry`, `OCRETURN`), 52/52 full regression. That pass surfaced a real, necessary refinement
to this document's own Section 2/Finding 2 below: a bare `OCJALR` extension cannot deliver a cheap
cross-compartment exit, because `veda_pcc_base`/`veda_pcc_length` narrowing is exclusively
`OCInvoke`'s (now also `OCRETURN`'s) job in this architecture — `MILESTONE_B_RESULTS.md`'s own
opening section states the corrected finding in full; Section 3 below is otherwise unchanged.
RTL mirrors for both Milestone A and Milestone B remain explicit, separate, not-yet-started
follow-ons.

---

## 1. The question this document actually answers

The toolchain (Milestones 1-9) and the security-audit series (Milestones 19-22, Sail and RTL)
are both complete. The next item in this project's own already-agreed sequencing is a minimal OS
kernel for Veda-Core. Before writing any code, the real question needed answering first: **what
does a hardware-native, capability-only OS kernel actually need to look like, grounded in real
CHERI/CHERIoT precedent rather than invented from scratch?** This required reading, in full, two
official primary sources — not fragments, not summaries:

- **CHERIoT RTOS's own architecture document** (`github.com/CHERIoT-Platform/cheriot-rtos`,
  `docs/architecture.md`, 109 lines, downloaded and read complete via direct raw-file fetch after
  the web-fetch summarization layer's own quote-length limit made a full read impossible through
  that path).
- **The CHERI ISA specification** (UCAM-CL-TR-987, Version 9, September 2023, University of
  Cambridge, 523 pages), read in full for every section load-bearing to this design: §2.4.8
  "Operating-System Support," §3.8-3.11 "Protection-Domain Transition with CInvoke" through
  "Traps, Interrupts, and Exception Handling," the real `CInvoke`/`CJAL`/`CJALR`
  instruction-reference semantics, and §9.18-9.22 "Detailed Design Rationale."

## 2. Real findings that changed/refined the design, stated honestly

**Finding 1 — real CHERI does not mandate an asymmetric exit.** Earlier project research into
CHERIoT's real implementation found compartment return is asymmetric (heavy 2-capability
`CInvoke` in, light 1-capability sentry-checked exit out), and the explicit direction was to
prefer this for the OS kernel. The core CHERI ISA spec itself (p.100) shows this is
software-defined, not architecturally mandated: *"the semantics of secure message passing or
invocation are software defined... allowing different userspace runtimes to select... the
specific semantics their programming model requires."* CHERIoT's asymmetric switcher is one real,
validated instantiation of this freedom — not "the CHERI way" in any exclusive sense. Veda-Core's
current symmetric double-`OCInvoke` design (RTL Milestone 22, `MILESTONE_22_RESULTS.md`) is
equally spec-compliant.

**Finding 2 — real CHERI's lightweight exit is cheap for one specific, concrete reason: a
hardware-reserved otype.** `CJALR`'s real semantics: every ordinary `CJALR` call automatically
mints a fresh sentry — `C(cd) = sealCap(linkCap, otype_sentry)` — using a hardware-reserved otype
value (`2^XLEN - 2`, a fixed sentinel never available to ordinary `CSeal`). Returning is then just
`cjalr` through that sentry: the hardware checks only "is this specifically sentry-typed" — no
second, explicit type-authority capability operand is needed at all, unlike ordinary
`CSeal`/`CUnseal`. Checked directly against `veda_cap_insts.sail`: Veda-Core's existing `OCJALR`
reuses the *general* `CSeal`/`CUnseal` type-authority mechanism (an arbitrary, software-chosen
`otype`, requiring an explicit authorizing capability operand every time), not a reserved
sentinel — it costs two capability operands, architecturally identical to `OCInvoke`. Getting
real CHERI-style cheap exits requires a new, dedicated primitive (reserved otype sentinel +
automatic mint-on-call + single-operand verify-on-return) that does not exist yet. This is real,
scoped follow-on engineering — Milestone B (Section 6) — not a same-pass instruction-reuse task.

**Finding 3 — "privilege through capability context" is the CHERI spec's own explicit answer for
ring-free designs**, confirmed directly (p.316, §9.21): *"In a ring-free design (e.g., one
without an MMU or kernel/supervisor/user modes), the privileged permission would be the SOLE
means of authorizing privilege."* This is a direct, authoritative validation — from CHERI's own
core spec, not just CHERIoT's specific choice — that Veda-Core's existing M-mode-only design can
and should use `PERMIT_ACCESS_SYSTEM_REGISTERS` (already real, already implemented, already the
exact gate `OSpecialRW`/`veda_oda` delegation already uses, `OSPECIALRW_PRIVILEGE_GATING_AUDIT.md`)
as the actual privilege boundary for kernel components, rather than inventing new ring levels.

**Finding 4 — "pure-capability operating system" is an explicitly named, official CHERI pattern**
(p.69, §2.4.8), word-for-word matching Veda-Core's own architecture: *"A clean-slate
operating-system design might choose to minimize or eliminate MMU use in favor of using the CHERI
capability model for all protection and separation. Such a design might reasonably be considered
a single address-space system... All separation would be implemented in terms of the
object-capability mechanism, and all memory sharing in terms of memory capability delegation."*
Veda-Core (no MMU, single address space, ODT-based object-capability isolation) is a real,
officially-named CHERI pattern, not an improvised novel OS model.

**Finding 5 — the real CInvoke design rationale directly confirms Veda-Core's existing OCInvoke
choices were already correct**, not just plausible. Real `CInvoke` deliberately does not
auto-generate a return capability (unlike `CJALR`) — *"the caller can itself perform any
necessary sealing of its own return state, if required"* — exactly the "seal the return
capability before entering" pattern already used in `veda_smoke_m22.S`. And the real switcher
pattern is spelled out explicitly (p.317-318, §9.22): *"CInvoke will be used to invoke trusted
software routines... to invoke a trusted supervisor responsible for mediating messages...
clearing non-argument registers... followed by a CJR to transfer control to the callee."* This is
a direct, primary-source confirmation that CHERIoT's real switcher-mediated design (`CInvoke`
always lands in one trusted switcher, which then internally hands off) is exactly what core
CHERI's own design rationale anticipated — not a CHERIoT-specific invention layered outside the
spec. **This is the mechanism Milestone A implements.**

**Finding 6 — the real `IDC`/`C31` mechanism validates Veda-Core's own `c15` convention.** Real
`CInvoke` writes the unsealed data capability into `C(31)`, real CHERI-RISC-V's own 32-entry
file's last register. Veda-Core's `VEDA_IDC_INDEX = Vcapno(15)` (last entry of its 16-entry CRF)
is the exact, already-correct proportional adaptation.

## 3. Design decision

**Milestone A (implemented this pass, zero new instructions beyond one register-selector
extension): the switcher pattern**, using Veda-Core's already-existing primitives. Every
cross-compartment call routes through `OCInvoke` into one fixed, trusted switcher compartment
(never compartment-to-compartment directly) — matching Finding 5's own real CHERI rationale
exactly. The switcher:

1. Clears non-argument GPRs (ordinary register writes — no new instruction needed).
2. Can hold a real, tagged capability to the current thread's trusted-stack/register-save area in
   a new Special Capability Register — the **TSC** (Trusted Stack Capability), a genuine second
   capability register alongside `veda_oda`, term-for-term adapted from real CHERIoT's own `mtdc`
   M-mode Trusted Data Capability.
3. Performs the real hand-off into the target compartment via a second `OCInvoke` — symmetric, as
   the current design stands, since the reserved-otype sentry primitive (Finding 2) does not
   exist yet.

**Milestone B (explicit, scoped follow-on, not this pass)**: a reserved-otype sentinel and a new
instruction pair (auto-mint-on-call, single-operand verify-on-exit) matching real `CJALR`'s exact
mechanism (Finding 2) — the concrete, buildable form of the asymmetric-exit preference already
decided, named and scoped precisely rather than vaguely deferred.

**Scheduling**: cooperative-first, per this project's own already-completed IBM System/38
research (a real historical precedent for rejecting interrupt-driven multitasking in favor of a
single dispatch queue) — an explicit `ECALL`-based yield, hardware-timer/CLINT preemption a later,
separate milestone.

**Privilege model**: capability-context-only, per Finding 3 — no new ring levels. The
switcher/scheduler compartments are distinguished from ordinary compartments purely by which
ODA-delegated capabilities they hold (`PERMIT_ACCESS_SYSTEM_REGISTERS`), exactly matching
`veda_oda_authorized()`'s own already-audited real mechanism.

## 4. What was actually built (Sail side)

**`veda_regs.sail`**: a new capability-register pair, following `veda_oda`/`veda_oda_tag`'s own
established precedent exactly (a genuine `capability`-typed register pair, not a plain CSR — it
does not consume a `0x7Cx` CSR address):

```sail
register veda_tsc : capability
register veda_tsc_tag : bool
```

**`veda_types.sail`**: a new `veda_scr` enum, placed here rather than in an instruction file for
the same real, previously-hit scattered-union type-ordering reason `veda_atomicop`/`veda_capquery`
already established as precedent — any type referenced by a `union clause instruction` must be
defined in an earlier-ordered module:

```sail
enum veda_scr = {VEDA_SCR_ODA, VEDA_SCR_TSC}
```

**`veda_cap_insts.sail`**: `OSpecialRW` extended from a fixed, ODA-only instruction to a
selector-based one. The original `VEDA_OSPECIALRW : (vcapidx, vcapidx)` with a hardcoded
`0b00000` encoding slot became `VEDA_OSPECIALRW : (veda_scr, vcapidx, vcapidx)`, with the
selector occupying exactly the bit range an ordinary `rs2` GPR field would in the R-type layout —
the same real RISC-V `.insn r` encoding trick already used elsewhere in this project (a register
index field repurposed as a small immediate/selector). The `execute` clause now `match`es on
`scr` to read-then-write either `veda_oda`/`veda_oda_tag` or the new `veda_tsc`/`veda_tsc_tag`,
gated identically (`cur_privilege == Machine`) for both — the same, already-audited privilege
check, applied uniformly rather than re-derived per register.

**Backward compatibility, verified directly rather than assumed**: the pre-existing
`vc_ospecialrw.S` test encodes `.insn r 0x5b, 0x1, 0x13, x2, x1, x0` — `x0` in the selector/rs2
position decodes to `0b00000` = `VEDA_SCR_ODA`, so every pre-existing encoding's meaning is
unchanged. Confirmed empirically: `vc_ospecialrw` still passes in the full regression (Section 5).

## 5. Switcher-pattern tests and one real bug found and fixed

Two new tests, `veda-core/sail_tests/vc_switcher_tsc_roundtrip.S` and
`vc_switcher_register_clear.S`, added to `run_veda_selfcheck_tests.sh`'s existing corpus.

`vc_switcher_tsc_roundtrip.S` mirrors `vc_ospecialrw.S`'s own proven read-then-write structure,
with `x1` in the selector position choosing `VEDA_SCR_TSC` instead of the default `VEDA_SCR_ODA`
(`x0`). It proves: TSC starts genuinely untagged (Sail's own default-zero init, the same
precedent `veda_oda` already relies on); TSC round-trips a real capability's `Base` field
correctly; and ODA remains independently untouched by a TSC write — proving these are two real,
separate registers, not the same storage aliased by selector value. Passed on first run.

`vc_switcher_register_clear.S` is the core Milestone A proof: builds a TARGET compartment
(Object_ID 33/34/35) and a SWITCHER compartment (Object_ID 30/31/32), poisons a non-argument GPR
(`x20 = 0xBAD5EC12`), `OCInvoke`s into the switcher, whose own code clears `x20` and then performs
a second, real `OCInvoke` into the target, which sets a marker (`x22 = 0x600D`); the final check
asserts `x20 == 0` (the switcher's clearing genuinely ran and survived into the target — not
merely assumed clean) and `x22 == 0x600D` (the second hand-off genuinely landed).

**A real bug was found and fixed while building this test, empirically, not by inspection alone.**
The first version used `Length = 0x0004` (4 bytes — exactly one instruction) for both
compartments' CODE capability, copied by pattern-analogy from `veda_smoke_m22.S`'s own tiny,
deliberately single-instruction compartment. That was the wrong precedent to copy: M22's test is
a *negative* test whose entire point is that a one-instruction compartment cannot be escaped by
`OCJALR` — it never needed to execute more than one instruction. The switcher needs at least two
(clear the register, then the second `OCInvoke`), so the narrowed PCC excluded the second
instruction's own address, and `sail_riscv_sim` correctly faulted on the resulting out-of-bounds
fetch — surfacing as a trap loop (no trap handler installed in this bare self-check harness).
Fixed by widening both compartments' `Length` to `0x0100` (256 bytes), the same generous headroom
`vc_ocinvoke.S`'s own working `landing_pad` compartment already uses. This also exposed the same,
already-once-fixed gap `vc_ocinvoke.S`'s own Milestone 19 comment documents: `RVMODEL_HALT_PASS`
performs an ordinary `sw` to the `tohost` MMIO region, which the `ext_data_get_addr` hook
correctly blocks from inside any still-live, bounded compartment. Fixed the same, already-
established, architecturally correct way — not by weakening enforcement — by building a real,
sealed RETURN capability (Object_ID 40/41/42) inside the target compartment and `OCInvoke`-ing
through it to widen PCC back to `VEDA_PCC_UNBOUNDED` (`Length = 0xFFFF`) before the halt macro
ever runs, mirroring `vc_ocinvoke.S`'s own `landing_pad`/`return_pad` pattern exactly.

## 6. Verification

```
$ bash run_veda_selfcheck_tests.sh
=== Veda-Core Milestone V-C self-check results ===
PASS      vc_atomic
...
PASS      vc_ospecialrw
...
PASS      vc_switcher_register_clear
PASS      vc_switcher_tsc_roundtrip
---
44/44 passed
```

All 42 pre-existing tests pass unchanged (zero regressions from the `OSpecialRW`/TSC extension),
and both new switcher-specific tests pass: a real two-compartment call routed through a switcher,
register non-leakage verified by reading the cleared register back from inside the target
compartment (not merely assumed clean by convention), and the TSC's own independent round-trip
correctness verified in isolation.

## 7. Deliberately out of scope for this pass, named rather than silently dropped

- **Milestone B's reserved-otype asymmetric exit** (Section 3, Finding 2) — a real, separate,
  scoped follow-on requiring a new sentinel otype and instruction pair, not attempted here.
- **RTL mirror of Milestone A** — this project's own established Sail-then-RTL sequencing
  (every prior milestone) applies here too; not started until this Sail-side pass, including its
  test corpus, is fully closed out.
- **Hardware-timer/CLINT preemption** — cooperative `ECALL`-yield scheduling only, per Section 3's
  own scheduling decision; preemptive scheduling is a later, separate milestone.
- **A real scheduler/allocator compartment implementation** — this pass builds and proves the
  switcher *mechanism* two arbitrary compartments can route through; a real scheduler compartment
  (holding TSC-authorizing capabilities, making dispatch decisions) is the next, not-yet-started
  layer on top of this mechanism.
- **S/U-mode privilege transitions** — unchanged from this project's own already-documented
  limitation (`MILESTONE_11_RESULTS.md`); the capability-context-only privilege model (Finding 3)
  is deliberately independent of ring levels, not a workaround for their absence.

## 8. Sequencing

Sail first (this document, complete), then RTL — the same order and reasoning already established
and followed for every prior milestone in this project.
