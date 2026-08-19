# VEDA_LOCAL_HANDLER: hardware-enforced compartment-local fault recovery (Sail)

**Date:** 2026-08-19
**Scope:** closes §3.5 of `NEXT_STEPS_ROADMAP.md` -- a real architectural gap found this session by a
full re-read of the CHERIoT RTOS paper (Amar et al., ACM SOSP '25) and the base CHERI ISA spec
(UCAM-CL-TR-987, Version 10-DRAFT): Veda-Core had no equivalent of CHERIoT's compartment-scoped
`compartment_error_handler()` (paper's own design principle P2). Every real Veda-Core trap reset PCC
to fully unbounded and ran the single global `mtvec` handler with ambient authority -- confirmed base
CHERI's own default (§2.4.6/§3.11.2 both explicitly expect elevated-rights exception handlers), but
strictly weaker than CHERIoT's own accepted-residual-risk bound (a buggy handler's blast radius scoped
to one compartment's own rights, per the paper's §5.1.2). Full research grounding and the design
decision (hardware-native scoping guarantee, not a copy of CHERIoT's software-switcher convention) are
in `LOCAL_FAULT_RECOVERY_DESIGN.md`; this doc records verification.

## Mechanism (summary; full design in `LOCAL_FAULT_RECOVERY_DESIGN.md`)

Reuses three pieces of infrastructure already built and verified this session under
`VEDA_TRAP_QUARANTINE`/Milestone 21-restore, unmodified: `veda_pcc_otype` (faulting-compartment
identity), `veda_mepcc_base`/`veda_mepcc_length` (pre-trap bounds, already captured on every real
trap), `veda_trap_tracker_is_quarantined()` (the authoritative repeated-fault signal). New 8-entry,
otype-keyed `veda_local_handler_table` (deliberately separate from `veda_trap_tracker` -- quarantine
entries decay/evict opportunistically, a registered handler must be stable). New self-registration-only
instruction `VEDA_SET_LOCAL_HANDLER rs1` (assembly `osethandler`, encoding `funct7=0x17` within the
`opcode=0x5b`/`funct3=0b001` custom-2 family, the next free slot after `OCRETURN`'s `0x16`) -- hard-traps
unless called from a live bounded compartment, and unless the target address lies within that SAME
compartment's own current bounds (the confused-deputy guard: no operand names a target otype, so
nothing lets one compartment register a handler for a different one). Trap-time redirect lives in
`veda_pcc_save_and_reset()`: if the faulting compartment is not quarantined and has a registered
handler, PCC is restored to the SAME (never widened) bounds and PC redirects to the handler instead of
the ordinary global `mtvec` fallback -- composing with, not bypassing, `VEDA_TRAP_QUARANTINE` (every
redirect still runs through the unconditional `record_fault` call above it, so a handler that keeps
faulting quarantines itself within the same 3-fault budget as any other compartment).

**Real architectural constraint found while implementing, not assumed away**: `veda_pcc_save_and_reset()`
cannot itself redirect the PC -- the real jump target is computed in the base (non-Veda)
`exceptions/sys_exceptions.sail`'s `prepare_trap_vector()`. Resolved with a small hand-off
(`veda_local_handler_redirect_pending`/`_target` registers, read-and-cleared by a new
`veda_trap_vector_override()` wrapping `prepare_trap_vector`'s own result) plus a forward `val`
declaration in the base file -- the same established cross-file pattern `M27-mtvec-gate` already used
for touching this exact file.

## Verification

**Positive** (`sail_tests/vc_local_handler_pos.S`): registers `handler_entry` (within the compartment's
own bounds) via `osethandler`, then drives a real deliberate out-of-bounds fetch. Confirms via CSR
readback (`veda_pcc_base`/`veda_pcc_length`, 0x7c0/0x7c1) that the redirect lands with PCC narrowed to
*exactly* the pre-fault bounds -- not unbounded, not any other region -- and that the test's own
`mtvec`-pointed `trap_handler` is never touched at all (traced: fetch fault redirects directly to
`handler_entry+0`). Handler exits cleanly via a pre-minted sentry `OCReturn`; `return_landing`
re-confirms PCC widened back to unbounded and the expected sentinels. `SUCCESS`.

**Negative 1 -- no handler registered** (`sail_tests/vc_local_handler_neg_no_handler.S`): a compartment
that never calls `osethandler` faults; confirms completely unchanged pre-existing global-fallback
behavior (`cause=0x01`/`cap_idx=16`, PCC reset to unbounded/`base=0`) -- zero regression from this
session's new mechanism. `SUCCESS` on first try.

**Negative 2 -- quarantine composition** (`sail_tests/vc_local_handler_neg_quarantine.S`): a handler
that unconditionally re-faults every time it runs. Confirms exactly **2** successful redirects, then
the 3rd real fault falls straight through to the ordinary global `mtvec` path with genuinely unbounded
PCC. **This corrects the design doc's own original, less precise expectation** ("3 redirects then a
4th fallback") -- empirically traced, not assumed: `veda_pcc_save_and_reset()` increments the
trap-tracker count *first*, then checks quarantine, so the SAME trap that brings the count to the
threshold (3) is itself refused a redirect (count 0->1 and 1->2 both check "not yet quarantined" and
redirect; count 2->3 checks "quarantined" and falls through). `SUCCESS` after a real bug fix (below).

**Negative 3 -- confused-deputy guard** (`sail_tests/vc_local_handler_neg_bounds_guard.S`): attempts to
register a genuinely, independently valid (freshly-bound, correctly-tagged, `Permit_Execute` set)
capability whose address lies far outside the compartment's own current bounds. Confirms hard-trap
(`VEDA_CAUSE_BOUNDS_VIOLATION`, `cause=0x01`, `cap_idx` matching the named operand) and that the
rejection is genuine -- a subsequent, ordinary out-of-bounds fault from the SAME re-invoked compartment
(deliberately never calling `osethandler` again) falls straight through to the plain global path,
proving nothing was actually written to the table by the rejected attempt. `SUCCESS` after two real
test-design corrections (below).

## Real bugs found via testing, not inspection

**1. Double-call of `veda_pcc_save_and_reset()` (Negative 2).** `handler_entry` was observed running
only once, not twice as expected. Root cause: the redirect branch deliberately leaves `veda_pcc_length`
narrowed (not `VEDA_PCC_UNBOUNDED`) so the handler runs with the faulting compartment's own bounds --
but `handle_trap_extension`'s own pre-existing guard (`if veda_pcc_length != VEDA_PCC_UNBOUNDED then
veda_pcc_save_and_reset()`) implicitly assumed that condition meant "not yet processed this trap," an
invariant that only held because the function previously *always* reset PCC to unbounded. Since
`handle_trap_extension` runs unconditionally inside `trap_handler()` after the direct call sites
(`ext_handle_fetch_check_error` etc.), it was calling `veda_pcc_save_and_reset()` a second time for the
same logical fault, double-incrementing the trap-tracker count and consuming the quarantine budget
twice as fast as intended. Fixed with `& not(veda_local_handler_redirect_pending)` added to the guard
in `postlude/step_ext.sail`. Traced before/after: exactly 2 `handler_entry+0` entries then exactly 1
`trap_handler+0` entry (previously 1 and 1).

**2. Test-design flaw, not a mechanism bug (Negative 3, first attempt).** The first version of the
bounds-guard test derived its "outside" pointer via `OCA` from the compartment's own `c0` with an
offset exceeding `c0`'s own `Length` -- this tripped `OCA`'s own, unrelated, pre-existing
out-of-range tag-clearing (`wCTag(rdno, CTag(capidx) & not(out_of_range) & ...)`) *before*
`VEDA_SET_LOCAL_HANDLER`'s own new bounds check was ever reached, producing `VEDA_CAUSE_TAG_VIOLATION`
(`cause=0x02`) instead of the intended `VEDA_CAUSE_BOUNDS_VIOLATION` (`cause=0x01`) -- confirmed via
`--trace-exception` (`mtval=0x142`, decoding to `cap_idx=10`/`cause=0x02`). Fixed by binding a
*separate*, freshly-tagged capability directly at the out-of-bounds address (Object_ID 643,
`Permit_Execute` set) before `OCInvoke`, so it survives into the compartment unchanged and the test
isolates `VEDA_SET_LOCAL_HANDLER`'s own check from `OCA`'s.

**3. Test-flow bug (Negative 3, second attempt).** `comp_entry` unconditionally retried `osethandler`
on the phase-2 re-invocation, so phase 2 hit the identical confused-deputy trap instead of the intended
"prove nothing was registered" check. Fixed by branching `comp_entry` on the phase flag: phase 1
attempts the rejected registration; phase 2 (never touching `osethandler` again) drives an ordinary
out-of-bounds fetch and confirms it falls through to the plain global path (`cause=0x01`/`cap_idx=16`),
proving the rejected phase-1 attempt left nothing behind.

## Mutation tests

**Mutation (a) -- drop the quarantine gate on the redirect** (`if veda_local_handler_registered(...)
then` instead of `if not(is_quarantined(...)) & veda_local_handler_registered(...) then`): rebuilt.
`vc_local_handler_neg_quarantine.S` correctly flipped to `FAILURE` -- with the composition guard gone,
the self-faulting handler redirects into itself forever; the *simulator's own independent* trap-loop
detector caught the resulting infinite loop (`FAILURE: possible trap loop detected`) rather than the
test's own 2-redirects-then-fallback check ever completing. Confirms the quarantine gate is the only
thing standing between this mechanism and a self-inflicted, unbounded-redirect DoS vector -- exactly
the risk the design doc named and closed at design time. Reverted, rebuilt, re-confirmed clean.

**Mutation (b) -- drop the `veda_pcc_otype`-preservation fix** (add back `veda_pcc_otype =
UNSEALED_OTYPE` on the redirect path): rebuilt. `vc_local_handler_neg_quarantine.S` correctly flipped
to `FAILURE`, and the *mechanism* of failure was traced and matches the predicted misattribution
exactly, not just a matching overall verdict: the first fault is correctly recorded against the real
otype and redirects; but because `veda_pcc_otype` now resets to `UNSEALED_OTYPE` while the handler
runs, the handler's own second fault is recorded against `UNSEALED_OTYPE` instead -- an identity that
was never registered via `osethandler` -- so `veda_local_handler_registered(UNSEALED_OTYPE)` is false
and the redirect condition fails on only the *second* fault. Traced: `handler_entry` runs exactly once
(not twice), then falls straight through to `trap_handler` with the ordinary global cause, and
`fail_wrong_redirect_count` fires (`x24=1`, expected `2`). Reverted, rebuilt, re-confirmed clean.

## Full regression

**Sail self-check** (`run_veda_selfcheck_tests.sh`): **78/78 passed** (74 prior + 4 new:
`vc_local_handler_pos`, `vc_local_handler_neg_no_handler`, `vc_local_handler_neg_quarantine`,
`vc_local_handler_neg_bounds_guard`), zero regressions, re-confirmed after both mutation reverts.

**Toolchain regression** (all layers, against the final rebuilt `sail_riscv_sim`, confirming this
Sail-only change has zero effect on the compiler/runtime stack, none of which calls `osethandler`):
- `run_veda_shadow_prop_tests.sh`: **8/8 passed**
- `run_veda_demo_tests.sh`: **9/9 passed**
- `run_veda_rt_tests.sh`: **2/2 passed**
- `run_veda_compartment_test.sh`, `run_veda_compartment_nested_test.sh`,
  `run_veda_syscall0_hello_world_test.sh`, `run_veda_syscall0_forged_oid_test.sh`,
  `run_veda_alloca_protect_test.sh`, `run_veda_sched_global_combo_test.sh`,
  `run_veda_global_protect_test.sh`, `run_veda_sched_demo_test.sh`: **all PASS**

## Adversarial review finding and fix (found after the RTL mirror, before this milestone was considered closed)

An RTL-mirror workflow ran two independent adversarial reviews of the finished RTL diff (one focused on
general correctness, one specifically on security -- different lenses, per this project's own "diverse
lens beats redundant review" discipline). **Both, independently, found the identical real, critical
gap** -- confirmed by me directly against the primary Sail source before accepting it, per this
project's own "refute findings before recording them" discipline (not merely trusting either review's
self-report):

**Cross-compartment handler-table collision via the shared `UNSEALED_OTYPE` sentinel.** The original
`VEDA_SET_LOCAL_HANDLER` "live compartment" check tested only `veda_pcc_length != VEDA_PCC_UNBOUNDED`
-- PCC boundedness -- never `veda_pcc_otype` identity. But PCC can be genuinely bounded while
`veda_pcc_otype` still holds the shared `UNSEALED_OTYPE` (`0xFFFF`) sentinel: confirmed directly by
reading `veda_cap_insts.sail:718` (`VEDA_OCRETURN` explicitly sets `veda_pcc_otype = UNSEALED_OTYPE`
on every successful return, since a return target has no per-destination identity) and by reading
`veda_pcc_otype`'s own register-mux -- there is no `is_mret` arm anywhere (confirmed identically in
RTL: grepped every `is_mret` occurrence in `veda_core.tlv`, none touches `$veda_pcc_otype`). So after
*any* ordinary trap+`mret` round trip that never re-enters via `OCInvoke`, or after *any* successful
`OCReturn`, a compartment resumes with its real bounds restored but its identity still the shared
sentinel. Before the fix, `osethandler` succeeded in this window and wrote a handler-table entry keyed
under `0xFFFF` -- not a genuine per-compartment identity. A completely unrelated compartment resumed
into that same ordinary window would collide on the same key on its own next fault and get redirected
into a *different* compartment's chosen handler address, defeating the mechanism's entire purpose
(bounded, per-compartment blast radius). **Not hypothetical**: this project's own shipped
`runtime/veda_sched_asm.S` cooperative-scheduler threads are entered exclusively via `OCReturn`, so both
threads run under the shared `UNSEALED_OTYPE` identity for their entire execution -- a real,
already-existing collision surface, reachable by ordinary program flow, no attacker-crafted sequence
required. None of the four original tests exercised this path (all four mint fresh, distinct real
otypes via `CSeal`/`OCInvoke`).

**Fix** (both layers, same shape): exclude `UNSEALED_OTYPE` as an eligible registration key.
`VEDA_SET_LOCAL_HANDLER` now hard-traps with `VEDA_CAUSE_NO_LIVE_COMPARTMENT` when
`veda_pcc_otype == UNSEALED_OTYPE`, in addition to the existing PCC-unbounded check (semantically
honest: this state genuinely has no live compartment *identity* to register a handler against, even
though PCC itself is bounded). A second, defense-in-depth exclusion was added to the trap-time redirect
condition itself (`veda_pcc_otype != UNSEALED_OTYPE`), so a future change to the registration side alone
cannot silently reopen the hole at the redirect chokepoint.

**New test** (`sail_tests/vc_local_handler_neg_unsealed_otype.S`): reproduces the simplest real instance
directly -- `OCRETURN` through a sentry into a *bounded* region, called from the initial,
never-compartmentalized `_start` context (no `OCInvoke` anywhere in the file at all), then attempts
`osethandler` on a genuinely in-bounds capability. Confirms hard-trap
(`VEDA_CAUSE_NO_LIVE_COMPARTMENT`, cause=`0x0a`, `cap_idx` matching the operand) and the ordinary global
fallback (PCC reset to unbounded). `SUCCESS` on first attempt. Mutation-tested: disabling the new check
flips the test to `FAILURE` -- traced and confirmed `osethandler` genuinely succeeds under the mutation
(the `fail_unexpected_no_trap` path fires first), with a secondary, independent out-of-bounds fault (the
test's own `done` label lies outside the tiny 64-byte compartment) providing a second, corroborating
signal rather than a contradiction. Reverted cleanly; **full regression re-confirmed 79/79** (78 prior +
this new test).

## Files changed

`toolchain/sail-riscv` (Sail fork): `model/extensions/Veda/veda_types.sail` (+`local_handler_entry`
struct, +`LOCAL_HANDLER_TABLE_ENTRIES`), `model/extensions/Veda/veda_bind_insts.sail`
(+`VEDA_CAUSE_NO_LIVE_COMPARTMENT = 0x0a`, +`VEDA_CAUSE_HANDLER_TABLE_FULL = 0x0b`),
`model/extensions/Veda/veda_regs.sail` (+3 registers, +`veda_local_handler_registered`/
`_entry_of`/`_set` helpers, +`veda_trap_vector_override`, `veda_pcc_save_and_reset()` restructured
for the redirect branch -- redirect condition also gated on `veda_pcc_otype != UNSEALED_OTYPE`),
`model/extensions/Veda/veda_cap_insts.sail` (+`VEDA_SET_LOCAL_HANDLER` instruction, +`UNSEALED_OTYPE`
registration-side exclusion), `model/exceptions/sys_exceptions.sail` (+forward `val`,
`prepare_trap_vector()` wrapped), `model/postlude/step_ext.sail` (`ext_reset()` resets the new hand-off
registers, `handle_trap_extension`'s guard fixed for the double-call bug). `veda-core`:
`LOCAL_FAULT_RECOVERY_DESIGN.md` (design, pre-existing), this results doc, new
`sail_tests/vc_local_handler_pos.S`, `sail_tests/vc_local_handler_neg_no_handler.S`,
`sail_tests/vc_local_handler_neg_quarantine.S`, `sail_tests/vc_local_handler_neg_bounds_guard.S`,
`sail_tests/vc_local_handler_neg_unsealed_otype.S`. `veda-core/rtl/veda_core.tlv` (full mechanism
mirror, including the same `UNSEALED_OTYPE` fix on both the registration and redirect sides) -- see
`LOCAL_FAULT_RECOVERY_RTL_RESULTS.md` for the complete RTL-side verification record.

## Not yet built

**RTL mirror -- now built.** See `LOCAL_FAULT_RECOVERY_RTL_RESULTS.md` for the full RTL verification
record (implementation, two independent adversarial reviews, the `UNSEALED_OTYPE` fix applied
identically on both layers, mutation tests, and final regression counts).

**"Resume with modified registers"** -- named as an explicit, deferred scope limit in the design doc;
CHERIoT's own richer in-place-resume semantics (§3.2.6) is a real future extension, not required for
this pass's core guarantee (bounded-privilege recovery).

**Configurable table size / threshold sharing with quarantine** -- fixed 8-entry table, matching
`veda_trap_tracker`'s own established precedent; not made configurable this pass.

**Not committed or pushed yet**, matching this session's established pattern.
