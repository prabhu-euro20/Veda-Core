# Veda-Core RTL Minimal OS Kernel Milestone B Results — the Sentry Mechanism

**Date:** 2026-08-05
**Scope:** RTL mirror of the Sail-side minimal OS kernel Milestone B
(`veda-core/MILESTONE_B_RESULTS.md`) — the reserved-otype sentry mechanism: `VEDA_OTYPE_SENTRY`
(`0xFFFE`), hardened `CSeal`, `CSealEntry`, and `OCRETURN`. Mirrors `veda_cap_insts.sail`'s own
already-verified implementation field-for-field, following this project's own unbroken
Sail-then-RTL sequencing.

## What was built

`veda_core.tlv`:

1. **`CSeal` hardened**: `$veda_cseal_authorized` gained `&& ($veda_cs2_offset != 16'hFFFE)`
   alongside its existing `!= 16'hFFFF` exclusion — the load-bearing security property, mirroring
   the Sail side's identical fix.
2. **New `VEDA_CSEALENTRY`** (funct7 `0010101`): `cd = cs1` sealed with the fixed `16'hFFFE`
   constant, no authorizing capability operand — soft-fail only (`$veda_csealentry_ok =
   $veda_rs1cap_tag && !$veda_sealed`), joins the 8-field write-back mux copying every field from
   `$veda_rs1cap_*` except `otype`.
3. **New `VEDA_OCRETURN`** (funct7 `0010110`): single-operand verify (tag, sentry-otype check,
   `Permit_Execute`) reusing `OCJALR`'s own cause codes; on success, narrows
   `$veda_pcc_base`/`$veda_pcc_length` to `cs1`'s own `Base`/`Length` at the same priority tier as
   `OCInvoke`'s own identical assignment, then jumps. `OCJALR` itself is completely unmodified —
   direct, load-bearing preservation of RTL Milestone 22's own "OCJALR cannot cross a compartment
   boundary" finding, confirmed by rerunning `veda_smoke_m22.S` unmodified in the same full
   regression.

**One real, caught-before-shipping bug in the Sail-side encoding mirrored here too**: none new —
the RTL encoding was written directly from the already-corrected Sail mapping, so the earlier
33-bits-instead-of-32 mistake was not repeated.

## Two real bugs found and fixed during RTL test development (not in the RTL logic itself)

Both new test programs failed on the first run. Direct, empirical, cycle-by-cycle signal-trace
debugging (a purpose-built debug testbench dumping `$pc`/`$instr`/decode signals every cycle, the
same "verify via direct simulator output, not assumption" discipline this project has used
throughout) found the real causes — **in both cases, the actual `VEDA_CSEALENTRY`/`VEDA_OCRETURN`
hardware logic was already correct; the bugs were in the new test programs themselves**:

1. **A reserved Object_ID collision.** The positive test's compartment used Object_ID `60/61/62`,
   copied by pattern-analogy from an incorrect assumption about `veda_smoke_m22.S`'s own object
   IDs. Direct trace inspection showed `$veda_bind_trap` firing on the very first `bind` for
   Object_ID 60, with `owner=99`, `ownerok=0`. Reading `veda_core.tlv`'s own `initial` block
   (lines 99-121) revealed why: **Object_ID=60 is a permanent, deliberately-seeded RTL test
   fixture from Milestone 12's own wrong-owner negative test** ("pre-claimed by owner_hart=0x63
   (99 decimal)... chosen specifically because it's the one value genuinely unused anywhere else
   in this project's own existing RTL test corpus" — at the time Milestone 12 was written).
   `veda_smoke_m22.S` actually uses Object_ID `90-94`, not `60-62` — the real M22 file was
   misremembered rather than re-read directly before picking IDs, the exact class of mistake this
   project's own "verify before deciding" discipline exists to catch. Fixed by moving the
   compartment to Object_ID `70/71/72`, confirmed unused by grep against every existing
   `veda_smoke_*.S` file's own reserved/seeded IDs (`1`, `2`, `60`).
2. **An arithmetic slip in the negative test's own expected `mtval`.** The negative test used
   capability register `c1` for the untagged-OCRETURN check, but the expected `mtval` constant
   (`0xA2`) was copied from the Sail-side test's own `c5`-based calculation
   (`(5<<5)|0x02=0xA2`) without recomputing for `c1` (`(1<<5)|0x02=0x22`). Trace inspection showed
   the hardware's real `mtval` was `0x22` — exactly `TAG_VIOLATION` with the correct `cap_idx=1` —
   confirming `OCRETURN`'s own trap logic was already right; only the test's own expected constant
   was wrong. Fixed by correcting the constant to `0x22`.

## Verification

New tests `veda_smoke_mosB_sentry.S`/`tb_veda_smoke_mosB_sentry.sv` (positive: `CSealEntry` mints
a real sentry, and a single-operand `OCRETURN` from inside a live, narrowly-bounded `OCInvoke`
compartment both lands at the sentry's own target and genuinely widens
`veda_pcc_base`/`veda_pcc_length` — direct proof of a real compartment-boundary crossing, not just
a jump) and `veda_smoke_mosB_sentry_neg.S`/`tb_veda_smoke_mosB_sentry_neg.sv` (negative: ordinary
`CSeal` genuinely cannot forge the reserved sentry otype even when an authority capability is
walked to `Offset=0xFFFE` via `OCA`; `OCRETURN` correctly hard-traps `TAG_VIOLATION` on an
untagged capability and resumes via a real trap-and-recover cycle).

```
$ bash run_veda_smoke_test.sh
...
CSealEntry sentry tag (must be 1): x15=0x1
CSealEntry sentry type (must be 0xFFFE): x16=0xfffe
reached return_landing (must be 0x2222): x20=0x2222
veda_pcc_length after OCRETURN (must be 0xFFFF): x21=0xffff

*** TEST PASSED ***
...
OCA walk to Offset=0xFFFE tag (must be 1): x12=0x1
forged-sentry CSeal tag (must be 0, soft-failed): x10=0x0
OCRETURN-untagged trap reached with correct mcause/mtval (must be 0x600D): x11=0x600d

*** TEST PASSED ***
---
38/38 (35 pre-existing + 3 new, including Milestone A's own) TEST PASSED, 0 FAILED
```

Full regression (`run_veda_smoke_test.sh`, 38/38, including an unmodified rerun of
`veda_smoke_m22.S`) and ACT4 RV64I conformance (`run_act4_tests.sh`, 51/51) both green, zero
regressions.

## Not yet built

A real scheduler/allocator compartment using `OCRETURN` in production — this milestone builds and
proves the sentry *primitives* in RTL, matching the Sail side's own identical scoping; the next,
not-yet-started layer is a real minimal-OS scheduler built on top of both milestones' primitives.
