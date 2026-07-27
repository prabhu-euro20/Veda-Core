# Veda-Core RTL Milestone 16: ODT Generation-Wraparound Retirement (Real Bug Fix)

**Date:** 2026-07-27

## The real bug, found via empirical reproduction, not code review alone

`ARCHITECTURE_IMPROVEMENT_FINDINGS.md` Finding 2: the RTL's 8-bit
`generation` counter, empirically confirmed to wrap after exactly 256
`ODT-Destroy` operations on the same slot, creates a real ABA-problem
use-after-free false negative. A capability cached before the wrap can
pass the staleness re-check again once the counter wraps back to its old
cached value, silently granting continued access to memory it should have
lost the moment the object was first destroyed. Reproduced directly:
destroyed the same `Object_ID` 256 times, then re-populated the slot with
a different real object; the *original*, never-re-bound capability
successfully dereferenced memory through the staleness check as if
nothing had happened.

## Why the obvious fix (saturate instead of wrap) is not sufficient — reasoned through before writing any RTL

Simply freezing the counter at `0xFF` instead of wrapping back to `0`
does not close the vulnerability — it makes it *worse* in one respect:
every future re-populate of that slot would also land on `0xFF`, making
every incarnation from that point on permanently indistinguishable from
every other, rather than only periodically (every 256 cycles) as before.
The real fix needs a second bit: once generation would wrap, the slot is
**permanently retired** — no future `ODT-Populate` may ever target it
again — rather than reusing `0xFF` forever.

## The fix

Uses 1 bit of byte `+13`, real, allocated-but-unused space remaining
after Milestone 15's own use of bytes `+11`/`+12` (three full spare bytes
were left). `ODT-Populate`'s own generation-bump computation now freezes
at `0xFF` instead of wrapping, and simultaneously sets a `retired` bit
once that freeze point is reached (on either a `Destroy` or a
still-valid re-`Populate`). A retired slot's own `ODT-Populate
_violation` signal — the same one that already gates M-mode/ODA
privilege — now also fires for any future populate attempt, reusing the
established soft-no-op-on-violation write path with no new plumbing.

## Verification

- **Negative test** (`veda_smoke_m16_neg.S`): reproduces the exact
  256-destroy wraparound scenario; confirms the fix delivers a real hard
  trap on the stale capability's later use, instead of the old silent
  continued access. **PASSED.**
- **Positive test** (`veda_smoke_m16.S`): confirms the fix rejects only
  slots that have genuinely exhausted their real generation counter —
  five real destroy/re-populate cycles on the same `Object_ID` (far under
  the 255-reuse threshold) still work completely normally. **PASSED.**
- **Full Veda-Core RTL milestone suite** (all 27 positive/negative smoke
  tests, Milestones 1-16 combined): re-run against the fully-updated
  core. **27/27 passed, zero regressions.**
- **Full ACT4 RV64I conformance suite**: re-run against the fully-updated
  core. **51/51 passed, zero regressions.**

## Honest, real cost of this fix — stated plainly, not glossed over

An ODT slot can now only be destroyed-and-repopulated 255 times before
being permanently retired (never usable again for a new object). This is
a real, meaningful practical limit for any single Object_ID under
frequent churn — the price of eliminating the ABA vulnerability entirely,
the same real engineering tradeoff shape as write-endurance limits in
flash memory or poison bits in real cache-coherence protocols. Widening
the generation field itself (a much larger change, since `Reserved` is
also a field inside the 128-bit capability register struct, not just the
ODT entry) would remove this limit but was not attempted this milestone.

## Update — the Sail mirror is now done, verified, and real (not a mechanical port)

The structural blocker below was real when first found, but resolved: the
project's own toolchain already contained a complete, working OPAM-based
Sail install (`toolchain/opam-root/`, missed in the first search) — no new
tooling was needed after all, only finding what already existed. A real
rebuild of `sail_riscv_sim` was confirmed clean against the *unmodified*
model first (24/24 self-check tests passed, proving the toolchain itself
introduced no regression before any source was touched).

The fix was then mirrored — `odt_entry` gained a `retired : bool` field
(`veda_types.sail`); `VEDA_ODT_POPULATE`/`VEDA_ODT_DESTROY`
(`veda_ocl_insts.sail`) now freeze `generation` at `0xff` instead of
wrapping and set `retired` at the same point the RTL does; a retired
slot's own `ODT-Populate` now raises `Illegal_Instruction()` (matching
this same instruction's own existing convention for its other real
failure mode, privilege) instead of silently succeeding. All 8 real
`odt_entry` struct-construction sites across the extension (5 reset seeds,
`empty_odt_entry`, `VEDA_ODT_POPULATE`, `VEDA_ODT_DESTROY`, and Bind's own
`claimed_entry`) were updated — Sail's own strong typing made this
exhaustive by construction, a missed site would have been a compile
error, not a silent gap.

Two new real self-check tests were added and passed on the first run:
`vc_gen_retire_neg.S` (reproduces the exact 256-destroy wraparound
scenario; confirms the re-populate attempt is now refused with
`mcause=2`/Illegal Instruction, and the original stale capability still
correctly hard-traps with `cause=0x02`/Tag Violation) and `vc_gen_retire.S`
(positive control — five real destroy/re-populate cycles, far under the
255-reuse threshold, still round-trip a real write-then-read correctly).
**Full self-check suite: 26/26 passed, zero regressions** (24 pre-existing
+ 2 new).

## What remained open before this update — kept for the historical record

Unlike Finding 1, this one is real for Sail too: `veda_types.sail`'s own
`generation : bits(8)` uses plain Sail bitvector addition
(`veda_ocl_insts.sail` lines 340/369, `old_entry.generation + 1`), which
wraps at 256 exactly like the RTL did before this milestone.

But mirroring the RTL fix into Sail is **not just a mechanical port** —
checked directly against this project's own prior research
(`SCALING_BARRIERS_RESEARCH.md` §3/6) before deciding anything: the 8-bit
width itself was a **deliberate** choice, matching real, published
CHERI-D precedent (Wang et al., Cambridge, arXiv 2606.19055), which
**accepts** generation wraparound as a statistically-rare residual risk
(empirically derived from real C/C++ allocator reuse-frequency traces),
not an oversight to be closed. That same research honestly flags the
open question: "CHERI-D's real 8-bit choice was empirically derived from
... a workload context Veda-Core has no equivalent of."

**Decision, reasoned through rather than silently deferred**: this
milestone's RTL fix (permanent slot retirement) is a deliberate
*strengthening* beyond CHERI-D's own accepted-risk baseline, justified
specifically because (1) Veda-Core's own stated design priority is
security over throughput/compatibility — a different tradeoff position
than CHERI-D's own broader-deployability goals — and (2) this project now
has a *real, empirically demonstrated* exploit on its own RTL, not merely
a theoretical risk, which is a stronger basis for closing it than
CHERI-D's own statistical argument for accepting it. The RTL fix stands
as the right choice for this project specifically, not a claim that
CHERI-D's own real design is wrong for its own context.

**Real, structural blocker for actually mirroring this into Sail,
verified directly rather than assumed**: the Sail-to-C compiler itself is
not available in this environment — confirmed by editing a `.sail` file
and running `make c_emulator/sail_riscv_sim` in
`toolchain/sail-riscv/build/`, which completed with no output and exit
0, indicating the build system does not even track `.sail` sources as a
dependency for the pre-built emulator binary here. The real Sail
compiler (a separate, non-trivial OCaml/OPAM toolchain) would need to be
installed before any Sail-side change could be verified to the same
standard as the RTL fix — the same category of decision as installing
Yosys earlier this session, requiring the same explicit authorization,
not done unprompted. Making an untested Sail-side edit without this would
violate this project's own established "verify before deciding"
discipline, so it was not attempted.
