# Non-`veda_compartment`-Attributed Global Access: Policy Confirmed Safe, Documentation Gap Closed

## The question, restated precisely

`TOOLCHAIN_MILESTONE_13_RESULTS.md`'s own "Not yet built": global accesses inside functions NOT
attributed `veda_compartment`, even if transitively reachable from a live compartment, are left
completely untouched by Phase B1 — a real, already-documented, deliberate design choice
(`VedaShadowPropagation.cpp`'s own comment, `propagateInFunction`, Store/Load rewrite dispatch): "an
access from a DIFFERENT, unattributed function reaching the SAME global must still be left completely
untouched." Named as "a genuinely new policy question Phase B0 never faced."

## Direct verification: is this a live security gap, or a safe one?

Re-derived from primary sources this session, not assumed:

1. **`VedaShadowPropagation.cpp` itself confirms the scope**: the rewrite dispatch for both `Load` and
   `Store` is explicitly gated `if (F.hasFnAttribute("veda_compartment"))` (confirmed at the exact call
   sites, lines ~900/1010) — an unattributed function's own IR is never touched, its original `load`/
   `store` instruction survives compilation unmodified, lowering to an ordinary RV64I `lw`/`sw` (or
   `ld`/`sd`).
2. **The real hardware/Sail-side rule this collides with**: `toolchain/sail-riscv/model/extensions/Veda/veda_regs.sail`'s
   own comment on `veda_mode` bit 0 (`veda_purecap`), quoted verbatim: `"global 'ordinary LOAD/STORE/AMO/etc.
   is illegal everywhere' flag"`. This is Milestone 19's own real enforcement rule, and it is
   **unconditional** — it does not check which function is executing, whether Phase B1 ever analyzed it,
   or whether the specific instruction was compiler-pass-aware. It checks only whether `veda_mode.veda_purecap`
   is currently set (i.e., execution is inside a live, narrow `OCInvoke`/`OCReturn`-bound compartment).
3. **This exact mechanism is already what `TOOLCHAIN_MILESTONE_10_RESULTS.md`'s own real, previously-found
   finding rests on** (re-confirmed, not re-derived fresh): "ordinary compiler-generated C functions CANNOT
   run inside a narrowly OCInvoke/OCRETURN-bound compartment at all — standard RV64 ABI's own
   callee-saved-register prologue spill is an ordinary `sd`/`ld`, which Milestone 19's purecap rule
   hard-traps unconditionally inside any live narrow compartment." The exact same mechanism that already,
   today, hard-traps an unattributed function's own *prologue* spill would identically hard-trap that same
   function's own attempt to touch a global via ordinary `lw`/`sw`.

**Conclusion: this is not a silent, exploitable bypass.** An unattributed function reached from inside a
live compartment that tries to touch ANY memory via an ordinary load/store — a global, a stack variable,
anything — hard-traps immediately (`VEDA_CAUSE_PURECAP_VIOLATION`), the same fail-closed outcome M10's own
callee-saved-spill finding already demonstrated for the unrelated prologue-spill case. The program crashes;
it does not silently succeed with an unprotected access. `P(bypass)=0` is not weakened by this gap — what's
actually missing is *support* for a real, useful pattern (an ordinary, uninstrumented helper function
touching a global from inside a compartment), not a *hole* in enforcement.

## Resolution: generalize an already-established rule, not build a new mechanism

Milestone 12's own finding 2 (`TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md`'s own citation of it)
already answered the identical question for one specific case — runtime helpers: "any runtime helper
reached from inside a live compartment must itself be `veda_compartment`-attributed." The natural,
consistent generalization, and this document's own decision: **that rule is not runtime-helper-specific —
it is the general rule for this entire architecture.** Any function whose call graph can be reached from
inside a live compartment, and which touches a protected resource (global, stack-local, heap object), must
itself carry the `veda_compartment` attribute, or its access is not instrumented and will hard-trap. This
was already true in practice (every prior milestone's own real test programs, back to Milestone 10,
implicitly followed this rule); it has simply never been written down as a general statement before.

**Action taken**: this document records the general rule explicitly, for `VEDA_CORE_SPEC.md` or an
equivalent toolchain-facing doc to cite going forward. No `VedaShadowPropagation.cpp` change is needed —
the current gating behavior is already correct and matches this rule exactly. What was missing was the
documentation connecting "Phase B1 leaves unattributed-function accesses untouched" to "and that's safe,
because the hardware's own unconditional purecap rule fails closed on them" — stated here for the first
time as a general, cited fact rather than left as an unexplained gap.

## What remains genuinely open (not closed by this document)

- A **diagnostic** would still be real, useful future work: today, an unattributed function touching a
  global from inside a compartment fails at *runtime* (a hard trap during execution) rather than at
  *compile time* (a clear error from the pass itself, naming the exact function and global). This is a
  usability improvement, not a correctness or security fix — `VedaShadowPropagation.cpp` would need a
  call-graph reachability analysis (which function can be transitively reached from an `OCInvoke` call
  site) to produce such a diagnostic, real, non-trivial static-analysis work not attempted here.
- No real test in the current corpus exercises this specific trap (an unattributed function reached from a
  live compartment, touching a global) — the closest existing precedent is M10's own callee-saved-spill
  trap, a different instruction class. Per this project's own standing discipline, a compile-time
  diagnostic (if ever built) would need its own real positive/negative test pair, not assumed correct from
  this document's own reasoning alone.
