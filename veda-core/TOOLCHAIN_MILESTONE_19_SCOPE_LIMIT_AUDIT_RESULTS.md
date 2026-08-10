# Toolchain Milestone 19: Scope-Limit Audit -- 4 Empirical Tests

## Context

Toolchain Milestone 18 (`TOOLCHAIN_MILESTONE_18_CONTAINER_OF_RESULTS.md`) empirically confirmed the
`container_of()` backward-reconstruction pattern already works, unmodified, through
`VedaShadowPropagation.cpp`. That doc's own "Honest scope limits" section named four real,
still-open items the pass's own source comments already flag as deliberate scope boundaries. This
milestone tests each of the four directly, empirically, through the real toolchain and real
sail_riscv_sim hardware model -- not by inference. **`VedaShadowPropagation.cpp` was not modified by
any of these tests**; every finding below is about the pass's CURRENT, unmodified, already-shipped
behavior.

Four independent agents, each running the full design -> hypothesis -> build -> run -> mutation/
comparison-test -> report cycle this project's own discipline requires. Full raw agent output
(536K tokens, 156 tool calls across the four) archived; this doc distills the verified findings.

## Test 1: `void*` vs `uintptr_t` round-trip

**Question:** does capability protection survive a tracked pointer being cast to `void*` and back,
or to `unsigned long` (uintptr_t-style) and back?

**Finding:**
- `void*` round-trip: **protection survives completely.** Because this LLVM build uses opaque
  pointers, `(void*)p` and `(struct node*)v` produce no distinct IR instruction at all -- it is a
  plain pointer-typed memory round-trip, identical in shape to any other tracked-pointer store/load,
  already handled by the pass's existing `ShadowStoreFn`/`ShadowLoadFn` machinery. A deliberate
  out-of-bounds access through a `void*`-round-tripped pointer traps exactly like the baseline
  `veda_demo_oob_neg.c` (mtval=0x21, confirmed via `--trace-exception`).
- `unsigned long` round-trip: **protection is lost, but not in the way "unrewritten -> raw memory
  access" would suggest.** `ptrtoint`/`inttoptr` are not propagation edges the pass recognizes, so
  the shadow silently becomes `InvalidOid` (`0xFFFFFFFF`) at the point of the `ptrtoint`. The
  dereference is still redirected through real `veda_rt_ocl_d`, which issues `veda.bind.notrap` on
  the bogus Object_ID. That bind correctly comes back **untagged** (0xFFFFFFFF is not a live object),
  and the runtime's own tag check silently no-ops -- **no hardware trap, no real memory access, and
  no real data returned.** The caller gets a stale/zero value with no signal anything went wrong.
  Mutation test (same access with the round-trip removed) restored the hard trap exactly, isolating
  causation to the round-trip itself.

**Verdict: CONFIRMED_GAP_SILENT_UNPROTECTED.** This is the most concerning of the four findings: no
crash, no trap, no leak of real adjacent data either -- a caller who does not deliberately self-check
(as this test's own demo does) would see a wrong answer with zero signal that anything failed.

## Test 2: `container_of` across a function-call boundary

**Question:** does M18's proven `container_of` mechanism still work when the reconstruction and the
dereference happen in different functions?

**Finding -- two shapes, two different outcomes:**
- **Shape A** (helper reconstructs and *returns* the pointer; caller dereferences the returned
  value): **fails.** Root cause, confirmed by direct grep (zero matches) and source reading: the pass
  has **no logic anywhere that gives a `CallInst`'s own pointer return value a shadow**, except the
  one hardcoded `veda_malloc_raw` special case. Any tracked pointer returned from any ordinary
  function call loses its shadow at the call site. The failure mode matches Test 1 exactly: the
  runtime's `veda.bind.notrap` silently fails on the bogus `InvalidOid`, the caller reads back a
  hard zero (confirmed via a binary success/fail probe), no trap.
- **Shape B** (reconstruction *and* dereference both happen inside the same callee, only a scalar
  returned): **works correctly**, mutation-tested and confirmed.

**Verdict: CONFIRMED_GAP_BUT_FAILS_SAFE** (same "silent wrong answer, no trap" pattern as Test 1) --
**and a materially more general finding than the container_of question it was designed to answer.**
This is not a container_of-specific gap: it is a **generic "no function may return a tracked pointer
and have the caller dereference it correctly" gap**, since the missing logic is in the generic
`CallInst`-result handling, unrelated to GEP/offset arithmetic. Any function shaped like
`struct node *get_node(...)` -- an extremely common C idiom, not a container_of peculiarity -- would
hit this identical gap.

## Test 3: global array-of-structs (multi-level GEP)

**Question:** does Milestone 13's global-variable protection correctly handle `g_arr[i].field`,
which the pass's own `findGlobalRoot` comment already flags as a single-level-only scope limit?

**Finding:** confirmed, and via **two distinct real IR shapes**, not the one originally guessed
(correcting the test's own initial framing): at the real build's `-O1` optimization level, a
constant-index access (`g_arr[2].value = ...`) is folded by InstCombine into a nested GEP
`ConstantExpr` chain, while a runtime-variable-index access (`g_arr[i].value` in a loop) stays a
chain of two real `GetElementPtrInst`s. **Both** hit `findGlobalRoot`'s single-level check for the
same underlying reason (the field-GEP's pointer operand is another GEP, not the `GlobalVariable`
directly) -- confirmed via targeted debug instrumentation of a throwaway copy of the pass (the real,
shipped `VedaShadowPropagation.cpp` was never modified). Both accesses are left **completely
unrewritten**: post-pass IR is byte-for-byte identical to pre-pass IR for the whole function body.

The architecturally interesting part: because this code only runs meaningfully inside a live
`veda_compartment` (Milestone 13's own global-protection mechanism is gated on that), Milestone 19's
**existing, independently-verified, blanket purecap rule** (any raw load/store while a compartment is
live hard-traps, regardless of target) catches the unrewritten access anyway --
**mcause=0x18, mtval=0x227, exact match to `VEDA_CAUSE_PURECAP_VIOLATION`**, confirmed via full
instruction trace. A comparison build of the identical function called *outside* any compartment
(no `OCInvoke`, `veda_purecap` never set) shows the same unrewritten access executing silently,
untrapped, with zero enforcement -- isolating the safety net specifically to the live-compartment
condition.

**Verdict: CONFIRMED_GAP_BUT_FAILS_SAFE**, with an honest caveat: this is not a general guarantee.
It holds *because* this codebase's compartment-execution model happens to make M19's blanket rule an
orthogonal safety net for this specific gap -- not because `findGlobalRoot`'s own scope limit is
benign in isolation. A `veda_compartment` function that legitimately needs some other raw memory
operation would be unable to distinguish itself from this gap under the current blanket rule (the
same tension already named in `MILESTONE_19_RESULTS.md`'s own alloca-scratch-buffer finding).

## Test 4: indirect (function-pointer) calls

**Question:** what actually happens at compile time when a tracked-pointer-taking function is called
through a function pointer rather than by name?

**Finding: a real, deterministic compiler crash**, not a silent miscompilation and not a clean
diagnostic. `rewriteSignatures` only rewrites `CallInst` users of the old `Function` when building
its replacement (correctly matching its own documented "indirect calls ... out of scope" comment) --
but it then unconditionally calls `F->eraseFromParent()` on the OLD function regardless of whether
any *other* kind of `User` (e.g. a function-pointer-valued global variable's own initializer) still
references it. With a real function-pointer global in the test source, this trips LLVM's own
use-after-free guard:

```
While deleting: ptr %
Use still stuck around after Def is destroyed:@g_reader = dso_local global ptr <badref>, align 8
Uses remain when a value is destroyed!
UNREACHABLE executed at llvm/lib/IR/Value.cpp:102!
```

`cc1` aborts (SIGABRT, exit 134), the outer `clang` driver reports failure (exit 1), **no object file
is ever produced.** Reproduced twice, deterministically. A control build (identical source, calling
the function directly by name instead of through the pointer) compiles, links, and runs cleanly
(`SUCCESS` under `sail_riscv_sim`), isolating the crash precisely to the function-pointer-use
pattern.

**Verdict: COMPILE_CRASH_OR_ASSERT.** Honest, load-bearing caveat: this LLVM checkout is built with
assertions enabled (`Build config: +assertions`, confirmed in the crash banner) -- that build config
is *why* this fails loudly instead of silently. The tripped check (`Value.cpp:102`,
`materialized_use_empty()`) is assertion-gated; a release/`NDEBUG` build of the identical compiler
would very likely skip this check and proceed to actually free the `Function` while the global's
`Use` still points at it -- a real use-after-free of a `Function` object, silently. This was **not**
independently built and confirmed (only the assertions-enabled behavior was observed) and is flagged
explicitly as informed inference, not measured fact.

## Cross-cutting pattern across all four

Three of the four gaps (Tests 1, 2, and to a lesser extent 3) share the *same* underlying failure
shape, worth naming explicitly since it recurs: when the pass's `Shadow` map has no entry for a
tracked-looking pointer, it does not fall through to an ordinary, unprotected raw memory access (the
intuitive "worst case"). Instead, because the fallback sentinel `InvalidOid` (`0xFFFFFFFF`) still
gets *stored* as if it were a real shadow value, the dereference is *still redirected* through real
`veda_rt_ocl_d`/`veda_rt_ocs_d`, which issues a real (non-trapping) `veda.bind.notrap` against that
bogus Object_ID. The bind correctly fails (untagged), and the runtime silently returns a zero/stale
value with **no trap and no correct data** -- a third outcome, distinct from both "protected" and
"openly unprotected," that this project had not previously named or tested for. This is a real,
general property of the current `veda_rt_ocl_d`/`veda_ocl_d` runtime helpers (they treat a failed
bind as "return zero," not as "propagate failure to the caller" -- see `veda_rt.c`'s own
`veda_ocl_d`/`veda_ocs_d`, which return a `bool` success flag that every call site in
`VedaShadowPropagation.cpp`'s generated code discards), not specific to any one of these four test
scenarios. Test 4 is the exception -- it fails at compile time, before any of this runtime machinery
is ever reached.

## What this means for the project (not yet acted on -- reporting only)

None of these four gaps were fixed in this milestone -- by design, this was a pure empirical audit of
already-shipped M9-era behavior, matching this project's own established "test first, design the fix
as its own separate, reviewed step" discipline. Real, concrete next-step candidates this audit
surfaces, in rough order of how broadly they'd matter if Veda-Core's compiler toolchain were ever
pushed toward real, larger C programs (e.g. any future Linux-ABI-compatible OS libc/runtime port):

1. **Return-value shadow propagation** (Test 2's real finding) is the most architecturally central
   gap -- it blocks the ordinary `T *get_thing(...)` idiom generally, not just container_of. A real
   fix would need `ReturnInst` handling (attach the returned value's shadow at every return site) and
   a matching `Shadow[Call] = ...` read-back at the general call site (currently only the
   `veda_malloc_raw` special case does this) -- a real, non-trivial but bounded compiler change.
2. **`veda_ocl_d`/`veda_ocs_d`'s silent-zero-on-failed-bind behavior** (the cross-cutting pattern
   above) may be worth revisiting independent of any one call site: today a failed bind is
   indistinguishable, to the calling C code, from a real zero read -- a real availability/correctness
   risk even in cases where the underlying capability model is doing its job correctly.
3. **`rewriteSignatures`'s crash on indirect calls** (Test 4) is a real robustness gap in the pass
   itself, separate from the ISA/security model -- worth a defensive fix (e.g. skip/diagnose a
   function with non-CallInst uses rather than crash) regardless of whether indirect-call
   instrumentation is ever added.
4. **`uintptr_t` round-tripping** (Test 1) and **multi-level global GEPs** (Test 3) are narrower,
   already-documented scope limits; Test 3 in particular is currently caught by an orthogonal safety
   net (M19 purecap) specific to this codebase's compartment model, so it is the lowest-urgency of
   the four as currently used.

## Files created (compiler/ directory, new files only -- no existing file modified)

- `veda_demo_intptr_roundtrip.c`, `veda_demo_intptr_mutant_direct_oob.c` (Test 1)
- `veda_demo_container_of_param.c` (Test 2)
- `veda_demo_struct_array_global.c`, `veda_struct_array_global_entry.S`,
  `veda_struct_array_global_baseline_entry.S` (Test 3)
- `veda_demo_funcptr_indirect.c`, `veda_demo_funcptr_indirect_control.c` (Test 4)

These are diagnostic reproducers, not wired into `run_veda_demo_tests.sh`'s PASS/FAIL regression --
several of them *deliberately* trigger the documented gap (expected outcome is a wrong answer or a
compiler crash, not `SUCCESS`), which is a different contract than that script's binary pass/fail
harness assumes. Kept as standalone, re-runnable evidence for this doc's findings.
