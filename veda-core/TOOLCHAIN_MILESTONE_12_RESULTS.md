# Toolchain Milestone 12: Hardware-Native Protection for Stack-Local C Variables

## Context

Toolchain Milestone 11 closed one half of Milestone 10's finding (compiled C cannot run inside a
narrow `OCInvoke`-bound compartment): ABI-mandated callee-saved-register spills now route through
capability-checked `OCS.D`/`OCL.D` against a reserved `C15`. The other, still-open half, explicitly
named in Milestone 11's own "Not yet built" section: ordinary C **local variables**
(`int arr[4];`, an LLVM `AllocaInst`) were completely unprotected — any load/store against one went
through ordinary, un-redirected `sd`/`ld`, invisible to the whole capability model, and any two
adjacent local arrays could silently overflow into each other exactly like on any conventional stack.

Before any code, per this project's own standing instruction, a 5-track official-source research
program (own `VedaShadowPropagation.cpp`/runtime architecture; own LLVM `eliminateFrameIndex`/
`SelectionDAG` internals plus the real, in-tree `SafeStack.cpp` precedent; the real, official
CHERI-LLVM fork's own `CheriBoundAllocas.cpp` plus CHERI's own published scope decisions; own
`OCA`/`CSetBounds` real Sail semantics; own runtime calling-convention state) grounded the design in
`.claude/plans/jolly-leaping-lark.md` (approved plan). Every numeric claim used in the design was
personally re-verified against source before finalizing — `FixedCSRFIMap`'s 13 entries,
`VEDA_OCA`/`VEDA_CSETBOUNDS`'s real funct7 encodings, and the real mnemonic assembleability of
`oca`/`csetbounds` (`llvm-mc -show-encoding`).

## Design (as implemented)

**New Phase B0 in `VedaShadowPropagation.cpp`**, gated on `F.hasFnAttribute("veda_compartment")`,
run before the existing dataflow loop: for every static `AllocaInst` in the function's entry block,
compute its real byte size (`DataLayout::getTypeAllocSize`), assign it a fixed, compile-time byte
offset within a dedicated locals sub-region of the SSC region already established by Milestone 11,
and seed `Shadow[AI]` with that offset as a compile-time `i32` constant (not a runtime Object_ID,
unlike heap objects — a real simplification: a static alloca's size needs zero runtime dependency).
A parallel `AllocaBase`/`AllocaSize` map (keyed identically to `Shadow`) tracks each tracked value's
own `ptrtoint`'d base and real byte size, propagated through the existing GEP/BitCast logic
unmodified, and is what actually distinguishes "this shadow means a stack-local region offset" from
"this shadow means a heap Object_ID" at Load/Store rewrite time. A PHI merging alloca-derived and
other-provenance pointers is diagnosed via a new `isAmbiguousAllocaPhi` guard and left unrewritten
(a real, honest, narrow gap — matching this pass's own established convention for untracked
addresses — not a silent misinterpretation of a region-offset as an Object_ID).

**New runtime helper chain**, mirroring the heap-object path's own layering
(`veda_rt_ocl_d`→`veda_ocl_d`→`veda_bind_scratch_asm`) but with no Object_ID and no fresh
`veda.bind` (the target is always the already-bound `C15`): `veda_rt_ocl_stack_d`/
`veda_rt_ocs_stack_d` (`compiler/veda_compiler_rt.c`) → `veda_ocl_stack_d`/`veda_ocs_stack_d`
(`runtime/veda_rt.c`) → `veda_ocl_stack_d_scratch_asm`/`veda_ocs_stack_d_scratch_asm`
(`runtime/veda_rt_asm.S`), the real instruction sequence:
```asm
oca        c13, c15, a0   # region_offset -- position within c15's whole region
csetbounds c13, c13, a2   # size -- narrow to exactly this local variable's own bytes
ocl.d/ocs.d ...           # the real, hardware-enforced access
```
`C13` is the hand-picked scratch register (grep-audited collision-free, mirroring how Milestone 11
picked `C15` over the informally-used `C14`). Real, load-bearing instruction ordering (re-verified
against `veda_cap_insts.sail`): `OCA` must run first to reach an arbitrary offset within `C15`'s
whole region — `CSetBounds`'s own new `Base` starts at the capability's *current* offset, so
`CSetBounds`-first only works when offset is already 0.

## Three real bugs found and fixed during implementation and verification (empirically, not by inspection alone)

All three were found by actually running the compiled pipeline under `sail_riscv_sim` and tracing —
this project's own standing empirical-debugging discipline — not by assumption.

**1. Offset-space collision between Phase B0's alloca region and nested compartment-attributed
callees' own CSR spills.** The first working version anchored alloca offsets at the *top* of the
4096-byte SSC region (`kVedaSSCRegionLength - bytes_reserved_so_far`), reasoning this stayed clear
of the outermost compartment function's own Milestone-11 CSR spills (which land at
`SP_entry-8..SP_entry-104`, and `SP_entry = 4096` at compartment entry). This is true only for the
*outermost* function. This milestone's own runtime helpers (`veda_ocl_stack_d`/`veda_ocs_stack_d`)
are themselves `veda_compartment`-attributed (needed for a separate reason, finding 2 below) and get
called from inside the outer function's own call graph — their *own* CSR spills land at *their own*
current-SP-relative offset, and by the time such a nested call site is reached, SP has already
drifted down from 4096 by whatever real local-frame space the outer function needed for its own
ordinary (non-Phase-B0-tracked) allocas, invisible to Phase B0 since it runs at the IR level, long
before the backend decides real frame sizes. Confirmed via `--trace-gpr`: a nested
`veda_ocs_stack_d` call's own `ra`-spill offset (`SP-8`, SP having drifted to `0xF70`) landed at
absolute offset `0xF68` (3944) — exactly inside `upper[]`'s own allocation window `[3928,3960)`,
silently aliasing `upper[2]`'s real data byte with `veda_ocs_stack_d`'s own spilled return address,
corrupting `ra` and crashing on return (`misaligned-fetch`). **Fixed** by anchoring alloca offsets
at the *bottom* of the region instead (starting right after `kVedaCSRReservedBytes`, growing
upward) — maximally far from where any current-SP-relative CSR spill can land, since SP starts at
4096 and only ever decreases. An honest, empirically-grounded margin for this design's own realistic
call depths, not a formally proven bound (the same risk category as the file's own
`kVedaSSCRegionLength` constant).

**2. Purecap enforcement is global, not per-function — ordinary runtime helper functions called from
inside a live compartment must themselves be `veda_compartment`-attributed.** `veda_ocl_stack_d`/
`veda_ocs_stack_d` initially were ordinary (unattributed) C functions. Milestone 19's purecap
enforcement is tied to the `veda_mode` CSR, not to which function is currently executing — an
unattributed function's own ordinary `ra`-spill prologue (`sd ra, N(sp)`, needed because each
function calls further into its own `*_scratch_asm` helper, so `ra` cannot be tail-call-elided)
hard-traps with `VEDA_CAUSE_PURECAP_VIOLATION` exactly like any other raw store, the instant it
executes while still inside the live compartment. **Fixed** by attributing both functions (and their
compiler-facing wrappers `veda_rt_ocl_stack_d`/`veda_rt_ocs_stack_d`, for robustness independent of
whether the compiler happens to tail-call-optimize a given wrapper) with
`__attribute__((veda_compartment))` too — the identical, already-proven-safe nested-compartment
pattern Milestone 11's own nested-call test validated.

**3. An out-param write-back is fundamentally incompatible with live purecap enforcement, regardless
of which function performs it.** The original design mirrored the heap-object path's own
`OCL.D`-then-write-to-scratch-buffer convention (`void veda_ocl_stack_d(..., uint64_t *out)`,
writing the loaded value back via a plain `sd` to the caller's `%veda.ocl.scratch` alloca). Since
Phase B0's provenance tracking is purely intraprocedural, a pointer passed in as a function
argument has no tracked provenance in the callee — no function anywhere in the call chain can
safely perform this write, and it hard-trapped identically to finding 2 (`VEDA_CAUSE_PURECAP_VIOLATION`,
confirmed via trace). **Fixed** by changing the entire load-path signature to return the value
*directly* in `a0` (`uint64_t veda_ocl_stack_d(uint64_t region_offset, uint64_t access_offset,
uint64_t size)`) instead of an out-param — no memory access at all, sidestepping the whole class of
bug rather than routing around it. (The store path never had this problem: it passes the value
directly as an argument, never needs an output.)

**A fourth, smaller fix**: the compartment's own CODE capability `Length` (established by the
hand-written entry point) needed widening from Milestone 11's `0x0400` to `0x1000`. This milestone's
demo is the *first* compartment-attributed function to call genuinely external, separately-linked
code (the new runtime helpers) from inside a live `OCInvoke`-narrowed PCC — Milestone 11's own demo
never called anything external, so `0x0400` was never exercised against this case. Confirmed via a
real PCC-fetch-violation trap before the fix (`riscv64-unknown-elf-nm` showed the linked ELF's
`.text` spanning 1660 bytes past `landing_pad`, exceeding the old 1024-byte bound). A real, honest
scope note: this widens the CODE capability only, not the SSC/data capability — it does not weaken
this milestone's own actual claim (stack-local *data* isolation), which is orthogonal to PCC's
separate code-bounding property (Milestone 10/14's own concern).

## Verification

**Test files** (`veda-core/compiler/`): `veda_alloca_protect_demo.c`, directly modeled on the
official CHERI "inter-object stack buffer overflow" exercise — `unsigned long lower[4]`,
`unsigned long upper[4]` (64-bit elements: a real, hardware-forced choice, not convenience — the
pass's own existing dereference-rewrite rule, and the real `OCL.D`/`OCS.D` instructions themselves,
are 64-bit-only), a loop initializing both, then a `VEDA_OOB_INDEX`-controlled write (default `3`,
in-bounds; `4`, deliberately one element past `lower[]`'s own bound, landing inside `upper[]`).
`veda_alloca_protect_entry.S` (Object_IDs 416-421 — re-verified by grep across every existing `.S`
file's own Object_ID literals before picking; an earlier draft wrongly assumed 410-415 was free,
when `veda_compartment_nested_entry.S` already owns that exact block). `run_veda_alloca_protect_test.sh`.

```
=== Positive: in-bounds (VEDA_OOB_INDEX=3, the default) ===
SUCCESS

=== Negative control: deliberate cross-array overflow (VEDA_OOB_INDEX=4) ===
FAILURE: 1 (0x00000001)

=== Tracing negative run to confirm the EXACT expected trap cause ===
Confirmed: mcause=0x18, mtval=0x1a1 (VEDA_CAUSE_BOUNDS_VIOLATION via C13) -- real, specific proof.

*** TEST PASSED ***
```

The positive run's own return value (`113 = lower[3](13) + upper[0](100)`) is a real, checkable
result, not merely absence-of-trap. The negative run's trap cause was traced
(`--trace-instr --trace-exception --trace-csr`), not assumed: `mtval` packs `(cap_idx<<5)|cause`
(`veda_xtval`, re-verified), and the OOB access goes through scratch register `C13` (index 13) with
cause `VEDA_CAUSE_BOUNDS_VIOLATION=0x01`, giving the exactly-predicted `mtval = (13<<5)|0x01 =
0x1a1` — confirmed byte-for-byte against the real trace output, the actual, honest proof of
inter-variable isolation (CHERI's own `CBM_Conservative` default-scope property).

Mutation-tested the check itself (temporarily expecting `999` instead of `113`): correctly reports
`*** TEST FAILED ***`, confirming the pass/fail logic is non-vacuous.

**Full regression, zero regressions** (confirming this milestone is genuinely toolchain-only,
touching no hardware semantics):
- `sail_tests/run_veda_selfcheck_tests.sh`: **58/58**, unchanged — zero new Sail tests, since no
  Sail file was touched.
- `rtl/run_veda_smoke_test.sh`: unchanged (46 `TEST PASSED`, 0 failed) — zero RTL files touched.
- `rtl/run_act4_tests.sh`: **51/51** RV64I conformance, unchanged.
- `compiler/run_veda_shadow_prop_tests.sh`: **8/8**, unchanged (this milestone's own Phase B0
  additions do not alter any existing FileCheck-tested behavior).
- `compiler/run_veda_demo_tests.sh` (Milestone 9 heap-object demos): **2/2**. Initially regressed
  (single-stage `clang -c` compilation of `veda_compiler_rt.c`/`veda_rt.c` crashed
  `RISCVAsmPrinter`, since both files now contain `veda_compartment`-attributed functions needing
  `-mattr=+xveda` to lower — the identical class of bug as this milestone's own initial pipeline
  mistake). Fixed by switching that script's compilation of those two files to the same two-stage
  `clang -S -emit-llvm` → `llc -mattr=+xveda` pipeline this milestone's own test script already
  uses.
- `runtime/run_veda_rt_tests.sh`: **2/2**. Same regression, same fix, applied to `veda_rt.c`'s
  compilation there.
- `compiler/run_veda_sched_demo_test.sh`, `run_veda_compartment_test.sh`,
  `run_veda_compartment_nested_test.sh`: unaffected (confirmed by re-running) — none of these
  compile `veda_compiler_rt.c`/`veda_rt.c`.

## Not yet built (explicit, matching this project's own established honesty precedent)

- **Subobject/struct-field-internal bounds** — deferred, with real CHERI precedent (C/C++
  Programming Guide §4.3.3, `CBM_Conservative` default) as the reason this is a legitimate scope
  boundary, not a shortcut: protecting *separate* locals from each other is CHERI's own real
  default; protecting fields *within* one allocation is opt-in only.
- **Globals/statics** — unrelated, unaffected, still open (already named in Milestone 11's own doc).
- **Dynamic-size (VLA) allocas** — non-constant size breaks this design's core compile-time
  simplification; explicitly deferred, not attempted.
- **Non-entry-block / dynamically-placed allocas** — only entry-block static allocas are recognized;
  anything else is left completely unrewritten (zero protection, not degraded protection).
- **Mixed-provenance PHIs** (malloc vs. alloca on different paths) — diagnosed via
  `isAmbiguousAllocaPhi`, left unrewritten.
- **`kVedaSSCRegionLength`/entry-point `Length` cross-file constants** — hand-maintained, no
  compiler-enforced cross-check (same risk category as `kVedaNullBase`/`VEDA_NULL_BASE` today).
- **FPR/vector locals** — inherits the pass's own existing 64-bit-only dereference-rewrite scope.
- **A formally-bounded guarantee against the offset-collision class of bug (finding 1 above)** — the
  bottom-anchored placement is an empirically-grounded, generous margin for this project's own
  realistic call depths and frame sizes, not a compiler-enforced proof that no future, much deeper
  or much larger-framed nested call chain could ever drift SP far enough to reach the alloca region.
  A real, honestly-stated residual risk, in the same spirit as this file's other hand-maintained
  cross-file constants.
