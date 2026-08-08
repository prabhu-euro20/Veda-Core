# Milestone C Deferred Item: Full GPR Context Save

## Problem

`MILESTONE_C_RESULTS.md`'s own "Not yet built" section named a real, deliberate gap: the
cooperative scheduler (`sail_tests/vc_scheduler_cooperative_yield.S`) preserved only each thread's
own dedicated counter register (`x20` for THREAD_A, `x21` for THREAD_B) plus `mepc`/PCC-bounds
across a yield — every other GPR, including any scratch temporaries a thread body might use, was
silently lost on a context switch. The file's own header comment stated this explicitly as "a
real, named, later refinement, not silently dropped."

## Design process

A Plan agent produced an initial design (mscratch-based bootstrap, 34-dword save-area layout,
deferred-register restore ordering). Given the foundational, correctness-critical nature of this
mechanism, the design was then independently re-verified by a 3-lens adversarial workflow before
any code was written: one lens re-derived every register-conflict claim against the actual current
file, one independently recomputed every byte offset and cross-checked the ODT-Populate descriptor
packing, one re-verified every Sail-semantics claim (mscratch's real CSR wiring, `csrrw`'s
old-value-to-rd ordering, `VEDA_OCL`'s read-before-write hazard safety, `OCRETURN`'s zero-GPR-operand
property) against the real Sail source. Verdict: zero bugs found, all 12 checked claims confirmed,
two minor citation/phrasing corrections folded in. The design was then written into a plan and
approved before implementation began.

## Mechanism

**Bootstrap**: `mscratch` (CSR `0x340`), a standard, unconditionally-accessible Machine-mode CSR
(confirmed never gated by any Veda compartment check — `ext_check_CSR` is an unconditional `true`
stub, no override anywhere in `extensions/Veda/`), is seeded to `0` once at program start. At
`switcher_entry`, `csrrw x5, mscratch, x5` atomically parks `x5`'s true pre-trap value in
`mscratch` and frees `x5` as the switcher's one working scratch register — the textbook RISC-V
trap-entry idiom, applied here for the first time in this codebase.

**Save-area layout**: `save_area_a`/`save_area_b` grow from 3 `.dword`s (24 bytes: saved-PC/base/
length) to 34 `.dword`s (272 bytes = `0x110`): the original 3 slots unchanged at offsets 0/8/16,
then `x1` at offset 24 through `x31` at offset 264 (`offset(n) = 24 + (n-1)*8`), `x0` omitted
entirely (hardwired zero). `Length` in both `save_area_a`/`save_area_b`'s ODT-Populate descriptors
grows from `0x0020` to `0x0110` accordingly.

**Save path (`switcher_entry`)**: a real ordering hazard, found by re-reading the actual current
file rather than trusting the abstract design: the switcher's own pre-existing guard check and
`mepc`/`veda_mepcc_base`/`veda_mepcc_length` read already clobber `x28`/`x29`/`x30`, and used to run
*before* `thread_index` was even read. The fix: `thread_index` is read first (into the now-free
`x5`, not `x6` — `x6`'s own true value must survive to be saved), then the full 31-register save
runs immediately, capturing every register's still-undisturbed true value (including `x28`/`x29`/
`x30`) *before* the guard check and `mepc`/`mepcc` read are allowed to clobber them. `x5`'s own true
value is saved last, relayed out of `mscratch` through the now-already-saved `x31`.

**Restore path (`resume_a`/`resume_b`)**: the resume-jump machinery (fresh `veda.bind`, `OCA`,
`CSealEntry`, `OCRETURN`) still needs `x1`/`x5`/`x28`/`x29`/`x31` live, transiently, to compute and
perform the actual jump — so those five are restored to their TRUE values only *after* that
machinery finishes reading them (the same structural reason Toolchain Milestone 14 needed a second
capability register instead of reusing one already committed to a live role). The other 26 GPRs are
restored eagerly, in any order, before the jump machinery begins. The previously-shared `do_resume`
tail is retired — the eager-restore loop overwrites GPR `x6`, but `x6` was also the mechanism's own
means of remembering "A or B" for a shared tail; `resume_a`/`resume_b` are now each fully
self-contained instead, mirroring how this file already fully duplicates their TSC-round-trip-check
logic. The final restore (`x5`, self-referential: same register is both the `OCL.D` offset source
and destination) is safe by construction — confirmed against `VEDA_OCL`'s real execute clause, the
offset is bound to a local variable before the destination write occurs, no hazard even when both
operands name the same physical register.

## Two real bugs found only during implementation (not by the design or its adversarial review)

**1. `thread_a_entry`/`thread_b_entry` outgrew their own CODE bounds.** Adding the pattern-write/
check test logic pushed each thread body to 300 bytes (confirmed via `objdump`), exceeding the
original `Length=0x0100` (256 bytes) CODE capability bound. The very first attempt run hard-trapped
with a genuine `VEDA_CAUSE_BOUNDS_VIOLATION` (`mtval=0x201`) on ordinary instruction *fetch* —  not
a spurious event, a real PCC-bounds enforcement (Milestone 14's own mechanism) correctly catching
code that had grown past its declared capability. Root-caused by disassembling the ELF and computing
the real body size, not guessed. Fixed by growing `Length` to `0x0180` (384 bytes) for both CODE_A
and CODE_B, and updating the two hardcoded `0x0100` PCC-length assertions inside each thread's own
second-visit bounds check to match.

**2. The GPR-based `bounds_ok`/`gpr_ok` flags (and the original `x20`/`x21` counter checks)
themselves could not survive to `final_check`.** With every GPR now genuinely per-thread, whatever
THREAD_B's own *last* resume left in the physical register file is what `final_check` observes —
never THREAD_A's, since `final_check` runs immediately after the terminal (4th) yield's save step,
with no further resume. The original test's own `bne x20, 2, fail_halt` (and the newly-added
`gpr_ok` checks) relied on a register surviving *by omission* — true only under the old, incomplete
mechanism that never touched `x20`/`x22`/etc. during a resume. Under a mechanism that correctly
isolates every GPR per thread, that omission no longer exists, so the assumption silently breaks.
Root-caused by tracing the exact register-write history of `x20` through a full instruction trace
(confirmed it really was being reloaded from THREAD_B's own, unrelated save slot on B's last
resume). Fixed by committing each thread's own combined `bounds_ok && gpr_ok` result to **memory**
(`thread_a_ok`/`thread_b_ok`, two new `.dword`s placed inside the existing, already-bound `c8`
capability's own 32-byte region alongside `thread_index`) from within that thread's own context,
before any later switch could let another thread's resume overwrite the GPR that held it — memory is
not part of the per-thread GPR-context mechanism, so it survives unconditionally. `final_check` now
reads these two memory flags instead of the old, now-unreliable GPR-based checks. Committing via
ordinary `sd` was not an option — Milestone 19's purecap-independent rule ("any ordinary load/store
while running inside a narrowed compartment is blocked") already applies to every thread body here,
confirmed by the file's own pre-existing comment on the identical `thread_index` access pattern —
so the commit uses `OCS.D` through the already-bound `c8`, exactly like every other in-compartment
memory access in this file.

## Test extension

`thread_a_entry`/`thread_b_entry` each stamp a distinctive pattern (`0xAAAA0000|regnum` /
`0xBBBB0000|regnum`) across `x2, x9, x15, x18, x27, x30` before their first yield — deliberately
including `x27`/`x30`, registers the switcher itself uses as scratch, to catch an incomplete
refactor that still clobbers them without saving the thread's real values first. After the one real
resume each thread gets, the same registers are re-checked against the expected constant (same
low-order register number, different high-order thread prefix, so a cross-thread swap reads as
"right register, wrong thread" — legible by construction), combined with the existing PCC-bounds
check, and committed to the new memory flags.

## Verification

- **Positive**: `SUCCESS`, both `thread_a_ok`/`thread_b_ok` memory flags read `1` at `final_check`.
- **Mutation test**: temporarily removed the `x27`-save instruction in `yielding_is_a` (one line) —
  reran, got a clean `FAILURE`, confirming the test is non-vacuous, not passing by coincidence.
  Reverted, reran, confirmed `SUCCESS` again.
- **Full regression**: `sail_tests/run_veda_selfcheck_tests.sh`, **59/59 passed** (58 pre-existing +
  this modified test), zero regressions anywhere else in the corpus.

## Scope

Sail-level only, matching this project's established Sail-then-RTL sequencing — `veda_core.tlv` and
the toolchain-layer `runtime/veda_sched_asm.S`/`veda_sched.h` C-API (which documents the identical
limitation) are both untouched by this pass, and remain real, separately-scoped future work if this
mechanism is ever mirrored to those layers.
