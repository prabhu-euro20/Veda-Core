# SSC (Stack-Spill Capability): Real Stack Protection for Compiled C Inside a Compartment

**Date:** 2026-08-06
**Scope:** the real, scoped answer to the question the user asked directly: "if we relax purecap
for compartment-internal stack accesses, is that a vulnerability?" — verified yes (`sp` is not a
checked capability, so a blanket exemption reopens the exact `CGetBase`-then-raw-load/store bypass
Milestone 19 closed) — and the safe alternative the user asked to have designed as a real milestone
instead. Closes, in a Veda-Core-native way, the real limit `TOOLCHAIN_MILESTONE_10_RESULTS.md`
found: ordinary compiler-generated C cannot run inside a narrowly `OCInvoke`-bound compartment,
because standard RV64 ABI prologues spill callee-saved registers via ordinary `sd`/`ld`, which
Milestone 19's purecap rule hard-traps unconditionally.

## Research, read in full before any code was written

- **`STACK_FRAME_CALL_RETURN_ANALYSIS.md`**: built and RTL-proved a real, object-centric
  return-**address** protection using one long-lived stack-region object + one long-lived
  seal-authority object, bound once per program, not per call. The reusable building block for
  this milestone.
- **`rtl/MILESTONE_17_RESULTS.md`**: `OCJALR` closes the return-address gap structurally
  (hardware hard-trap), but protects exactly one sealed capability per call — it does not, and was
  never meant to, generalize to the many arbitrary callee-saved registers/locals an ordinary ABI
  prologue spills. A different, narrower problem than this milestone's.
- **Real CHERI-RISC-V and CHERIoT RTOS**, verified via WebSearch against official architecture
  documentation: both make the stack pointer itself (`csp`) a genuine, always-live capability
  register — every GPR is capability-widened. Directly porting this to Veda-Core would mean
  widening every GPR, contradicting Veda-Core's own foundational "opt-in, not ambient" design
  pillar (the iAPX 432 cautionary tale `DESIGN_SOUL_AND_UNIQUENESS.md` was built around). **Not a
  portable feature — required a genuinely Veda-Core-native design.**

## A real flaw found by independent adversarial review, before any code was written

The first design draft proposed a single, thread-scoped SSC following ODA/TSC's own established
"persistent, untouched by `OCInvoke`" pattern. An independent review (a fresh agent, prompted to
pressure-test rather than rubber-stamp) found this would let **a callee compartment silently
inherit full `OCL.D`/`OCS.D` read/write access to the caller's entire stack region** the instant it
was `OCInvoke`d — a real leak, larger than the purecap trap this milestone exists to safely
replace, and one that would have defeated the exact isolation Milestone 19 was built to enforce.
This finding directly drove the final design below.

## Design (as implemented, refined once more during implementation)

**1. A third Special Capability Register, `VEDA_SCR_SSC` (`0b00010`)** — `veda_types.sail`'s
`veda_scr` enum, `veda_regs.sail`'s `veda_ssc`/`veda_ssc_tag` register pair, and a third `match
scr` arm in `VEDA_OSPECIALRW` (`veda_cap_insts.sail`), all mirroring the existing ODA/TSC pattern
field-for-field. Zero new logic invented for this part.

**2. `VEDA_OCINVOKE` *and* `VEDA_OCRETURN` both gain an identical new side effect: unconditionally
clear (untag) `veda_ssc` on every successful compartment-boundary crossing.** This is the actual
fix for the review's finding, but it is **simpler** than the review anticipated and simpler than
the approved plan's own first sketch, found while implementing rather than designed up front:
- The plan's own draft envisioned OCInvoke *saving* the caller's SSC and *installing* the callee's
  own (via a new, not-yet-specified per-compartment storage mechanism). Implementing this honestly
  required a real answer to "where does the callee's own SSC value come from," and the simplest,
  lowest-risk, zero-new-state answer turned out to be: **don't automatically install anything —
  just clear the register, symmetrically, on every crossing.** The entered context (compartment or
  resuming caller) re-establishes its own SSC via an ordinary `OSpecialRW`, the identical
  already-established pattern ODA/TSC themselves use for their own setup. This requires no new
  encoding, no new operand, and no new per-compartment storage table.
- Clearing only the **Tag**, not zeroing the underlying value, matches this project's own
  established convention (Milestone 7's tag-clearing-on-plain-write) — any `OCL.D`/`OCS.D` against
  an untagged capability already hard-traps regardless of the stale bits underneath.
- **`OCRETURN` needed the identical fix, not just `OCInvoke`** — a real, necessary extension beyond
  the approved plan's own wording (which only named `OCInvoke`). `OCRETURN` is a real, general
  compartment-boundary-crossing mechanism (Milestone B), not exclusively used inside the
  scheduler's own switcher pattern, so the same hardware-guarantee-not-software-discipline
  reasoning applies to it equally.

**3. The review's Finding #4 (per-thread SSC save/restore in the scheduler) is closed for free, by
construction, not by new scheduler code.** Confirmed by direct source inspection of
`runtime/veda_sched_asm.S`: every thread resume (`resume_0`/`resume_1` → `do_resume`) already ends
in a real `ocreturn` (line 291). Since `OCRETURN` now unconditionally clears SSC as part of this
milestone's own change, **every thread switch already clears the previous thread's SSC before the
next thread's own code runs, with zero scheduler-side code changes needed.** The review's concern
was real and correctly raised against the *original* design sketch; the subsequent, simpler
OCInvoke/OCRETURN-level fix happens to close it as a structural side effect. Not independently,
empirically re-verified with a dedicated new scheduler test in this pass (the existing
`vc_scheduler_cooperative_yield.S` regression, unaffected, is the only evidence) — a real, honestly
named gap, not glossed over; a dedicated cross-thread SSC-leak test is a natural, cheap follow-on.

**4. Honest scope statement, not overclaimed**: **`OCL.D`/`OCS.D` against an already-bound CRF
register were never blocked inside a compartment by Milestone 19's purecap rule** — that rule is
scoped to ordinary base-ISA `is_load`/`is_store` only, and Veda-Core's own "use" instructions were
always exempt by construction (confirmed directly in `veda_core.tlv`'s own comment: "Deliberately
does NOT touch any Veda-Core instruction's own memory path"). SSC does **not** newly enable
something that was impossible before. What it actually, honestly adds: (a) a real, **dedicated**
register for a future compiler codegen mode to target instead of inventing an ad hoc convention,
and (b) the **security property** that this register is genuinely isolated across every
compartment/thread boundary — the part that was missing and the part the independent review
correctly flagged as necessary. SSC also gives **whole-region**, not **frame-level**, isolation:
one function's spills are not protected from another function's spills *within the same
compartment*, matching ordinary RV64 stack semantics today (no hardware frame isolation exists
there either) — not a regression, stated precisely rather than implied to be stronger.

**Explicitly distinct from `OCJALR`**: return-address protection is unrelated, already solved,
untouched by this milestone. SSC is specifically for the *other* stack-resident values that made
ordinary C thread bodies purecap-trap.

**Explicitly out of scope, deferred** (matching how every prior Veda-Core capability instruction —
`OCInvoke`, `OCJALR`, `CSealEntry` — was proven by hand-assembly first): the real LLVM codegen mode
that would make ordinary `clang` automatically emit SSC-relative `OCL.D`/`OCS.D` for
compartment-targeted functions. Confirmed via direct read of `compiler/VedaShadowPropagation.cpp`:
its rewrite mechanics are already generic and reusable, but it has zero `AllocaInst` recognition
today — deriving a stack slot's Object_ID/offset in IR is real, separate, unbuilt future work. RTL
mirror is also a separate, later pass, per this project's unbroken Sail-then-RTL sequencing.

## Two real test bugs found and fixed via `sail_riscv_sim` trace debugging (not assumed)

1. `vc_ssc_ocinvoke_clear_neg.S`'s own expected `mtval` was wrong: assumed `cap_idx=0`, but the
   test's own readback capability register was `c8`, giving the correct real value `0xA2`... i.e.
   `(8<<5)|0x02 = 0x102`, not the originally-assumed `0x02` — a mistake in the test's own
   assertion, not the mechanism; the real trap (Tag Violation, on the untagged post-`OCInvoke` SSC
   readback) fired exactly as designed on the first real run.
2. `vc_ssc_oob_neg.S` and `vc_ssc_spill_reload.S` both initially used `Perms=0x0080`
   (`PERMIT_ACCESS_SYSTEM_REGISTERS`, copied from an `OSpecialRW`-authority-object descriptor
   elsewhere) for objects meant to be accessed via `OCL.D`/`OCS.D` — the real, correct permission
   is `PERMIT_LOAD`/`PERMIT_STORE` (`0x000C`). The OOB test's real trap fired one check earlier
   than intended (Permit_Load Violation, cause `0x12`, not the intended Bounds Violation) until
   fixed.
3. `vc_ssc_spill_reload.S`'s own positive-path halt macro itself traps if executed while still
   inside the compartment (`RVMODEL_HALT_PASS`'s own `sw` is an ordinary store) — a real, direct,
   miniature reproduction of the exact Milestone 10 problem this whole mechanism exists to solve.
   Fixed by adding a genuine second `OCInvoke`, into a code capability with `Length =
   VEDA_PCC_UNBOUNDED (0xFFFF)`, to properly exit the compartment before halting — the same real
   "compartment exit needs a second OCInvoke" pattern `rtl/MILESTONE_22_RESULTS.md` already
   established.

## Verification

`sail_tests/run_veda_selfcheck_tests.sh`: **57/57 passed** (53 pre-existing + 4 new), zero
regressions.

New tests, each proving a distinct, named property:
- `vc_ssc_roundtrip.S`: SSC starts untagged, round-trips a real capability correctly, is genuinely
  independent of ODA/TSC.
- `vc_ssc_ocinvoke_clear_neg.S`: the review's Finding #1, closed operationally — a real object
  bound into SSC before `OCInvoke` reads back untagged inside the callee, and an attempted
  `OCL.D` through it hard-traps (Tag Violation, `mcause=0x18`/`mtval=0x102`).
- `vc_ssc_spill_reload.S`: the real, positive completion criterion — a compartment establishes its
  own SSC and performs a genuine two-value spill/reload sequence, both values round-trip correctly,
  with zero purecap traps anywhere in the sequence.
- `vc_ssc_oob_neg.S`: SSC gets the identical real spatial bounds check every other Veda-Core
  capability register already gets (Bounds Violation, `mcause=0x18`/`mtval=0xA1`).

## Not yet built

RTL mirror (Sail-first sequencing, matching every prior milestone); the real LLVM codegen mode
that would let ordinary `clang` automatically target SSC (a real, separate, substantial piece of
future toolchain work — the mechanics are reusable from the existing SoftBound-style pass, but
`alloca` recognition and stack-slot Object_ID derivation are wholly unbuilt); a dedicated,
empirical cross-thread SSC-isolation test (closed by construction per point 3 above, not yet
independently re-verified with its own test).
