# Veda-Core Milestone 10 Results — OCInvoke (Sail + RTL)

**Date:** 2026-07-25
**Scope:** `OCInvoke`, Veda-Core's own term-for-term adaptation of real
CHERI's `CInvoke` — the protection-domain-transition instruction
`VEDA_CORE_SPEC.md` Section 6 item 7 named and deliberately deferred
since it was first identified ("Veda-Core has no `PCC`-equivalent... so
there is presently no register for a `CInvoke`-equivalent to unseal
*into*, and inventing one without deliberately designing Veda-Core's
control-flow-capability model first would be exactly the kind of
unfounded, ungrounded addition the verification discipline for this
project rules out"). This milestone does that deliberate design work,
then implements it in both formal-model and RTL layers, per the
project's own established Sail-then-RTL sequencing.

## Ground truth used, not re-derived

Read real CHERI's own `CInvoke` in full before writing any code — not
the Chapter 3 architectural-mapping overview alone (already read in an
earlier session and cited at pp.106-108), but the actual
instruction-set-reference entry, `7.4 CHERI-RISC-V INSTRUCTIONS:
CInvoke`, CHERI ISA spec p.209 (`cheri-architecture.pdf`, extracted via
`pdftotext -layout` and read directly, not summarized): the real
encoding (`0x7e | cs2 | cs1 | 0x0 | 0x1 | 0x5b`), the real 9-check
authorization sequence in its exact order, and the real success-path
semantics (`C(31) = unsealCap(cs2_val); nextPC = newPC; nextPCC =
unsealCap(cs1_val)`).

Two concrete, non-obvious facts this reading corrected or confirmed,
neither assumed from the earlier summary-level pass:

1. **CHERI's own "`IDC`" is not a separate physical register at all** —
   it is `C31`, the *last* entry in CHERI's own ordinary 32-entry
   capability register file (`C(31) = unsealCap(cs2_val)` is a plain
   register-file write, index 31). This directly resolved the design
   question this project's own earlier deferral had left open ("no
   register for a `CInvoke`-equivalent to unseal into") — the answer
   real CHERI itself uses is a fixed-index convention within the
   *existing* capability register file, not a new register class.
   Veda-Core adapts this proportionally: `c15`, the last entry in its
   own 16-entry Capability Register File.
2. **CHERI's own `CInvoke` never has a destination-register field at
   all** — its two outputs (`PCC`, `C31`) are architecturally fixed,
   never instruction-selectable, confirmed directly from the real
   encoding (`rd`'s bit position is a fixed constant `0x1`, not a
   register-index field). `OCInvoke`'s own encoding mirrors this: `rs1`
   (code)/`rs2` (data) are its only real operands, its `rd` field is
   reserved and unused, not a design shortcut.

## Design decisions, reasoned and stated, not invented

- **`c15` as the fixed "IDC" target** — a software ABI convention
  exactly like CHERI's own `C31`, not a hardware-enforced lock. Any
  other instruction can still target `c15` like any ordinary capability
  register; `OCInvoke` simply always writes there on success.
- **No `PCC` storage — a deliberate, stated scope boundary, not a
  silent gap.** Real CHERI's own `CInvoke` also installs the unsealed
  CODE capability into `PCC`, a full capability register consumed by
  every subsequent instruction fetch for bounds/permission enforcement.
  Veda-Core has no `PCC`-equivalent and, more fundamentally, **no
  instruction-fetch-time capability enforcement at all** — fetch
  remains plain RV64I, unconstrained by any capability, confirmed
  unchanged even after RTL Milestone 9's own real trap infrastructure
  (which only ever gates dereference/domain-transition instructions,
  never fetch itself). Storing a full `PCC` struct now would therefore
  be genuinely dead state with zero real consumers. `OCInvoke` instead
  extracts only the unsealed code capability's own resolved target
  address (`Base + Offset`, the same real `CGetAddr` semantics already
  established) and redirects PC to it directly — achieving CHERI's own
  real "atomic unseal-and-jump" property literally (a true hardware
  jump in RTL, wired directly into Milestone 9's own trap/`MRET`
  PC-redirect mux) without inventing a storage mechanism nothing yet
  reads. A real `PCC` register and real fetch-time capability
  enforcement remain a distinct, separately-scoped future item — it
  would require changes to the RVA23 base core's own fetch stage, out
  of bounds for `veda_core.tlv`-only work.
- **CHERI's own trailing `PCC`-relocation/fetch-alignment/fetch-bounds
  checks are omitted** (`have_pcc_relocation`, `inCapBounds`,
  `min_instruction_bytes`) — they exist solely to validate a `PCC` this
  design deliberately never stores, so there is nothing for them to
  validate.
- **Cause codes and permission bits activated, not freshly chosen** —
  `VEDA_CORE_SPEC.md` Section 3 had already reserved `cause = 0x04`
  (Type Violation) and `cause = 0x19` (Permit_Invoke Violation) by exact
  value pending this design; Section 2 had already reserved
  `Permit_Invoke`/`Permit_Execute` bit positions. This milestone is the
  first real consumer of both — and the first instruction ever to
  actually trigger `cause = 0x11` (Permit_Execute Violation), reserved
  earlier but never previously exercised.

## Implementation

**Sail** (`veda_cap_insts.sail`, appended after `CUnseal`): `VEDA_OCINVOKE
: (vcapidx, vcapidx)` — no `rd`. Real CHERI's own check order mirrored
exactly: `Tag(cs1)` → `Tag(cs2)` → `Seal(cs1)` → `Seal(cs2)` → matching
`otype` → `Permit_Invoke(cs1)` → `Permit_Invoke(cs2)` → `Permit_Execute
(cs1)` must hold → `Permit_Execute(cs2)` must NOT hold. On success:
`wC(VEDA_IDC_INDEX, unsealed_cs2)` (`VEDA_IDC_INDEX = Vcapno(15)`),
`wCTag(VEDA_IDC_INDEX, true)`, then `jump_to([target with 0 = bitzero])`
using the real, already-established `jump_to()` primitive (`I/jalr_seq.sail`)
— the same real jump mechanism `JALR` itself uses, not a bespoke one.

**RTL** (`veda_core.tlv`): `$is_veda_ocinvoke` decoded at Custom-2's next
`funct7` slot (`0010010`). Reused, not reinvented: `$veda_rs1cap_*`
(cs1, already established since Milestone 3), `$veda_cs2_*` (cs2,
already established for `CSeal`/`CUnseal` in Milestone 6 — extended
this pass with `Object_ID`/`Base`/`Reserved` fields those two
instructions never needed but `OCInvoke` does, since it really copies
cs2's full field set into `c15`, unlike `CSeal`/`CUnseal`'s
type-authority-only use of cs2). `$veda_ocinvoke_violation`/`_cause`
join Milestone 9's own combined `$veda_trap_taken`/`$veda_trap_cause`
signals. **One genuinely new piece of infrastructure this milestone
needed**: `$veda_trap_cap_idx`, a per-family cap-index mux — every
prior "use"-family instruction (Milestone 9) could share one `cap_idx`
signal for `mtval` because each only ever involves a single capability
register; `OCInvoke` genuinely spans two, so the specific one that
actually failed a given check must be reported, exactly matching Sail's
own per-check `veda_trap(rs1 or rs2, ...)` choice. On success,
`c15`'s own `/vreg` write source (`$ocinvoke_wr_en`, fixed to
`#vreg==4'd15`, not `$veda_rd_cap`-indexed like every other write
source in the file) copies cs2's fields with `otype` overridden to
`UNSEALED_OTYPE`; PC redirect (`$veda_ocinvoke_target = cs1.Base +
cs1.Offset`) is wired into the same `$pc_src`/`$alt_pc` mux Milestone 9
built for trap/`MRET`, given real priority over `JAL`/`JALR`/branch (an
`OCInvoke` instruction can't itself be a `JAL`/`JALR`, so this is
non-overlapping, not a priority conflict).

## Result: clean first-pass Sail and RTL builds; two real, distinct positive-test bugs found and fixed — no bugs in the design itself

**Sail**: one real, mechanical fix needed during the build — the first
draft's `struct { cs2 with otype = UNSEALED_OTYPE }` syntax is not valid
Sail struct-update syntax in this codebase; fixed to the same full
field-literal-construction idiom already established and proven for
`OCA`/`CSetBounds`/`CSeal`/`CUnseal` elsewhere in the same file. Not a
correctness bug — a syntax-only fix, caught immediately by the build,
not by test failure.

**Both `vc_ocinvoke.S` (positive) and `vc_ocinvoke_neg.S` (Type
Violation + Permit_Execute Violation) passed on their first real
`sail_riscv_sim` run** once that syntax fix landed — no design bugs
found in Sail.

**RTL**: the core `OCInvoke` decode/execute/jump logic also passed its
own positive and negative tests on the first real Icarus Verilog
simulation run. The two real bugs found this milestone were both in
*test* construction, kept honestly distinct from the zero bugs found in
the design or RTL itself:

- **Test Bug 1**: `veda_smoke_m10.S`'s own first draft placed a
  fall-through failure catcher (`li x20,0xBAD; j fail`) immediately
  after the `.word` encoding for `ocinvoke`, forgetting to actually
  define a real `landing_pad:` label at the intended jump target — an
  `undefined reference to 'landing_pad'` linker error, caught before
  simulation ever ran. Fixed by adding the real label.
- **Test Bug 2**: `veda_smoke_m10_neg.S`'s own trap-and-resume structure
  needed the identical fix `MILESTONE_9_RESULTS.md`'s own Bug 2 already
  documented once — a "trap-didn't-fire" catcher instruction placed at
  the exact PC (`mepc+4`) a *correct* trap's own `MRET` resumes to.
  Recognized immediately from that prior lesson and fixed the same way:
  no separate catcher at that address, the real next test step follows
  directly.

## Full regression: zero impact

**Sail**: `run_veda_selfcheck_tests.sh` — **18/18 passed** (16 prior
tests + `vc_ocinvoke` + `vc_ocinvoke_neg`), zero regressions.

**RTL**: `run_veda_smoke_test.sh` — **18/18 passed** (16 prior tests +
`veda_smoke_m10` + `veda_smoke_m10_neg`), zero regressions, including
the base RV64I core's own unmodified 81-instruction smoke test.

## What the positive test actually proves

`veda_smoke_m10.S`/`vc_ocinvoke.S` mint a real CODE object (Base = the
test's own runtime `landing_pad` address, computed via `la`, not a
compile-time constant — the jump target is the test's own code) and a
real DATA object, seal both under a shared type-authority at a matching
`otype`, then issue one real `ocinvoke`. Execution is only ever observed
at `landing_pad` if the jump genuinely happened — there is no
fall-through path from the `ocinvoke` instruction to that label. Once
there, `c15` is read back via the query family and shown to hold: `Tag=1`
(populated), `otype=0xFFFF` (genuinely unsealed, not still showing the
sealed value), and `Base` equal to the DATA capability's own real,
distinct `Base` (0x80010700, not the CODE capability's `Base`,
confirming it's genuinely `c4` unsealed, not something else). This is
the real, literal "atomic unseal-and-jump" property CHERI's own
`CInvoke` provides — verified end to end, not asserted from the design
document alone.

## Not yet built

A real `PCC` register and real instruction-fetch-time capability
enforcement (the one deliberate, stated scope boundary this milestone
carries forward — see "Design decisions" above); `CSetCID`/`CGetCID`
and `Permit_Set_CID`/`cause 0x1c` (CHERI's own compartment-identifier
mechanism, a distinct, unrelated item); sentry capabilities and
`CSealEntry`/`CJALR`-style fast unsealing-jump (the second `otype`
sentinel CHERI reserves, still out of scope — `OCInvoke` alone already
provides Veda-Core's own real, working protection-domain-transition
primitive, matching CHERI's own text: "`CInvoke` is a primitive upon
which protection-domain switching can be implemented"). With this
milestone, `VEDA_CORE_SPEC.md` Section 6's original seven-item list is
six-sevenths closed — only formal-verification maturity (item 5, a
distant, explicitly-not-recommended-as-near-term aspiration per
`NEXT_STEPS_ROADMAP.md`) remains.
