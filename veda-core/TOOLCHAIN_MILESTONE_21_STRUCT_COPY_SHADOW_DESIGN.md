# Toolchain Milestone 21: memcpy/struct-copy shadow-metadata propagation -- design

**Status: built and verified. See TOOLCHAIN_MILESTONE_21_STRUCT_COPY_RESULTS.md for the
final mechanism (corrected from this doc's original plan -- real VALUE transport through
OclFn/OcsFn was needed for a tracked side, not just the shadow -- see that doc's own
"Correction found during implementation" section) and full verification results.

## The gap (NEXT_STEPS_ROADMAP.md §2.12, found by TOOLCHAIN_MILESTONE_20_KERNEL_GAPS_RESULTS.md)

`VedaShadowPropagation.cpp`'s per-instruction dispatch (Toolchain Milestones 8-9) tracks, for every
LLVM SSA pointer value, an opaque `i32` Object_ID "shadow" -- but only across the instruction shapes
it explicitly recognizes (GEP, BitCast, PtrToInt/IntToPtr, PHI, direct load/store, call argument/
return passing). A plain C struct assignment (`dst = *src;`) or an explicit `memcpy()` call lowers,
even at `-O0`, to a single opaque `call void @llvm.memcpy.p0.p0.i64(...)` the pass's dispatch loop
has no case for at all -- the copied bytes move correctly, but any pointer-typed field inside the
copied range loses its shadow silently. A subsequent dereference through the copied field is then
either an ordinary unrewritten load (if the address is untracked) or, worse on a real Veda-Core
access, is enforced with *no Object_ID at all* rather than the real one -- both cases are a silent
loss of protection, not a trap, confirmed empirically via `veda_demo_struct_copy.c`
(`TOOLCHAIN_MILESTONE_20_KERNEL_GAPS_RESULTS.md`).

## Two candidate fixes were researched; this milestone builds the first, names the second

**Researched via the project's own official primary source** (SoftBound: Highly Compatible and
Complete Spatial Memory Safety for C, Nagarakatte et al., PLDI 2009 -- fetched and read in full from
the paper's own official host, `llvm.org/pubs/2009-06-PLDI-SoftBound.pdf`, the exact reference design
this toolchain track's own header comment cites by name): Section 5.2's "Memcpy()" subsection is the
official answer to exactly this class of gap, quoted verbatim: *"memcpy must also copy the metadata
corresponding to any pointer in the region being copied... SoftBound infers whether the source of the
memcpy contains pointers by looking at the type of the argument at the call site. Although not
foolproof, we have found this heuristic sufficient..."* -- this is not a "genuinely new, type-aware
analysis pass component" as `NEXT_STEPS_ROADMAP.md`'s own §2.12 entry speculated; it is a
well-established, 15-year-old technique this project's own toolchain has simply not yet implemented,
closing a gap relative to its own declared reference design rather than inventing new compiler theory.

**A second, hardware-native candidate was found independently this session**, by direct reading of
`rtl/veda_core.tlv` (Milestone 7: "byte-granular tag invalidation" -- any plain store clears the
tag_mem[] granule it touches) and `mem_metadata.sail` (`default_meta = false` threaded through every
plain load/store unconditionally): Veda-Core's own hardware capability Tag mechanism is architecturally
immune to this whole bug *class*, not just this instance, because it uses inline/tag-based metadata
(the same principle as CCured's WILD pointers -- SoftBound's own paper, Section 3.4, states plainly
that WILD-style inline tagging means "all program memory operations cannot corrupt the metadata,
eliminating... the need for every store operation to update the tag"). If struct-embedded pointer
FIELDS were stored as real capabilities via `OCS.C`/`OCL.C` instead of the software shadow scheme, a
plain-byte memcpy of such a field would, for free, leave the destination reading back untagged --
hard-trapping on next dereference, no compiler memcpy-awareness needed at all.

**Decision: build the SoftBound-precedented fix (Option A) now; document Option B as a real, named,
deliberately-deferred future direction, not silently dropped.** Reasoning: Option A is small, bounded,
zero-ABI-impact, and closes the confirmed gap directly. Option B is architecturally stronger (immune to
the whole bug class, matching this project's own hardware-first standing philosophy) but has a real,
unmeasured cost -- migrating pointer-typed struct fields to full capability storage changes struct
memory layout/size (a real ABI break for any struct with a pointer field) and requires the field's own
storage location to satisfy `OCL.C`/`OCS.C`'s 32-byte alignment gate (this session's own widening
work). Committing to that cost without first measuring it would violate this project's own established
discipline of a scoped design/synthesis pass before a change with real, non-obvious cost (the same
discipline `NEXT_STEPS_ROADMAP.md` itself applied to Milestones 13 and 25, and to the widening's own
compressed-bounds-vs-widening decision). Shipping Option A first does not foreclose Option B -- if
Option B is later built, Option A's fix becomes dead code removable at zero sunk-cost regret.

## Option A: mechanism, precisely (grounded in the actual current pass, not assumed)

Read `VedaShadowPropagation.cpp` in full for the exact mechanism a fix must integrate with. Two
real facts, confirmed directly, that shape this design:

1. **The pass already has two distinct shadow-key regimes**, chosen per-address at every existing
   load/store site: (a) **real-address-keyed** (`ShadowStoreFn({Addr, Shadow})`/`ShadowLoadFn({Addr})`)
   for a pointer value stored into *ordinary* (non-Veda-Core-tracked) memory -- exactly SoftBound's own
   disjoint-metadata-by-storage-address scheme; (b) **object-relative synthetic-keyed**
   (`synthKey(ObjectIdShadow, ByteOffset)`, a deterministic `(ObjectId<<24)|Offset|kSyntheticKeyTag`
   value) for a pointer value stored *into a field of a Veda-Core-tracked object itself* (the
   `Shadow.lookup(Addr)` branch), since the object's own memory representation is an untyped
   offset-token with no real machine address to key by. A third regime (Milestone 12's
   `AllocaBase`-tracked, SSC-protected stack locals) exists for whole-alloca protection but has no
   parallel "pointer field stored into a protected alloca" sub-mechanism today.
2. **`synthKey`'s key is fully deterministic from (ObjectId, byte offset) alone** -- no runtime state
   beyond the two operands. This means a fix can synthesize, at the memcpy call site, the *exact same*
   key a later real load/store of that same field would independently derive -- no need to intercept
   or rewrite that later access at all, only to make sure an entry exists for it to find.

**Verified directly against `veda_demo_struct_copy.c`** (read in full, not paraphrased): the actual
probe's `dst = *src;` is a **mixed** case -- `src` is a heap object (`veda_malloc_raw`, `Shadow`-tracked,
synthKey regime) and `dst` is a plain local variable (`struct holder dst;`, an ordinary `alloca` --
confirmed `AllocaBase` population is itself gated on `F.hasFnAttribute("veda_compartment")`
(`VedaShadowPropagation.cpp:874`), and `main()` here carries no such attribute, so `dst` never enters
the alloca-family regime at all -- it is ordinary, real-address-keyed memory for this pass's purposes).

## The fix

At every `llvm.memcpy`/`llvm.memmove` intrinsic call whose length argument is a compile-time constant
(true for essentially every real struct-copy/fixed-size-memcpy call site -- `sizeof(struct X)` is a
compile-time constant in virtually all real C code, matching SoftBound's own "the few uses of memcpy
involving pointers" scoping, and this project's own established preference for compile-time-known,
fully-unrollable work over runtime-variable-count loops, e.g. NEXT_STEPS_ROADMAP.md's own tag-granule
Break-1 reasoning): for every 8-byte-aligned slot `k` in `[0, Len)`, read the shadow at
source-offset-`k` and write it at destination-offset-`k`, using whichever of the two existing regimes
(real-address-keyed via `Shadow.lookup`/ordinary, or object-relative via `synthKey`) applies
independently to the destination and to the source -- covering all four combinations
(ordinary-to-ordinary, object-relative-to-ordinary, ordinary-to-object-relative,
object-relative-to-object-relative). No struct-type recovery is needed at all: unconditionally walking
every 8-byte slot in the known-constant length range and reusing the pass's own existing
`ShadowLoadFn`/`ShadowStoreFn` declarations is sufficient -- a slot that was never really a pointer
field simply round-trips the default "no shadow" (`kInvalidObjectId`) value, a harmless no-op, exactly
mirroring the property that makes SoftBound's own coarser type-based heuristic safe to be imprecise
in the paper's own words ("not foolproof... sufficient").

No new runtime helper function is needed -- the fix is implemented entirely as additional IR
instructions the pass inserts at the memcpy call site, reusing `ShadowLoadFn`/`ShadowStoreFn`
(already declared, already used elsewhere in this same pass) and `synthKey`/`computeOffset` (already
private helper methods on the pass class).

**Explicit, honest scope limits, stated up front, not discovered later:**
- A memcpy/memmove whose length is **not** a compile-time constant is left completely unrewritten
  (matches this pass's own established "diagnosed and left unrewritten, not degraded" convention for
  every other out-of-scope shape -- e.g. non-64-bit dereference widths, ambiguous alloca PHIs).
- The **alloca-family (Milestone 12, `veda_compartment`-protected stack struct) regime is not covered
  by this fix** -- a struct copy where either side is a protected stack-local has no parallel
  synthKey-equivalent mechanism to hook into today. This is a real, separately-scoped gap, named here
  rather than silently left for a future re-discovery, matching this project's own established
  discipline (e.g. the tag-store granule straddle gap from the widening pass, or per-CPU addressing in
  §2.13).
- Only 8-byte-aligned slots within `[0, Len)` are walked; a `Len` not a multiple of 8, or field
  offsets not 8-byte-aligned, follow the pass's own pre-existing "only 64-bit-wide tracked
  dereferences" width limit -- unaligned bytes at the tail are left uncovered, matching how the rest
  of this pass already treats sub-64-bit accesses.
- Global-to-global or global-involving memcpy is out of scope for this pass -- Milestone 13's own
  global-capability-table regime has no per-field shadow concept either, matching the alloca-family
  limit above for the same underlying reason.

## Verification plan

Positive: `veda_demo_struct_copy.c` (already exists, currently deliberately unregistered as a
known-failing probe) must, after this fix, correctly compute `got == 77` and be moved into
`run_veda_demo_tests.sh`'s passing suite. Negative/mutation: temporarily disable the new memcpy
instrumentation, confirm the demo fails again (dereferences an untracked/wrong-Object_ID pointer), then
revert. Full regression required with zero new failures: `run_veda_demo_tests.sh`,
`run_veda_shadow_prop_tests.sh`, the compartment/alloca/global/scheduler suites, `runtime/
run_veda_rt_tests.sh`, and Sail self-check (this is a compiler-only change -- Sail/RTL should be
provably unaffected, but the full regression is run anyway per this project's own standing discipline
of not assuming instead of checking).
