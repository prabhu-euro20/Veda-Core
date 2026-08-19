# Toolchain Milestone 21: memcpy/struct-copy shadow-metadata propagation -- results

**Status: built, verified, zero regression on every suite that actually exercises this
pass. See TOOLCHAIN_MILESTONE_21_STRUCT_COPY_SHADOW_DESIGN.md for the original design
and background (SoftBound PLDI 2009 precedent, the gap itself, Option A vs Option B).**

## Correction found during implementation (the design doc's own plan was incomplete)

The design doc's plan was: at a compile-time-constant-length `llvm.memcpy`/`llvm.memmove`,
walk every 8-byte slot and copy only the **shadow** (Object_ID) from source offset to
destination offset, trusting the underlying (unmodified) `llvm.memcpy` call to move the
**real bytes** correctly. That is correct when *neither* side of the copy is a
Shadow-tracked object -- but wrong whenever *either* side is tracked, discovered only by
building the design-doc version, running it against `veda_demo_struct_copy.c` under
`sail_riscv_sim`, and finding it produced a **real hardware trap**
(`VEDA_CAUSE_BOUNDS_VIOLATION`, mcause=0x18/mtval=0x21, decoded via `veda_xtval`'s own
`cap_idx5 @ cause` packing in `veda_bind_insts.sail`) instead of either passing or
reproducing the original silent-gap symptom.

Root cause, confirmed by reading `veda_compiler_rt.c` and the post-pass LLVM IR side by
side (not assumed): **every fresh `veda_malloc_raw` call returns the exact same fixed
`kVedaNullBase` (`0x1000`) pointer value**, regardless of Object_ID -- it is a shared,
symbolic "offset token" base, not a real per-object address. Milestone 9's own
dereference codegen already rewrites *every* ordinary load/store touching a tracked
object into a real `veda_rt_ocl_d`/`veda_rt_ocs_d` call (confirmed: the original
`store ptr %1, ptr %ptr_field` in pre-pass IR is *completely replaced*, not
supplemented, by a `veda_rt_ocs_d` call in post-pass IR) -- so a tracked object's real
field VALUES live *exclusively* in the OCL.D/OCS.D-addressed arena. Nothing real is ever
written at the object's own fake-token address in ordinary memory. An `llvm.memcpy` that
reads from or writes to that fake address therefore moves *unrelated garbage* (empirically:
zero) whenever the source or destination is tracked -- it only moves real bytes correctly
between two *ordinary* (untracked) addresses.

The design-doc version's shadow-only copy therefore produced a copied pointer field with
the **correct shadow Object_ID** but **wrong underlying value** (0 instead of the real
heap token), which the pass's own pre-existing dereference-rewrite logic then computed an
offset from (`0 - kVedaNullBase = -4096`), passed to `veda_rt_ocl_d`, and correctly
hard-trapped on as out-of-bounds -- a real, working enforcement mechanism catching a real
bug in the fix itself, not a false positive. This is the same kind of "verify before
deciding" discipline this project applies throughout: the design doc's plan was
plausible, grounded in the right precedent, and still wrong in a way only running it
against real hardware semantics revealed.

## The corrected mechanism

For every 8-byte-aligned slot in `[0, Len)` of a compile-time-constant-length
`llvm.memcpy`/`llvm.memmove` where neither side is alloca-tracked:

1. **Read the real value.** If the source is Shadow-tracked, read it through `OclFn`
   (`veda_rt_ocl_d`, the same real hardware primitive every ordinary tracked load already
   uses) at `(SrcObjShadow, SrcOffset+K)`, via the pass's existing lazily-created
   per-function `ScratchSlot` out-param. If the source is ordinary, a plain `i64` load
   from `Src+K` is correct as-is (ordinary memory is real memory).
2. **Read the source slot's own shadow** (for a copied field that is itself a pointer),
   via `synthKey`+`ShadowLoadFn` (tracked source) or a real-address-keyed
   `ShadowLoadFn` call (ordinary source) -- unchanged from the design doc's own plan.
3. **Write the real value.** If the destination is Shadow-tracked, write it through
   `OcsFn` (`veda_rt_ocs_d`) at `(DstObjShadow, DstOffset+K)`. If the destination is
   ordinary, a plain `i64` store to `Dst+K` is correct.
4. **Write the destination slot's shadow**, keyed the same way as step 2, unchanged from
   the design doc's own plan.

This whole block is now inserted **after** the original `llvm.memcpy`/`llvm.memmove`
call (`IRBuilder<> B(Call->getNextNode())`), not before it -- so an ordinary
destination's authoritative real-value write here is not silently clobbered by the
memcpy's own (possibly garbage-source) subsequent byte copy. The original memcpy call
itself is left completely unmodified either way: for the ordinary-to-ordinary case it
still does the real, efficient bulk copy (now redundantly re-confirmed slot-by-slot by
this new code, which is harmless); for tail bytes past the last full 8-byte slot
(the design doc's own stated scope limit, unchanged) it remains the only mechanism that
moves those bytes at all, correct only for the ordinary-to-ordinary case exactly as
before.

## Verification

- **FileCheck unit suite** (`run_veda_shadow_prop_tests.sh`): 8/8 pass, zero regression.
- **End-to-end demo suite** (`run_veda_demo_tests.sh`): now 9/9 -- `veda_demo_struct_copy`
  registered and passing (previously deliberately unregistered as a known-failing probe).
  The other 8 demos remain green.
- **Mutation test**: temporarily forced the entire memcpy-interception `if` to `false`
  (disabling the fix) and rebuilt -- `veda_demo_struct_copy` failed again with the
  original symptom (`FAILURE: possible trap loop detected`, the shadow-invalid ODT-miss
  hard-trap this milestone exists to close). Reverted; confirmed the source file is
  byte-identical to before the mutation (`diff` clean) before rebuilding the real fix.
- **Manual root-cause trace**: `sail_riscv_sim --trace` on the design-doc (pre-correction)
  version decoded the real trap cause (`VEDA_CAUSE_BOUNDS_VIOLATION` on capability
  register c1) via the Sail model's own `veda_xtval` bit-packing, which is what led to
  discovering the real-value-transport gap above rather than assuming the design doc's
  plan was already correct.

## Pre-existing, unrelated failures found while running the full toolchain regression sweep

Per this project's own standing discipline (full regression, not just the suites
believed relevant), the following suites were also run. Four of them fail --
**confirmed pre-existing and structurally unrelated to this fix**, not a new regression:

- `run_veda_alloca_protect_test.sh`, `run_veda_global_protect_test.sh`: fail identically
  (`positive ok=0, negative trapped=1`) when built against the plugin rebuilt from the
  **last-committed** `VedaShadowPropagation.cpp` (`git show HEAD:...`, before any of this
  milestone's changes) -- i.e., these were already broken before this work started.
- `run_veda_compartment_test.sh`, `run_veda_compartment_nested_test.sh`,
  `run_veda_sched_demo_test.sh`, `run_veda_sched_global_combo_test.sh`: none of these
  four scripts reference `-fpass-plugin` or `VedaShadowPropagation` at all (confirmed by
  `grep`) -- their build pipelines go `clang -S -emit-llvm` (no pass plugin) straight to
  `llc`/`llvm-mc`, so this milestone's change cannot possibly affect them either way.

Suites that **do** exercise real toolchain paths and pass cleanly:
`run_veda_syscall0_hello_world_test.sh`, `run_veda_syscall0_forged_oid_test.sh`,
`runtime/run_veda_rt_tests.sh` (2/2, no plugin used), and
`sail_tests/run_veda_selfcheck_tests.sh` (70/70 -- this is a compiler-only change, Sail
model untouched, run anyway per this project's own "verify, don't assume" discipline).

**This is a real, separate finding, named here rather than silently left for a future
re-discovery** (matching this project's own established pattern) -- six suites broken by
something unrelated to any change in this session (compartment/scheduler pipeline and/or
environment drift since these were last verified green). Out of scope for this milestone
to fix; flagged for a future, dedicated investigation.

## Scope limits (unchanged from the design doc)

- Non-compile-time-constant memcpy length: left completely unrewritten.
- Alloca-family (Milestone 12, `veda_compartment`-protected stack struct) regime: not
  covered -- no parallel synthKey-equivalent mechanism exists for it today.
- Sub-8-byte tail bytes and non-8-byte-aligned offsets: uncovered, matching this pass's
  pre-existing "only 64-bit-wide tracked dereferences" width limit elsewhere.
- Global-involving memcpy: out of scope, matching Milestone 13's own global-table limit.

## Option B (hardware-native alternative) -- still a named future direction, not built

Unchanged from the design doc: migrating struct-embedded pointer fields to real
`OCL.C`/`OCS.C` capability storage would make this whole bug *class* structurally
impossible (byte-granular tag invalidation means a plain memcpy automatically leaves the
destination untagged), at the real, unmeasured cost of an ABI-breaking struct layout
change and the 32-byte `OCL.C`/`OCS.C` alignment requirement. Not committed to without a
dedicated measurement pass, per this project's own standing discipline.
