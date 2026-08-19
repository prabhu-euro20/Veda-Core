# Toolchain Milestone 22: closing the Length/Offset widening's toolchain-layer parity gap

**Status: built, verified. All 6 suites found broken by the full regression sweep
(TOOLCHAIN_MILESTONE_21_STRUCT_COPY_RESULTS.md) are now green, zero regression
elsewhere.**

## Background

Earlier this session, the Length/Offset capability-register fields were widened
16->20 bits (RTL commit `9de3742`, Sail commit `5f145092`), growing the packed
capability register 128->136 bits and the real OCL.C/OCS.C on-the-wire access width
16->17 bytes, plus introducing a brand-new hard 32-byte physical-address alignment
gate on OCL.C/OCS.C that did not exist before. That work was deliberately scoped to
the RTL and Sail model only, per its own commit message and file list.

Running the FULL toolchain regression sweep (not just the suites believed relevant)
after closing §2.12 found 6 previously-passing suites now failing:
`run_veda_alloca_protect_test.sh`, `run_veda_global_protect_test.sh`,
`run_veda_compartment_test.sh`, `run_veda_compartment_nested_test.sh`,
`run_veda_sched_demo_test.sh`, `run_veda_sched_global_combo_test.sh`. All were
diagnosed via a parallel research/diagnose workflow (real `sail_riscv_sim` traces,
not assumption) before any fix was written, per this project's own standing
"verify before deciding" discipline.

## Root causes -- three distinct kinds of staleness, one shared class

The widening's own deliberate RTL+Sail-only scope left three different kinds of
hand-maintained, hand-duplicated toolchain-layer constants stale, each independently
confirmed via real trace evidence before being fixed:

### 1. Stale "PCC unbounded" sentinel literal (5 `.S` exit ceremonies + 1 return-sentry)

The widening moved `VEDA_PCC_UNBOUNDED` from the old 16-bit `0xFFFF` sentinel to the
new 20-bit `0xFFFFF` sentinel (`veda_regs.sail:91`). Six hand-written toolchain `.S`
files still populated their "exit into an unbounded compartment" object via plain
`VEDA_ODT_POPULATE`, whose Length field stays permanently 16-bit-capped by design and
can never represent `0xFFFFF` at all. The resulting OCInvoke/OCRETURN installed a
still-*bounded* PCC (`Length=0xFFFF != 0xFFFFF`), so the very next ordinary `sw`
(`RVMODEL_HALT_PASS`) hard-trapped under Milestone 19's purecap enforcement.

Fixed by switching all six to `VEDA_ODT_POPULATE_FAST` + the widened `veda_attr` CSR
(0x7C4), mirroring `vc_ocinvoke.S`'s own already-correct pattern -- the same fix this
project's own commit `9de3742` had already applied to the RTL smoke-test corpus, just
never mirrored into these compiler/runtime-layer files:
- `veda-core/compiler/veda_alloca_protect_entry.S`
- `veda-core/compiler/veda_global_protect_entry.S`
- `veda-core/compiler/veda_compartment_entry.S`
- `veda-core/compiler/veda_compartment_nested_entry.S`
- `veda-core/compiler/veda_struct_array_global_entry.S` (not exercised by any
  registered regression suite, fixed anyway for consistency -- same bug, same file
  family)
- `veda-core/runtime/veda_sched_asm.S` (a second, distinct instance: the scheduler's
  own OCJALR/OCRETURN return-sentry object, `csealentry`-minted and consumed via
  `ocreturn` -- confirmed by reading `VEDA_OCRETURN`'s own Sail semantics that it
  ALSO narrows `veda_pcc_length` from the sentry's Length field, exactly like
  OCInvoke, so this was a real, latent instance of the same bug, not yet observed
  only because the file's own separate bug below traps first during bootstrap)

### 2. Stale 16-byte capability-table-slot stride, compiler pass + runtime C (security-relevant)

`VedaShadowPropagation.cpp`'s `kVedaCapTableSlotBytes` constant (governing the
per-global capability table Phase B1/Milestone 13 emits) was still `16` -- the
pre-widening capability width -- with its own comment explicitly citing
`veda_ocl_insts.sail:130`, a line that now reads "17 (bytes) = 136 bits" post
-widening. This left odd-indexed global table slots landing on a 16-byte-aligned
-but-not-32-byte-aligned address, hard-trapping `OCS.C` (`VEDA_CAUSE_ALIGNMENT_VIOLATION`)
during bootstrap minting for any program with 2+ tracked globals -- **a real,
security-relevant regression**: silent bootstrap failure, not a narrow test-only
artifact, for any real compartment using this mechanism.

Fixed in two parts:
- `kVedaCapTableSlotBytes: 16 -> 32` (>=17 bytes AND, since every Nth slot at
  `N*32` is 32-aligned whenever the table's own base is, satisfies the new
  alignment gate too) -- `veda-core/compiler/VedaShadowPropagation.cpp`.
- The table `GlobalVariable`'s LLVM default alignment for an `[i8 x N]` array is 1
  byte, which would NOT actually guarantee the slot-stride math above holds at the
  real link-time address -- added an explicit
  `CapTableGV->setAlignment(Align(kVedaCapTableSlotBytes))` rather than relying on
  incidental linker behavior.
- A **second**, independently-stale hand-mirrored copy of the same constant was
  found in `runtime/veda_rt.c`'s `veda_rt_init_globals` bootstrap loop
  (`table_slot_offset = i * 16;`, explicitly commented "kVedaCapTableSlotBytes,
  mirrored" -- a real, hand-maintained cross-file constant that was never updated
  when the compiler-side one changed). This is the reason the fix did NOT close
  `global_protect` on the first attempt: the compiler pass alone lays out the table
  correctly, but the runtime's own bootstrap loop was still writing capabilities at
  the OLD stride. Fixed: `i * 16` -> `i * 32`, plus updating the two weak-fallback
  declarations (`g_veda_global_cap_table[16]` -> `[32]`,
  `__veda_global_cap_table_bytes = 16` -> `= 32`) for consistency (functionally
  inert when the pass provides a strong override, but misleading to leave stale).

### 3. Stale 16-byte object Length constants sized for the old OCS.C/OCL.C width

Two hand-written scheduler-layer objects held a single spilled/restored capability
each, sized under the pre-widening 16-byte convention -- `offset + 17 > Length`
overflowed them by exactly 1 byte, producing a direct `VEDA_CAUSE_BOUNDS_VIOLATION`
during early bootstrap/init (well before the file's own trap handler, if any, is
wired up -- both manifested as `sail_riscv_sim`'s "possible trap loop detected"):
- `runtime/veda_sched_asm.S`: `save_area_0`/`save_area_1`'s capability slot
  (Length 0x30=48 -> 0x40=64; alignment `.align 4`(16B) -> `.align 5`(32B) so the
  slot's own physical address at offset 32 is genuinely 32-byte aligned, not merely
  16-byte aligned as before).
- `veda-core/compiler/veda_sched_global_combo_entry.S`: `g_combo_table` (Length
  0x10=16 -> 0x20=32; alignment `.align 4` -> `.align 5`).

## Verification

- All 6 previously-failing suites now pass, re-run individually after each fix
  landed (not just at the end): `run_veda_alloca_protect_test.sh`,
  `run_veda_global_protect_test.sh`, `run_veda_compartment_test.sh`,
  `run_veda_compartment_nested_test.sh`, `run_veda_sched_demo_test.sh`,
  `run_veda_sched_global_combo_test.sh`.
- Full toolchain regression, zero new failures: `run_veda_shadow_prop_tests.sh`
  8/8, `run_veda_demo_tests.sh` 9/9, `run_veda_syscall0_hello_world_test.sh`,
  `run_veda_syscall0_forged_oid_test.sh`, `runtime/run_veda_rt_tests.sh` 2/2,
  `sail_tests/run_veda_selfcheck_tests.sh` 70/70 (compiler-only change; Sail model
  untouched, run anyway per standing discipline).
- Mutation test on the security-relevant fix (#2 above): temporarily reverted
  `kVedaCapTableSlotBytes` to `16`, confirmed `run_veda_global_protect_test.sh`
  fails again with the identical original symptom (`positive ok=0, negative
  trapped=1`); reverted the mutation (`diff` clean against the pre-mutation source)
  and rebuilt the real fix before re-verifying green.

## What this closes, honestly

This is a toolchain-layer parity fix, not a new architectural capability -- it
restores the Length/Offset widening milestone's own completeness across ALL the
layers it touches (Sail, RTL, *and* the compiler/runtime files that construct
capabilities by hand), closing a real regression window this session's own earlier
work opened. Item 2 (the compiler-pass table-stride bug) is the one genuinely
security-relevant finding here: a silent bootstrap-time hard-trap for any real
program with 2+ tracked globals is a functional break, not merely a test artifact,
and would have surfaced in any real deployment exercising Milestone 13's own
global-protection mechanism.
