# Toolchain Milestone 20 (part 2): Return-Value Shadow Propagation

## The gap (TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md, Test 2)

`VedaShadowPropagation.cpp` had real, working shadow propagation INTO a function (via appended
per-pointer-parameter shadow arguments) but none OUT of one: a `CallInst`'s own result never got a
`Shadow` map entry, except the single hardcoded `veda_malloc_raw` special case. Any ordinary
module-defined function shaped like `struct node *get_thing(...)` lost its return value's shadow at
the call site -- more general than the `container_of` question that surfaced it: this affects any
function returning a tracked pointer, not just backward-reconstruction patterns.

## The fix

Generalizes the exact out-param convention this file already used for `veda_malloc_raw` (an
already-proven, real pattern) to ordinary functions:

- **`rewriteSignatures`**: the function-selection condition is broadened from "has a pointer
  parameter" to "has a pointer parameter OR returns a pointer." Any such function now gets ONE
  trailing `ptr` (pointer-to-i32) out-param appended, always AFTER the existing per-pointer-parameter
  shadow params. Its index is recorded in the new `ReturnShadowParamIndex` map. Existing direct call
  sites get a `null` placeholder argument appended (the same "structure now, real value later"
  two-phase pattern this file already uses for the scalar shadow placeholders).
- **New `ReturnInst` handling** (`propagateInFunction`, Pass 2): if the current function has a
  `ReturnShadowParamIndex` entry, every `ret ptr %x` stores `%x`'s known shadow (or `InvalidOid`)
  through the out-param immediately before returning -- the write-back half.
- **Extended `CallInst` handling**: for a call to a callee with a `ReturnShadowParamIndex` entry,
  a lazily-created, per-calling-function scratch `alloca i32` (`veda.ret.shadow.scratch`, mirroring
  `ScratchSlot`'s already-established reuse-across-call-sites idiom) receives the address, is passed
  in place of the placeholder, then loaded right after the call to seed `Shadow[Call]`.

**A real, second bug found and fixed while implementing this, before any test exposed it**: the
existing parameter-shadow-seeding code's own `NumOrig` computation (`getNumParams() -
PPI->second.size()`) did not account for a function ALSO having a trailing return-shadow param --
for a function with both a pointer parameter and a pointer return type (exactly `reconstruct(struct
link_node *l)` from the M19 audit's own test file), this silently computed an off-by-one index,
seeding the parameter's shadow from the WRONG argument. Fixed by subtracting the return-shadow slot
too when present.

## Verification

**Full regression, all pre-existing suites, zero collateral breakage**:
- `run_veda_demo_tests.sh`: 3/3 (unaffected suites) + the new permanent 4th case (below) = 4/4.
- `run_veda_shadow_prop_tests.sh` (Milestone 8's own FileCheck corpus): **8/8** -- `call_argument.ll`
  needed its CHECK lines updated to the new, intentional IR shape (a stale expectation, not a
  regression -- its own function, `@callee`, returns a pointer and correctly gains the new out-param).
  The updated CHECK lines directly confirm the mechanism composes correctly across a real
  TWO-level call chain (`caller` calls `callee`; `caller` itself also returns a pointer and correctly
  chains `callee`'s return-shadow into its own).
- `run_veda_alloca_protect_test.sh`, `run_veda_global_protect_test.sh`, `run_veda_compartment_test.sh`,
  `run_veda_compartment_nested_test.sh`, `run_veda_sched_demo_test.sh`,
  `run_veda_sched_global_combo_test.sh`: all **PASSED**, unchanged verdicts.
- `runtime/run_veda_rt_tests.sh`: 2/2 (standalone C runtime suite, does not use the compiler pass --
  confirms this change has zero reach outside `VedaShadowPropagation.cpp`).
- `sail_tests/run_veda_selfcheck_tests.sh`: **63/63** (Sail-level suite, entirely unaffected by a
  compiler-only change -- run as a final sanity check).

**The real, previously-broken case now genuinely works end-to-end**: `veda_demo_container_of_param.c`
Shape A (helper reconstructs via `container_of` and RETURNS the pointer; `main()` dereferences fields
on it after the call) -- previously silently read back a hard zero with no trap
(`TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md`), then (after the M20-part-1 bind fix alone)
correctly hard-trapped instead of lying -- now, with this fix, **genuinely succeeds**: `SUCCESS` under
`sail_riscv_sim`, both `got_tag_a == 0xBBBB` and `got_payload_a == 54321` read back correctly through
the returned, cross-function-boundary pointer.

**Mutation test** (confirm the fix does not mask a real logic bug): a variant of the SAME reconstruct
function with the `container_of` subtraction removed (`return (struct container *)l;` directly,
misinterpreting the field pointer as the container's own base) was rebuilt against the fixed pass and
rerun -- correctly still `FAILURE: 1` (the shadow IS now real/propagated, so the wrong-offset read
returns real-but-wrong data, exactly matching plain-C undefined-but-not-trapped behavior; the fix
closes the shadow-loss gap, it does not suppress genuine offset/logic errors).

`veda_demo_container_of_param.c` is now wired into `run_veda_demo_tests.sh` as a permanent 4th
positive case (4/4).

## Honest scope limits (real, not yet covered)

- Only DIRECT calls are handled (matches this pass's own pre-existing, stated indirect-call scope
  limit -- unrelated to and not fixed by this milestone; see
  `TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md` Test 4, a real compiler crash on indirect
  calls, still open).
- A function returning a pointer through a `phi`-merged multi-path return, or via `unreachable`/
  no-return paths, was not specifically tested -- the `ReturnInst` handling fires per return site
  independently, which should generalize, but multi-return-site functions were not built and run.
- Recursive functions (a pointer-returning function calling itself) were not tested -- the lazy
  per-function `ReturnShadowSlot` reuse should be safe (each call's result is read back immediately),
  but this was not empirically exercised.
- Does not address Test 1 (`uintptr_t` round-trip) or Test 3 (global multi-level GEP) from the M19
  audit -- both remain real, separately-scoped, currently-open gaps.

## Files changed

- `veda-core/compiler/VedaShadowPropagation.cpp` -- `ReturnShadowParamIndex` map added;
  `rewriteSignatures` broadened target selection + appends the return-shadow out-param;
  `propagateInFunction` gets new `ReturnInst` handling, extended `CallInst` handling, and the
  `NumOrig` off-by-one fix in parameter-shadow seeding; file header comment updated.
- `veda-core/compiler/test/call_argument.ll` -- CHECK lines updated to the new, correct IR shape.
- `veda-core/compiler/veda_demo_container_of_param.c` -- promoted from M19-audit reproducer to a
  permanent positive regression case.
- `veda-core/compiler/run_veda_demo_tests.sh` -- registers the promoted test as a 4th case.
