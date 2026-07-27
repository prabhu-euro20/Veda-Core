# Real Cycle-Count Study: Capability-Register Working-Set Pressure

**Date:** 2026-07-26
**Motivation:** the previous DRAM/TCM study found Veda-Core's overhead is
fixed for a bind-once-reuse-many pattern but scales as `E×N` for a
repeated-rebind pattern — conditioned entirely on how many distinct
objects compete for the 16 real capability registers. This was flagged as
the single most decision-relevant open question and is answered here with
a real, simulated-and-then-executed experiment, not assumed.

## Methodology

`k` distinct objects, each a real, separately-populated object, accessed
in round-robin order (obj0, obj1, ..., obj(k-1), repeated for 4 rounds).
Object `i` is always addressed via capability register `c(i mod 16)` — the
same assignment an optimal compiler register-allocator would use (never
worse than this; this is the *best case* for a given `k`, not a
pessimistic one). Whether a given touch needs a real, fresh `Bind` (i.e.,
the register currently holds a *different* object) was computed by
**simulating the exact round-robin schedule** — tracking which object last
occupied each of the 16 slots — not assumed from a formula, then verified
against real executed cycle counts on the actual, unmodified, committed
`veda_core.tlv`.

Four points: `k=8` (half capacity), `k=16` (exactly at capacity, zero
aliasing possible), `k=17` (one object over — exactly one aliasing pair),
`k=32` (double capacity — full aliasing, worst case). A traditional-core
(`rv64i_core.tlv`) baseline runs the identical round-robin access pattern
via plain `ld` for reference.

A real bug was found and fixed before trusting any result: the first
`Object_ID` numbering (`30+i`) collided with the RTL's own pre-seeded,
already-owned `Object_ID=60` fixture at `k=32` — the same collision class
already hit twice earlier in this project (Milestones 13 and 14). It
produced a real hang (owner-violation trap into an uninstalled handler),
caught via a timeout, not a silent wrong answer. Fixed by moving the ID
base to 100.

## Real results, every row's sum independently verified correct

| k | traditional cycles | Veda-Core cycles | real binds / total touches | veda/traditional ratio |
|---|---|---|---|---|
| 8 | 129 | 153 | 8 / 32 (25%) | 1.186 |
| 16 | 257 | 305 | 16 / 64 (25%) | 1.187 |
| 17 | 273 | 336 | 23 / 68 (34%) | 1.231 |
| 32 | 513 | 801 | 128 / 128 (100%) | 1.561 |

Traditional cycles-per-touch is flat across every `k` tested (4.03, 4.02,
4.01, 4.01) — expected and confirmed: plain addressing has no
capacity-dependent behavior, any of 32 GPRs reaches any of 2^64 locations
directly, so `k` cannot affect it.

## The real finding: not a cliff, a graceful slope proportional to the aliasing fraction

At `k=8` and `k=16` — both at or under the real 16-register capacity — the
overhead ratio is **identical** (1.186 vs 1.187), because the fraction of
touches needing a real bind is identical (25% in both cases: exactly one
bind per object, ever, regardless of how close to 16 that object count
is). This confirms the earlier "fixed one-time setup cost, reused for
free" finding holds *all the way up to the real hardware limit*, not just
for small `k`.

Past 16, the overhead does **not** jump discontinuously — it rises in
proportion to how many objects actually alias. `k=17` has exactly one
aliasing pair (objects 0 and 16 sharing register `c0`), so only those two
objects lose their reuse benefit; the ratio rises modestly, 1.187→1.231.
`k=32` fully oversubscribes every register 2:1, so *no* object ever keeps
its binding between touches — every single touch needs a real bind, and
the ratio rises to 1.561. The real, quantitative rule this data supports:
**overhead scales with the *fraction* of the working set that exceeds 16,
not with a step function at 16.**

## What this means, combined with the earlier DRAM/TCM finding

The two studies now form one coherent picture. Object-centric access is
close to free (≈19% overhead, and falling as N grows per the very first
benchmark) whenever a program's real working set of simultaneously-hot
objects fits in 16 capability registers — true regardless of whether that
working set is 8 or all the way up to 16. It degrades smoothly, not
catastrophically, as the working set exceeds 16, scaling with *how far*
over capacity the program runs, capped at roughly the same order-of
-magnitude overhead the DRAM/TCM study's worst rebind case showed. A
program with a genuinely large object working set (dozens to hundreds of
simultaneously "hot" objects) — not tested here, a real, honest limit —
would be expected to continue this same trend, and is the natural next
data point.

## Honest scope limits

- Only linear round-robin access was tested. Real programs' object access
  patterns (temporal locality, clustering, one-shot vs. hot objects mixed
  together) will produce a different real aliasing fraction than pure
  round-robin, which is close to a worst-case-uniform assumption for a
  given `k`.
- Register assignment (`i mod 16`) assumes an optimal allocator; a real
  compiler's actual allocation policy for Veda-Core's custom ISA does not
  exist yet (no compiler backend targets these instructions), so this is
  a best-case bound, not a measured real-compiler number.
- Single-cycle microarchitecture only, same caveat as every other study
  in this project to date.

## Reproducing this

`/tmp/claude-.../scratchpad/regpressure/` (session-scoped, not committed):
`gen_pressure.py` (simulates the real bind/no-bind schedule and emits the
Veda-Core program), `gen_traditional.py` (baseline), `run_pressure.sh`
(builds both real cores once, runs all four `k` points, verifies sums).
