# RTL Milestone 25: RTL Mirror of Full GPR Context Save

## Problem

The Sail side of the cooperative scheduler (`sail_tests/vc_scheduler_cooperative_yield.S`,
`MILESTONE_C_GPR_CONTEXT_SAVE_RESULTS.md`) now saves/restores all of x1-x31 across a yield. Per
this project's established Sail-then-RTL sequencing, the identical mechanism needed mirroring into
`rtl/sim/veda_smoke_m23_scheduler.S` (the RTL scheduler smoke test, previously an exact structural
twin of the Sail file's original, pre-fix 3-dword-only design) and `rtl/veda_core.tlv` itself.

## Design process

A Plan agent produced the RTL port design from a thorough reading of the current RTL source; it was
then independently re-verified by a 3-lens adversarial workflow (mscratch-CSR-addition correctness,
RTL-scheduler-port register/Object_ID accuracy, timing/bring-up risk), each lens re-deriving every
claim directly from the real `veda_core.tlv`/`.S` source, not the design's own restatement. Verdict:
READY_WITH_MINOR_FIXES — zero fundamental defects, one real precision correction (below), a
documentation nit, and two flagged risks the plan's own sequencing was designed to catch
empirically.

## The one genuinely new RTL feature: `mscratch`

Confirmed absent from `veda_core.tlv` by exhaustive grep before this milestone (the file's own
header comment explicitly scoped CSR recognition to "only 4 addresses": mtvec/mepc/mcause/mtval).
`mscratch` (CSR `0x340`) was added as a byte-for-byte structural copy of the existing `$mtvec`
pattern — the one existing CSR with no hardware-capture logic, exactly matching `mscratch`'s own
real semantics (nothing but software CSRRW ever writes it):

1. Decode: `$csr_is_mscratch = ($csr_addr == 12'h340);`
2. Read mux: one more arm in `$csr_rdata`'s ternary chain.
3. State register: `$mscratch[63:0] = $reset ? 64'b0 : (>>1$csr_write_en && >>1$csr_is_mscratch) ? >>1$csr_wdata : >>1$mscratch;`

Confirmed by adversarial review: `$veda_csr_escape_violation` correctly excludes `mscratch` (it
names five specific compartment-state CSRs, `mscratch` has no compartment-authority semantics,
matching `mtvec`'s own exclusion), `$alt_pc` correctly has no `mscratch` entry (never a jump
target), and CSRRW's "read old value into rd, write new into CSR" semantics are already fully
generic across every CSR via shared `$csr_rdata`/`$csr_wdata`/`$csr_write_en` signals — no
CSR-specific wiring needed beyond the three sites above. Two stale comment blocks (claiming "only 4
CSR addresses") were updated to name `mscratch` as a 5th.

**Verified empirically before use**, per the plan's own risk mitigation: a standalone round-trip
smoke test (`rtl/sim/veda_smoke_mscratch_roundtrip.S` + testbench, 8 real instructions: plain
csrw/csrr, then csrrw's atomic read-old/write-new) passed on the first real clocked-simulation run —
both `mscratch` properties confirmed, not just reasoned by analogy to `mtvec`.

## The RTL scheduler port

Structurally identical port of the Sail diff into `rtl/sim/veda_smoke_m23_scheduler.S`, using this
file's own real Object_IDs (110-122, no new IDs minted): mscratch bootstrap seed; `save_area_a`/
`save_area_b` grown from 3 dwords to 34 (`Length` `0x0020`→`0x0110`); `thread_index`'s own capability
(Object_ID 121) grown to also cover two new memory-backed flags, `thread_a_ok`/`thread_b_ok`
(`Length` `0x0020`→`0x0030`); `switcher_entry` reordered so the full 31-register save runs *before*
the pre-existing mcause-guard + mepc/mepcc read (which clobber x28/x29/x30); `resume_a`/`resume_b`
made fully self-contained (the shared `do_resume` tail is retired, since the eager-restore loop
overwrites x6, previously the shared tail's own means of remembering "A or B"); `thread_a_entry`/
`thread_b_entry` stamp and re-check a distinctive GPR pattern, committing the result to memory (not
a GPR — GPRs are now genuinely per-thread) via the already-bound `c8`; `final_check` reads the two
memory flags instead of the now-unreliable `x20`/`x21`/`x22`/`x26` GPR checks, preserving this
file's own `x27=0x600D`/`0xDEAD` sentinel convention (no HTIF in this RTL test style).

**Precision correction from adversarial review**: only `switcher_entry`'s own initial `thread_index`
branch changes from `lw x6,0(x5)` to `lw x5,0(x5)` (freeing x5 without touching x6's true
pre-trap value). `after_scheduler_return`'s own separate branch (deciding `resume_a` vs `resume_b`)
stays unchanged — by that point every GPR has already been durably saved to memory, so nothing
"true" is at risk there. Confirmed by direct re-reading of the literal current file, exactly the
discipline that caught two real bugs during the Sail port.

CODE_A/CODE_B `Length` was measured via `objdump -d` on the real assembled ELF (both thread bodies:
`0x134` = 308 bytes) rather than assumed — set to `0x0180` (384 bytes), comfortable margin.

## A real bug found only during implementation (not by design or adversarial review)

Both `thread_a_entry` and `thread_b_entry` were missing their own `li x19, 1` / `li x17, 1`
initialization (the `gpr_ok` markers) — present in the already-proven Sail source but dropped during
the RTL port. Every individual GPR-pattern comparison in the second-visit check block passed
correctly (confirmed by tracing all six `actual` vs `expected` values directly in simulation — all
six matched exactly), yet `thread_a_ok`/`thread_b_ok` still committed `0`, because the uninitialized
marker itself (defaulting to whatever the physical register held, `0`) was being ANDed into the
result regardless of the checks' own outcome. Root-caused via a disciplined bisection: traced the
exact fail-halt entry point (`final_check`'s own first `bne`), then the exact commit site
(`thread_a_commit`), confirming `x22=1` (bounds fidelity genuinely correct) but `x19=0`
(uninitialized) — then confirmed every one of the six pattern comparisons independently matched
(ruling out a save/restore mechanism bug), isolating the true cause to the missing initialization
line. This is the identical class of subtlety the Sail port's own methodology exists to catch: a
plausible-looking implementation that silently fails one specific check while everything else works.

## Verification

- **Standalone mscratch round-trip**: PASSED (plain write/read, and atomic CSRRW semantics).
- **Full scheduler port, positive**: PASSED — `x27=0x600D`, `x9` (TSC round-trip fidelity)=1.
- **Mutation test**: temporarily removed the `x27`-save instruction in `yielding_is_a` — reran, got
  a clean `x27=0xDEAD` / `*** TEST FAILED ***`, confirming the test is non-vacuous. Reverted, reran,
  confirmed `PASSED` again.
- **Testbench cycle budget**: raised from `repeat(700)` to `repeat(5000)` (the save/restore path now
  covers 31 registers per direction instead of 3, roughly 8x more `OCL.D`/`OCS.D` traffic per yield);
  confirmed empirically sufficient (test completes and settles well within budget).
- **Full RTL smoke-test regression**: `rtl/run_veda_smoke_test.sh`, **49/49 passed**, zero
  regressions elsewhere in the corpus.
- **ACT4 RV64I conformance suite**: `rtl/run_act4_tests.sh`, **51/51 passed**, zero regressions.

## Scope

RTL now has full Sail/RTL parity for this mechanism. `runtime/veda_sched_asm.S`/`veda_sched.h` (the
toolchain-layer C scheduler API, which documents the identical original limitation) remains
untouched by this pass — real, separately-scoped future work if this mechanism is ever mirrored to
that layer too.
