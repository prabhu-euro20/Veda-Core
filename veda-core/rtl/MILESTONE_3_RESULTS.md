# Veda-Core RTL — Milestone 3 Results

**Date:** 2026-07-23
**Scope:** the Veda-Cap query family (`CGetBase`/`Len`/`Perm`/`Tag`/`Type`/
`Addr`/`Offset`) and `CSetBounds`/`CSetBoundsExact` — real, working
TL-Verilog RTL, on top of Milestones 1/2's Capability Register
File/Object-Bind/`OCL.D`/`OCS.D`/`OCA`/`NMC_ADD`/Veda-Atomic. Scoped
deliberately to these two instruction groups only, not `CSeal`/`CUnseal`
or `ODT-Populate`/`ODT-Destroy` — see the decision below.

## Real scoping decision made before writing any code

This core's RTL has **no privileged architecture at all** (no CSRs, no
privilege-mode register) — confirmed by re-checking the base core before
starting, not assumed. `ODT-Populate`/`ODT-Destroy`'s real M-mode-only
gate (`VEDA_CORE_SPEC.md` §5.1, and `MILESTONE_PLAN.md`'s own Milestone 1
decision) would currently be checking against a privilege concept that
doesn't exist in this RTL yet. Building privilege infrastructure just to
make that one gate meaningful would be the identical disproportionate
scope creep already ruled out once for trap handling. `CSeal`/`CUnseal`
also need a genuinely new operand pattern (a second *capability* register
operand, not a GPR) not yet exercised in this RTL. Given that, Milestone 3
scoped to the two instruction groups that reuse patterns already built and
tested: the query family (read-only, same shape as `OCL`'s read side) and
`CSetBounds`/`Exact` (soft-fail copy-then-override, the exact skeleton
already fixed once for `OCA`). `CSeal`/`CUnseal` and
`ODT-Populate`/`ODT-Destroy` become Milestone 4, once the privilege
question gets real, unhurried treatment rather than a rushed answer here.

## Result: PASS — one real bug in test setup (not RTL) found and
corrected, then both positive and negative paths verified

### Query family (`sim/veda_smoke_m3.S`, combined with `CSetBounds`)

All 7 queries against an `OCA`-positioned `c1` returned exact values on
the first real test run:

```
base=0x80010000 len=0x40 perm=0x100c tag=1 type=0xffff addr=0x80010010 offset=0x10
```

### `CSetBounds` (same test)

`csetbounds c2, c0, 0x20` (narrowing to a fresh window) followed by 4
queries against `c2`. **The first run showed `c2`'s `Tag` reading back as
`0`, everything else correct** — diagnosed with a real per-cycle debug
trace (`CPU_veda_csetbounds_ok_a0`, `CPU_Vreg_tag_a0[2]`) rather than
guessed at. The trace showed `c2.Tag` genuinely becoming `1` the cycle
after `CSetBounds` executed and staying `1` — the RTL was correct. The
real cause was the **testbench**: `CGetTag`'s own writeback lands one
cycle after it occupies `@0`, and the test's fixed cycle budget ended
exactly one cycle too early to observe it — the identical class of
"ran one cycle short" issue already hit and fixed once in the Sail V-C
self-check work. Fixed by extending the cycle budget, not by touching any
RTL. Re-run: all 4 queries against `c2` exact
(`base=0x80010000 len=0x20 offset=0x0 tag=1`).

### Negative control (`sim/veda_smoke_csetbounds_neg.S`)

A requested `Length` exceeding `c0`'s own remaining window correctly
soft-fails: `c2.Tag` reads back `0`, no trap — verified via `CGetTag`
itself (the query family doubling as its own verification instrument,
now that it exists).

### Full regression: zero impact

All of Milestones 1 and 2's own tests (2 positive, 3 negative) and the
base RV64I core's own unmodified 81-instruction smoke test were re-run
against the final Milestone 3 build — 8 real test programs through one
script (`run_veda_smoke_test.sh`), zero regressions.

## Design notes worth recording

- The query family, once built, became its own verification tool —
  `CSetBounds`'s negative control was checked by reading `c2`'s `Tag`
  through `CGetTag` itself, rather than only through testbench-internal
  signal introspection (`dut.CPU_Vreg_tag_a0[...]`). This is a real,
  concrete step toward RTL tests that verify *through the ISA itself*
  rather than only through simulator-internal signals.
- `/vreg`'s write logic now has three independent sources (`Bind`, `OCA`,
  `CSetBounds`), each targeting the same shared `$veda_rd_cap` index —
  extended carefully field-by-field from the two-source version Milestone
  2 already established, reusing the exact "copy every field from rs1,
  override only what changes" pattern the `OCA` bug fix already proved
  correct.
- `CSetBoundsExact`'s own real distinction from `CSetBounds` (rounding vs.
  trapping on a non-representable bound) still doesn't materialize in this
  design (no bounds compression exists to make it meaningful) — both
  decode to their own real, distinct `funct7` values but share one
  execute path, the same honest conclusion already reached once in Sail.

## Not yet built

`CSeal`/`CUnseal` and sealed-capability enforcement (no capability can be
sealed in RTL yet), `ODT-Populate`/`ODT-Destroy` (pending the privilege-
architecture question above), `NMC_ADD.W`, the remaining 8 Veda-Atomic
ops, and real trap/exception infrastructure. All real, deferred, later
milestones.
