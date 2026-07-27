# Real Security A/B Comparison: Traditional RV64I vs Veda-Core Object-Centric Access

**Date:** 2026-07-26
**Motivation:** every prior empirical study in this project
(`OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`, `DRAM_TCM_LATENCY_STUDY.md`)
measured Veda-Core's *cost* against a traditional core. None measured its
claimed *benefit* — the actual reason `DESIGN_SOUL_AND_UNIQUENESS.md` states
this architecture optimizes for security over throughput in the first
place. This study closes that gap with two real, concrete attack scenarios,
run on both the real, unmodified, committed `rv64i_core.tlv` and
`veda_core.tlv` — not asserted, executed.

## Methodology

Two classic vulnerability shapes, each run on both cores, same off-by-one
bug injected identically in both versions so the only variable is the
memory-access mechanism (matching the same isolation principle the earlier
benchmark used):

1. **Out-of-bounds read (secret leak)**: an 8-element array is immediately
   followed in memory by a `secret` value. A loop meant to process 8
   elements instead runs 9 times (the injected bug), reading one element
   past the array's end.
2. **Out-of-bounds write (adjacent corruption)**: the same shape, but a
   `canary` value follows the array and the loop *writes* attacker-value
   `0xBAD0BAD0BAD0BAD0` for 9 iterations instead of 8.

Veda-Core's versions bind the 8-element array as a real object with
`Length=64` (exactly 8 dwords, no slack) before the loop, via `ocl.d`/
`ocs.d` instead of `ld`/`sd` — otherwise identical logic, identical bug.
Real cause code verified against Sail source before running anything
(`veda_ocl_insts.sail`: `offset + width > cap.Length` → `VEDA_CAUSE_BOUNDS_VIOLATION`,
`veda_bind_insts.sail`: `= 0b00001 = 0x01`), not assumed.

## Real results — all four cases, register and memory state directly inspected

| Program | Core | X7 (register) | Trapped? | Memory at target |
|---|---|---|---|---|
| `trad_read_leak` | traditional | `0xdeadbeefcafebabe` | no | secret = `0xdeadbeefcafebabe` |
| `veda_read_leak` | Veda-Core | `0x8` (legit last value) | **yes**, cause verified | secret = `0xdeadbeefcafebabe` (never read) |
| `trad_write_corrupt` | traditional | `0xbad0bad0bad0bad0` | no | canary = `0xbad0bad0bad0bad0` (**corrupted**) |
| `veda_write_corrupt` | Veda-Core | `0xbad0bad0bad0bad0` | **yes**, cause verified | canary = `0x1111111111111111` (**untouched**) |

For both Veda-Core runs, `x22` (a sentinel the trap handler alone sets)
read back `0x600D`, confirming the trap fired for the *specific* verified
reason (`mcause=0x18`, `mtval=0x01` — Bounds Violation on `c0`), not some
other accidental fault.

## What this real result actually establishes

The traditional core reads/writes silently past the array boundary in
both cases — there is no bounds concept anywhere in the base RV64I ISA, so
nothing *can* stop it at the hardware level. Veda-Core's object model
traps the 9th access before it ever reaches the secret or the canary, in
both directions (load and store), confirmed via real register and real
memory inspection, not just a printed "PASS."

## A critic's-eye look at what this does *not* establish — stated plainly

**This is an ISA-floor comparison, not a full-system comparison.** The
traditional core here has zero mitigations modeled — no compiler stack
canaries, no ASLR, no MMU/PMP page permissions, nothing. A real production
RV64I system would layer *some* of those on top. This study does not claim
Veda-Core beats a fully-mitigated real system; it claims something
narrower and more precise: **the RV64I ISA itself provides no memory-safety
guarantee — every protection is a software or OS-level add-on, optional
and bypassable if misconfigured. Veda-Core's guarantee is unconditional
and at the ISA level: it is not possible to construct a plain `ocl.d`/
`ocs.d` access that reads or writes outside an object's declared `Length`,
regardless of what software does.**

**The real, deeper reason this matters — not just "traditional has zero
protection"**: even where real systems do add protection, the standard
mechanism (MMU/PMP page permissions) works at page granularity — typically
4 KiB. An 8-element (64-byte) array overflowing into an adjacent 8-byte
value sits *inside a single page* in virtually every real deployment; an
MMU cannot see or stop this class of bug by construction, no matter how
well-configured. This is not a novel claim — it is exactly why real,
production stack-canary and ASAN-style tooling exists as a *software*
patch for a gap real hardware MMUs structurally cannot close. Veda-Core's
object-granularity bounds check (down to 1 byte, per `Length`) closes
precisely this gap at the hardware level, which no MMU-based real system
does today. This is the study's real, load-bearing finding — not "Veda-Core
has a trap," but "Veda-Core catches a vulnerability class real, deployed
MMU-based hardware structurally cannot."

**What was not tested, honestly**: only linear out-of-bounds read/write
was exercised here. Veda-Core's other four `veda_check_access` checks
(Tag, generation-staleness, Seal, Permission) each guard a *different*
real vulnerability class — respectively: use of a freed/never-bound
capability, use-after-free via a destroyed-and-recreated object (the
generation mechanism specifically), execution/type confusion via a sealed
capability, and read/write-permission violations — none of which were
empirically demonstrated here, only asserted to exist by prior milestones'
own passing tests. A rigorous next step, not yet done, would build the
same kind of concrete before/after A/B demonstration for at least the
use-after-free case (generation-staleness), since that is arguably the
second most common real-world memory-safety vulnerability class after
plain bounds overflows.

## Reproducing this

`/tmp/claude-.../scratchpad/security/` (session-scoped, not committed):
`trad_read_leak.S`, `veda_read_leak.S`, `trad_write_corrupt.S`,
`veda_write_corrupt.S`, `tb_sec.sv` (generic register/memory-dump
testbench, `+check_addr` plusarg computed per-program via `nm`, never
hardcoded), `build_and_run.sh`.
