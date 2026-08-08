# Toolchain Milestone 14: CRF-Exhaustion Fix — Globals Table-Base Capability Survives the Scheduler

## Problem, restated from `TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md`

Milestone 13 permanently binds CRF register `c11` to a "table-base" capability (the base of an
in-memory table of per-global-variable capabilities, minted once at bootstrap). Separately,
`runtime/veda_sched_asm.S`'s cooperative scheduler *also* used `c11` — transiently, rebound fresh to
each thread's own CODE capability on every resume. Any program needing both mechanisms together had its
persistent table-base capability silently clobbered the instant the scheduler resumed a thread. The
decision doc chose the fix (spill/restore `c11` across every thread switch via `OCS.C`/`OCL.C`) but left
it unimplemented, explicitly requiring a fresh register audit and a real combined test before building.

## What changed from the decision doc's own plan — two real corrections, found empirically

**1. Register choice: `c12`, not `c10`.** The decision doc's own open question ("which register survives
the switch") was resolved during implementation by first trying the obvious answer — reroute the
switcher's transient resume-jump machinery (`veda.bind` fresh CODE → `oca` → `csealentry` → `ocreturn`)
off `c11` onto `c10`, freeing `c11` for pure persistence. A Plan-agent review (requested specifically to
avoid rushing this) found `c10` is *also* used as `runtime/veda_rt_asm.S`'s own Milestone-13 per-global-
access scratch register — exactly the code path a real combined program would call from inside a thread
body. On direct re-analysis this specific collision turned out to be temporally safe (the switcher's own
use of `c10` and a thread body's own use of `c10` never overlap in real execution order — matching the
same "transient, non-overlapping reuse" convention this whole project already relies on for `c10`
elsewhere), but chasing it surfaced a cleaner option that avoids the question entirely: `c12` is *already*
a pure `OSpecialRW` discard-sink in this exact file (`ospecialrw c12(discard), tsc, c6/c7`) — its written
value is never read by anything, anywhere in the corpus, the strongest "genuinely free" property available.
Reusing `c12` for the resume-jump role, immediately after its own discard-write, needed zero new claims
and creates zero cross-file collision, since `c12` was never used by Milestone 13's helpers at all. `c11`
is now *exclusively* the persistent table-base register, matching the same "permanent, never repurposed"
pattern `c6`/`c7`/`c8`/`c9` already have.

**2. A real, independently-found bug: the FIRST-EVER resume needs pre-population, not just steady-state
resumes.** `save_area_0`/`save_area_1` are zero-initialized and only written by `yielding_is_0`/
`yielding_is_1` — which only run *after* a real yield. The very first call into `resume_0`/`resume_1`
(from `veda_sched_run_asm`, before any yield has ever happened) would `OCL.C`-read the new capability
slot from memory that was never `OCS.C`-written — an untagged, all-zero region — corrupting `c11` with
garbage on the thread's very first entry. The existing PC/base/length fields avoid this exact trap by
being explicitly pre-populated in `veda_sched_init_asm` before the scheduler ever runs; the new capability
slot needed the identical treatment. Fixed by having `veda_sched_init_asm` `OCS.C` the just-bound `c11`
into both save-areas' new slot, right after `c11` is bound and before `veda_sched_run_asm` is ever called.

## A third, unplanned real finding: Sail cannot round-trip a capability's tag through `.tcm_scratch`

Milestone 24's own `save_area_0`/`save_area_1` placement (in `.tcm_scratch`, `TCM_SCRATCH_BASE=0xA0000000`)
was carried forward unchanged into this milestone's first implementation attempt — the new capability slot
was placed at offset 32 within that same region, 16-byte-aligned, matching `veda_core.tlv`'s own
`(addr-BASE)>>4` tag-granule convention. The combined test built to verify this (below) hung indefinitely
on its very first thread entry. Tracing (`sail_riscv_sim --trace-instr --trace-exception`) showed a real
`VEDA_CAUSE_TAG_VIOLATION` (`mtval` decoding to `cap_idx=11, cause=0x02`) firing the instant the restored
`c11` was first used — and the switcher's own known, already-documented limitation ("real fault recovery
out of scope this pass") turns an unexpected trap into an infinite `switcher_entry` spin rather than a
clean failure, which is what produced the hang.

Isolated with a minimal, scheduler-free reproduction (`sail_tests/vc_ocsc_bind_spill_restore_roundtrip.S`):
a plain `veda.bind` → `OCS.C` → `OCL.C` → use round-trip **passes** when the spill target is ordinary
`.data`, and **fails with the identical `VEDA_CAUSE_TAG_VIOLATION` signature** when the exact same
instructions target `.tcm_scratch` (0xA0000000) instead — confirmed by rebuilding the same source against
`veda_rt.ld` (which maps `.tcm_scratch`) versus `veda_selfcheck.ld` (which does not).

Root cause: the Sail model has zero TCM concept by design — the DRAM-latency/TCM stall model is 100%
RTL-only (`rtl/TCM_FAST_PATH_DESIGN.md`'s own explicit scoping), so its tag-storage mechanism was never
built to cover that address range, even though `0xA0000000` falls inside the declared RAM memory region
for *ordinary* load/store (`sail_tests/veda_test_sail.json`'s RAM region: `base=0x80000000,
size=0x80000000`, i.e. `0x80000000..0xFFFFFFFF`+ — `.tcm_scratch` is physically inside it, but Sail's tag
tracking still doesn't cover it). `runtime/veda_sched_asm.S` has no RTL mirror of any kind — the RTL
scheduler test (`rtl/sim/veda_smoke_m23_scheduler.S`) is a wholly separate file/context — so `.tcm_scratch`
placement here provides no real benefit for a file that only ever executes under Sail, and actively broke
the new capability slot. **Fix: moved the whole `save_area_0`/`save_area_1` struct back to ordinary
`.data`** (not just the new slot, so both old and new fields stay reachable through the same `c6`/`c7`
capability — splitting them would have required a third Object_ID/CRF-register claim, reopening the exact
exhaustion problem this milestone exists to close).

## Scope of the fix (final, as built)

Purely a software/convention change, `runtime/veda_sched_asm.S` only — no Sail file, no RTL file, no new
instruction:

- `save_area_0`/`save_area_1`: `.tcm_scratch` → `.data`; `.align 3` → `.align 4` (16-byte, matching the
  capability tag-storage granule); grown from 24 to 48 bytes (3 original `.dword`s unchanged at offsets
  0/8/16, 8 bytes of padding at 24-31, the new 16-byte capability slot at 32-47).
- `veda_sched_init_asm`: `Length` for Object_ID 165/166 grows `0x0020`→`0x0030`; new `OCS.C` pair
  pre-populates both save-areas' new slot with the caller's already-bound `c11`.
- `yielding_is_0`/`yielding_is_1`: one new `OCS.C` each, spilling `c11` alongside the existing PC/base/
  length spill.
- `resume_0`/`resume_1`: one new `OCL.C` each, restoring `c11` alongside the existing PC/base/length
  restore.
- `resume_0`/`resume_1`/`do_resume`: the fresh-CODE-bind/`oca`/`csealentry`/`ocreturn` resume-jump
  sequence renamed `c11`→`c12` throughout (5 instruction lines).

## Verification

**New test** (`compiler/veda_sched_global_combo_entry.S` + `veda_sched_global_combo_threads.S` +
`veda_sched_global_combo_demo.c` + `run_veda_sched_global_combo_test.sh`), Object_IDs 431/432
(grep-audited fresh, collision-free past Milestone 13's own 430): a minimal, hand-written bootstrap mints
one table-base capability (`c11`, Object_ID 432) bounding a one-entry table, itself pointing at a small
shared data region (Object_ID 431); both threads inline raw `oca`/`csetbounds`/`ocl.c`/`ocs.c` (the M13
`ret`-based helpers are `OCInvoke`-only and cannot run inside the scheduler's `OCReturn`-sentry thread
bodies — confirmed via `runtime/veda_sched.h`'s own documented constraint, independently re-verified by
the Plan agent). Each thread writes a known constant to its own private offset, yields, and on its SECOND
resume re-reads the SAME table entry through the restored `c11`, stashing the result for `main()` to
check after `veda_scheduler_start()` returns.

```
SUCCESS
*** TEST PASSED *** (globals table-base capability c11 survived a real scheduler yield/resume
round-trip -- both threads' second table access, through the restored c11, returned the exact
constant each wrote on its first access)
```

Both threads' checkable values (`0xAAAA`, `0xBBBB`) matched exactly what each wrote on its own first
access — and this positive run directly exercises the thread's very first resume (the pre-population
fix's own target), since neither thread had yielded before its first table access.

**Isolated regression test** (`sail_tests/vc_ocsc_bind_spill_restore_roundtrip.S`, added to the permanent
self-check corpus): a plain bind→spill→restore→use round-trip through ordinary memory, independent of the
scheduler — passes, and documents the real `.tcm_scratch` finding above for any future engineer who hits
the same trap.

**Mutation test**: temporarily reverted the `c12` rename back to `c11` (reproducing the exact original
bug this milestone fixes — the resume-jump machinery clobbering the persistent table-base register again)
and reran the combined test. Result: the program hangs (rather than reporting a clean failure) — a real,
different outcome from the fixed version's clean `PASS`, confirming the check is not vacuous. The hang
itself is expected and consistent with the switcher's own pre-existing, already-documented limitation
("real fault recovery out of scope this pass" — an unexpected trap, here a capability-permission
violation on the CODE-only `c11`, spins `switcher_entry` forever rather than failing cleanly) — not a new
bug introduced by this milestone. Reverted immediately after confirming; the shipped code is the fixed
version.

**Full regression, zero regressions in every suite this milestone did not intend to change**:
- `sail_tests/run_veda_selfcheck_tests.sh`: **59/59** (58 pre-existing + 1 new — the isolated round-trip
  test above).
- `rtl/run_veda_smoke_test.sh`: **49/49**, unchanged — zero RTL files touched.
- `rtl/run_act4_tests.sh`: **51/51**, unchanged.
- `runtime/run_veda_rt_tests.sh`: **2/2**.
- `compiler/run_veda_demo_tests.sh`: **2/2**.
- `compiler/run_veda_sched_demo_test.sh`, `run_veda_global_protect_test.sh` (its `mtval=0x141` trace
  assertion through `c10` — a direct tripwire for any accidental `c10` disturbance — stayed
  byte-identical, confirming this fix never touches `c10`), `run_veda_alloca_protect_test.sh`,
  `run_veda_compartment_test.sh`, `run_veda_compartment_nested_test.sh`: all still pass.

## Not yet built / genuinely out of scope

- No RTL mirror — `runtime/veda_sched_asm.S` and this whole toolchain layer are Sail-only by established
  convention, matching every prior Toolchain Milestone (M1-M13).
- Only 2 threads, matching the scheduler's own existing, explicitly-stated scope (`veda_sched.h`).
- `TOOLCHAIN_MILESTONE_13_CRF_EXHAUSTION_DECISION.md`'s own remaining honest gaps (extern globals,
  non-attributed-function accesses, subobject bounds) are untouched by this milestone — it closes only
  the specific register-exhaustion wall that document named.
