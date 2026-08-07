# Toolchain Milestone 11: `veda_compartment` — Automatic Callee-Saved-Register Spill Redirection Through SSC

## Context

SSC (Stack-Spill Capability, `SSC_STACK_SPILL_CAPABILITY_DESIGN.md`) was built specifically to give a
future compiler a capability-checked register to route ABI-mandated stack spills through, closing
Toolchain Milestone 10's real finding: ordinary compiler-generated C functions cannot run inside a
narrowly `OCInvoke`/`OCRETURN`-bound compartment at all, because a standard RV64 ABI prologue spills
callee-saved registers via ordinary `sd`/`ld`, which Milestone 19's purecap rule hard-traps
unconditionally inside a live compartment.

Before writing any code, a 4-track official-source research workflow (our own LLVM
`RISCVFrameLowering`/`RISCVRegisterInfo`/`RISCVInstrInfo` internals; the real upstream CHERI-LLVM
fork; the ratified RISC-V psABI; existing LLVM custom-calling-convention precedent) plus two
follow-on Explore passes (our own LLVM fork's actual Veda-specific code state; our own
compartment/SSC runtime conventions) grounded the design in `.claude/plans/jolly-leaping-lark.md`
(approved plan, quoted findings below). A Plan agent then turned those findings into a concrete
implementation design, re-verifying every claim against the real checkout before finalizing.

## Design (as implemented — two real refinements found during implementation, both documented below)

**New Clang attribute: `__attribute__((veda_compartment))`**, `TargetSpecificAttr<TargetRISCV>`,
`SimpleHandler = 1` (`clang/include/clang/Basic/Attr.td`). A real, deliberate simplification found
during implementation versus the plan's own sketch (which anticipated a custom `SemaRISCV.cpp`
handler): `RISCVInterrupt`'s own arg-count/void-return restrictions come from its *own* explicit
Sema checks, not from any inherited default — an ordinary attribute with no `Args` needs no custom
semantic-check function at all. Real precedent confirmed directly in-tree (`NoMicroMips` uses the
identical `TargetSpecificAttr<...> { ...; SimpleHandler = 1; }` shape). Bridged to the IR-level
`Function::hasFnAttribute("veda_compartment")` via a new line in
`RISCVTargetCodeGenInfo::setTargetAttributes` (`clang/lib/CodeGen/Targets/RISCV.cpp`).

**Reserved CRF register: `C15`.** Conditionally reserved in `RISCVRegisterInfo::getReservedRegs`
(gated on a new `RISCVMachineFunctionInfo::useVedaCompartmentSpills()` predicate, mirroring
`useQCIInterrupt`'s shape) — chosen over `c14` (an existing informal "OSpecialRW-discard"
convention across 5 files) and `c0`-`c13` (heavily used as general scratch in every existing `.S`
test).

**Core new logic — `RISCVFrameLowering::spillCalleeSavedRegisters`/`restoreCalleeSavedRegisters`**:
a new branch, parallel to the existing push/libcall/QCI-interrupt chain. `assignCalleeSavedSpillSlots`
reuses `FixedCSRFIMap` unchanged — it already lists exactly `{ra, s0, s1, s2-s11}`, the same GPR
callee-saved set this needs — via `MFI.CreateFixedSpillStackObject`, giving each register a
compile-time-known, already-resolved offset with zero dependency on post-RA frame finalization.
For each spilled register: materialize the address into a scratch GPR (`X6`/`t1`, the same register
`allocateAndProbeStackForRVV` and the stack-probing epilogue code already hardcode as scratch for
an identical reason — never callee-saved, guaranteed dead this early in the prologue), then
`BuildMI` a direct `VEDA_OCS`/`VEDA_OCL` against `C15`.

## A real correctness bug found and fixed during verification (not caught by inspection alone)

The first working version materialized the scratch address as the bare `FixedCSRFIMap` offset
(`li t1, -8`), matching the plan's own draft. Direct codegen inspection (`llc -mattr=+xveda`
output) looked plausible, but re-deriving the real memory-address semantics from
`veda_ocl_insts.sail`'s `veda_check_access` (`real_loc = cap.Base + offset`, re-verified against
source, not assumed) exposed a genuine bug: SSC is a **single, whole-region capability established
once per compartment entry**, shared across every nested `veda_compartment` call within that
compartment. A bare compile-time offset is identical for every call frame at every depth — a
caller's own spill slot and a nested callee's spill slot would compute the exact same SSC-relative
offset, silently aliasing and clobbering the caller's saved registers the instant a nested call
occurred. (This session's own `spill_test`/`compartment_counter_loop` scenarios never exercised
nested `veda_compartment`→`veda_compartment` calls, so the bug did not show up in the codegen
inspection or even the real end-to-end simulator run below — it was found by re-deriving the real
address arithmetic from source, not by any test failing.)

**Fix**: the scratch register now holds `SP + FixedCSRFIMap_offset` (via
`RISCVRegisterInfo::adjustReg`, the same helper `eliminateFrameIndex` itself uses for identical
scratch-register materialization, `std::nullopt` alignment — real, existing precedent, not new
logic), not the bare offset. Since `SP` genuinely differs per call depth, exactly as it does for
ordinary `sd`/`ld` addressing, this correctly disambiguates every frame's own slots. Verified via
`llc` output: `addi t1, sp, -8` / `ocs.d c15, t1, ra` (spill) and the mirror-image on restore.

## A second real architectural finding, verified from source before writing the entry point

`cap.Length` is `bits(16)` in the real capability struct (`veda_types.sail`) — at most 65535 bytes.
`SP`'s own ordinary, real absolute address (~0x8001xxxx on this platform) is far too large to ever
be a valid in-bounds *offset* against any capability whose `Base` is 0. This means, inside a
`veda_compartment` function's own call graph, **`SP` must be a small, logical, SSC-region-relative
offset (0 = this compartment's own dedicated stack region's `Base`, growing down from the region's
`Length` like an ordinary stack) — not a raw absolute address.** This is a deliberate, honestly
named departure from ordinary RV64 ABI semantics, required by the 16-bit `Length` field, not an
oversight: it does not require any change to the compiler's own codegen (which only ever computes
`SP + constant`, unaffected either way) — only the hand-written entry point that establishes SSC
is responsible for this one-time repurposing of `SP` before ever calling into compiled
`veda_compartment` code, exactly mirroring how it is already responsible for establishing SSC
itself in the first place.

## OSpecialRW's real read/write direction — verified before writing the entry point

`VEDA_OSPECIALRW`'s real Sail execute clause (`veda_cap_insts.sail`, re-verified, not assumed):
`rd := old SCR value; SCR := rs1's value` — a real atomic read-then-write. Since `rs1` is read-only,
binding the compartment's dedicated stack-region object **directly into `C15`** (rather than a
scratch register, then copied) and using `C15` as `rs1` in `ospecialrw c14(discard), ssc, c15`
simultaneously installs it into SSC *and* leaves `C15` holding that same live capability afterward —
zero extra copy instruction, a real simplification found while implementing the plan's own flagged
"must re-verify before finalizing" item.

## Verification

**Test files** (`veda-core/compiler/`): `veda_compartment_demo.c` (a single source, gated by a
`VEDA_COMPARTMENT_ATTR` macro so both variants come from identical source), directly reproducing
Milestone 10's own rejected Attempt 2 — a function-local register-pinned counter
(`register unsigned long counter asm("x20")`), forced to remain genuinely live across every
iteration via a real inline-asm input operand (a bare compiler barrier alone was not sufficient —
LLVM proved the first, barrier-only version of this test was a no-op and optimized the whole
function away, a real empirical finding worth recording: `asm volatile("" ::: "memory")` alone does
not force a pinned register to materialize, only a genuine `"r"(counter)` input operand does).
`veda_compartment_entry.S`, a hand-written entry point (Object_IDs 400-405, a fresh, non-colliding
block confirmed by grepping every existing Object_ID literal across the whole test corpus before
picking — prior highest use was 330) mirroring `vc_ssc_spill_reload.S`'s own already-proven
ODT-Populate/Bind/CSeal/OCInvoke ceremony, extended with the SSC-establishment and `SP`-repurposing
steps above. `run_veda_compartment_test.sh` builds and runs both variants from the identical
source via `clang (IR only) → llc +xveda (real lowering, since `Subtarget->hasVendorXVeda()` is
only true there — the clang *driver*'s own ISA-string parser still rejects `-march=...xveda`,
`TOOLCHAIN_MILESTONE_7_RESULTS.md`'s own already-documented, still-unfixed gap) → llvm-mc → ld`.

```
=== Positive: WITH __attribute__((veda_compartment)) ===
SUCCESS

=== Negative control: WITHOUT the attribute (must still trap) ===
FAILURE: 1 (0x00000001)

*** TEST PASSED ***
```

Traced the negative control (`--trace-instr --trace-exception --trace-csr`) rather than assuming
*why* it failed: `mcause=0x18` (every Veda-Core violation's shared top-level cause, per this
project's own established trap-model convention), `mtval=0x227` — low 5 bits `= 0x07`, exactly
`VEDA_CAUSE_PURECAP_VIOLATION`. Confirms the negative control fails for precisely the intended
reason, not an unrelated bug.

Full regression, zero regressions: `sail_tests/run_veda_selfcheck_tests.sh` 58/58,
`compiler/run_veda_demo_tests.sh` 2/2, `compiler/run_veda_shadow_prop_tests.sh` 8/8,
`compiler/run_veda_sched_demo_test.sh` (scheduler demo) still passes.

## Not yet built (explicit, matching this project's own established honesty precedent)

- **Globals/statics inside a `veda_compartment` function** — Milestone 10's own Attempt-1 failure
  mode (ordinary global-variable memory access), unrelated to callee-saved spilling, stays open.
- **`alloca`-based C locals** — remains `VedaShadowPropagation.cpp`'s own, separate, still-unbuilt
  domain (confirmed zero `AllocaInst` handling exists there).
- **Multi-function compartment call graphs** — the attribute must be applied by hand to every
  function that actually needs a callee-saved spill; a plain (un-attributed) function that itself
  needs one, called from inside a compartment, will still trap the instant its own ordinary
  prologue runs. (A function that needs zero callee-saved registers at all — a true leaf, like this
  milestone's own `step()` helper — needs no attribute regardless, since it never emits an ordinary
  `sd`/`ld` in the first place; a real, honest edge case, not a bypass of the rule.)
- **FPR/vector callee-saved spills through SSC** — GPR-only (`ra`, `s0`-`s11`); RVV CSI stays on
  its existing path.
- **Nested `veda_compartment`→`veda_compartment` calls** — the `SP + offset` fix above makes this
  architecturally correct (each frame's own `SP` genuinely differs), but no test in this milestone
  actually exercises a real nested call between two `veda_compartment`-attributed functions;
  flagged honestly as unverified-by-test, not merely unverified-by-construction, matching the
  precedent this project already set for SSC's own cross-thread isolation gap.
- **`SelectionDAG`-pattern-based `OCL.D`/`OCS.D` selection for arbitrary `*p` dereferences** —
  unrelated, unattempted; this milestone is scoped exclusively to the frame-lowering-level
  callee-saved-register spill mechanism.
