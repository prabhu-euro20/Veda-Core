# VEDA_LOCAL_HANDLER: hardware-enforced compartment-local fault recovery (RTL mirror)

**Date:** 2026-08-19
**Scope:** mirrors the verified Sail model (`LOCAL_FAULT_RECOVERY_DESIGN.md`/`LOCAL_FAULT_RECOVERY_RESULTS.md`)
into synthesizable RTL (`veda-core/rtl/veda_core.tlv`) -- the step that turns this security mechanism
from a formal-model guarantee into a real hardware one, directly serving this project's own
"hardware-native security system" goal. Built via a multi-agent workflow (parallel audit of the current
RTL's touch points and conventions, a single implementation pass, then two independent adversarial
reviews and a fresh, independently re-run regression -- none of which trusted the implementer's own
self-report), followed by a real, critical fix (below) found by that adversarial review and closed
directly by me before this milestone was considered done.

## Mechanism (RTL-specific notes; full mechanism description in the Sail-side docs)

New 8-entry, otype-keyed `local_handler_table` (hand-unrolled `$veda_lh0..7_{valid,otype,entry_addr}`,
matching the existing `VEDA_TRAP_QUARANTINE` tracker table's own established shape, deliberately a
*separate* structure for the same reason as Sail: quarantine entries decay/evict opportunistically, a
registered handler must be stable). New `VEDA_SET_LOCAL_HANDLER` instruction (`osethandler`,
`opcode=0x5b`/`funct3=0b001`/`funct7=0x17`, the next free slot after `OCRETURN`'s `0x16`), with the same
three checks Sail uses (live-compartment, confused-deputy bounds, table-full) in the same order, plus
the `UNSEALED_OTYPE` exclusion found necessary by adversarial review (below). New top-priority redirect
arm added to the existing `$veda_pcc_base`/`$veda_pcc_length`/`$veda_pcc_otype` register mux (the exact
chokepoint `VEDA_TRAP_QUARANTINE`'s own RTL mirror already extended) and to the `$alt_pc` PC-on-trap mux
-- unlike Sail, which needed a new `veda_trap_vector_override()` wrapper around a base-file function
because no existing hook point existed, RTL already had a single clean priority-mux ternary at the
`$alt_pc` chokepoint, so no comparable base-file surgery was needed here.

**Real, honestly-documented structural difference from Sail, found via trace, not assumed**: the
quarantine-composition redirect count is **exactly 3 redirects then fallback on the 4th** in RTL, not
Sail's corrected "2 then 3rd." Root cause: RTL's redirect decision is a single same-cycle combinational
mux that can only read the trap-tracker's fault count *as it stood before this fault's own increment* (a
register write that lands the following cycle) -- i.e. check-before-increment -- structurally different
from Sail's sequential record-then-check, which observes the post-increment count in the same step. Both
are correct implementations of the same underlying guarantee (a self-faulting handler is bounded by the
same fixed threshold as any other compartment); the exact count differs because Sail is sequential
software semantics and RTL is single-cycle hardware, not because either is wrong.

## Verification

**Implementation** (via workflow, independently re-confirmed): 4 new smoke tests mirroring the Sail
side's own four (positive, no-handler negative, quarantine-composition negative, confused-deputy
bounds-guard negative), Object_IDs 590-603 (audit found 570-583 initially, but 572 collided with a
pre-existing seeded ODT fixture baked into `veda_core.tlv`'s own `$reset` block at `odt_idx=60` --
caught, diagnosed, and moved to a genuinely collision-free block). Full smoke regression: **71/71
passed**. ACT4 RV64I conformance: **51/51 passed**. Both counts independently re-confirmed by a separate
agent running fresh from a clean invocation (not reusing the implementer's own log), exact match.

**Real bugs found via testing during implementation** (none in the core mechanism itself, all in test
authoring -- matching the Sail side's own experience that real bugs surface through testing, not
inspection): an Object_ID/ODT-index aliasing collision (572 vs. a pre-existing seeded fixture), an
off-by-one `handler_entry` offset (a dead `poison_mid` instruction sat between the jump and the real
target), an undersized compartment `Length`, a capability-register reuse bug (the same register used for
both the handler pointer and the pre-minted `OCRETURN` sentry, clobbering the sentry), a RISC-V ABI
register-name collision (`t3` used as scratch while also holding a live sentinel value in the same test),
and a confused-deputy test target that landed accidentally in-bounds given that file's specific layout.
All fixed; all confirmed via `objdump`/direct trace, not assumption.

**Mutation tests** (via workflow, independently re-confirmed): dropping the quarantine gate on the
redirect flips the composition test to `FAILURE` (unbounded redirect, pinned only by the testbench's own
cycle budget, with corrupted fallback-state readback) -- confirms the gate is real and load-bearing.
Reinstating the otype-reset-on-redirect flips the same test to `FAILURE` with a *different*, predicted
signature (exactly 1 redirect instead of 3, all other fallback checks reading correctly) -- confirmed via
a temporary, non-registered cycle-accurate trace testbench (built, used, and deleted, never checked in)
that the compartment's live otype genuinely reads back as the wrong sentinel after the mutation, causing
the second real fault to miss the table and fall through -- the exact misattribution mechanism predicted,
not a coincidental failure. Both mutations reverted; `md5sum`-confirmed byte-identical to a pre-mutation
snapshot; full regression re-confirmed unchanged after each revert.

## Adversarial review finding and fix (found before this milestone was considered closed)

Two independent adversarial reviews of the finished implementation -- one general-correctness, one
security-focused, deliberately different lenses -- **both, independently, found the identical real,
critical gap**, described in full (with the fix applied identically on both Sail and RTL) in
`LOCAL_FAULT_RECOVERY_RESULTS.md`'s own "Adversarial review finding and fix" section: `osethandler`'s
original "live compartment" check tested only PCC boundedness, never `veda_pcc_otype` identity, so a
compartment resumed via an ordinary trap+`mret` round trip or via `OCReturn` (both leave `veda_pcc_otype`
at the shared `UNSEALED_OTYPE` sentinel) could register a handler-table entry under that shared key --
letting a completely unrelated compartment, also resumed into that same ordinary window, collide on the
same key and get redirected into a different compartment's chosen handler address. Confirmed as a
genuine RTL property, not just inherited from Sail's own text, by directly grepping every `is_mret`
occurrence in `veda_core.tlv` -- none touches `$veda_pcc_otype`'s own register mux -- and by reading
`OCRETURN`'s own execute logic (line ~3244), which explicitly sets `$veda_pcc_otype = 16'hFFFF` on every
successful return.

**Fix**: `$veda_osethandler_violation` gained a new OR-term, `($veda_pcc_otype == 16'hFFFF)`, alongside
the matching cause-code arm (reusing `VEDA_CAUSE_NO_LIVE_COMPARTMENT = 0x0a`); `$veda_lh_redirect_active`
gained the matching defense-in-depth exclusion (`$veda_pcc_otype != 16'hFFFF`), mirroring the Sail-side
fix exactly.

**New test** (`rtl/sim/veda_smoke_local_handler_neg_unsealed_otype.S`/`.sv`, Object_ID 610, GPR-readback
convention): `OCRETURN` through a sentry into a bounded region, called directly from `_start` with no
`OCInvoke` anywhere in the file, then an in-bounds `osethandler` attempt. Confirms hard-trap
(`cause=0x0a`, `cap_idx=8` matching the operand) and the unchanged ordinary global fallback. **Passed on
first attempt.** Registered in `run_veda_smoke_test.sh`; **full regression re-confirmed 72/72 smoke
passed, 51/51 ACT4 passed**.

**Mutation-tested directly by me** (not delegated, given the finding's severity): disabling the new
`$veda_osethandler_violation` term flips the new test to `FAILURE` (70/71 that run). Traced with a
temporary, non-registered debug testbench (built, used, and deleted -- never checked in,
`tb_debug_unsealed_mutation.sv`): the mutation genuinely lets `osethandler` succeed (`x22` transiently
reads `0xBAD1`, the "unexpected success" fail-sentinel, proving the confused-deputy fallthrough path
fired), and a second, independent effect -- the test's own `done` label sits outside the tiny 64-byte
compartment's own bounds, so the subsequent `j done` genuinely faults with an ordinary bounds violation,
overwriting `x22` to `0xBAD5` (cause-mismatch) -- both signals independently confirm the check is real
and load-bearing, the second one via a legitimately different (not contradictory) mechanism. Reverted;
`md5sum`-confirmed byte-identical to the pre-mutation snapshot; **full regression re-confirmed 72/72
smoke, 51/51 ACT4**, matching the pre-mutation baseline exactly.

## Files changed

`veda-core/rtl/veda_core.tlv` (full VEDA_LOCAL_HANDLER mirror: `local_handler_table`, `osethandler`
instruction, redirect arms on the PCC-state and PC-on-trap muxes, plus the `UNSEALED_OTYPE` fix on both
the registration and redirect sides). `veda-core/rtl/run_veda_smoke_test.sh` (+5 test registrations: the
4 original mirror tests + the new collision-fix test). New `rtl/sim/veda_smoke_local_handler_pos.S`/`.sv`,
`veda_smoke_local_handler_neg_no_handler.S`/`.sv`, `veda_smoke_local_handler_neg_quarantine.S`/`.sv`,
`veda_smoke_local_handler_neg_bounds_guard.S`/`.sv`, `veda_smoke_local_handler_neg_unsealed_otype.S`/`.sv`
(`.o`/`.elf`/`.hex` build artifacts are gitignored, regenerated from source by the established build
recipe). This results doc.

## Final verification summary

**Sail**: 79/79 self-check regression (including the `UNSEALED_OTYPE` collision-fix test), zero
regressions across the full toolchain sweep.
**RTL**: 72/72 smoke regression (including the same collision-fix test), 51/51 ACT4 RV64I conformance,
zero regressions.
Both layers now carry the identical `UNSEALED_OTYPE` fix, both independently mutation-tested and
confirmed load-bearing.

## Not committed or pushed yet

Matching this session's established pattern -- a fresh, explicit instruction from the user is required
before any of this work is committed or pushed.
