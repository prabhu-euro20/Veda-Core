# Veda-Core RTL Minimal OS Kernel Milestone A Results — TSC + OSpecialRW SCR-Selector

**Date:** 2026-08-05
**Scope:** RTL mirror of the Sail-side minimal OS kernel Milestone A
(`veda-core/MINIMAL_OS_KERNEL_DESIGN.md`) — the TSC (Trusted Stack Capability) Special
Capability Register and `OSpecialRW`'s new SCR-selector operand. Mirrors
`veda_cap_insts.sail`'s own already-verified `VEDA_OSPECIALRW`/`veda_tsc`/`veda_tsc_tag`
field-for-field, following this project's own unbroken Sail-then-RTL sequencing.

## What was built

`veda_core.tlv`:

- **`$veda_ospecialrw_scr_sel[4:0] = $instr[24:20]`** — the SCR-selector operand, read from the
  **full** 5-bit rs2 register-field position. This is a real, load-bearing distinction from
  every vcapidx-shaped rs2-capability operand elsewhere in this file (e.g.
  `$veda_cseal_cunseal_rs2_cap[3:0] = $instr[23:20]`, a `0`-spacer + 4-bit split) — confirmed
  directly against Sail's own `encdec_veda_scr` mapping before writing this, not assumed from
  the vcap pattern. `5'b00000` = ODA (the pre-existing, backward-compatible encoding — `x0` in
  this position, exactly what every already-shipped `OSpecialRW` test still uses); `5'b00001` =
  TSC (new).
- **`$veda_tsc_*`** (tag/object_id/base/length/offset/perms/otype/reserved) — a new, parallel
  8-field persistent-register set, structurally identical to the existing `$veda_oda_*` set,
  gated by the opposite selector value so the two registers are genuinely independent, never
  aliased.
- **Write-back mux** — the 8 `$ospecialrw_wr_en`-gated branches (previously unconditionally
  reading `$veda_oda_*`) now select between `$veda_tsc_*`/`$veda_oda_*` based on
  `$veda_ospecialrw_scr_is_tsc`.

## Verification

New test `veda_smoke_mosA_tsc.S`/`tb_veda_smoke_mosA_tsc.sv`, mirroring Sail's own
`vc_switcher_tsc_roundtrip.S`: proves TSC starts genuinely untagged, round-trips a real
capability's `Base` field correctly, and remains independent of the ODA (writing TSC never
touches ODA's own separately-tracked state). Passed on the first run — no debugging needed.

```
$ bash run_veda_smoke_test.sh
...
CSealEntry sentry tag (must be 1): x15=0x1
...
*** TEST PASSED *** (OSpecialRW's new SCR-selector genuinely round-trips the TSC...)
...
---
38/38 (35 pre-existing + 3 new) TEST PASSED, 0 FAILED
```

Full regression (`run_veda_smoke_test.sh`, 38/38) and ACT4 RV64I conformance (`run_act4_tests.sh`,
51/51) both green, zero regressions.

## Not yet built

RTL mirror of Milestone B is covered separately in `MILESTONE_B_RESULTS.md` (this same
directory). A real scheduler/allocator compartment using either SCR in production is a later,
not-yet-started layer.
