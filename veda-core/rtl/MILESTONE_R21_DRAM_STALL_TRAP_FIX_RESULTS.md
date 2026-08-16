# R21 fix: the Milestone 24 DRAM-stall must not swallow a real trap redirect

**Date:** 2026-08-16

## The gap, and where it came from

R21 was found on the Linux line (`veda-core-sindhu`, a separate throughput/multi-hart initiative
sharing this repo's own Milestone 24 lineage via a full-history clone) while adversarially
refuting an unrelated timing-side-channel claim. Milestone 24's own DRAM-latency stall FSM
(`$veda_dram_stall_req`, `rtl/veda_core.tlv`) gated its stall request on `!$veda_pcc_violation` --
a **fetch-side** check only. It never referenced the **data-side** violations `$veda_oclc_violation`,
`$veda_ocsc_violation`, or plain Bind's own `$veda_bind_trap`. Since `$veda_dram_stall_req` drives
`$veda_dram_busy`, and the `$pc` mux ranks `>>1$veda_dram_busy` **above** `>>1$pc_src` (the trap
redirect to `mtvec`), a DRAM-tier access that both violates and misses its TCM tier could discard
the trap redirect while every trap **state** effect (PCC reset to unbounded, etc.) still fired --
a real compartment escape, not merely a missed-handler bug.

Because Milestone 24 was built *on this line* (`rva23-core`) before the Linux line's fork existed,
the bug's origin is here. The Linux line's own fix (its own `FIX 1`) closed it there; this document
is that same fix, independently re-derived and verified for this line's own real signal set (this
core has no domain/region/residency concepts, so the fix shape differs -- see below), not copied.

## The fix

`rtl/veda_core.tlv`'s `$veda_dram_stall_req`:

```
$veda_dram_stall_req =
   !$veda_pcc_violation && !(>>1$veda_dram_busy) &&
   ((($is_veda_bind_plain || $is_veda_bind_notrap || $is_veda_rebind) && !$veda_odt_tcm_hit && !$veda_bind_trap) ||
    (($is_veda_ocl_c || $is_veda_ocs_c) && !$veda_capmem_tcm_hit && !$veda_oclc_violation && !$veda_ocsc_violation));
```

Two new conjuncts, one per arm:

- **Bind arm:** `&& !$veda_bind_trap`. Safe for all three bind modes -- `$veda_bind_trap` is defined
  purely in terms of `$is_veda_bind_plain` (`veda_core.tlv:1252`/`:1267`/`:1268`), so it reads a
  structural constant 0 whenever `$is_veda_bind_notrap` or `$is_veda_rebind` is the decoded
  instruction, changing nothing for those two (neither ever traps in this core -- only plain Bind
  does, Milestone 13).
- **Capability-width arm:** `&& !$veda_oclc_violation && !$veda_ocsc_violation`. Mutually exclusive
  by construction (`$is_veda_ocl_c`/`$is_veda_ocs_c` can't both be the decoded instruction), so this
  correctly captures "this specific OCL.C or OCS.C instruction did not violate."

**Strictly monotone**, matching the same reasoning the Linux-line fix used: this can only ever
*remove* a stall, on a path that traps anyway via `$veda_trap_taken`'s own existing OR-list
(`veda_core.tlv:986-988`, unchanged). It cannot create a stall that did not exist, so it cannot open
a new escape.

**Deliberately not attempted in this pass, for the identical reason the Linux line gave for its own
`FIX 2`:** the swallowed-branches/JAL/JALR/OCInvoke/OCReturn/mret correctness issue, which needs
restructuring the `$pc` mux itself -- the single most safety-critical expression in the core. That
is not monotone the way this fix is, and needs its own test. Named here as a real, separate,
still-open item, not silently folded in.

## Real verification, both directions

**At the shipped `DRAM_EXTRA_CYCLES=0` default**, the stall path is structurally unreachable (the
`(DRAM_EXTRA_CYCLES != 0)` guard Milestone 24 itself already added), so this fix cannot be exercised
by the committed regression suite alone -- exactly why every other Milestone 24 test's own
"busy stays 0" convention exists. New permanent regression member,
`rtl/sim/veda_smoke_r21_dram_stall_trap_neg.S`: Object_ID=1 (a reset-seeded DRAM-tier object, Base
in `elfmem[]`, nowhere near `TCM_SCRATCH_BASE`), an `OCL.C` at offset 1000 (far past Length=0x40 --
a real bounds violation), with a sentinel GPR (`x20`) checked before/after. At E=0 this test's job
is to confirm the violation still traps correctly (**PASSED**, `x20=0x600D`, never `0xE5CA`) -- proof
of zero regression from this fix at the default configuration, not proof of the fix itself.

**The real escape-vs-fix proof, both directions, at a temporarily nonzero `DRAM_EXTRA_CYCLES`**
(matching this project's own established "temporary build, not committed" precedent for exploring
nonzero-E behavior -- `DRAM_EXTRA_CYCLES` is a `localparam`, not externally overridable): two scratch
copies of `veda_core.tlv`, both with `DRAM_EXTRA_CYCLES=10`, one with the fix applied and one with
the original vulnerable condition restored, both run against the identical
`veda_smoke_r21_dram_stall_trap_neg` test:

| Variant (DRAM_EXTRA_CYCLES=10) | `x20` result |
|---|---|
| Vulnerable (pre-fix condition) | `0xE5CA` -- **the escape happened**: execution fell through past the trapping `OCL.C` instead of trapping |
| Fixed (this change) | `0x600D` -- correctly trapped, no escape |

This is a real, reproducible, both-directions demonstration: the bug is genuinely live under a
nonzero-latency configuration, and this fix genuinely closes it, not merely a plausible-looking
guard that was never actually exercised failing.

**Full regression, at the shipped E=0 default (`run_veda_smoke_test.sh`): 54/54 passed, 0 failed**
(53 pre-existing + this new test). **ACT4 RV64I conformance (`run_act4_tests.sh`): 51/51 passed, 0
failed, 0 timed out.** Zero regressions from this fix.

## What remains genuinely open

- **FIX 2-equivalent** (swallowed ordinary branches/jumps/`mret` during a stall) -- named above,
  not attempted, needs its own `$pc`-mux-restructuring design pass and its own test.
- **Widening the regression suite's own cycle budgets to enable a nonzero `DRAM_EXTRA_CYCLES` in the
  committed default** is blocked on FIX 2 landing first, exactly as the Linux line already noted for
  its own fork of the identical constraint.
- **A grep-audit for the same pattern class elsewhere in `veda_core.tlv`** ("does any other
  stall/busy/freeze signal outrank a trap redirect in the `$pc` mux") was not performed in this
  pass -- named explicitly as a real, separate next step for the broader real-time/safety-critical
  audit this fix was the first, most urgent item of, not assumed clean by extension.

## Files

- `rtl/veda_core.tlv` -- the two-conjunct fix to `$veda_dram_stall_req`.
- New: `rtl/sim/veda_smoke_r21_dram_stall_trap_neg.S` + `tb_veda_smoke_r21_dram_stall_trap_neg.sv`.
- `rtl/run_veda_smoke_test.sh` -- registers the new test.
- Scratch-only, not committed: two temporary `DRAM_EXTRA_CYCLES=10` copies of `veda_core.tlv` (one
  fix-reverted, one fixed) used solely for the escape-vs-fix table above.
