# Toolchain Milestone 20 (part 4): The Four Kernel-Critical Gaps

Follows on from `TOOLCHAIN_MILESTONE_20_REMAINING_FIXES_RESULTS.md` -- addresses the four gaps
identified while projecting the M19 audit findings onto real Linux kernel idioms: bulk struct
copies, unions, per-CPU addressing, and RCU. Two are real fixes (union punning; a correction of
the struct-copy finding's own severity). Two are honest, source-grounded research findings, not
code changes -- per-CPU addressing needs a new design, not a propagation rule, and the shadow-table
concurrency/RCU-ordering question turned out to be **narrower and more precisely characterized**
than first thought, once Linux's own real macros were read in full (not assumed).

## 1. `memcpy`/struct-assignment: confirmed real, unfixed in this milestone

**Empirical finding**: `dst = *src;` for a small (16-byte, 2-field) struct compiles, even at `-O0`,
to `call void @llvm.memcpy.p0.p0.i64(...)` -- a completely opaque intrinsic, not per-field
scalar GEP/load/store the pass could see through. Confirmed via direct pre-pass IR inspection
(`veda_demo_struct_copy.c`), not assumed from Clang's general reputation.

**Runtime behavior, confirmed via `sail_riscv_sim`**: the copied pointer field's raw bits survive
correctly (memcpy moves real bytes), but its shadow does not -- dereferencing it afterward hits a
genuine **raw memory fault** (`fetch-access-fault`, not a Veda-Core capability trap), since the
access is left completely unrewritten and the fake offset-token bit pattern is not real, backed
memory.

**Why this milestone does not attempt a fix**: correctly propagating a shadow through `memcpy`
requires knowing WHICH byte ranges within the copied region are pointer-typed fields -- information
`@llvm.memcpy`'s own signature (`dst, src, len, isvolatile`) does not carry at all. A real fix would
need the pass to trace back to the GEP/alloca/malloc call that established `dst`'s and `src`'s real
struct TYPE, enumerate that type's own pointer-typed sub-fields (recursively, for nested structs),
and emit per-field shadow-copy calls alongside the `memcpy` -- a genuinely new, type-aware analysis
pass component, not a bounded extension of the existing per-instruction dispatch loop. Real, honest
scope limit, left for a dedicated future milestone.

## 2. Union type-punning: a real gap, found and FIXED this milestone

**Empirical finding**: `union { struct node *ptr; unsigned long bits; }` -- writing through `.ptr`
then reading through `.bits` (same address, zero offset, no GEP at all -- confirmed via pre-pass IR)
initially failed identically to the `memcpy` case (raw memory fault), for a distinct reason: the
`uintptr_t`-round-trip fix (Toolchain Milestone 20 part 3) only recognized an i64 LOAD's shadow when
that SPECIFIC load had a direct `IntToPtrInst` user -- but the union's own load (`u.bits`) is
consumed by an intermediate local-variable store first, one hop further away than that narrow check
covered.

**Fix**: `PointerStoredAddrs`, a real, compile-time-only `DenseSet<Value*>` recording every address
that has received a pointer-typed store within the current function (populated at the SAME site the
existing pointer-typed store fallback already runs). The i64-load extension's gate is now
`(has an IntToPtrInst user) OR (Addr is in PointerStoredAddrs)` -- the second condition precisely
targets "this address was used for a pointer at some point in this function," a real, own-address
provenance signal, still zero-overhead for the overwhelming majority of i64 loads that never
alias a pointer-typed store at all.

**Verified**: `veda_demo_union_punning.c` -- both the direct-member read (`u.ptr`) and the punned,
same-offset integer-then-cast-back read (`u.bits`) now correctly recover the real object and its
real data (`SUCCESS`). Mutation test (deliberately wrong expected value) correctly fails. Full
regression (demo 8/8, FileCheck 8/8, all compartment/scheduler suites, runtime 2/2, Sail 63/63)
stays green.

## 3. Per-CPU addressing (`this_cpu_ptr`/`per_cpu_ptr`): real, structural, needs new design

**Real source read in full**: `/usr/src/linux-headers-*/include/linux/percpu-defs.h`,
`include/asm-generic/percpu.h` (this machine's own installed kernel headers -- the actual Linux
implementation, not summarized from memory).

**Finding**: `this_cpu_ptr`/`raw_cpu_ptr`/`per_cpu_ptr` all bottom out in
`SHIFT_PERCPU_PTR(__p, __offset) = RELOC_HIDE(PERCPU_PTR(__p), (__offset))`. `RELOC_HIDE` is a
deliberate GCC/Clang trick -- it round-trips the pointer through an **empty, identity inline-asm
statement** (`__asm__ ("" : "=r"(ptr) : "0"(ptr))`-shaped) specifically to make the optimizer treat
the resulting value as opaque, unrelated to its input, so it cannot fold or hoist per-CPU address
computation across a context switch. At the LLVM IR level, this is a `CallInst` to an `InlineAsm`
value, not a `Function*` -- `Call->getCalledFunction()` returns `nullptr` for it, the SAME code path
that already (deliberately) treats indirect calls as out of scope.

**Why this is not "just needs a propagation rule"**: the opacity is the whole POINT of `RELOC_HIDE`
-- it exists specifically to defeat the KIND of forward dataflow analysis this pass performs. A real
fix has two honest options, neither a quick patch: (a) special-case-recognize the exact
`RELOC_HIDE`/per-CPU inline-asm shape and thread a shadow through it anyway (fragile -- tied to one
specific kernel-build's exact macro expansion, would break silently on a kernel version that changes
the trick), or (b) define a Veda-Core-native per-CPU primitive that achieves `RELOC_HIDE`'s real goal
(preventing incorrect compiler hoisting across a context switch) WITHOUT opaque inline asm -- e.g. a
real Veda-Core instruction or intrinsic the pass is taught to recognize by construction. Option (b)
matches this project's own hardware-first philosophy far better than reverse-engineering GCC's own
optimizer-defeat trick. Either way, this is a genuine, separate design milestone, not attempted here.

## 4. RCU: the real finding is narrower than first estimated -- corrected, not just documented

**The previous turn's own framing over-stated this.** Having now read the actual kernel macros in
full (`include/linux/rcupdate.h`, `include/asm-generic/barrier.h`), the real mechanics are NOT
opaque to this pass at all on the generic/RISC-V-relevant path:

- `rcu_assign_pointer(p, v)` expands (non-constant case) to: `uintptr_t _r_a_p__v = (uintptr_t)(v);`
  then `smp_store_release(&p, ...)`, which itself expands (generic `__smp_store_release`) to
  `__smp_mb(); WRITE_ONCE(*p, v);` -- a `ptrtoint`, a real fence instruction, then an ORDINARY,
  non-atomic, volatile `store`. Not an LLVM atomic store; not opaque inline asm hiding the pointer
  itself (the fence is a separate instruction that never touches the tracked value).
- `rcu_dereference(p)` bottoms out in `READ_ONCE(p)` -- an ordinary volatile `load`.

**This means the direct-round-trip (`ptrtoint`/fence/store) and plain pointer store/load mechanisms
THIS SESSION ALREADY SHIPPED (Toolchain Milestone 20 parts 1 and 3) already correctly handle RCU's
real publish/consume mechanics.** Verified empirically, not assumed: `veda_demo_rcu_pattern.c`, a
minimal, faithful reproduction of the exact real macro expansion (`fence rw,rw` inline asm between
the ptrtoint and the real store, matching `__smp_mb()`), compiled and run under `sail_riscv_sim` --
**`SUCCESS`**, and a mutation test (a deliberate out-of-bounds access through the RCU-published
pointer) correctly produces a real, genuine `VEDA_CAUSE_BOUNDS_VIOLATION` trap (`mtval=0x21`,
confirmed via `--trace-exception` reading the FIRST trap before an unrelated, expected
missing-trap-handler cascade -- a real, initially-confusing artifact of this diagnostic reproducer
having no installed `mtvec`, not a second bug; resolved by reading the trace from its start rather
than only its tail).

**What remains genuinely, honestly unverifiable -- and why**: this session's OWN prior finding
(`ATOMIC_AQRL_SAFETY_ANALYSIS.md`, written earlier in this project, re-read and confirmed this
session) already establishes that **Veda-Core, in both Sail and RTL, is genuinely single-hart,
strictly in-order** -- there is no second, independent instruction stream anywhere in this project's
own simulators. The shadow table itself (`g_shadow_keys`/`vals`/`used` in `veda_compiler_rt.c`) is a
single, global, entirely unsynchronized array -- confirmed by direct re-read this session. Whether a
DIFFERENT hart's `rcu_dereference` would correctly observe a first hart's `rcu_assign_pointer`
through this table is consequently **not an empirically testable question in this project's current
infrastructure at all** -- there is no second hart to test it with, mirroring exactly the same
honest limitation the existing `aq`/`rl` analysis already named for Veda-Atomic. This is *not* "we
didn't get to it" -- it is the same real, structural, load-bearing warning that document already
established, now shown to apply identically to the compiler's own shadow-tracking side-table, not
just to the ISA's own atomic instructions.

**The deeper point worth naming precisely, even though untestable today**: a lock alone would not be
sufficient even if a second hart existed. Mutual exclusion (no two harts corrupt the table
simultaneously) is a different property from publication ordering (a second hart's `rcu_dereference`,
having correctly observed the real pointer via RCU's own release/acquire pair, ALSO reliably
observing the shadow-table's own, separate write). The shadow-table write in this pass's current
codegen happens strictly AFTER the real pointer store, with no fence of its own -- meaning even a
perfectly-locked table would need its own acquire/release discipline correctly composed with
whatever real barrier the surrounding C code already uses, not simply "add a mutex." This is named
here as the correct, precise formulation of the open problem for whenever real multi-hart execution
is added to either the Sail or RTL model -- exactly the same kind of "reopened as a hard prerequisite"
warning `ATOMIC_AQRL_SAFETY_ANALYSIS.md` already sets a precedent for.

## Summary

| Gap | Outcome |
|---|---|
| `memcpy`/struct-copy | Confirmed real (raw fault), NOT fixed -- needs a type-aware analysis, a real future milestone |
| Union type-punning | Fixed and verified (`PointerStoredAddrs` heuristic) |
| Per-CPU (`this_cpu_ptr`) | Confirmed real and structural (`RELOC_HIDE`'s deliberate opacity) -- needs new design, not a propagation rule |
| RCU | Corrected: the PUBLISH/CONSUME mechanics already work (verified empirically); the CROSS-HART table-visibility question is real but untestable in this project's current single-hart-only infrastructure -- same honest limitation already established for Veda-Atomic's own `aq`/`rl` bits |

## Files changed

- `veda-core/compiler/VedaShadowPropagation.cpp` -- `PointerStoredAddrs` set added; i64-load
  extension's gate broadened; file/comment updates.
- `veda-core/compiler/veda_demo_struct_copy.c`, `veda_demo_union_punning.c`,
  `veda_demo_rcu_pattern.c` -- new research/regression probes.
- `veda-core/compiler/run_veda_demo_tests.sh` -- registers `veda_demo_union_punning` and
  `veda_demo_rcu_pattern` as permanent cases (8/8). `veda_demo_struct_copy.c` deliberately NOT
  registered -- it demonstrates a confirmed-but-unfixed gap (expected outcome is a fault, not
  `SUCCESS`), matching this project's own convention for diagnostic-only reproducers.
