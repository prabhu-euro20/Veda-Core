# Toolchain Milestone 20: Fix -- Silent Bind Failure in the Compiler-Pass-Facing Runtime

## The bug (found empirically, TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md)

Three of the four M19 scope-limit tests shared one root cause: when
`VedaShadowPropagation.cpp`'s Shadow map has no entry for a pointer (uintptr_t round-trip,
function-return value), the pass-generated dereference is still redirected through
`veda_rt_ocl_d`/`veda_rt_ocs_d`, which binds via `veda.bind.notrap` -- a deliberately
non-trapping mode. On an invalid Object_ID that bind correctly comes back untagged, and
`veda_compiler_rt.c`'s wrappers **discarded the resulting bool**, so the runtime silently
returned zero/stale data with **zero hardware trap and zero error signal**. `veda_compiler_rt.c`'s
own pre-existing comment had assumed the opposite ("a real failure ... hard-traps"), which was
simply wrong for this one case -- an honest miscalibration between Milestone 7's own
deliberately-recoverable `veda_ocl_d`/`veda_ocs_d` API and Milestone 9's compiler-generated path,
which never actually wants that recoverability.

## The fix

Hardware-first, minimal blast radius, zero new software checks:

1. **New asm helper**, `veda_bind_scratch_trap_asm` (`runtime/veda_rt_asm.S`) -- identical to the
   existing `veda_bind_scratch_asm` except it issues the plain, **already-existing, already-tested,
   trapping** `veda.bind c1, a0` (mode 0b00) instead of `veda.bind.notrap`. Confirmed via direct
   TableGen read (`RISCVInstrInfoXVeda.td`: `VEDA_BIND : VedaBind<0b00, "veda.bind">`) that the real
   mnemonic is genuinely assembler-recognized -- it had simply never been used by its real name
   anywhere in this codebase before (every prior `veda.bind` reference used hex `.insn` encoding).
2. **`veda_compiler_rt.c`'s `veda_rt_ocl_d`/`veda_rt_ocs_d`** (the ONLY two functions
   `VedaShadowPropagation.cpp`'s automatic dereference-rewrite ever calls) now bind via this new
   trapping helper directly, then call the existing `veda_ocl_d_scratch_asm`/`veda_ocs_d_scratch_asm`
   -- bypassing `veda_rt.c`'s `veda_ocl_d`/`veda_ocs_d` (Milestone 7's own graceful, bool-returning
   API) entirely for this one call path.

**What was deliberately left untouched:** `veda_rt.h`/`veda_rt.c`'s public `veda_ocl_d`/`veda_ocs_d`
API and `veda_bind_scratch_asm` keep their exact original `.notrap`, bool-returning contract --
Milestone 7's own direct C callers (anything hand-written that legitimately wants to check "is this
object still live?" without crashing) are completely unaffected. `VedaShadowPropagation.cpp` itself
was not modified. This is a real hardware enforcement mechanism doing the work (an already-shipped
instruction mode, previously simply unused by this one call path) -- not a new `if (!ok) abort();`
software check.

## Verification

Full existing regression, unchanged: `run_veda_demo_tests.sh` -- **3/3 passed**
(`veda_demo_linked_list`, `veda_demo_oob_neg`, `veda_demo_container_of`), confirming zero collateral
regression to the correct/happy path.

Both M19-identified silent gaps re-tested directly against the fix:

- **`veda_demo_intptr_roundtrip.c` sub-case 4** (uintptr_t round-trip, OOB deref) -- previously
  `--trace-exception` showed **zero** trap lines and a clean `FAILURE: 1` (wrong-value) exit. Now:
  `trapping from M to M to handle extension-exception`, `tval 0x0000000000000025` -- decodes to
  cap_idx=1 (c1, the runtime's scratch register), cause=0x05 (`VEDA_CAUSE_OBJECT_NOT_FOUND`) -- a
  real, correct, expected hard trap.
- **`veda_demo_container_of_param.c` Shape A** (container_of result returned across a function call,
  dereferenced in the caller) -- previously a clean `FAILURE: 1` with `got_tag_a` silently reading a
  hard zero. Now: a real hard trap fires (observed as a fetch-access-fault trap loop, since this
  reproducer was never built with its own trap handler -- confirms a genuine unhandled exception now
  occurs where previously none did). **Shape B** (the correct usage: reconstruct and dereference
  inside the same callee) re-verified unaffected: still a clean `SUCCESS`.

## Honest scope note

This fix closes the *silent* failure mode for the compiler-pass-generated access path specifically.
It does not, by itself, make either Test 1 (uintptr_t provenance) or Test 2 (return-value shadow) a
*working* pattern -- both are still real, unsupported gaps in `VedaShadowPropagation.cpp`'s shadow
tracking. What changes is the failure mode: a program that hits either gap now gets a real,
loud, correctly-caused hardware trap (debuggable, matching this whole project's "fail loud"
discipline everywhere else) instead of a silently wrong answer. Test 3 (global array multi-level
GEP) is unrelated to this fix -- it uses a completely separate access path (`ocl.c`/`veda_ocl_global_d`)
and was already failing safe via the pre-existing, orthogonal Milestone 19 purecap rule. Test 4
(indirect-call compiler crash) is also unrelated -- a `rewriteSignatures`-internal robustness bug, not
a runtime data-flow question.

## Files changed

- `veda-core/runtime/veda_rt_asm.S` -- added `veda_bind_scratch_trap_asm`, additive only.
- `veda-core/compiler/veda_compiler_rt.c` -- `veda_rt_ocl_d`/`veda_rt_ocs_d` rewritten to use the new
  trapping bind path.
