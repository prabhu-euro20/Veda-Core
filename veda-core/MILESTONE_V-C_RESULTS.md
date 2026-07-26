# Veda-Core Formal Model — Milestone V-C Results

**Date:** 2026-07-22
**Scope:** a real, self-checking directed test corpus for the full Veda-Core
ISA built in Milestones V-A/V-B, per `FORMAL_VERIFICATION_PLAN.md`'s own
description: "a small directed self-check test corpus, explicitly
including both positive and negative sealed/unsealed cases... a
deliberately-wrong capability check must be caught, not just a correct one
shown to pass."

## What changed from Milestone V-B's own tests

V-B's 13 tests were real and passing, but *manually* verified — each one
required reading `sail_riscv_sim`'s register/CSR trace output by eye and
comparing it against the expected value written in a code comment. That
doesn't scale and isn't genuinely "self-checking" in the sense ACT4's own
real conformance tests are (`RVMODEL_HALT_PASS`/`RVMODEL_HALT_FAIL`,
polling `tohost`). This pass closes that gap for real, not by inventing a
new mechanism, but by confirming and reusing one that already existed:

**`sail_riscv_sim` has real, working, built-in HTIF/`tohost` support**,
confirmed directly (not assumed) by giving it a real `.tohost` linker
section for the first time and observing its actual behavior: writing the
real ACT4 `tohost` low-word pass code (`1`) makes it print `SUCCESS` and
exit `0`; the fail code (`3`) makes it print `FAILURE: 1` and exit `1`.
Every prior test run in this project's own Sail work had `tohost`
disabled purely because the minimal linker scripts used never defined the
symbol — not because the mechanism doesn't work.

## Infrastructure built this pass

- `sail_tests/veda_selfcheck_macros.S` — `RVMODEL_HALT_PASS`/
  `RVMODEL_HALT_FAIL`, reused field-for-field from this project's own
  already-verified ACT4 `rvmodel_macros.h` (two 32-bit stores to
  `tohost`'s low/high words, not one 64-bit store — a real mistake made
  and caught while writing this: an initial draft used `sd` twice at the
  same address, which would have silently zeroed the pass code it had
  just written).
- `sail_tests/veda_selfcheck.ld` — a linker script with a real `.tohost`
  section, extending the project's existing minimal test `.ld`.
- `sail_tests/run_veda_selfcheck_tests.sh` — a batch runner mirroring
  `rtl/run_act4_tests.sh`'s own real pattern: assemble, link, run, check
  `tohost` via `sail_riscv_sim`'s own exit code and `SUCCESS`/`FAILURE`
  output, print a PASS/FAIL table and an `N/M passed` summary.
- A reusable trap-handler pattern for negative (trap-expected) tests:
  install a handler via `mtvec`, have it compare `mcause`/`mtval` against
  the exact expected values, and only then signal `RVMODEL_HALT_PASS` —
  proving the trap fired for the *right* reason, not just that a trap
  happened at all. Falling through the expected-to-trap instruction
  without ever trapping correctly falls into `RVMODEL_HALT_FAIL`.

## Result: 14/14 real, self-checking tests pass

| Test | Covers | Kind |
|---|---|---|
| `vc_ocl_ocs_selfcheck` | `OCL.D`/`OCS.D` round-trip | positive |
| `vc_ocl_ocs_neg` | unbound capability | negative (trap) |
| `vc_nmc_add` | `NMC_ADD.D` old/new value | positive |
| `vc_nmc_add_neg` | missing `Permit_NMC_Compute` | negative (trap) |
| `vc_atomic` | Veda-Atomic `AMOXOR.D` | positive |
| `vc_oca` | `OCA` repositioning, verified via `NMC_ADD` | positive |
| `vc_oca_neg` | `OCA` soft-fail then downstream hard-trap | negative (trap) |
| `vc_capquery` | all 7 query instructions in one program | positive |
| `vc_csetbounds` | `CSetBounds` narrowing | positive |
| `vc_cseal` | `CSeal` mint | positive |
| `vc_seal_enforce_neg` | sealed capability used for `OCS.D` | negative (trap) |
| `vc_cunseal` | `CUnseal` round-trip + reuse | positive |
| `vc_cseal_unauth_neg` | `CSeal` with no `Permit_Seal` | negative (soft-fail, no trap) |
| `vc_odt_lifecycle` | Populate → Bind → use → Destroy → stale reuse | positive + negative (trap) in one |

**Real negative control on the test infrastructure itself**, not just the
instructions under test: a copy of `vc_atomic` with one expected value
deliberately changed (`0xF0` → `0xF1`) was run through the same batch
runner and correctly reported `FAIL (exit=1)`, confirmed *before* trusting
the clean `14/14` result — the same discipline this project used for the
RTL ACT4 testbench (a deliberately-broken core must be shown to fail, not
just a correct one shown to pass).

## Explicitly not covered this pass

The remaining 8 of 9 Veda-Atomic ops at non-`AMOXOR` operations, and all
non-D widths across every instruction family — the same, already-stated
V-B scope boundary, not re-litigated here. `CInvoke`-equivalent domain
transition remains out of scope (no `PCC`-equivalent exists to test
against). This is a "small directed" corpus per the plan's own words, not
an exhaustive one — broader coverage is real, identifiable future work,
not silently declared "done."

## What this closes

Per `FORMAL_VERIFICATION_PLAN.md` §5: *"Only after V-A/B/C does it make
sense to start real Veda-Core RTL (Custom-0/1/2 decode) — catching spec
bugs in Sail first, before hardware exists to debug against, is the entire
point of doing this work now rather than after."* V-A, V-B, and V-C are
now all real and done. Starting Veda-Core RTL is no longer blocked on
unstarted formal-model work.
