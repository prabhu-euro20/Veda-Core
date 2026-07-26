# Veda-Core RTL — Milestone 9 Results

**Date:** 2026-07-25
**Scope:** Real trap infrastructure — `NEXT_STEPS_ROADMAP.md`'s Tier 2
item, the largest remaining architectural divergence between Sail and
RTL. Every RTL milestone through Milestone 8 shared the same honest
floor: a Veda-Core violation suppressed the write but let execution
continue at PC+4 — Sail's own security model (a genuine hard trap,
`mcause=0x18`, an exact `mtval` cause/cap_idx encoding) was never
actually what the RTL enforced. This milestone closes that gap: a real
Zicsr-lite CSR file (`mtvec`/`mepc`/`mcause`/`mtval`), real
`CSRRW`/`CSRRS`/`MRET` (standard RISC-V encoding, confirmed via the
assembler's own native mnemonics, not `.word` hand-encoding), and a
real PC redirect wired to every Sail "use"-family violation.

## Ground truth used, not re-derived

Read `veda_ocl_insts.sail`, `veda_atomic_insts.sail`, and
`veda_cap_insts.sail` in full before writing any RTL, to settle — not
assume — exactly which instructions genuinely hard-trap in Sail and
which soft-fail by permanent design:

- **Hard-trap ("use") family** — `OCL`/`OCS`/`OCL.C`/`OCS.C` (share
  `veda_check_access`), `NMC_ADD.{W,D}`/Veda-Atomic (share
  `veda_check_nmc_access`/`veda_check_access`). Each calls `veda_trap()`
  with an exact priority order: Tag/generation → Seal → Permission →
  Bounds — mirrored field-for-field into RTL's own new per-family cause
  signals, not re-derived from intuition.
- **Permanent soft-fail ("manipulate") family** — `OCA`, `CSetBounds`/
  `CSetBoundsExact`, `CSeal`/`CUnseal`, and `Bind-NoTrap`/`Rebind`
  (Object-Bind's own two non-plain modes). None of these ever call
  `veda_check_access` at all in Sail — confirmed by reading every one of
  their `execute` clauses, not assumed from the "manipulate vs. use"
  language already in `VEDA_CORE_SPEC.md`. Correctly untouched by this
  milestone.
- **A third, separate class, deliberately deferred** — `ODT_POPULATE`/
  `ODT_DESTROY`'s own privilege check (`if cur_privilege != Machine then
  Illegal_Instruction()`) is a real trap too, but a different exception
  class (standard `Illegal_Instruction`, not `veda_trap()`'s
  `E_Extension`) with no `cap_idx`/cause encoding to mirror. Left as RTL's
  existing `$priv`-gated soft-fail, named explicitly as a real, separate,
  not-yet-closed gap rather than silently folded into this milestone.
- **Also deliberately deferred** — plain `Bind`'s own ODT-miss hard-trap
  (`VEDA_CAUSE_OBJECT_NOT_FOUND`, `0x05`) is real in Sail but was not
  wired into RTL this pass: doing so would, for the first time, make
  RTL's plain `Bind` and `Bind-NoTrap` behaviorally different (they have
  been identical on this RTL since Milestone 8, since neither ever had
  real trap delivery) — a real, separate, correctly-named follow-on, not
  bundled into an already-large milestone.

## Implementation

- **CSR state**: `mtvec`/`mepc` are genuinely software-writable (`mtvec`
  so software can install a handler; `mepc` because a real handler must
  advance past the faulting instruction before `MRET`, confirmed a real,
  load-bearing need while building this milestone's own test — leaving
  `mepc` unchanged would `MRET` straight back into the same faulting
  instruction and re-trap forever). `mcause`/`mtval` are hardware-write-
  only (real RISC-V's own WARL convention for a field software isn't
  meant to move) — no real trap-handler pattern in this project ever
  needs to fabricate a cause/value it didn't actually observe.
- **CSR instructions**: only `CSRRW`/`CSRRS` decoded (real, standard
  Zicsr I-type/SYSTEM-opcode encoding) — `CSRRC`/`CSRRWI`/`CSRRSI`/
  `CSRRCI` deliberately deferred, a stated scope reduction: every real
  trap-handler pattern in this project only ever needs "install a value"
  (`CSRRW`, for `mtvec`) and "read a value" (`CSRRS` with `rs1=x0`, the
  real `csrr` pseudo-instruction's own expansion). `CSRRS` with `rs1=x0`
  correctly does not write the CSR (real Zicsr rule, not RTL's own
  invention).
- **`MRET`**: matched as one fixed 32-bit literal (`0x30200073`) rather
  than field-by-field decode — this core has no privilege-level stack to
  restore (it's always effectively M-mode, matching `$priv`'s own
  existing one-way-drop model since Milestone 4), so `MRET` here means
  exactly "PC = mepc", not a full `mstatus.MPP`/`MPIE` restore.
- **Trap-taken redirect**: one combined `$veda_trap_taken` signal ORs
  every hard-trap family's own violation signal; `$veda_trap_cause` muxes
  in the winning family's own cause code. `cap_idx` is not muxed
  per-family — all seven hard-trapping instructions share the identical
  `rs1`-capability field position already established since Milestone 1,
  so one signal is correct regardless of which family actually trapped.
  `$pc_src`/`$alt_pc` now redirect to `mtvec` on a trap (checked before
  `MRET`/`JAL`/`JALR`/branch in the mux, the most security-critical
  condition first, matching this file's own established mux-ordering
  style).

## Real bugs found and fixed — five, kept honestly distinct

**Bug 1 (test, not RTL) — a stale Object_ID assumption from Milestone 1,
never caught until now.** `veda_smoke_neg.S`'s own original version used
`Object_ID=2` to prove "an unpopulated object's capability reads
untagged" — true when written in Milestone 1, but Milestone 2 later
seeded `Object_ID=2` into `veda_core.tlv`'s own reset scaffold for an
unrelated reason (a `Permit_NMC_Compute`-less object for Milestone 2's
own negative test), silently making `Object_ID=2` VALID from that point
on. The old testbench also checked the wrong memory address
(`Object_ID=1`'s own `Base`, not `Object_ID=2`'s), so it kept reporting
`PASS` for the wrong reason — the OCS.D write was actually succeeding
the entire time, just landing somewhere the assertion never looked.
Found while designing this milestone's own trap-handler upgrade for that
same file, not by the old test ever failing on its own — a real instance
of exactly the kind of latent bug this project's own "verify before
deciding" discipline exists to catch. Fixed: `Object_ID=50` (never
populated anywhere in this suite), a real trap-handler asserting
`mcause`/`mtval` directly.

**Bug 2 (test, a new class, found and fixed in three files) — a
"trap-didn't-fire" fallback placed at the exact PC a *correct* trap
resumes to.** The first draft of every trap-and-resume test (including
this milestone's own new `veda_smoke_m9.S`) placed a
`li x20,0xBAD; j fail` sentinel immediately after the faulting
instruction, intending it to catch a missing trap. But `mepc+4` — where
the handler's own `MRET` actually resumes execution on the *success*
path — is that exact same address, so the "failure" sentinel fired on
every successful run instead. Diagnosed via a real per-cycle debug trace
(`tb_veda_smoke_m9_debug.sv`, deleted after use) showing `mret` correctly
landing at the intended PC, yet the test still failing — not assumed
from source review. Fixed uniformly: nothing but the real next test step
follows the faulting instruction directly; a missing/wrong trap is
caught by the success sentinel simply never being set, not by a separate
catcher instruction at that address. Applied to `veda_smoke_m9.S`,
`veda_smoke_neg.S`, `veda_smoke_m2_neg.S`, and `veda_smoke_m6.S`'s own
sealed-use-blocked section.

**Bug 3 (real, genuine RTL-wide behavioral consequence, not a bug in any
one file) — enabling real hard traps broke three unrelated, already-
passing tests.** `veda_smoke_m4.S`, `veda_smoke_m5.S`, and
`veda_smoke_m8.S` (all positive tests) each embed a deliberate, expected
*soft-fail* check from an earlier milestone (a stale-generation OCL.D, a
`Permit_NMC_Compute`-less NMC_ADD.W, a stale-generation Veda-Atomic AMO)
as one step in a longer, otherwise-unrelated proof. Once "use"-family
violations genuinely trap RTL-wide, each of those checks now hard-traps
too — but none of those three files ever installed a handler (`mtvec`
still reset to its default, `0`), so the real trap redirected PC to
address `0`, an address `elfmem[]` doesn't cover, causing the very next
instruction fetch to read `x` (Icarus's genuine "never `$readmemh`-
initialized" value, the same real convention already documented in
`MILESTONE_8_RESULTS.md`) and every downstream register to go `x` with
it. `veda_smoke_oca_neg.S` had the identical latent exposure but
happened to still report `PASS` — its own 8-cycle simulation window
ended before the corrupted post-trap fetch ever executed, a coincidence
of that one file's own short cycle count, not a real guarantee (found by
re-auditing every `.S` file in the suite for an embedded "use"-family
soft-fail assumption, not just the three files that failed outright).
Fixed uniformly: all four files now install a small, assertion-free
"skip the faulting instruction and resume" handler
(`generic_trap_handler`) up front, so each file's own original assertion
keeps meaning exactly what it always meant, without needing to become a
trap-delivery test itself (that's this milestone's own dedicated
`veda_smoke_m9.S`'s job).

**Bug 4 (real, a register-naming collision between two independently-
correct pieces of code).** `generic_trap_handler`'s first draft used
`t3` (`x28`) as scratch space to compute `mepc+4` — but
`veda_smoke_m5.S`'s own, pre-existing test design also uses `x28` as its
negative check's sentinel register. The handler firing correctly (Bug 3's
own fix) then correctly overwrote its own test's sentinel with the
handler's own scratch value (`mepc`'s address), a real, load-bearing
bug neither piece of code had in isolation. Diagnosed directly from the
failure output (`x28=0x80000134`, an address, not `0x5555`) — not
assumed. Fixed by auditing all four `generic_trap_handler`-using files
for their own register usage and moving the handler's own scratch
register to `x31` (`t6`), confirmed unused by any of them.

**Bug 5 (test, a cycle-count budget too tight for its own new
instructions).** `veda_smoke_oca_neg.S`'s own testbench ran only 8
cycles — enough for its original ~8-instruction program, but not for the
2 additional handler-install instructions (`la`/`csrw`) this milestone's
own Bug 3 fix added. Fixed by raising the window to 20 cycles, the same
real headroom-discipline already used for this suite's other short
tests.

## Full regression: zero impact

**16 real test programs** through one script (`run_veda_smoke_test.sh`):
every Milestone 1–8 test (now including three upgraded to real
trap-handler assertions, and four given a generic resume handler),
Milestone 9's own new `veda_smoke_m9.S`, and the base RV64I core's own
unmodified 81-instruction smoke test. Zero regressions.

## Design notes worth recording

- **The "manipulate vs. use" split, already named in `VEDA_CORE_SPEC.md`,
  turned out to be exactly the right fault line for this milestone's own
  RTL scope** — every instruction this milestone touched was decided by
  which Sail `execute` clause actually calls `veda_trap()`, not by
  intuition about which "feels like" a violation.
- **A working feature can break already-passing, unrelated tests the
  moment it's turned on RTL-wide** — Bug 3 is the clearest instance of
  this in the project's own history so far: the new trap infrastructure
  itself had zero bugs (`veda_smoke_m9.S` passed on its first real run
  once Bug 2's own fallback-placement mistake was fixed), but *enabling*
  it exposed three latent assumptions in unrelated, previously-verified
  test files that had never been true until this exact moment.
- **`CSRRW`/`CSRRS`/`MRET` needed zero `.word` hand-encoding anywhere in
  this milestone's own new test** — the assembler's real, standard
  RISC-V mnemonics produced exactly the encodings this RTL's own decode
  logic expects, a genuine (not just intended) confirmation that this
  milestone implemented real Zicsr, not an invented lookalike.

## Not yet built

Plain `Bind`'s own ODT-miss hard-trap (`VEDA_CAUSE_OBJECT_NOT_FOUND`,
`0x05` — still RTL's existing soft-fail, `Bind`/`Bind-NoTrap` remain
behaviorally identical on this RTL until this is closed);
`ODT_POPULATE`/`ODT_DESTROY`'s own `Illegal_Instruction` privilege trap
(a distinct exception class from every family this milestone closed,
still RTL's existing `$priv`-gated soft-fail); `CSRRC`/`CSRRWI`/
`CSRRSI`/`CSRRCI` (no real consumer in this project's own trap-handler
pattern yet); `CInvoke`-equivalent domain transition;
capability-authority-gated `ODT-Populate`/`ODT-Destroy` — all real,
previously-named, still-deferred items, unaffected by this milestone.
With this milestone, RTL's own security model now genuinely matches
Sail's for every "use"-family instruction: a violation is a real,
observable, architectural trap, not merely an invisible suppressed
write.
