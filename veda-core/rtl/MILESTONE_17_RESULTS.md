# Veda-Core Milestone 17 Results (Sail + RTL): OCJALR — Closing the Real Software-Discipline Gap

**Date:** 2026-07-27
**Scope:** `OCJALR`, a new instruction closing the one real, honest gap
`STACK_FRAME_CALL_RETURN_ANALYSIS.md` found by testing rather than
assuming: a return-address protection convention built entirely from
already-existing instructions (`OCA`+`CSeal` at the call site) worked
correctly only if the caller remembered an explicit `CGetTag` check
before jumping through the reloaded capability — nothing in hardware
stopped that check from being silently omitted. `OCJALR` merges unseal
-verification and jump into one atomic instruction, adapted from real
CHERI's own `CJALR` (CHERI ISA spec p.213, full semantics read directly
from `specs/cheri-architecture.pdf` before writing any code, not assumed
from a summary).

## Design, reasoned before writing any code

Real CHERI's own `CJALR` is a general-purpose jump-through-any-capability
instruction: it also mints a fresh sentry-sealed return capability as a
side effect of every jump, using a dedicated, reserved `otype` sentinel
distinct from the general-purpose `CSeal` mechanism. Veda-Core's own
`OCJALR` is deliberately narrower — scoped to exactly the half of the
vulnerability that was real: the *verify-and-consume* side of an
already-sealed return-capability. It reuses Milestone 6's existing,
already-verified `CSeal`/`CUnseal` type-authority model (the call site
already works today, unmodified, per `STACK_FRAME_CALL_RETURN_ANALYSIS.md`'s
own `prot_caught` experiment) rather than inventing a second, parallel
sealing mechanism for one purpose.

**Operands**: `cs1` (the sealed return-capability being verified and
jumped through), `cs2` (the same seal-authority capability the call
site's own `CSeal` used). No `rd` — matches `OCInvoke`'s own established
precedent for an instruction whose real output is a PC redirect, not a
register value.

**Check order**, grounded in real, established precedent rather than
invented fresh:
1. `Tag(cs1)` must hold — else Tag Violation (`0x02`).
2. `Tag(cs2)` must hold — else Tag Violation (`0x02`).
3. `cs1` must be sealed — else Seal Violation (`0x03`). `VEDA_CORE_SPEC.md`'s
   own cause table already cites real CHERI's `CJALR`
   (`CapEx_SealViolation`) as the grounding for this exact cause code.
4. `cs2` must NOT be sealed — else Seal Violation (`0x03`).
5. `cs2` must carry `Permit_Unseal` — else Seal Violation (`0x03`).
6. `cs2.Offset == cs1.otype` (the identical type-authority match `CUnseal`
   itself already checks) — else Type Violation (`0x04`).
7. `cs1` must carry `Permit_Execute` — else Permit_Execute Violation
   (`0x11`).
8. Success: `PC := cs1.Base + cs1.Offset` — the identical `CGetAddr`
   arithmetic already established, now performed atomically as part of
   the check-and-jump rather than as a separate, skippable instruction.

## A real encoding collision, found and fixed before any RTL was written

The first-draft `funct7 = 0010011` (the value naturally "next" after
`OCInvoke`'s own `0010010`) was found — on the Sail side, before RTL
existed — to collide with `OSpecialRW`'s own already-existing encoding at
that exact `funct7`. The collision is narrow (`OSpecialRW` hardwires its
own `rs2`-position field to all-zero rather than treating it as a real
operand, so only `OCJALR` instances with `cs2 = c0` would actually have
aliased), which is precisely why it didn't surface as an immediate build
or test failure — a real, easy-to-miss bug this project's "verify before
deciding" discipline exists to catch. Fixed by moving to `funct7 =
0010100`, the next genuinely free slot, verified directly via a full grep
of every existing Custom-2/`funct3=001` user before adopting it.

## Sail implementation and verification

`veda_cap_insts.sail` gained `VEDA_OCJALR : (vcapidx, vcapidx)` (encdec,
execute, assembly clauses), inserted directly after `VEDA_OCINVOKE`,
reusing the same real `veda_trap()`/`jump_to()` primitives.

Two new self-check tests, both passing on the first real run:
- **`vc_ocjalr.S`** (positive): mints a real target object (`Permit_Execute`)
  and a real seal-authority object, seals the target under the authority,
  and issues `ocjalr` — proven to land exactly at `landing_pad` (the
  real, runtime-computed target address), not merely "didn't trap."
- **`vc_ocjalr_neg.S`** (negative): three real, distinct trap scenarios —
  Seal Violation (an unsealed capability used directly, the exact real
  vulnerability class `prot_gap` demonstrated), Type Violation (a
  mismatched seal-authority, mirroring `OCInvoke`'s own real negative
  -1 technique), and Permit_Execute Violation (a jump target lacking
  execute permission, mirroring `OCInvoke`'s own real negative-2
  technique) — each verified via the real `mcause`/`mtval`/`mepc` a
  shared trap handler dispatches on.

**Full Sail self-check suite: 28/28 passed** (26 pre-existing + 2 new),
zero regressions.

## RTL implementation and verification

`veda_core.tlv` gained `$is_veda_ocjalr`/`$veda_ocjalr_violation`/
`$veda_ocjalr_cause`/`$veda_ocjalr_cap_idx`/`$veda_ocjalr_target`,
inserted directly after `OCInvoke`'s own equivalent block, reusing the
already-established `$veda_rs1cap_*`/`$veda_cs2_*` field-extraction
signals (no new field-extraction logic needed — `OCJALR` shares the
identical operand shape `OCInvoke`/`CSeal`/`CUnseal` already use). Joined
the same combined `$veda_trap_taken`/cause/cap_idx mux `OCInvoke` already
established, and the same `$pc_src`/`$alt_pc` real-hardware-jump mux.

Two new RTL smoke tests, mirroring the Sail scenarios field-for-field
(same objects, same encodings, identical bit layout in both layers), both
passing on the first real Icarus Verilog run:
- **`veda_smoke_m17.S`/`tb_veda_smoke_m17.sv`** (positive): real jump
  lands exactly at `landing_pad`, confirmed via `x23=0x600D`.
- **`veda_smoke_m17_neg.S`/`tb_veda_smoke_m17_neg.sv`** (negative): all
  three trap scenarios (Seal/Type/Permit_Execute Violation) genuinely
  hard-trap with the correct `mcause`/`mtval`, all three `MRET`s resume
  correctly, confirmed via `x23=0x600D` after all three round trips.

**Full regression**: the pre-existing Milestone 1–14 aggregate suite (25
`TEST PASSED` markers, run via `run_veda_smoke_test.sh`), Milestones
15/16's own four positive/negative tests (re-run directly against the
`OCJALR`-updated core), and the two new Milestone 17 tests — **31 real
RTL test programs total, zero regressions**. The full real ACT4 RV64I
conformance suite: **51/51 passed, zero regressions**.

## The real point of this milestone: proving the exact gap is now closed

`STACK_FRAME_CALL_RETURN_ANALYSIS.md`'s own `prot_gap` experiment
(session-scoped, not committed) demonstrated that omitting the explicit
`CGetTag` check before `CUnseal`+`CGetAddr`+`JALR` left a corrupted
return-capability's `Base`/`Offset` fields fully readable and jumpable —
the resulting jump landed at an undefined, out-of-range address, and both
`$pc` and the marker register X-propagated for the rest of the run
(`FINAL_X30=0xxxxxxxxxxxxxxxxx`).

A new program, `prot_fixed.S` (session-scoped, not committed), reproduces
the identical setup and the identical corruption — but replaces the
vulnerable `CUnseal`+`CGetAddr`+`JALR` tail with a single `ocjalr`
instruction, **with no explicit software Tag check written anywhere in
the file**. Real result, run against the real, updated, committed
`veda_core.tlv`:

| | `prot_gap` (before this milestone) | `prot_fixed` (using `OCJALR`) |
|---|---|---|
| Final `x30` | `0xxxxxxxxxxxxxxxxx` (undefined) | `0xca11` (real, controlled hard-trap) |
| Final PC | `0xxxxxxxxxxxxxxxxx` (undefined) | `0x800000fc` (a real, valid address — the trap handler's own resume point) |
| Cycle of divergence | 56 | 59 |

The corruption is now caught **structurally**, not by programmer
discipline — there is no explicit check in `prot_fixed.S` for `OCJALR`'s
own hardware gate to bypass, and none was needed. This is the concrete,
empirical closing of the real gap this milestone set out to fix.

## Real, measured per-call cost — not estimated

A third experiment, built specifically to answer this: two loop
benchmarks, both performing a **real jump every iteration** (not just a
computed-but-unused value) so the comparison is apples-to-apples — a
traditional `sd ra`/`ld ra`/`jr ra` sequence, and an `OCJALR`-based
sequence (`OCA`+`CSeal`+`OCS.C`+`OCL.C`+`OCJALR`, the one-time
`Populate`/`Bind`/offset-derivation setup hoisted outside the loop,
matching how a real compiler would treat a loop-invariant call site) —
run at `N`=1,2,4,8,16 against the real, unmodified, committed
`veda_core.tlv`, each point independently assembled and simulated:

| N | Traditional (cycles) | `OCJALR` (cycles) | Overhead |
|---|---|---|---|
| 1 | 11 | 42 | +31 |
| 2 | 16 | 49 | +33 |
| 4 | 26 | 63 | +37 |
| 8 | 46 | 91 | +45 |
| 16 | 86 | 147 | +61 |

Exact closed form, matching every row: **`trad_cycles = 6 + 5N`**,
**`ocjalr_cycles = 35 + 7N`** — a real **+2 cycles/call** steady-state tax
over the traditional convention (5 vs. 7 cycles/call), plus the same
one-time 29-cycle setup `STACK_FRAME_CALL_RETURN_ANALYSIS.md` already
measured for the call-side machinery.

**`OCJALR` is also cheaper than the vulnerable sequence it replaces, not
just safer**: `STACK_FRAME_CALL_RETURN_ANALYSIS.md`'s own hand-rolled
`CUnseal`+`CGetAddr` sequence (that experiment's own loop deliberately
never included the trailing jump, to isolate the "verify" cost alone)
measured at **10 cycles/call**. `OCJALR` collapses `CGetTag`+`beqz`+
`CUnseal`+`CGetAddr` — 4 separate, software-discipline-dependent
instructions — into one atomic, hardware-enforced instruction, at **7
cycles/call**, a genuine ~30% reduction, because merging the check into
the jump itself removes the branch and one of the two capability-query
instructions, not just the software gap they left open.

## What remains open, honestly

- `OCJALR` does not itself mint a new sealed return-capability (unlike
  real CHERI's own general-purpose `CJALR`) — the call site still needs
  its own `OCA`+`CSeal` pair, already proven working and unchanged by
  this milestone. A fused "seal-and-store-on-call" instruction was
  considered and explicitly not pursued here, matching this project's
  own established scope discipline (`ARCHITECTURE_IMPROVEMENT_FINDINGS.md`'s
  own fused-instruction investigation reached the identical conclusion
  for a different instruction pair).
- No compiler exists to automatically emit this convention for ordinary
  function calls — every test in this project remains hand-assembled,
  the same honest, already-stated limit as every other milestone.
- Zicfiss (the ratified RISC-V shadow-stack alternative
  `STACK_FRAME_CALL_RETURN_ANALYSIS.md` also identified) remains
  unbuilt — a real, separate, smaller piece of future work at the RVA23
  base-core level, not touched by this milestone.
