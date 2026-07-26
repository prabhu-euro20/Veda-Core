# Veda-Core RTL — Milestone 5 Results

**Date:** 2026-07-23
**Scope:** closes a real, honest test-coverage gap left open since Milestone
2 — `NMC_ADD.W` and 8 of Veda-Atomic's 9 ops (`SWAP`/`ADD`/`AND`/`OR`/`MIN`/
`MAX`/`MINU`/`MAXU`; only `AMOXOR` was independently tested in Milestone 2).
No new RTL was written this milestone — the ALU mux, decode, permission
gating, and `elfmem[]` write-back for all of these already existed (verified
by re-reading `veda_core.tlv` before writing any test, not assumed from the
Milestone 2/3 "not yet built" notes, which turned out to overstate the gap
— see below). This milestone is pure verification of already-existing
hardware.

## Why this milestone, not `CSeal`/`CUnseal`

Before deciding what to build next, the actual current RTL state was
checked directly (`grep` against `veda_core.tlv`), not assumed from the
milestone docs' own prose. That check found `$veda_atomic_result`'s ALU mux
already lists all 9 real Zaamo-derived ops, and `NMC_ADD.W`'s own decode
(`$is_veda_nmc_add_w`), permission/bounds gating
(`$veda_nmc_add_w_violation`), and `elfmem[]` write-back (the trailing
`always_ff` block's `else if` branch) all already exist — a genuine,
already-built vertical slice, just never independently exercised by a real
test. That is a different, smaller, more honest category of debt than
`CSeal`/`CUnseal` (which has zero RTL at all — no decode, no ALU logic,
nothing). Leaving real-but-untested logic sitting in a "verified" milestone
would be inconsistent with this project's own repeated finding that
undertested logic is exactly where real bugs hide (`OCA`'s field-copy bug in
Milestone 2, the testbench timing bug in Milestone 3) — the signed
MIN/MAX comparator (`$veda_atomic_lt_signed`) in particular had never been
exercised by any real test until now. Closing this gap first, before
starting the larger, genuinely-new `CSeal`/`CUnseal` RTL, was the
research-backed decision.

## Result: PASS — one real bug found, and it was in the test, not the RTL

### The bug (test-design, caught by an actual failing run, not assumed away)

The first draft of `veda_smoke_m5.S` assumed `NMC_ADD`/Veda-Atomic take a
GPR-supplied offset the way `OCL`/`OCS` do (mirroring how those two
instructions' own tests are written). Running it produced clearly wrong,
*shifted* results — e.g. `ADD`'s reported "old" value (`0x2222`) was
`SWAP`'s own expected *new* value, not anything written at `ADD`'s intended
offset. Rather than patch the assertion values to match whatever came out
(which would have silently hidden a real test-design error), the actual RTL
was re-checked: `$veda_cap_real_addr = rs1cap.Base + rs1cap.Offset` —
`NMC_ADD`/Veda-Atomic address off the capability's own **persistent**
`Offset` field (the "compute-at-memory" cursor, by design — the whole
reason these ops don't take a GPR offset operand at all, unlike `OCL`/
`OCS`'s fresh per-access GPR offset), not a GPR value. `c1`'s `Offset` was
never moved from its bind-time default of `0`, so every atomic op in the
first draft actually executed at `c1.Base+0`, regardless of where the
matching `OCS.D` had just written. **The RTL was correct the entire time —
this was the test's own addressing-mode assumption, wrong from the start,
not an RTL regression.** Fixed by using `OCA` (already RTL-verified in
Milestone 2) to walk `c1`'s own `Offset` cursor forward in fixed `+8` steps
between ops — which also happens to match the real, intended usage pattern
for these instructions (position via `OCA`, then dispatch a compute-at-
memory op right where the cursor now sits), not just a testing workaround.

### Verified results (`sim/veda_smoke_m5.S`, `tb_veda_smoke_m5.sv`)

All values below matched on the corrected test's first real run:

- **`NMC_ADD.W`** (via `c0`, `Object_ID=1`, has `Permit_NMC_Compute`):
  `x10 = 0xFFFFFFFF80000000` — the old 32-bit value (`0x80000000`, sign bit
  set) correctly sign-extends into a 64-bit `rd`, real logic
  (`{{32{cap_old_w[31]}}, cap_old_w}`) never exercised before this.
  `x11 = 0xCAFEBABE80000020` — the write-back correctly touched only the
  low 4 bytes (`0x80000000 + 0x20 = 0x80000020`), leaving the upper 4 bytes
  (`0xCAFEBABE`) genuinely untouched.
- **Veda-Atomic, all 8 remaining ops** (via `c1`, `Object_ID=2`, Load+Store
  only — deliberately *without* `Permit_NMC_Compute`, which also reconfirms
  Atomic's real permission gate is Load+Store, not NMC_Compute, by
  construction):
  `SWAP: old=0x1111 new=0x2222`, `ADD: old=0x5 new=0xF`,
  `AND: old=0xFF new=0xF`, `OR: old=0xF0 new=0xFF` — straightforward, all
  exact.
  `MIN: old=0xFFFFFFFFFFFFFFFF new=0xFFFFFFFFFFFFFFFF` (signed `-1 < 1`,
  keeps old), `MAX: old=0xFFFFFFFFFFFFFFFF new=0x1` (signed `-1 < 1`, takes
  the smaller argument's *complement* — `MAX` takes `rs2`), `MINU:
  old=0xFFFFFFFFFFFFFFFF new=0x1` (same bit pattern, **unsigned**
  interpretation: `0xFFFF...FFFF` is the larger value, so `MINU` takes
  `rs2`), `MAXU: old=0xFFFFFFFFFFFFFFFF new=0xFFFFFFFFFFFFFFFF` (unsigned:
  `0xFFFF...FFFF` is already the larger value, keeps old) — the identical
  bit pattern (`0xFFFF...FFFF`/`1`) genuinely produces opposite outcomes
  between the signed and unsigned op pairs, a real, meaningful confirmation
  that `$veda_atomic_lt_signed`'s sign-bit-based comparator and the
  unsigned `<`/`>` comparisons are both independently correct, not
  coincidentally matching.
- **Negative check** (new, not run before): `NMC_ADD.W` via `c1`
  (`Object_ID=2`, no `Permit_NMC_Compute`) — `x28` stays `0x5555`,
  confirming `$veda_nmc_add_w_violation` (a signal distinct from
  `$veda_nmc_add_d_violation`, which was the only one Milestone 2's own
  negative test actually exercised) genuinely blocks the write on its own.

### Full regression: zero impact

All of Milestones 1–4's own tests (9 positive/negative programs) and the
base RV64I core's own unmodified 81-instruction smoke test were re-run
against the final build — **12 real test programs through one script**
(`run_veda_smoke_test.sh`), zero regressions.

## Design notes worth recording

- **A real, useful distinction**: this milestone's one real bug was in the
  *test*, not the RTL — worth stating plainly rather than folding it into
  the same "real bug found and fixed" language used for Milestones 2/3's
  actual RTL bugs. The RTL's own behavior was correct and consistent
  throughout; verifying that required correctly understanding the real
  addressing-mode distinction between OCL/OCS (fresh GPR offset) and
  NMC_ADD/Atomic (capability's own persistent cursor) — already documented
  in this file's own comments, but not internalized correctly on the first
  attempt.
- **`MILESTONE_2_RESULTS.md`/`MILESTONE_3_RESULTS.md`'s own "not yet built"
  language was imprecise**, worth correcting here rather than silently
  carrying the imprecision forward: the *hardware* for `NMC_ADD.W` and the
  8 untested atomic ops was already built in Milestone 2 (a natural
  consequence of one shared ALU mux covering all op values, and one shared
  decode/write-back path covering both widths) — only the *test coverage*
  was deferred. Future milestone docs should distinguish "no RTL exists"
  from "RTL exists but is untested" explicitly, since they carry very
  different risk.

## Not yet built

`CSeal`/`CUnseal` and sealed-capability enforcement in RTL (genuinely zero
RTL exists for these — no decode, no ALU logic; needs a new operand pattern,
a second *capability*-register operand, not yet used anywhere in this file)
remains the next real, deferred milestone. Real trap/exception
infrastructure and any privilege-raising mechanism remain out of scope per
earlier milestones' own decisions.
