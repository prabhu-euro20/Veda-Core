# Veda-Core Milestone 12 Results — Owner-Hart ODT Enforcement (Sail + RTL)

**Date:** 2026-07-26
**Scope:** `VEDA_CORE_SPEC.md` §4.1's own long-named gap, real since the
Object-Bind exclusive-ownership policy was first documented: *"an
owner-hart field in the ODT entry, checked at Bind/Rebind time... real,
identified future work."* This milestone closes it — a real
`owner_hart` byte now lives in every ODT entry, checked and claimed at
Bind/Rebind time, in both Sail and RTL.

## Scope decision carried in from the prior milestone

Real, physical multi-hart RTL (shared-memory arbitration, a new
multi-hart module structure) was considered as the next step after
Milestone 11 and explicitly scoped down — `NEXT_STEPS_ROADMAP.md` §2.7
itself already named owner-hart enforcement as separate, undesigned
work, distinct from an RTL-instantiation task. Since neither this
project's own single-process Sail C emulator (`veda_test_sail.json` has
no multi-hart support; `mhartid` is config-fixed at 0) nor the current
single-core RTL can produce two real, concurrently-executing harts, the
"wrong-owner" negative scenario in both is proven via **direct
ODT-state injection** — a test-scaffold precondition, mirroring this
project's own already-established seeded-fixture pattern (Sail's
`veda_test_seed_odt()`; RTL's own top-level reset `initial` block) —
not genuine concurrent execution. Stated explicitly here and in
`VEDA_CORE_SPEC.md` §4.1, not glossed over.

## Design decisions, reasoned and stated, not invented

- **`owner_hart : bits(8)`** added to Sail's `odt_entry` struct
  (`veda_types.sail`), alongside a `VEDA_OWNER_UNOWNED = 0xFF` sentinel.
  RTL adds the identical byte at offset **+10** within each 16-byte ODT
  entry (`veda_core.tlv`) — one of the six previously-spare bytes in
  that window (80 of 128 bits were used before this milestone; 88 of
  128 now), not a new/wider entry layout.
- **`MHARTID`**: Sail already has a real, existing `mhartid`
  architectural register (`core/sys_regs.sail`) — reused directly,
  truncated to `owner_hart`'s own 8-bit width, not a new register. RTL
  had no `mhartid` concept at all before this milestone; a real, new
  `localparam bit [7:0] MHARTID = 8'h00` was added — fixed at 0, the
  standard RISC-V single-hart convention, matching Sail's own
  single-hart config exactly, extendable to a real per-instance value
  if this core is ever replicated into an actual multi-hart system
  (still out of scope, `NEXT_STEPS_ROADMAP.md` §2.7).
- **`owner_ok` rule** (both Sail and RTL, field-for-field identical):
  `entry.owner_hart == VEDA_OWNER_UNOWNED | entry.owner_hart ==
  mhartid` — an object with no live owner yet, or one this same hart
  already owns, is fair game to claim (or idempotently re-claim).
- **Manipulate-vs-use split extends to owner violations**, matching
  this project's own established, load-bearing design principle
  (Section 1): plain **Bind hard-traps** on a live, wrong-owner object
  (a new cause code, `0x06`/`VEDA_CAUSE_OWNER_VIOLATION` — the next
  reserved slot in `VEDA_CORE_SPEC.md`'s own cause-code table since
  `0x04`/`0x19` were activated in Milestone 10); **Bind-NoTrap and
  Rebind both always soft-fail** (Tag cleared, no trap) — Rebind joins
  "sealed rd" and "ODT miss" as a third soft-fail reason, never a
  fourth hard-trap reason, matching its own established "never traps
  for any reason" rule from Milestone 8.
- **The claim is a real write-back**, not just a read-side check: every
  successful Bind/Bind-NoTrap/Rebind writes `owner_hart := mhartid`
  into the ODT entry (Sail's `claimed_entry`; RTL's own new dedicated
  `always_ff` block), unconditionally on success — including an
  idempotent re-claim when the object was already owned by this same
  hart, matching Sail's own unconditional write exactly rather than
  special-casing "already correct, skip the write."
- **RTL's own trap-family cap_idx precedent extended, not reinvented**:
  every other hard-trapping family in this file traps with `cap_idx =
  rs1` (the capability being *dereferenced*); Bind's owner-violation
  traps with `cap_idx = rd` (the capability being *written*) — mirrors
  `veda_bind_insts.sail`'s own `veda_trap(rd, ...)` call exactly, and
  reuses the same per-family `$veda_trap_cap_idx` override pattern
  Milestone 10 already established for OCInvoke's own two-capability
  case.
- **RTL's destination register left completely untouched on the
  hard-trap path**, not just Tag-cleared — matching Sail exactly
  (`veda_trap()` diverts control flow before `wC()`/`wCTag()` are ever
  called). `$bind_wr_en` gained a new `!$veda_bind_owner_violation`
  exclusion term, the identical precedent already established for
  `$ocinvoke_wr_en`'s own `!violation` exclusion in Milestone 10.

## Implementation

**Sail**: `veda_types.sail` (`owner_hart` field + `VEDA_OWNER_UNOWNED`
constant); `veda_bind_insts.sail` (`VEDA_CAUSE_OWNER_VIOLATION = 0x06`;
`VEDA_BINDINST`'s `owner_ok`/`claimed_entry` bindings, consumed by both
the `VEDA_REBIND` arm and the shared `Bind`/`Bind-NoTrap` catch-all
arm); `veda_regs.sail` (`veda_test_seed_odt()` gained `owner_hart =
VEDA_OWNER_UNOWNED` on its four pre-existing fixtures, plus a fifth new
fixture, Object_ID=5, `owner_hart = 0x63`).

**RTL** (`veda_core.tlv`): `MHARTID`/`VEDA_OWNER_UNOWNED` localparams;
`odt_mem[]`'s reset `initial` block extended with `owner_hart` bytes for
the two pre-existing seeded objects (Object_ID=1/2, both
`VEDA_OWNER_UNOWNED`) plus a third new fixture (Object_ID=**60** —
deliberately not 3; see "A real bug found and fixed" below);
`$veda_odt_owner`/`$veda_owner_ok` read alongside the existing ODT
field reads; `$veda_rebind_ok` gained `&& $veda_owner_ok`;
`$veda_bind_owner_violation` (new, plain-Bind-only) wired into the
existing combined `$veda_trap_taken`/`$veda_trap_cause`/
`$veda_trap_cap_idx` mux three-way, alongside a new dedicated
`always_ff` block performing the owner-claim write-back to `odt_mem[]`
byte offset +10.

## A real bug found and fixed: Object_ID collision with Milestone 4's own test

The RTL Milestone 12 fixture was first seeded at **Object_ID=3**
(mirroring Sail's own choice of a small, memorable ID). Running the
full regression immediately caught a real failure: **Milestone 4's own
positive test (`veda_smoke_m4.S`) failed**, a test unrelated to this
milestone's own changes. Root cause: `veda_smoke_m4.S` line 27's own
comment states its precondition explicitly — *"Object_ID = 3 (never
seeded at reset — a real fresh mint)"* — Milestone 4 mints Object_ID=3
fresh via a real `ODT-Populate` and depends on it starting invalid.
Seeding it at reset for Milestone 12 silently violated that
precondition. **Fixed** by grepping every existing `veda_smoke_*.S` file
for every `Object_ID=`/`x1, N` literal already in use (found: 1, 2, 3,
5, 6, 10, 20, 30, 31, 32, 40, 50, 99) and choosing **Object_ID=60** — a
genuinely unused value — instead, for both the RTL fixture and the two
new Milestone 12 test programs. Re-ran the full regression after the
fix: clean. A real, caught regression, not a hypothetical risk — the
project's own pre-existing test suite is what caught it.

## A real gap found and fixed: stale Sail binary during test authoring

While first running the new `vc_owner_hart_neg.S` Sail test against an
already-built `sail_riscv_sim`, the trap fired with `mtval = 0x05`
(`VEDA_CAUSE_OBJECT_NOT_FOUND`) instead of the expected `0x06`
(`VEDA_CAUSE_OWNER_VIOLATION`) — not a logic bug: the 5th ODT seed
fixture (`veda_regs.sail`'s Object_ID=5 entry) had been added to source
*after* the C emulator's last successful build, so the running binary's
own `odt_lookup(5)` still returned `valid=false` from the *previous*
`veda_test_seed_odt()` (only four entries). Confirmed via
`--trace-instr --trace-exception` showing the real `tval` value, not
assumed. **Fixed** by rebuilding (`cmake --build build`) before
re-running — a process/sequencing lesson (new Sail test fixtures must
be built in before the tests that exercise them can be trusted), not an
implementation bug in `VEDA_BINDINST` itself.

## Result

Both Sail tests (`vc_owner_hart`, `vc_owner_hart_neg`) and both RTL
tests (`veda_smoke_m12`, `veda_smoke_m12_neg`) passed after the two
fixes above. `vc_owner_hart`/`veda_smoke_m12` each prove, against a
single real hart: claiming a genuinely-unowned object (Bind), an
idempotent self-owned re-claim (Rebind), and both Bind-NoTrap's and
Rebind's own soft-fail against an injected wrong-owner fixture.
`vc_owner_hart_neg`/`veda_smoke_m12_neg` each prove the genuine
hard-trap path: correct `mcause`/`mtval`/`mepc`, correct `MRET` resume,
and — RTL's own additional, stronger check — the destination capability
register left completely untouched by the trap, not merely
Tag-cleared.

## Full regression: zero impact beyond the one caught-and-fixed collision

**Sail**: `run_veda_selfcheck_tests.sh` — **21/21 passed** (19 prior
tests + `vc_owner_hart`/`vc_owner_hart_neg`), zero regressions.

**RTL**: `run_veda_smoke_test.sh` — **22/22 passed** (20 prior tests +
`veda_smoke_m12`/`veda_smoke_m12_neg`), zero regressions after the
Object_ID fix above, including the base RV64I core's own unmodified
81-instruction smoke test.

## Not yet built

Real, physical multi-hart RTL (shared-memory arbitration between
genuinely concurrent harts) remains out of scope — `NEXT_STEPS_ROADMAP.md`
§2.7's own still-open item. `ODT-Destroy` still has no owner-hart gate
of its own (a live object can still be destroyed by any privileged/
ODA-authorized caller regardless of `owner_hart` — Destroy was never in
this milestone's own named scope, which was specifically Bind/Rebind,
matching `VEDA_CORE_SPEC.md` §4.1's own original gap statement
precisely). `MHARTID` remains a fixed `localparam=0` in RTL, not a real
per-instance configurable value — the correct floor for a single-core
implementation, revisited only if this core is ever actually
replicated.
