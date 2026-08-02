# Veda-Core RTL Milestone 20 Results: Compartment-State CSR Self-Escape Fix

**Date:** 2026-08-02
**Scope:** the real RTL mirror of the Sail-side Milestone 20
(`veda-core/MILESTONE_20_RESULTS.md`) -- closing, in the actual
hardware model, the real, empirically-confirmed vulnerability found
while auditing the compartmentalization machinery Milestones 14 and 19
just built: code entered via a real `OCInvoke` compartment could
simply execute an ordinary `CSRRW` to its own compartment-state CSRs
to undo its own bounding, with zero trap or restriction. Deliberately
bundled with Milestone 19's own RTL mirror as one combined follow-up
(named explicitly in that milestone's Sail-side "Not yet built"
section) rather than two separate small RTL passes, since both were
un-mirrored for the identical reason.

## Design, mirrored field-for-field from the already-verified Sail side

Five CSRs gated: `veda_pcc_base`/`_length` (`0x7C0`/`0x7C1`, the live
compartment bounds), `veda_mepcc_base`/`_length` (`0x7C2`/`0x7C3`, the
trap-time save registers -- the second real attack the Sail side's own
design review found: corrupting the *saved* bounds a legitimate
handler's own restore convention would later trust, not just the
*live* ones), and `veda_mode` (`0x7C5`, Milestone 19's purecap
toggle). A write to any of these five while a compartment is live
(`$veda_pcc_length != 16'hFFFF`) is now illegal -- real-world grounded,
not invented: matches CHERI's own actual rule ("Reading or writing any
CSR requires the Access_System_Registers permission on the PCC").
`veda_attr` (`0x7C4`) confirmed correctly out of scope, unchanged from
the Sail side's own reasoning -- its sole consumer already has its own
independent capability-authority gate.

**A real implementation subtlety, found by direct inspection before
writing any test**: four of the five gated CSRs (`veda_pcc_base`/
`_length`/`veda_mepcc_base`/`_length`) already had a higher-priority
"any trap resets `veda_pcc_base`/`_length` to unbounded, saving the
pre-trap bounds into `veda_mepcc_base`/`_length`" branch in their own
existing definitions (Milestone 14's own save-and-reset discipline,
applied uniformly to every trap family, not just PCC violations).
Since the new `$veda_csr_escape_violation` joins the same
`$veda_trap_taken` family, that pre-existing, higher-priority branch
*already* correctly prevents the attacker's `csr_wdata` from landing
on those four CSRs, with zero additional per-CSR guard needed --
confirmed by tracing the actual ternary priority, not assumed.
`veda_mode` has no such pre-existing branch (nothing else in this file
ever writes it), so it alone needed an explicit, hand-written
`!$veda_csr_escape_violation` guard -- verified independently with its
own dedicated negative test (below), precisely because it was the one
case not covered "for free."

**Trap cause, deliberately different from every other family in this
file**: `mcause=0x02` (standard RISC-V `Illegal_Instruction`), not
Veda-Core's own `0x18` (`E_Extension`) every other violation here
shares -- matches the Sail side's own real, idiomatic
`write_CSR`-returns-`Err(())`-triggers-`Illegal_Instruction()`
mechanism exactly. `mtval` for this specific case holds the real,
standard convention for an illegal-instruction trap -- the raw
faulting instruction bits -- rather than a `cap_idx`/`cause` pair,
since this is not a Veda-specific violation family at all.

Read access is deliberately **not** gated on any of the five, matching
the Sail side's own explicit reasoning: capability metadata is always
inspectable (the same principle `CGetTag`/`CGetType` already rely on)
-- code inside a compartment already knows its own bounds, it got
there via the capability that defined them, so reading them back leaks
nothing new. `$csr_rdata`'s own mux (already unconditional for these
five addresses) needed no change.

## Real verification -- not estimated

Three new RTL test programs, assembled with the real
`riscv64-unknown-elf-as`/`-ld`/`-objcopy` toolchain, run against the
real, unmodified, committed `veda_core.tlv`:

| Test | Result |
|---|---|
| `veda_smoke_m20` (positive) | Outside any live compartment, ordinary writes to `veda_mepcc_base`/`_length` and `veda_mode` round-trip correctly (`x10=0x80`, `x11=1`, `x12=0`) -- **all correct**. `veda_pcc_base`/`_length` deliberately not exercised with arbitrary values here, matching the Sail side's own identical scoping note: doing so risks immediately tripping Milestone 14's own real PCC-fetch enforcement on this test's own next instruction fetch. |
| `veda_smoke_m20_neg` (`veda_pcc_length` self-escape) | From inside a live `OCInvoke` compartment (`Length=0x40`), `csrw 0x7c1, 0x1000` genuinely hard-traps -- `mcause=0x02` (`x21=0x600D`), and `veda_pcc_length` reads back exactly `0xFFFF` afterward, neither the original `0x40` nor the attacker's `0x1000` -- **all correct**. |
| `veda_smoke_m20_neg2` (`veda_mode` self-escape) | The one CSR whose suppression needed an explicit, hand-written guard rather than the pre-existing PCC-reset priority. From inside the same compartment shape, `csrw 0x7c5, 1` genuinely hard-traps -- `mcause=0x02` (`x21=0x600D`), and `veda_mode` reads back `0` afterward, never written at all -- **all correct**, confirming the one non-"free" part of this implementation independently. |

Full regression: `run_veda_smoke_test.sh` -- **33/33 passed, 0 failed**
(30 pre-existing tests, including Milestone 19's own three RTL tests
from earlier this same pass, + these 3 new ones, zero regressions).
`run_act4_tests.sh` -- **51/51 passed, 0 failed, 0 timed out**.

## What this closes, stated plainly

Before this milestone, code inside a live compartment could undo its
own bounding with a single, ordinary `CSRRW` -- no trap, no
restriction, in the actual hardware model (Sail already closed this;
RTL did not). That gap, and the related "corrupt the saved bounds
instead of the live ones" variant, are both closed, with the exact
same real, empirically-verified enforcement point Sail already proved.

## What remains open, honestly

- RTL mirror for Milestone 21 (universal PCC reset on any trap,
  closing the `mtvec`-rewrite / ordinary-exception trap-state
  -integrity gap the Sail side's own Milestone 20 design review found
  and deliberately deferred) is separate, not-yet-attempted work.
- As on the Sail side, the `mtvec`-rewrite gap itself (a compartment
  rewriting the standard, non-Veda trap-vector CSR, then deliberately
  triggering an ordinary exception to reach a handler still observing
  stale `veda_pcc_*`/`veda_mepcc_*` state) is exactly what Milestone
  21 exists to close -- named here again for continuity, not a new
  finding.
