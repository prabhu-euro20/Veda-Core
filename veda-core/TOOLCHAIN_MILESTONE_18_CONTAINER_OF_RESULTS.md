# Toolchain Milestone 18: `container_of()` -- Backward Pointer Reconstruction

## Question being answered

A prior research workflow (Linux-port feasibility study, this session) unanimously found that
literally porting unmodified Linux source is structurally impossible under Veda-Core's "no pointer
at any level" axiom, and specifically named the kernel's pervasive `container_of()` macro --
`(type *)((char *)ptr - offsetof(type, member))`, reconstructing an enclosing struct's base address
via pointer SUBTRACTION from an embedded field's own address -- as a concrete blocker, by direct
analogy to real CHERI's own documented `container_of` pain point.

Toolchain Milestone 9 already has a real, working, end-to-end compiled-and-hardware-verified demo
(`veda_demo_linked_list.c`) of ordinary C pointer-chasing (`cur = cur->next`) being transparently
retrofitted into real OCL.D/OCS.D hardware accesses by `VedaShadowPropagation.cpp`, with zero
Object_ID handling in the C source. That demo's own pattern is FORWARD dataflow (dereferencing an
already-tracked pointer field to obtain another already-tracked pointer) -- a different problem from
`container_of`'s BACKWARD reconstruction (deriving a *different* logical base address via arithmetic
on an existing pointer's own bit pattern). This milestone asks, empirically rather than by inference:
does the EXISTING, unmodified M9 compiler pass also handle the backward case, or is this a real,
separate gap the Linux-port research correctly identified?

## Hypothesis (stated before running anything, per this project's own rigor discipline)

Three independent architectural facts, each independently verified from source before writing any
test code, combine into a testable prediction:

1. **Clang's own frontend lowering.** `(char *)ptr - N` (pointer minus a compile-time-constant
   integer) is standard C pointer arithmetic on a `char*` -- Clang lowers this to a plain
   `GetElementPtrInst` with a negative `i64` index, not a `ptrtoint`/`sub`/`inttoptr` chain.
2. **The pass's own GEP-propagation rule is sign-agnostic.**
   `VedaShadowPropagation.cpp:820-840` (`propagateInFunction`'s GEP case): "GEP never changes which
   object a pointer refers to -- same shadow value, no new instruction needed." The code
   (`if (Value *S = Shadow.lookup(GEP->getPointerOperand())) Shadow[GEP] = S;`) does not inspect the
   GEP's index at all, positive or negative.
3. **Veda-Core has no subobject-bounds narrowing anywhere.** Neither this compiler pass nor the
   underlying ODT/Object-Bind hardware ever shrinks an object's registered capability bounds
   (`Base`/`Length`) to a sub-range when a GEP computes a field pointer -- the WHOLE
   `veda_malloc`'d allocation stays in bounds for the object's entire life; a GEP only ever changes
   the byte OFFSET passed to OCL.D/OCS.D. This is the precise architectural reason real CHERI's
   `container_of` failure mode (a genuine *hardware* bounds violation, when CHERI's own opt-in
   subobject-bounds hardening is enabled) has no obvious analogue here: there is no narrowed boundary
   to walk backward past.

**Prediction:** the existing, unmodified M9 pass should transparently handle a real
`container_of`-shaped access, with zero pass changes, because pointer subtraction and forward field
access are the same IR instruction kind under this pass's own generic handling.

## Empirical test

New file `veda-core/compiler/veda_demo_container_of.c`: a `struct container` with a `struct
link_node link` EMBEDDED by value (mirroring `struct task_struct { ...; struct list_head tasks; };`),
plus a `tag` field before it and a `payload` field after it. `main()`:
1. Allocates one `struct container` via `veda_malloc_raw`, writes `tag=0xAAAA`, `payload=12345`.
2. Forward-navigates to `struct link_node *l = &c->link` -- exactly what real Linux list-walking code
   sees (only a `struct list_head *`, never the container directly).
3. Backward-reconstructs via the real macro shape:
   `#define container_of(ptr,type,member) ((type*)((char*)(ptr) - __builtin_offsetof(type,member)))`.
4. Reads `back->tag` and `back->payload` -- two fields OTHER than the one `container_of` started
   from, through the reconstructed pointer, deliberately proving genuine backward reconstruction
   (correct base *and* correct bounds), not merely "the subtraction produced some in-range garbage
   that happened not to trap."

### Step 1 -- confirm the IR lowering (fact #1 above), before running anything

```
clang --target=riscv64 ... -S -emit-llvm -o raw.ll veda_demo_container_of.c   # no -fpass-plugin
```
Result (`raw.ll`, real Clang 21.1.8 output):
```llvm
%4 = load ptr, ptr %l, align 8
%add.ptr = getelementptr inbounds i8, ptr %4, i64 -8
store ptr %add.ptr, ptr %back, align 8
```
Confirmed: a plain `GetElementPtrInst` with `i64 -8` (the real `offsetof(struct container, link)` on
this layout), the identical instruction kind used for every ordinary forward field GEP in the same
function. Hypothesis fact #1 empirically confirmed, not assumed.

### Step 2 -- build and run through the real, unmodified pass and hardware

Built via the same pipeline `run_veda_demo_tests.sh` already uses (`clang -fpass-plugin=VedaShadowPropagation.so -c`,
linked with `crt0.o`/`veda_compiler_rt.o`/`veda_rt.o`/`veda_rt_asm.o`, run under `sail_riscv_sim
--config veda_test_sail.json`). **Zero modifications to `VedaShadowPropagation.cpp` or any other
existing file** -- only the new demo `.c` file.

```
HTIF located at 0x80001018
Entry point: 0x80000000
SUCCESS
```

Post-pass IR (`veda_demo_container_of.ll`) confirms the mechanism precisely:
```llvm
%add.ptr = getelementptr inbounds i8, ptr %16, i64 -8
call void @veda_shadow_attach(ptr %add.ptr, i32 %.shadow11)   ; SAME Object_ID shadow, unchanged
...
%tag2 = getelementptr inbounds nuw %struct.container, ptr %17, i32 0, i32 0
%18 = ptrtoint ptr %tag2 to i64
%19 = sub i64 %18, 4096                                        ; offset correctly recomputed to 0
call void @veda_rt_ocl_d(i32 %.shadow12, i64 %19, ptr %veda.ocl.scratch)
```
The `-8` GEP undoes the `+8` forward GEP that produced `l`; `computeOffset()`'s
`ptrtoint(Addr) - kVedaNullBase` naturally recomputes offset 0 (container's own base) from the
corrected pointer bit pattern, entirely through the SAME generic GEP/dereference-rewrite code path
M9 already established for `cur->next`. No special-casing anywhere.

### Step 3 -- mutation test (this project's standing discipline: confirm the check is real, not vacuous)

Temporarily removed the `container_of` subtraction (`back = (struct container *)l;` directly --
misinterpreting the embedded field pointer as if it WERE the container's own base). Rebuilt, reran:
```
FAILURE: 1 (0x00000001)
```
Correctly fails at the first check (`got_tag != 0xAAAA`, since `back->tag` at the mutant's wrong base
reads `link.next`'s real stored value, not the real tag) -- confirms the real (non-mutated) demo's
`SUCCESS` is a genuine, meaningful, hardware-checked result: real backward pointer arithmetic,
reconstructing the correct base address, reading real data back through real OCL.D against real
capability bounds -- not a false pass.

### Step 4 -- full regression, zero collateral change

Wired into `run_veda_demo_tests.sh` as a third permanent case (alongside the M9 linked-list and
out-of-bounds demos):
```
=== Toolchain Milestone 9 (real end-to-end demo) test results ===
PASS      veda_demo_linked_list
PASS      veda_demo_oob_neg
PASS      veda_demo_container_of
---
3/3 passed
```

## Finding

**The existing, unmodified Milestone 9 compiler pass already correctly handles the real Linux
`container_of()` pattern, with zero code changes, verified empirically end-to-end through the real
LLVM pass and real Sail hardware model -- not just in the narrow, single-flat-struct shape this demo
tests, but for the general reason stated in the hypothesis (sign-agnostic GEP propagation + no
subobject-bounds narrowing anywhere in this architecture).**

This directly refines, not overturns, the prior Linux-port-feasibility research's `container_of`
finding:

- The research was reasoning **by analogy to real CHERI**, where `container_of` breaks under a
  specific, real, *opt-in* hardening feature (subobject bounds) that narrows a field-pointer
  capability's bounds to just that field. That analogy does not transfer to Veda-Core as currently
  designed, because Veda-Core has never implemented (and per this finding, may now have a real,
  concrete reason not to implement) any equivalent subobject-bounds narrowing -- whole-object bounds
  is not a stopgap, it is what makes this exact backward-reconstruction idiom fall out for free.
- **This narrows, but does not close, the Linux-port gap.** `container_of` was ONE named blocker
  among several in that research (others: raw pointers crossing untracked provenance boundaries --
  e.g. through `void*`, across an unattributed/non-instrumented function call, through inline asm, or
  via a value round-tripped through a non-pointer integer type long enough that Shadow-map provenance
  is lost; multi-level/VLA GEP chains, explicitly left unrewritten by this same pass's own stated
  scope limits; the pass's own single-translation-unit, no-indirect-call, no-multi-level-global-GEP
  boundaries). Those remain real, and are NOT retested or resolved by this milestone.
- **A genuine, new architectural argument, not just a compatibility footnote:** this result gives a
  concrete, positive reason (beyond "we haven't built it yet") for Veda-Core to deliberately NOT adopt
  CHERI-style subobject-bounds hardening as a future hardening feature, specifically because doing so
  would reintroduce, by construction, the exact `container_of` breakage this milestone just showed
  Veda-Core currently avoids. This is a real trade-off to name explicitly in any future hardening
  proposal, not an oversight to quietly fix later: whole-object bounds trades away some
  intra-object memory safety (an adjacent field can still be reached from a stray field pointer,
  same as ordinary C) for pervasive compatibility with backward-reconstruction idioms real kernels
  rely on throughout.

## Honest scope limits (not yet tested, real open items)

- Only a single-level embedding (`struct container` directly embeds `struct link_node`) was tested.
  Real Linux code sometimes chains multiple `container_of`-equivalent reconstructions, or embeds a
  `struct list_head` inside a struct that is itself reached only through another pointer indirection
  -- not retested here.
- The field pointer (`l`) was used immediately, in the same function, as the one that took its
  address -- matching this pass's own already-documented intraprocedural-only shadow-propagation
  scope. A `container_of` call on a field pointer received as a function *parameter*, loaded back out
  of a *different* tracked object, or passed through an unattributed helper function was not tested,
  and per the pass's own stated boundaries (Phase A signature rewriting only instruments
  module-defined, non-runtime-helper functions; PointerParamIndices-seeded shadow propagation only
  covers direct calls) may behave differently.
- This does not, by itself, make a full Linux port newly feasible -- it removes exactly one named
  blocker from that research's list, under the specific shape tested.

## Files changed

- **New**: `veda-core/compiler/veda_demo_container_of.c`.
- **Modified**: `veda-core/compiler/run_veda_demo_tests.sh` (registers the new demo as a third
  permanent positive case).
- No changes to `VedaShadowPropagation.cpp`, `veda_rt.c/.h`, or any Sail/RTL source -- this milestone
  is a pure empirical test of already-shipped M9 machinery.
