# Veda-Core Milestone 19 Results — Veda-Purecap Enforcement (Sail)

**Date:** 2026-08-01
**Scope:** closes a real, previously-unstated gap found via direct source verification while discussing Veda-Core's CHERI-community outreach thread: `VEDA_CGETBASE` legitimately extracts a capability's raw `Base` address into an ordinary GPR (a real, spec-required query instruction), but ordinary RV64I `LOAD`/`STORE` had zero awareness of Veda-Core, capabilities, or the ODT — so `cgetbase x1,c2` followed by an ordinary `ld x3,0(x1)` completely bypassed every Veda-Core protection. Architecturally the same real property CHERI's own "hybrid mode" has. This milestone adds Veda-Core's own equivalent of CHERI's "purecap mode" to close it, plus closes a second, related gap in Milestone 14's own `OCInvoke` compartment-bounding (fetch was bounded, ordinary data access was not). RTL mirror deliberately not attempted this pass (see "Not yet built").

## Full-codebase audit performed before design, not assumed

Before designing a fix, every memory-touching instruction class in the Sail model was checked for the same vulnerability class, per explicit direction to verify robustness project-wide, not just patch the one reported instance:

- Ordinary RV64I `LOAD`/`STORE` (`extensions/I/base_insts.sail`) — confirmed live and vulnerable (routes through `vmem_read`/`vmem_write`, enabled in the real test config).
- AMO/LR-SC (`extensions/A/zalrsc_insts.sail`), FP loads/stores (`extensions/FD/fext_insts.sail`), Vector loads/stores (`extensions/V/vext_mem_insts.sail`), CFI shadow-stack (`extensions/cfi/zicfiss_insts.sail`) — confirmed via grep to route through the exact same `vmem_read`/`vmem_write` pipeline, hence the same vulnerability class, but all four extensions are currently `"supported": false` (or `"Disabled"`) in `sail_tests/veda_test_sail.json` — not live today.
- Veda-Core's own `OCL.D`/`OCS.D`/`OCL.C`/`OCS.C`/`NMC_ADD.{W,D}`/9 Veda-Atomic ops — confirmed via an exhaustive grep of the whole model tree that all 8 real memory-touching call sites use `read_ram`/`write_ram` directly (`core/phys_mem_interface.sail`), the *only* callers of those two functions anywhere in the tree besides the definitions themselves. This means a single fix on the ordinary-access chokepoint can never interfere with any legitimate Veda capability-checked access, and automatically extends to AMO/FP/Vector/CFI the moment any of those extensions is ever enabled — no per-extension patches needed.

Secondary, honest, out-of-scope finding: since Veda's own accesses bypass `read_ram`/`write_ram` directly, they also skip PMP and address-translation. Not live today (PMP `"count": 0`, no virtual-memory scheme enabled in the real test config) — named for future hardening, not fixed here.

## The real, unclaimed hook used

`core/addr_checks.sail` already defines `ext_data_get_addr(base, offset, access, width)`, called by `get_transformed_data_addr()` in `sys/vmem_utils.sail` before every `vmem_read`/`vmem_write` — its own comment already invites this: "Extensions might override and add additional checks." Confirmed via grep: nothing in this codebase overrode it before this milestone. Structurally identical to `ext_fetch_check_pc`, Milestone 14's own hook for PCC fetch-bounding — an established pattern, not a new idiom.

## Design implemented

1. **`ext_data_addr_error`** (`core/addr_checks.sail`) widened from `unit` to `struct { cap_idx: bits(5), cause: bits(5) }`, mirroring `veda_xtval`'s own two-part signature. Confirmed safe via grep: the four currently-disabled extensions that already propagate this type through `Ext_DataAddr_Check_Failure` only ever forward it opaquely.
2. **New CSR `0x7C5` (`veda_mode`)** (`extensions/Veda/veda_regs.sail`), bit 0 = `veda_purecap`. Write gated to `cur_privilege == Machine` explicitly inside `write_CSR`'s own clause, matching `VEDA_OSPECIALRW`'s established precedent (noted honestly: this is not independently enforced for the pre-existing `0x7C0`-`0x7C4` CSRs either — this milestone matches that existing pattern consistently, doesn't silently fix a different milestone's scope).
3. **New cause `VEDA_CAUSE_PURECAP_VIOLATION = 0x07`** (`extensions/Veda/veda_bind_insts.sail`) — `VEDA_CORE_SPEC.md`'s own cause table already listed `0x07` as reserved; not an arbitrary new pick.
4. **The real enforcement** (`postlude/step_ext.sail`, moved there for the identical real module-ordering reason `ext_fetch_check_pc`'s body already lives there — `postlude` requires `Veda_insts`, `core` does not): an ordinary memory access traps if EITHER `veda_purecap` is set OR `veda_pcc_length != VEDA_PCC_UNBOUNDED` (currently inside a live `OCInvoke` compartment). The second condition reuses Milestone 14's existing compartment-bounds infrastructure for free, closing a real gap that infrastructure left open: compartmentalized code's instruction fetch was bounded, but its ordinary data access was not.
5. Both conditions deliver the trap via the same direct-construction technique the real PCC-fetch-violation precedent already uses (`cap_idx = 0b10001` = 17, the next sentinel value after PCC's own 16, genuinely outside the real 0-15 `vcapidx` range), calling `veda_pcc_save_and_reset()` first, matching `veda_trap()`'s own established discipline.

Deliberately reuses one cause code for both trigger conditions rather than inventing a third — mirrors the fetch-time precedent's own "one cause regardless of *why* PCC was narrowed" pattern, and `xtval` has no spare room for a distinction with no current behavioral consequence.

## A real, honest consequence found via actual testing, not assumed — and fixed the architecturally correct way, not by weakening the enforcement

The first full regression run produced four failures, all "trap loop detected," not simple mismatches: `vc_purecap_load_after_cgetbase_neg`, `vc_purecap_store_neg`, `vc_purecap_veda_ops_unaffected` (all three new), and — a real regression — the pre-existing `vc_ocinvoke.S`. Root cause, found by running the sim directly rather than guessing from the batch summary: `RVMODEL_HALT_PASS`/`RVMODEL_HALT_FAIL` (`veda_selfcheck_macros.S`) signal completion via an ordinary `sw` to the `tohost` MMIO region — and the CPU has no way to distinguish that store from any other ordinary store. So the same enforcement correctly blocked the test harness's own signaling mechanism whenever it ran while `veda_purecap` was still set, or from inside a still-live compartment.

This is the architecturally correct behavior, not a bug in the enforcement — a real compartmentalized program in a real system genuinely cannot write to an arbitrary MMIO device without an explicit capability for it either. Fixed accordingly, matching this project's own established precedent for this exact class of situation (Milestone 13's "switching to Bind-NoTrap, the architecturally correct choice, not a workaround"; Milestone 14's own fixture-widening):

- The three new negative/mixed tests now explicitly clear `veda_purecap` (`csrw 0x7c5, x0`) before calling the HALT macros, once the actual condition under test has already been observed.
- `vc_ocinvoke.S` (pre-existing, Milestone 10) never previously exited its compartment before halting — unlike `vc_pcc_bounds.S`, which already does a return-`OCInvoke` into an unbounded capability first. Fixed by adding the identical real return-`OCInvoke` sequence (`Object_ID`=33/34, mirroring `vc_pcc_bounds.S`'s own 53/54 pattern) before `RVMODEL_HALT_PASS`, widening PCC back to unbounded so the macro's own store succeeds. This was a real, previously-invisible gap in that test's own fixture, only exposed because this milestone is the first to make ordinary data access inside a compartment actually load-bearing.

## Test plan and result

Seven new `sail_tests/vc_purecap_*.S` tests, all real, self-checking positive/negative pairs:

- `vc_purecap_load_after_cgetbase_neg.S` — the literal reproduction of the vulnerability: bind Object_ID=1 (pre-seeded, Load+Store+NMC perms), `cgetbase` its raw Base, set `veda_purecap`, attempt an ordinary `ld` through the raw address — hard-traps with `mcause=0x18`, `mtval=0x227` ((17<<5)|7).
- `vc_purecap_load_after_cgetbase.S` — same setup, purecap OFF — the `ld` succeeds and reads back the exact value a real, capability-checked `OCS.D` wrote moments earlier, proving both "no regression" and "genuinely the same memory."
- `vc_purecap_store_neg.S` — mirror using `sd`/`STORE`, a separate union clause in `base_insts.sail`, independently confirmed.
- `vc_purecap_ocinvoke_compartment_load_neg.S` — inside a real `OCInvoke`-entered compartment (Object_ID=30/31/32, the same fixture as `vc_ocinvoke.S`), without ever setting `veda_purecap`, an ordinary `ld` still hard-traps — proves the compartment-bounding trigger independently of the global-mode trigger, and the `mtval=0x227` check (not `0x201`, the PCC-fetch cause) confirms the right one of the two conditions fired.
- `vc_purecap_veda_ops_unaffected.S` — the critical regression guard: under `veda_purecap` set, a real `OCS.D`-then-`OCL.D` round trip against a validly bound capability succeeds normally, proving with a real test (not just the architectural argument) that Veda's own accesses are untouched by this hook.
- `vc_purecap_csr_privgate.S` — confirms `0x7C5` is read/write-able from Machine mode. A true non-M-mode negative case can't be exercised in this project's own Sail test config (S/U-mode both `"supported": false`) — the same real, already-documented scope limitation Milestone 11 hit for `OSpecialRW`'s own privilege gate, stated honestly here too rather than silently skipped.
- `vc_purecap_reset_default_off.S` — immediately after reset, with no explicit CSR write, an ordinary `sd`-then-`ld` round trip succeeds and `veda_mode` reads back 0 — the test most likely to catch an `ext_reset()` omission, guarding the entire pre-existing corpus.

`run_veda_selfcheck_tests.sh` — **37/37 passed** (30 pre-existing, one fixture fix in `vc_ocinvoke.S` explained above + 7 new), zero regressions after the fix.

## Not yet built

**RTL mirror** — deliberately not attempted this pass, matching this project's own established Sail-first sequencing. RTL's own version will need a genuinely new kind of check for the load/store datapath (an unconditional-every-cycle data-address gate, analogous to but distinct from Milestone 14's own fetch-time `$instr`-forcing-to-NOP mechanism), new CSR decode for `0x7C5`, and reuse of the existing `pcc_length` signal for the compartment trigger — scoped as an explicit `rtl/MILESTONE_19_RESULTS.md` follow-up.

**Also out of scope, named honestly, not silently dropped**: Veda's own `OCL`/`OCS`/`NMC_ADD`/Veda-Atomic bypassing PMP and address-translation (found during the audit above, not live today since PMP has zero entries and no virtual-memory scheme is enabled in the real test config); a per-access-type purecap mode (the new hook's `access`/`width` parameters are currently unused — this milestone blocks all ordinary access uniformly, not selectively by read/write); compressed-instruction (`Zca`/`Zcf`/`Zcd`/`Zcb`) re-verification — these are believed to legalize down to the same `LOAD`/`STORE` union clauses and so inherit the fix automatically, but this was not independently re-verified this pass since all four are disabled in the real test config.
