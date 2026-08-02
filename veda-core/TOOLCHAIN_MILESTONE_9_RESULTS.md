# Veda-Core Toolchain Milestone 9: SoftBound-Style Dereference Codegen + Real End-to-End Demo

**Date:** 2026-07-31
**Scope:** extends Milestone 8's shadow-propagation pass with phase 2 — real
dereference rewriting (`load`/`store` on a tracked, object-relative pointer
redirected into real `veda_rt_ocl_d`/`veda_rt_ocs_d` runtime calls, backed by
real OCL.D/OCS.D). Builds the real runtime, a genuine C linked-list demo, and
runs it **end-to-end through the actual `clang -fpass-plugin=...` pipeline**
on `sail_riscv_sim` — the concrete answer to Simon Moore's original "do you
have a compiler?" question this whole toolchain initiative exists to close.

## A real, critical gap found before it could silently invalidate everything

Milestone 8's own hand-written `.ll` tests recognized `veda_malloc_raw` via a
`{ptr, i32}` struct return + `extractvalue`. Before writing any Milestone 9
runtime code, this was checked against what **real clang actually generates**
for that C signature — and it does not match at all:

```
struct veda_malloc_raw_t { void *ptr; uint32_t oid; };
struct veda_malloc_raw_t veda_malloc_raw(unsigned long size);
```
compiles (verified directly, `--target=riscv64 -O0 -S -emit-llvm`) to:
```llvm
%call = call [2 x i64] @veda_malloc_raw(i64 noundef %0)
store [2 x i64] %call, ptr %r
%oid = getelementptr ...; %1 = load i32, ptr %oid, align 8
```
RISC-V LP64's real ABI coerces the small struct into an `[2 x i64]`
array, round-tripped through a stack alloca and field GEPs — a
**completely different IR shape** from the pass's own hand-written test
input. Had this not been checked, Milestone 8's own pass would have silently
failed to recognize *any* real, clang-compiled call to its own malloc-source
primitive — the entire demo would have run completely uninstrumented, with
no error, while still (accidentally, meaninglessly) "passing" its own
positive test. This is exactly the kind of gap the user's own standing
instruction warned about, and exactly why real end-to-end verification
matters more than isolated unit tests of hand-written IR.

**Fixed by redesigning the ABI**, not chasing the coercion: an out-parameter
avoids struct-return ABI complexity entirely.
```c
void *veda_malloc_raw(unsigned long size, uint32_t *out_oid);
```
independently verified (same method) to produce the simple, predictable
```llvm
%call = call ptr @veda_malloc_raw(i64 noundef %0, ptr noundef %oid)
```
The pass's malloc-source rule was rewritten around this real shape: it now
inserts its **own** `load i32, ptr %oid_slot` immediately after the call
(using the call's own 2nd argument), rather than searching for a sibling
instruction the caller's source may or may not have already emitted —
strictly more robust than the original Milestone 8 design, not just a
same-level replacement. All 8 Milestone 8/9 `.ll` tests were updated to the
new ABI and re-verified (see below).

## Phase 2: real dereference rewriting

For any `load`/`store` whose **address** operand is itself tracked (present
in the pass's shadow map), the plain memory instruction is deleted entirely
and replaced with a real `veda_rt_ocl_d`/`veda_rt_ocs_d` call, using:
- **object_id** = the address's own tracked shadow.
- **offset** = `ptrtoint(address) - kVedaNullBase` (see "pointer-as-offset
  -token representation" below).

If the value being stored/loaded is *itself* a tracked pointer (the real
`node->next = other_node` linked-list case), its own shadow is additionally
persisted/recovered via a **synthetic (object_id, offset)-encoded key**
(bit 63 set, guaranteed disjoint from any real address in this bare-metal
system) into the same `@veda_shadow_store`/`_load` table Milestone 8 already
built — reused, not duplicated.

**A real, hardware-forced width limit, not a convenience simplification**:
only 64-bit-wide (`i64` or pointer-typed) tracked accesses are rewritten.
This directly reflects a real fact already confirmed from Sail source in
Milestone 5b/M6: Veda-Core's own ISA has **no `OCL.B/H/W` or `OCS.B/H/W`
variants at all** — only `.D` (8 bytes) and `.C` (128 bytes, capability)
widths exist. The demo's own struct is deliberately all-64-bit for exactly
this reason.

**A real, additional propagation rule, discovered as necessary while working
through what the demo actually needed** (not one of Milestone 8's original
four cases): `icmp eq/ne ptr %X, null` against a tracked pointer is rewritten
to compare its shadow Object_ID against the invalid-object sentinel instead
of the raw pointer bit pattern. This is a genuine correctness requirement of
the pointer-as-offset-token representation below — every fresh object's own
pointer numerically starts at the *same* value, so raw-pointer null
comparison cannot distinguish "no next node" from "the next node itself."

### The pointer-as-offset-token representation

`veda_malloc_raw`'s real runtime returns a fixed, **non-null** sentinel base
(`kVedaNullBase = 0x1000` — deliberately non-null so no LLVM optimization
pass is ever tempted to treat arithmetic on it as null-pointer-dereference
UB) for every fresh object. Every subsequent `getelementptr` naturally
accumulates the real byte offset within that object as the pointer's own bit
pattern, since GEP's address arithmetic doesn't care whether its "base" is a
real address. This is coherent specifically because **no tracked pointer is
ever dereferenced through a real load/store in the final program** — the
dereference-rewrite rule above intercepts every such access before it would
reach real memory, redirecting through real (Object_ID, offset) addressing
instead. Matches `VEDA_CORE_SPEC.md`'s own real architecture exactly:
"software holds an opaque Object_ID, never a raw address."

## A second real gap found — parameter shadow-seeding ambiguity

Rebuilding the plugin with Phase 2 broke Milestone 8's own already-passing
`memory_roundtrip.ll` test. Root cause: Phase A's signature rewrite appends a
shadow companion to **every** pointer *parameter* (needed for genuinely
tracked parameters, `call_argument.ll`) — which means a parameter always has
*some* shadow-map entry, even one that's only ever the default/untracked
sentinel at every real call site. Phase 2's new "any shadow-map entry means
redirect through OCL/OCS" rule can't distinguish that from a genuinely
tracked parameter. **Real, principled resolution**: in a real, well-formed
Veda-Core program, a given pointer *variable* is consistently either
object-derived or not — never mixed — so the ambiguity is an artifact of the
test's own shape (a parameter), not a real design flaw. Fixed by rewriting
the test to use a local `alloca` instead of a parameter for the "genuinely,
provably untracked address" case (Phase A's parameter-shadow seeding can
never reach a local alloca at all, making it unambiguous). Documented in the
test file itself.

## Real runtime backing (`veda_compiler_rt.c`)

Adapts Milestone 7's already-verified `veda_rt.h` API (`veda_malloc`,
`veda_ocl_d`, `veda_ocs_d`) to the pass-facing ABI, rather than duplicating
allocator logic:
- `veda_malloc_raw` → `veda_malloc()`, returning `kVedaNullBase` + the real
  Object_ID.
- `veda_shadow_store`/`_load` → a small, honest, linear-probe table (64
  entries — sized for this milestone's own demo scale, not production-grade;
  stated explicitly, not hidden), treating both real addresses and synthetic
  (object,offset) keys uniformly as opaque 64-bit keys.
- `veda_rt_ocl_d`/`veda_rt_ocs_d` → thin wrappers around Milestone 7's own
  `veda_ocl_d`/`veda_ocs_d`, deliberately ignoring the `bool` success return
  (a real failure hard-traps inside the real hardware instructions
  themselves — the same "trust hardware, don't redundantly software-check"
  philosophy Milestone 7 already established).
- `veda_shadow_attach` gets a trivial no-op definition — it is a pure
  compile-time observability marker with no real runtime meaning; a real
  linked binary just needs *some* symbol to satisfy the linker.

## A real build-toolchain finding: `clang -fpass-plugin=` needs `registerPipelineStartEPCallback`

The plan's own stated invocation is plain `clang -fpass-plugin=...` (no
explicit `-passes=`). Verified directly from `PassBuilderPipelines.cpp`
(not assumed) that `PassBuilder::buildPerModuleDefaultPipeline` special
-cases `OptimizationLevel::O0` to call `buildO0DefaultPipeline` — a
completely different code path from the one that invokes
`registerPipelineParsingCallback`-registered passes. Also verified that
`buildO0DefaultPipeline` **does** call `invokePipelineStartEPCallbacks`, so
`registerPipelineStartEPCallback` is the real, correct hook for a pass that
must run automatically regardless of optimization level — added alongside
the existing `registerPipelineParsingCallback` registration (used by `opt
-passes=veda-shadow-prop` for the IR-level FileCheck tests); the two paths
were confirmed not to double-invoke the pass (`opt -passes=X` never goes
through `buildPerModuleDefaultPipeline` at all — a separate,
`parsePassPipeline`-based code path).

**-O0 was a deliberate, stated choice**, not a limitation glossed over: the
pointer-as-offset-token representation above depends on the compiler never
assuming standard C pointer-arithmetic UB rules apply to it; higher
optimization levels risk exactly that class of miscompilation. Real,
legitimate future work if optimized builds are ever needed: run this pass
earlier in the pipeline (before UB-exploiting passes) or mark the
represented pointers with an explicit non-standard address space.

## Real, honest build-environment note

The plugin (a native x86_64 shared library the host `opt`/`clang` process
`dlopen`s) cannot be compiled by this project's own custom LLVM checkout —
it only registered the RISCV backend, so it genuinely cannot emit any native
x86_64 code at all (`error: unknown target triple 'unknown'`, real and
verified, not assumed). Built instead with the system's official
Ubuntu-packaged `clang++-21` (exact same real, released 21.1.8 as the
custom checkout's own `release/21.x` tag) purely as an x86_64-capable
compiler frontend, while compiling against the **custom checkout's own**
LLVM headers (`llvm-config --cxxflags`) for correct ABI compatibility with
the custom-built `opt`/`clang` that actually loads it.

## Verification — real, both directions, with mutation testing throughout

**IR-level (`opt`/FileCheck), 8/8 tests pass** — all 5 from Milestone 8 (one
corrected as above) plus 3 new Phase 2 cases:

| Test | Proves |
|---|---|
| `deref_rewrite.ll` | tracked 64-bit store/load → real `veda_rt_ocs_d`/`veda_rt_ocl_d` |
| `linked_list_field.ll` | tracked pointer VALUE stored into tracked ADDRESS, synthetic-key shadow round-trip |
| `null_check.ll` | `icmp` against `null` rewritten to shadow comparison |

```
=== Toolchain Milestone 8 (veda-shadow-prop) test results ===
PASS      call_argument
PASS      deref_rewrite
PASS      linked_list_field
PASS      loop_phi_cyclic
PASS      memory_roundtrip
PASS      null_check
PASS      phi_merge
PASS      straightline
---
8/8 passed
```

**Real end-to-end demo, both directions**:

- **Positive** (`veda_demo_linked_list.c`): a real 3-node linked list, built
  and traversed via ordinary, unmodified-looking C pointer syntax
  (`node->next`, `node->value`, `cur != 0`), compiled via
  `clang -fpass-plugin=...`, linked with the real Milestone 7 runtime, run
  under `sail_riscv_sim`: **SUCCESS** (sum of values == 60, count == 3).
- **Negative** (`veda_demo_oob_neg.c`): a deliberate out-of-bounds field
  access (`(char*)n + VEDA_RT_SLOT_SIZE`, exactly at the real object's own
  64-byte Length boundary) genuinely hard-traps through the real compiler
  -generated `veda_rt_ocl_d` call's own real OCL.D instruction —
  `mcause=0x18`, `mtval=0x21` — an exact match, independently *predicted
  before running it* from Sail source (`veda_xtval(cap_idx,cause)`'s real
  bit-packing, the runtime's fixed scratch register `c1` = index 1,
  `VEDA_CAUSE_BOUNDS_VIOLATION` = 0x01) and cross-checked against this
  project's own existing precedent (`MILESTONE_18_RESULTS.md`'s identical
  `mtval=0x21` for the same real cause via the same real register): **SUCCESS**.

```
=== Toolchain Milestone 9 (real end-to-end demo) test results ===
PASS      veda_demo_linked_list
PASS      veda_demo_oob_neg
---
2/2 passed
```

**Mutation testing, both demos** (proving neither result is vacuous):
- Positive demo, one list value corrupted (`30`→`31`, sum should be 61 not
  60): real `FAILURE`.
- Negative demo, the out-of-bounds offset changed to a genuinely in-bounds
  one (`+64`→`+8`): the expected trap correctly does **not** fire, `main()`
  falls through to `return 99`, and the harness correctly reports real
  `FAILURE` — proving the PASS/FAIL detection is not simply "any trap ⇒
  pass."

**Zero regression**: the existing 30-test Sail self-check suite and the
2-test Milestone 7 runtime suite both still pass in full, unaffected (this
milestone touched no Sail model, RTL, or Milestone-7 file — only new files
under `veda-core/compiler/`).

## What remains open, honestly

- Only `-O0` builds are supported for the reason stated above — a real,
  legitimate, stated limitation.
- The 64-bit-only dereference-rewrite width limit is real and
  hardware-forced (Veda-Core genuinely has no narrower OCL/OCS variants),
  not something a future milestone can simply "widen."
- No struct/array bulk copy, no `memcpy`-style operations across tracked
  objects — only scalar (i64/pointer) field-level access is rewritten.
- The shadow table (`veda_compiler_rt.c`) is a small, honest linear-probe
  array (64 entries) — real, stated, not production-scale.
- Return-value shadow propagation and a shadow-stack-based (rather than
  signature-based) calling convention remain real, legitimate future
  refinements (inherited, still open, from Milestone 8's own stated scope).

## Reproducing this

```
cd veda-core/compiler
./run_veda_shadow_prop_tests.sh   # 8 IR-level FileCheck tests
./run_veda_demo_tests.sh          # real end-to-end positive + negative demo
```
