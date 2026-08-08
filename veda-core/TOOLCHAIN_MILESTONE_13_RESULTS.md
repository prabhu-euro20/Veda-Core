# Toolchain Milestone 13: Hardware-Native Protection for C Global/Static Variables

## Context

Milestone 11 closed callee-saved-register spills (`C15`/SSC). Milestone 12 closed stack-local
`alloca`s (Phase B0, offsets inside the same `C15` region via `C13` scratch). Both explicitly named
the same remaining gap: C global and static variables — `int g;` at module scope, or `static int s;`
inside a function — which lower to an LLVM `GlobalVariable` at a fixed, link-time address in
`.data`/`.bss`/`.rodata`. Any access to one inside a `veda_compartment` function previously emitted
an ordinary `lui`/`auipc`+`ld`/`sd` pair, hard-trapping under Milestone 19's purecap rule.

A rigorous, multi-track research program ran before any code — own architectural state (CRF/SCR
budget, ODT real capacity), real compiled LLVM IR shape, and official CHERI precedent (the CHERI-RISC-V
ELF psABI spec, the `cheri_init_globals.h` reference implementation, the CHERI C/C++ Programming
Guide, CherIOS's build config). The CHERI-precedent track initially failed and was re-run separately;
its real findings — individually-bounded per-symbol capabilities, not one coarse region — materially
changed the design mid-stream, requiring a full reconciliation pass. The complete design writeup, with
every citation, lives in `TOOLCHAIN_MILESTONE_13_DESIGN.md` and the approved plan
(`.claude/plans/jolly-leaping-lark.md`); this document covers the implementation, the real bugs found
along the way, and verification.

## Design (as implemented)

**Per-global individually-bounded capabilities, minted once at bootstrap, cached in an in-memory
capability table** — real CHERI's own `__cap_relocs` property, adapted (not copied 1:1) to this
project's own real, currently-binding 256-entry ODT (`rtl/veda_core.tlv:994`,
`$veda_odt_idx[7:0] = $veda_object_id[7:0]`, a literal low-8-bit index, not a saturating clamp —
personally re-verified before finalizing the design). Instead of one `Object_ID` per global (CHERI's
literal mechanism), three `Object_ID`s total: `.rodata`, `.data+.bss`, and the capability-table region
itself. Each qualifying global's own exact-bounds capability is derived from one of the two source
regions via `OCA`-then-`CSetBounds`, performed **once, at program bootstrap** (before the first
`OCInvoke`), and the resulting 128-bit tagged capability is stored into a small in-memory table via
`OCS.C` (Milestone 7, newly load-bearing — previously implemented and tested but never used by any
toolchain milestone). Every real access thereafter is one `OCL.C` (load the already-exact capability)
+ `OCL.D`/`OCS.D` — no `OCA`/`CSetBounds` at the access site at all, cheaper and strictly more precise
than a shared-region-plus-per-access-narrowing design would be.

**New Phase B1 in `compiler/VedaShadowPropagation.cpp`**, module-wide (`for (GlobalVariable &GV : M)`),
unlike Phase B0's entry-block-of-one-function scan — a `GlobalVariable`'s own uses genuinely span the
whole module. Gated on the *using function* carrying `veda_compartment`: a global's uses inside an
unattributed function are left completely untouched, a genuinely new policy question Phase B0 never
faced (an `alloca` is inherently function-local; a global's `users()` are not). Sizing gates on
`!GV.isDeclaration()` (an extern, incomplete-type global like this project's own real
`extern char _end[];` is unsafe to size and is left unrewritten). Dereference resolution handles all
three real access shapes — direct `@name` operand, `GEPOperator`-matched constant-index `ConstantExpr`,
and `GEPOperator`-matched variable-index `GetElementPtrInst` — uniformly via a single
`ptrtoint`-subtraction offset computation (mirroring Phase B0's own `AllocaBase` pattern exactly; no
separate `accumulateConstantOffset` handling turned out to be necessary — ordinary LLVM constant
folding already collapses the constant-index case to a literal integer). Phase B1 also emits a
compiler-generated bootstrap tuple table (`{region_selector, region_offset, size}` per qualifying
global, a packed `<{i64,i64,i64}>` constant array) — a real, checked departure from CHERI's own
literal linker-emitted `__cap_relocs` mechanism: this project's real linker (`GNU ld 2.46`) and `clang`
(not the CHERI-LLVM fork) have no cap-reloc feature, confirmed directly.

**New runtime helper chains**, mirroring `veda_ocl_stack_d`/`veda_ocs_stack_d`'s established ABI shape
(value returned directly, no out-param — Milestone 12's finding 3 applies identically):
- **Bootstrap minting** (`veda_rt_init_globals`, `runtime/veda_rt.c`) — NOT `veda_compartment`
  -attributed, a real, load-bearing difference from every other runtime helper this milestone adds:
  it runs before the first `OCInvoke`, in "wide open" PCC mode, where M19's purecap enforcement is
  genuinely not yet active (gated on `veda_mode.veda_purecap` OR live `OCInvoke`-narrowing, neither
  holds here). It is an ordinary C function with a real stack frame, walking the compiler-emitted
  tuple table and calling two new hand-written `.S` helpers
  (`veda_mint_global_cap_rodata_asm`/`veda_mint_global_cap_data_asm`) that perform
  `oca`+`csetbounds`+`ocs.c` per entry.
- **Per-access load/store** (`veda_rt_ocl_global_d`/`veda_rt_ocs_global_d` →
  `veda_ocl_global_d`/`veda_ocs_global_d` → `veda_ocl_global_d_scratch_asm`/`veda_ocs_global_d_scratch_asm`)
  — both attributed `veda_compartment` (Milestone 12's finding 2: any function reached from inside a
  live compartment must itself be attributed, so its own `ra`-spill routes through `C15`).

**Register plan** (grep-audited before picking, the same discipline Milestones 11/12 used for
`C15`/`C13`): a real, empirically-discovered finding this audit surfaced — **every CRF register 0-15
already has some real use** in this project's hand-written corpus (C0-C4 by the compartment-entry
ceremony, C5-C12 by the scheduler switcher, several explicitly marked "permanent bind", C13/C14/C15 by
Milestones 11/12). No register is unconditionally free. Resolved for this milestone's own standalone
(non-scheduler) scope: `C8`/`C9` (bootstrap-only source regions), `C10` (transient scratch, reused
non-overlapping across bootstrap minting and every per-access call), `C11` (persistent table-base
register) — all scheduler-exclusive, safe here because this milestone's own verification program never
invokes the scheduler. A real, honestly-named residual risk for any *future* program combining
globals-protection with multi-threading (see "Not yet built" below).

**Linker script addition** (`runtime/veda_rt.ld`): `__rodata_start`/`__rodata_end` and `__data_start`
symbols (mirroring the existing `__bss_start`/`__bss_end`), giving the bootstrap ceremony real,
runtime-computed Base/Length values for the two source regions. `__data_start..__bss_end` is one
contiguous span honestly over-covering the small `.tohost` section the real linker script places
between `.data` and `.bss` — harmless, since an `Object_ID`'s own bounds accounting never affects an
ordinary (non-capability) access to the same physical bytes, confirmed by direct read of the script.

## Real bugs found and fixed during implementation and verification (empirically, not by inspection alone)

**1. `x2` is `sp` — a new call inserted between two `mv x2, t0` ceremony steps corrupted the real stack
pointer.** The entry point's own region-setup code reuses `x2` as scratch for the packed
`Base<<32|Length<<16|Perms` descriptor before each `ODT-Populate` call, the identical convention every
prior milestone's entry point already uses — harmless there only because nothing reads `sp` again
before it is deliberately re-established (`li sp, 0x1000`) much later. This milestone inserted a
genuine, ordinary C function call (`veda_rt_init_globals`, whose own real prologue does
`addi sp,sp,-0x20; sd ra,0x18(sp)`) between the region-setup code and that re-establishment point.
Confirmed via `--trace-gpr`: a real `store/amo-access-fault` inside `veda_rt_init_globals`'s own
prologue, `sp` still holding the stale capability-table descriptor value. Fixed with a one-line
`la sp, _stack_top` immediately before the call — the one place in the whole ceremony that genuinely
needs a valid stack pointer before `landing_pad`.

**2. A real link-time regression across three unrelated, pre-existing test suites**: `veda_rt_init_globals`'s
own body unconditionally references `__veda_global_table_meta`/`__veda_global_table_count`, but Phase
B1 only emits these symbols for a translation unit that actually contains at least one qualifying
global. Any program linking `veda_rt.c` without such a module — Milestone 9's own heap-object demos
(zero module-scope globals), and `runtime/run_veda_rt_tests.sh`'s own standalone suite (never invokes
the pass plugin at all) — had no file anywhere in its own link line defining them, a genuine
`undefined reference` link failure, found only by running the full regression, not by inspection.
Fixed with **weak** fallback definitions (an empty, `count=0` table) directly in `veda_rt.c`: real
C/ELF weak-symbol semantics mean Phase B1's own strong (`ExternalLinkage`) emission, when it exists
anywhere in a given program's link line, correctly overrides the default; when it does not, the
harmless empty default is used and `veda_rt_init_globals`'s own loop performs zero iterations.

## Verification

**Test files** (`veda-core/compiler/`): `veda_global_protect_demo.c`, directly modeled on
`veda_alloca_protect_demo.c` (itself modeled on the official CHERI inter-object exercise) —
`unsigned long g_lower[4]`, `unsigned long g_upper[4]`, initialized via a runtime-variable loop index
(the more representative real-world shape, confirmed this milestone: a literal index folds to a
`ConstantExpr`, a loop variable does not), then a `VEDA_OOB_INDEX`-controlled write.
`veda_global_protect_entry.S` (Object_IDs 422-430, a fresh block one past Milestone 12's own highest
use). `run_veda_global_protect_test.sh`.

```
=== Positive: in-bounds (VEDA_OOB_INDEX=3, the default) ===
SUCCESS

=== Negative control: deliberate cross-global overflow (VEDA_OOB_INDEX=4) ===
FAILURE: 1 (0x00000001)

=== Tracing negative run to confirm the EXACT expected trap cause ===
Confirmed: mcause=0x18, mtval=0x141 (VEDA_CAUSE_BOUNDS_VIOLATION via C10) -- real, specific proof.

*** TEST PASSED ***
```

The positive run's own return value (`113 = g_lower[3](13) + g_upper[0](100)`) is a real, checkable
result. The negative run's trap cause was traced, not assumed: `mtval` packs `(cap_idx<<5)|cause`; the
OOB access goes through the per-access scratch register `C10` (index 10) with cause
`VEDA_CAUSE_BOUNDS_VIOLATION=0x01`, giving the exactly-predicted `mtval = (10<<5)|0x01 = 0x141` —
confirmed byte-for-byte. A real, honest distinction from Milestone 12's own equivalent test: this trap
fires the instant `g_lower[4]`'s own `access_offset(32)+width(8)` exceeds `g_lower`'s **own**
table-resident capability's own `Length(32)` — before the access could ever reach `g_upper`'s own
bytes at all, since the two globals carry separate, individually-bounded capabilities, not one shared
region narrowed per access.

Mutation-tested the check itself (temporarily expecting `999` instead of `113`): correctly reports
`*** TEST FAILED ***`, confirming the pass/fail logic is non-vacuous.

**Full regression, zero regressions in every suite this milestone did not intend to change**:
- `sail_tests/run_veda_selfcheck_tests.sh`: **58/58**, unchanged — zero Sail files touched.
- `rtl/run_veda_smoke_test.sh`: unchanged (46 `TEST PASSED`, 0 failed) — zero RTL files touched.
- `rtl/run_act4_tests.sh`: **51/51** RV64I conformance, unchanged.
- `compiler/run_veda_shadow_prop_tests.sh`: **8/8**, unchanged.
- `compiler/run_veda_demo_tests.sh` (Milestone 9): **2/2** — regressed then fixed (see bug 2 above).
- `compiler/run_veda_sched_demo_test.sh`, `run_veda_compartment_test.sh`,
  `run_veda_compartment_nested_test.sh`, `run_veda_alloca_protect_test.sh`: all still pass — the
  alloca-protect suite regressed then was fixed by the same weak-symbol change.
- `runtime/run_veda_rt_tests.sh`: **2/2** — regressed then fixed (same root cause).

## Not yet built (explicit, matching this project's own established honesty precedent)

- **No CRF register is free for a future program combining globals-protection with multi-threading.**
  This milestone's own register audit found every CRF register 0-15 already has some real use; the
  four registers this milestone reuses (`C8`-`C11`) are scheduler-exclusive and safe only because this
  milestone's own verification program never invokes the scheduler. A real, concrete resource-exhaustion
  wall for the next milestone that needs to combine the two, not a hypothetical concern.
  **Mechanism now decided** (rigorous, multi-track, primary-source-cited research —
  `TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md`): extend the scheduler's own per-thread save-area
  (`runtime/veda_sched_asm.S`) to spill/restore the table-base capability at every thread switch,
  matching CHERIoT's own documented "nothing is switch-exempt" discipline — rejected a 4th SCR (real
  per-access instruction tax + an unresolved OSpecialRW privilege-gate question) and rejected widening
  the CRF to CHERI-RISC-V's own real merged-register-file convention (a full ISA change, disproportionate
  to a one-register conflict). Software-only, no Sail/RTL change. **Not yet implemented** — this
  project's own discipline is to not build code with no test exercising it, and no test program yet
  combines globals-protection with the scheduler; implement at the next real trigger (that combined test
  becoming necessary, or this milestone's own register choice being grep-audited and finalized).
- **Extern globals** (`isDeclaration()==true`), especially incomplete-array-typed ones (this project's
  own real `extern char _end[];`) — left completely unrewritten, not silently mis-sized.
- **Global accesses inside non-`veda_compartment`-attributed functions**, even if transitively
  reachable from a live compartment — left untouched, a genuinely new policy question Phase B0 never
  faced.
- **Subobject/struct-field-internal bounds** — same CHERI `CBM_Conservative` scope boundary Milestone
  12 already drew.
- **A linker-emitted relocation mechanism** (CHERI's own literal `__cap_relocs`) — investigated and
  rejected for v1 given this project's real toolchain; the compiler-emitted-table approach is the v1
  answer, revisitable if the toolchain ever grows real linker-level capability-relocation support.
- **Capability-table sizing** — a fixed 16-slot (256-byte) upper bound, not exactly-sized to any one
  program's own real global count (which the compiler pass itself already knows at compile time — the
  natural, not-yet-implemented fix).
- **Multiple independent compartments in one program concurrently sharing a global** under the ODT's
  exclusive-by-default owner-hart Bind policy — no existing test corpus exercises multiple live
  compartments in one program at all.
- **`-O2`/`-O3`** — untested, matching this pass family's own established never-target-higher
  -optimization convention.
- **Function-local `static` variables** — confirmed to lower to an ordinary module-scope
  `GlobalVariable` (internal linkage) by direct compilation, and Phase B1 needs no special-casing for
  them, but no dedicated end-to-end test exercises this specific case yet (only module-scope globals
  are exercised by `veda_global_protect_demo.c`).
