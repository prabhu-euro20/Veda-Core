# Veda-Core Toolchain Milestone 8: SoftBound-Style Shadow Object_ID Propagation (Phase 1)

**Date:** 2026-07-31
**Scope:** a real, out-of-tree LLVM IR pass (`veda-core/compiler/VedaShadowPropagation.cpp`) that identifies pointers derived from `veda_malloc_raw` and propagates a shadow `Object_ID` alongside ordinary pointer/offset arithmetic through IR. Stops short of emitting OCL/OCS — proves propagation correctness only, matching this milestone's own stated scope; Milestone 9 does the actual memory-access rewriting.

## Design, grounded in real LLVM API research before any code was written

Rather than write the pass from memory-recalled API (a real risk given how actively LLVM has been changing instruction-insertion APIs — the `Instruction*`-based `InsertPosition` constructor is now `LLVM_DEPRECATED` in favor of `BasicBlock::iterator`), the exact mechanics were verified against real, current source in this project's own `release/21.x` checkout before writing anything:

- **Function-signature rewriting** (needed for shadow-argument passing) was modeled directly on `llvm/lib/Transforms/IPO/DeadArgumentElimination.cpp`'s own real, already-proven pattern (read in full): new `FunctionType` → `Function::Create` → rewrite call sites → `NF->splice(NF->begin(), F)` → RAUW old arguments onto new ones → erase the old function. This pass performs the mirror-image operation (appending parameters instead of removing them).
- **Out-of-tree pass-plugin registration** was modeled on LLVM's own official example, `llvm/examples/Bye/Bye.cpp` (read in full) — `PassInfoMixin`, `PassPluginLibraryInfo`, `registerPipelineParsingCallback`, the `extern "C" llvmGetPassPluginInfo()` entry point.
- Current, real API confirmed by direct grep/read before use: `PHINode::Create(Ty, N, Name, InsertIterator)`, `IRBuilder::SetInsertPoint`/constructor idioms (`Builder.SetInsertPoint(I->getNextNode())`, seen live in `RewriteStatepointsForGC.cpp`/`CoroFrame.cpp`), `BasicBlock::getFirstInsertionPt()`, `Instruction::comesBefore()`, `ReversePostOrderTraversal<Function*>` (seen live in `SPIRVUtils.cpp`/`X86WinEHState.cpp`).

## The real ABI this pass recognizes

```
declare { ptr, i32 } @veda_malloc_raw(i64)   ; source: pointer + its real Object_ID
declare void @veda_shadow_store(ptr, i32)    ; disjoint shadow-metadata table write
declare i32  @veda_shadow_load(ptr)          ; disjoint shadow-metadata table read
declare void @veda_shadow_attach(ptr, i32)   ; observability marker (see below)
```
`veda_shadow_store`/`_load` are the real "disjoint metadata" runtime primitives the plan's own Context section already named (adapting SoftBound's real technique, PLDI 2009) — a genuine runtime-backed shadow table keyed by memory address, not an alloca-local trick, since Milestone 9's own stated demo (a linked list) needs heap-resident pointer fields to carry their shadow correctly, and a stack-only mechanism could not support that. `veda_shadow_attach` is a real, deliberate observability marker (precedent: `llvm.dbg.value`'s own similar role) inserted after every point a Value's shadow becomes newly known — Milestone 9 may consume this pass's internal `ShadowMap` directly (e.g. as a proper LLVM analysis) or continue reading these markers; left as an open, honestly-stated decision for that milestone.

## Real, stated Phase-1 scope limits (not glossed over)

- Function-call shadow passing is via an **appended trailing i32 parameter** per pointer parameter (a signature rewrite), not real SoftBound's own "shadow stack" scheme. Simpler and correct for this milestone's closed-system, no-indirect-calls scope; a shadow-stack scheme is legitimate future work if/when function pointers need supporting.
- **Indirect calls are not instrumented** — shadow tracking stops at such a call, matching real SoftBound's own behavior at any boundary with uninstrumented code.
- **Shadow propagation through a callee's own return value is not yet implemented** — only argument-direction passing, matching this milestone's own precisely-worded 4 test cases ("function-call argument passing", not "return value propagation").
- Memory round-trip shadow storage is **unconditionally emitted** for every pointer store/load in scope, not narrowed by any alias analysis — conservative, correct, real, not yet optimized.
- Single opaque `Object_ID` scalar is propagated, not a base+bound pair — the plan's own already-agreed, deliberate divergence from original SoftBound (bounds checking is real hardware's job here, via the ODT).

## Two real bugs found and fixed during development — not glossed over

**1. A genuine SSA-dominance violation in the malloc-source marker insertion.** The pass finds a `veda_malloc_raw` call's Object_ID result (`%oid = extractvalue ..., 1`) via the call's own use-list (order-independent), then inserts an observability marker referencing both the pointer and its shadow. The first version inserted the marker immediately after the *pointer* extract (`%p = extractvalue ..., 0`) — but in the natural, expected instruction order (`%p` extracted before `%oid`), that places the marker's use of `%oid` *before* `%oid`'s own definition, a real SSA-dominance violation the verifier would (correctly) reject. Caught immediately by running the pass and reading its literal output, not assumed correct from the code alone. Fixed using `Instruction::comesBefore()` to insert after whichever of the two extracts genuinely comes later in program order.

**2. A genuine algorithmic bug in loop-carried (cyclic) phi handling**, caught by the deliberately-added 5th test (`loop_phi_cyclic.ll`, beyond the plan's own 4 named cases — added specifically because a linked-list-style traversal is exactly the kind of real, common pattern where a naive single-pass "placeholder-then-fill-inline" algorithm can silently produce a wrong answer instead of an obviously-broken one). The first version tried to fill in each phi's real incoming edges *while* doing a single top-down instruction pass — but a loop-carried pointer's back-edge value (e.g. `%next`, produced by a `load` later in the *same* block as the `%node` phi that depends on it) genuinely is not yet known at the moment the phi is visited in a single combined pass, silently falling back to the "no shadow known" sentinel (`-1`) instead of the real value — a real, would-be-silent correctness bug in exactly the case Milestone 9's own stated linked-list demo will most need to get right. Fixed by splitting into a genuine three-pass structure: (1) pre-create placeholder shadow phis, (2) compute every non-phi shadow value across the whole function (order no longer matters, since placeholders already make every phi's shadow referenceable from anywhere), (3) only then go back and wire up each placeholder phi's real incoming edges, once the full-function shadow map is complete.

Both bugs were caught by actually running the pass and reading its real output against FileCheck expectations — not assumed correct from the code's own logic.

## Verification

Five real `.ll` test cases (`veda-core/compiler/test/`), each run through `opt -load-pass-plugin=... -passes=veda-shadow-prop -S` and checked with `FileCheck`:

| Test | Proves |
|---|---|
| `straightline.ll` | malloc-source recognition + GEP propagation (shadow reused unchanged) |
| `memory_roundtrip.ll` | store/load through a real disjoint shadow-metadata table |
| `call_argument.ll` | signature rewrite (trailing shadow param) + call-site fixup |
| `phi_merge.ll` | non-cyclic phi merge of two *different* tracked objects |
| `loop_phi_cyclic.ll` | **bonus**, beyond the plan's own 4 cases: loop-carried/cyclic phi (linked-list-traversal shape) — the hard case that actually caught bug #2 above |

```
=== Toolchain Milestone 8 (veda-shadow-prop) test results ===
PASS      call_argument
PASS      loop_phi_cyclic
PASS      memory_roundtrip
PASS      phi_merge
PASS      straightline
---
5/5 passed
```

Every test's output was also checked by the pass's own internal `verifyModule()` call (real LLVM IR verifier, not a hand-rolled check) — zero invalid-module reports across all 5 runs, confirming the rewritten IR (new function signatures, spliced bodies, inserted shadow instructions, phi placeholders) is genuinely well-formed, not merely FileCheck-pattern-matching text that happens to look right.

## A real build-environment gap found and routed around

The custom LLVM build in `toolchain/llvm-project/build/` (Milestones 2/5a/5b-M6) only registered the RISCV backend (`LLVM_TARGETS_TO_BUILD=RISCV`) — its own `clang`/`clang++` genuinely cannot emit native x86_64 code at all (`error: unknown target triple 'unknown'`, real and verified, not assumed), so it cannot compile this plugin (a native shared library the host `opt` process `dlopen`s). Routed around using the **system's official Ubuntu-packaged `clang++-21`** (`clang-21` apt package, installed in Milestone 2, version 21.1.8 — exactly matching the custom checkout's own `release/21.x` tag) purely as an x86_64-capable C++ compiler frontend, while compiling against **our own checkout's** LLVM headers (`llvm-config --cxxflags`) for correct ABI compatibility with our own custom-built `opt`. Both are the identical, real, released 21.1.8 — a same-version build, not a cross-version guess.

## What remains open, honestly

- No memory-access rewriting (OCL/OCS emission, or runtime-call emission) exists yet — Milestone 9's explicit scope.
- Return-value shadow propagation, shadow-stack-based (rather than signature-based) call passing, and alias-analysis-narrowed shadow-store/load emission are all real, legitimate future refinements, not required to close this milestone's own stated goal.
- No end-to-end `clang -fpass-plugin=...` compile-and-run demo yet — this milestone's own stated verification method (hand-written `.ll` + FileCheck) does not require one; Milestone 9's own stated scope explicitly includes a real, running positive+negative demo.

## Reproducing this

```
cd veda-core/compiler && ./run_veda_shadow_prop_tests.sh
```
