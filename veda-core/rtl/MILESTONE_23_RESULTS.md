# Veda-Core RTL Milestone 23 Results — Real ECALL Support

**Date:** 2026-08-06
**Scope:** add real `ecall` support to `veda_core.tlv` — closing a gap the RTL's own header comment
has carried since the original RV64I base-ISA milestone ("excl. ECALL/EBREAK, deferred") and that
`MILESTONE_21_RESULTS.md` explicitly named and pre-scoped the fix for. Discovered as a real,
unplanned blocker while starting the RTL mirror of Sail-side Milestone C (the cooperative
scheduler, `MILESTONE_C_RESULTS.md`), which yields via `ecall` — RTL had never implemented it.

## Why this exists

A parallel research pass (5 agents reading `veda_core.tlv` directly) confirmed by exhaustive grep:
zero `$is_ecall`, zero `mcause=11` anywhere in the file. `MILESTONE_21_RESULTS.md`'s own
investigation had already gone further and pre-written the fix's requirement: *"if and when a
future milestone adds `ecall`... that work must wire its own new violation signal into the
existing `$veda_trap_taken` OR-chain... Doing so would automatically and correctly get PCC-reset
for free, by construction."* This milestone is a direct, verified execution of that prescription.

## What was built

Four edit sites in `veda_core.tlv`, each independently re-verified against the real current
source by a Plan agent before implementation (not just designed and trusted):

1. **`$is_ecall = ($instr == 32'h00000073);`** — a single fixed-literal decode, the same idiom
   already used for `$is_mret` (`32'h30200073`). Confirmed distinct from EBREAK (`0x00100073`,
   differs only in bit 20).
2. **`$veda_trap_taken`'s OR-chain** gains `|| $is_ecall` — unlike every other term (all
   conditional security violations), `ecall` is unconditional by design.
3. **`mcause` mux** gains a branch: `$is_ecall ? 64'h0B : 64'h18` — `0x0B` (11) is the real,
   standard RISC-V mcause for "Environment call from M-mode," not an invented code, and the only
   possible value since this core only ever runs M-mode.
4. **`mtval` mux** gains a branch: `$is_ecall ? 64'b0` — real spec convention, mtval=0 for ecall.

**Nothing else changes.** `$mepc` capture, Milestone 21's universal PCC reset (all four CSRs),
and the `$pc_src`/`$alt_pc` jump-to-`$mtvec` mux are all keyed purely on the single
`$veda_trap_taken` signal as their highest-priority branch — confirmed line-by-line, both by
direct reading and independently by the Plan-agent verification pass, that they apply to the new
`ecall` trap automatically. This is the entire reason the diff is 4 lines, not a larger one.

Header comment updated: "excl. ECALL/EBREAK, deferred" → "excl. EBREAK, deferred."

## Independent verification, not just design-and-trust

Before writing any code, an independent Plan agent re-derived every claim above against the real
`veda_core.tlv` source from scratch (no context from the design session) and additionally
confirmed: no opcode-space collision is possible between `ecall` and any other `$veda_trap_taken`
term (every other term gates on Custom-0/1/2 opcodes or load/store/CSRRW/CSRRS, all disjoint from
SYSTEM opcode); `0x0B`/11 was unclaimed anywhere else in the file; `$reg_write` and the data-memory
write-enable never gate on SYSTEM-opcode instructions, so `ecall` correctly writes no GPR and
touches no memory with zero extra gating; and — critically — flagged a real hazard from this
project's own Milestone 9 precedent ("Bug 3," `MILESTONE_9_RESULTS.md:124-149`): `mtvec` resets to
`0`, and a trap before `mtvec` is explicitly installed redirects to uninitialized address 0,
producing `x`-propagation through every downstream register in Icarus. Both new tests below
install `mtvec` before executing `ecall` specifically because of this prior, documented finding.

## Tests

Both follow the exact convention of the two most recent, closely related RTL tests
(`veda_smoke_mosA_tsc.S`/`veda_smoke_mosB_sentry.S`): fixed-cycle-count testbench, no HTIF/tohost,
final PASS/FAIL via `$display` + hierarchical `dut.CPU_Xreg_val_a0[N]` GPR readback.

- **`veda_smoke_m23_ecall.S`** (baseline, unbounded context): installs `mtvec`; executes `ecall`;
  handler confirms `mcause==11`, `mtval==0`, `mepc==` the `ecall` instruction's own address (no
  auto-advance — the same "exact trapping PC" behavior already true of every other trap since
  Milestone 9); writes a marker register; advances `mepc+4` and `mret`s to resume cleanly.
- **`veda_smoke_m23_ecall_compartment.S`** (proves Milestone 21's universal reset applies to the
  new trap, not assumed): reuses `veda_smoke_mosB_sentry.S`'s own OCInvoke/Object_ID/populate/bind
  scaffold (Object_IDs 100/101/102 — personally grepped every existing `rtl/sim/*.S` file's own
  Object_ID usage before picking: union is
  `{1,2,3,5,6,10,20,30-35,40,41,50-54,61,70-73,80-94,99,200,288}` plus permanently-seeded `1`/`2`/
  `60` in `veda_core.tlv`'s own `initial` block — `100-199` is completely free); `ecall`s from
  inside the compartment; handler confirms live `veda_pcc_base`/`veda_pcc_length` (CSR
  `0x7c0`/`0x7c1`) read back genuinely unbounded (`0`/`0xFFFF`) while `veda_mepcc_base`/
  `veda_mepcc_length` (`0x7c2`/`0x7c3`) hold the compartment's true pre-trap bounds, and `mepc`
  equals `ecall`'s own address inside the compartment (positively distinguishing this trap from
  the preceding OCInvoke-entry itself).

**One real bug found and fixed during test development** (in the new tests, not the RTL logic):
both tests' first cycle-count budgets were too tight — the compartment test's own setup (3
`veda.odt.populate` + 3 `veda.bind` + 2 `cseal` + `ocinvoke` + the trap handler's own 4 CSR reads)
needed more headroom than the initial guess. Found via a purpose-built cycle-by-cycle debug
testbench (`$display` of `$pc`/`$instr`/`x21`/`x22` every cycle, this project's standing empirical
debugging method): the success sentinel `x21=0x600D` was reached at cycle 60 against a 50-cycle
budget. Fixed by raising the budget to 80 cycles.

## Verification

```
$ bash run_veda_smoke_test.sh
...
*** TEST PASSED *** (ECALL genuinely traps with real RISC-V mcause=11/mtval=0, mepc at the
ECALL's own PC with no auto-advance, MRET closes the full trap-and-resume cycle -- RTL
Milestone 23)
...
*** TEST PASSED *** (ECALL from inside a live OCInvoke compartment genuinely traps with
mcause=11; Milestone 21's universal PCC reset applies to it for free -- live PCC reads
unbounded, veda_mepcc_base/_length hold the compartment's true saved bounds, mepc pins the
trap to ECALL's own address inside the compartment -- RTL Milestone 23)
```

**40/40** RTL smoke regression (38 pre-existing + 2 new), **51/51** ACT4 RV64I conformance —
independently confirmed unaffected before the change too: the Plan-agent disassembled every ACT4
`.elf` and found zero `ecall`/`ebreak` occurrences anywhere in that corpus. Zero regressions on
either suite.

## Not yet built

EBREAK, general illegal-instruction trapping, and misaligned-access detection remain explicitly
out of scope, matching Milestone 21's own prior scoping decision. The actual reason this milestone
exists — the RTL mirror of Sail-side Milestone C's cooperative scheduler — is the next,
not-yet-started piece of work, now unblocked.
