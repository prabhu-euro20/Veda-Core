# Extern Globals: Design Direction Decided, Implementation Deferred

## The gap, restated precisely

`TOOLCHAIN_MILESTONE_13_RESULTS.md`'s own "Not yet built" section: extern globals
(`GlobalVariable::isDeclaration()==true`, especially incomplete-array-typed ones like this project's own
real `extern char _end[];`) are left completely unrewritten by Phase B1 — not silently mis-sized, but not
protected either. A `veda_compartment`-attributed function touching such a global today gets an ordinary,
uninstrumented pointer access.

## Official-source research (both primary sources read in full, not summarized from memory)

**LLVM's own semantics** (`llvm.org/doxygen/classllvm_1_1GlobalVariable.html`, fetched directly):
`isDeclaration()` — "Return true if the primary definition of this global value is outside of the current
translation unit." `hasInitializer()` — "Definitions have initializers, declarations don't." This confirms
precisely why Phase B1 cannot compute real bounds for `extern char _end[];` from IR alone: the actual
storage (and its real size) is defined in a different translation unit, or — in `_end`'s specific case — is
a linker-synthesized address marker with no real "size" at all, not even conceptually.

**Real CHERI's own answer to this exact problem** (`CTSRD-CHERI/clang`'s `cheri_init_globals.h`, the
official upstream CHERI-clang header, fetched and independently re-confirmed twice, verbatim):

```c
if (!isFunction && (reloc->size != 0)) {
  src = __builtin_cheri_bounds_set(src, reloc->size);
}
```

When the linker-computed `reloc->size` is zero (exactly the extern/incomplete-size case), CHERI does
**not** attempt to bound the capability — it leaves it unbounded and moves on. No error, no warning, a
deliberate, silent fallback. Critically, this is still a real, tagged, provenance-tracked CHERI capability
— unbounded, but not unprotected: it still can't be forged, and Veda-Core's own architectural equivalent
of "unbounded but real" is a wide, whole-source-region capability, not the complete absence of one.

## Honest architectural gap this exposes in Veda-Core specifically

Veda-Core's *current* fallback ("leave it unrewritten") is **weaker** than CHERI's own precedent, not
merely different: an unrewritten access is a plain pointer dereference, outside the capability system
entirely — zero enforcement, not "wide but real" enforcement. This is worth stating plainly rather than
glossing over, since Veda-Core's own core claim (`P(bypass)=0` for globals it protects) is silently scoped
to exclude extern globals today, and that scoping is not yet written down anywhere as an explicit
disclaimer.

## Proposed design direction (Veda-Core-specific synthesis, not a copy)

Veda-Core cannot literally reuse CHERI's "unbounded capability" idea (Veda-Core has no unbounded-capability
concept at the point of access — a capability's `Length` is always a real, checked field). The genuine
Veda-Core-shaped translation of CHERI's own precedent: **route an extern global's access through the SAME
whole-source-region capability Phase B1's bootstrap ceremony already establishes** (the `.rodata` or
`.data+.bss` SOURCE region, currently `c8`/`c9`, per-global capabilities are `OCA`+`CSetBounds`-narrowed
*from*) — i.e., treat an extern global exactly like CHERI treats a zero-size relocation: fall back to the
coarsest real bound already available, not zero bound.

The real obstacle: `c8`/`c9` are explicitly bootstrap-only today ("discarded the moment minting finishes"
— `runtime/veda_rt_asm.S`'s own header comment), not available once a compartment function actually runs.
Making them persistent would reopen the exact CRF-register-pressure wall `TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md`
just closed for a different register. The cleaner fix, consistent with that milestone's own resolution
pattern: mint the wide, whole-region fallback capability into the **table** (`g_veda_global_cap_table`,
now exactly-sized per Toolchain Milestone 15) at bootstrap, exactly like every other cached per-global
capability — accessed via the already-persistent `c11`, not a new register. Phase B1 would recognize an
extern `GlobalVariable` used from inside a compartment function and emit ONE additional table entry (a
region-selector-only "whole source region" capability, no per-symbol narrowing) that every extern-global
access in that module shares.

## Why implementation is deferred, not built now

This project's own established, repeatedly-applied discipline (explicitly restated for the CRF-exhaustion
fix, Milestone 12's alloca work, and every prior milestone): do not build code with no test exercising it.
Checked directly against the real, current codebase (not assumed): the one real extern-global usage that
exists today, `runtime/veda_rt.c`'s own `extern char _end[];`, is used exclusively inside `veda_rt_init` —
a bootstrap-only function, **not** `veda_compartment`-attributed, running in the same "wide open PCC, no
enforcement active yet" window `veda_rt_init_globals` already relies on. It is not currently reachable from
inside a live compartment at all, so the gap this document analyzes has zero live exposure in the current
corpus — there is no real test scenario today that would exercise, or fail without, this fix.

**Decision: the design direction above is adopted and recorded now** (matching `TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md`'s
own precedent of deciding a mechanism ahead of its trigger), **implementation is deferred** until either
(a) a real program needs a `veda_compartment`-attributed function to touch an extern global, or (b) this
gap is promoted ahead of other work by direct instruction. Building it now, with no real test able to prove
it correct, would itself violate the same rigor this document's own research was done in service of.

## Open questions a future implementation must resolve, named honestly now

- Whether "whole source region" is the right fallback granularity, or whether a real multi-translation-unit
  Veda-Core program would need per-extern-symbol sizing information the linker *does* have (via `.size`
  directives) that Phase B1 currently has no mechanism to consume — LLVM IR alone, scoped to one
  translation unit, cannot see this; a real fix might need a linker-cooperation mechanism this toolchain
  does not have today (the same real gap `TOOLCHAIN_MILESTONE_13_RESULTS.md` already named for
  `__cap_relocs` generally).
- Whether a program with BOTH a real per-global table (Milestone 13/15) AND an extern-global fallback entry
  needs the fallback capability to be individually revocable, or whether "shared, coarse, never
  individually narrowed" is acceptable for v1 — undecided, not assumed.
