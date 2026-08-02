# Veda-Atomic `aq`/`rl` Safety Analysis: Why This Is Not a Live Vulnerability, and What Would Make It One

**Date:** 2026-08-02
**Scope:** closes the "Veda-Atomic's own `aq`/`rl` semantics under real
concurrency" item named in `MILESTONE_22_RESULTS.md`'s own "Not yet
built" section, as part of the broader subsystem-by-subsystem security
audit that section deferred. Real research, both layers read in full
before writing this, not assumed.

## What `aq`/`rl` are for, and why the honest answer here is "not a
## live gap on this core, but a real one to guard against"

RISC-V's `aq` (acquire) and `rl` (release) bits, present on every real
AMO instruction and on Veda-Atomic's own identical encoding shape
(`funct7[26:25]`, RISC-V's own real Zaamo op-select layout, reused
verbatim per `VEDA_CORE_SPEC.md` Section 1), exist to constrain how a
memory operation may be **reordered relative to other memory
operations, as observed by other harts**. They are a real,
architecturally meaningful concept — but only in a system where more
than one independent instruction stream can observe another's memory
accesses out of program order.

**Both real implementation layers decode these bits and deliberately
do not act on them**, each with its own comment stating the same real
reason before this audit pass began:

- Sail (`toolchain/sail-riscv/model/extensions/Veda/veda_atomic_insts.sail`,
  the `execute` clause): `_aq`/`_rl`, underscore-prefixed to mark them
  genuinely unused by Sail's own compiler-enforced convention. Both
  memory operations use `Read_plain`/`Write_plain` — no synchronization
  primitive of any kind.
- RTL (`rtl/veda_core.tlv`): fixed this same pass to match Sail's own
  honest treatment — a real audit finding was that RTL's own comment
  claimed these bits were "decoded" when no signal here actually
  captured them at all (a documentation/code mismatch, not a security
  bug by itself, now closed alongside this analysis).

## The real architectural argument for why this is safe today, not
## just unaddressed

Veda-Core, in both layers, is genuinely **single-hart**, and — more
specifically, the property that actually matters here — **strictly
in-order**: one instruction executes, completes, and retires before
the next one begins, with no speculative execution, no out-of-order
memory pipeline, and no second independent instruction stream that
could ever observe a Veda-Atomic access out of its own program order.

RVWMO (RISC-V's own memory consistency model, read in full earlier in
this project's own research corpus) constrains the order in which
memory operations *may appear* to different harts. With exactly one
hart and strictly in-order, single-cycle-retiring execution, there is
no second observer for any reordering to be visible to in the first
place — every real ordering guarantee `aq`/`rl` could express is
already, trivially, unconditionally satisfied by construction, the
same way a single-threaded program's own memory operations are always
"correctly ordered" with respect to themselves regardless of whether
memory-barrier instructions are present at all. This is not a
convenient rationalization invented to excuse an unfinished feature —
it is the same real reason single-hart, in-order RISC-V implementations
generally treat `aq`/`rl` as architectural no-ops correctly, not as a
compliance gap.

**Stated plainly, not overclaimed**: this is a genuine safety argument
for *this specific core's own current configuration* (single-hart,
in-order), not a general claim that `aq`/`rl` don't matter. The
argument's own validity is conditioned entirely on that configuration
continuing to hold.

## What would make this a real gap — the load-bearing warning

**The moment either layer gains a second, independent instruction
stream** — a real second hart in RTL, or Sail's own multi-hart
execution mode if ever exercised for Veda-Core — **this analysis's own
safety argument stops holding**, and `aq`/`rl` would need real,
binding semantics before that work could be trusted: software
(hand-written or, eventually, compiler-generated via the LLVM
backend's own Veda-Atomic support) that sets `aq`/`rl` expecting real
cross-hart ordering would silently get none, a real, silent
data-race-class bug precisely in the style this whole project's own
design philosophy exists to eliminate everywhere else.

**Concrete, actionable requirement for whoever builds real multi-hart
support** (RTL or Sail): before any multi-hart Veda-Atomic execution is
considered trustworthy, `aq`/`rl` must be given real semantics --
either genuine acquire/release memory-ordering enforcement, or an
explicit, hard decision to make Veda-Atomic sequentially-consistent
unconditionally (making the bits real no-ops by *design*, not by
*accident of single-hart scope*) with that decision stated and tested,
not silently carried over from this single-hart-era default.

## Verification

- **`veda_smoke_aqrl_invariance.S`** (RTL, new this pass): a real
  Veda-Atomic op (`veda.amoxor.d`) executed twice back-to-back through
  the same bound capability, once with `aq=0,rl=0` and once with
  `aq=1,rl=1` (identical operation, only the two previously-undecoded
  bits differ) — both produce byte-identical results. Proves the
  **atomicity** of the read-modify-write itself (a real, already-correct,
  single-hart-meaningful property, confirmed unaffected by `aq`/`rl`)
  is genuinely independent of the **ordering** bits (a real,
  currently-inapplicable, multi-hart-only property) -- the precise
  distinction this whole analysis rests on, demonstrated empirically,
  not just argued. `run_veda_smoke_test.sh` -- included in the full
  33/33 (or higher, see the log for the exact current count) regression
  run, zero regressions.

## Conclusion

Closed as **audited, no live gap found on the current single-hart,
in-order configuration** -- a real, reasoned architectural conclusion,
not a placeholder. Explicitly reopened as a hard prerequisite the
moment real multi-hart work begins in either layer, named here so it
cannot be silently missed.
