# Veda-Core RTL — Milestone 8 Results

**Date:** 2026-07-25
**Scope:** `Rebind`/`Bind-NoTrap` — the two remaining Object-Bind modes
(`veda_bind_mode`), real in Sail since Milestone V-A/B but never branched
on in RTL until now (`NEXT_STEPS_ROADMAP.md`'s last open Tier 1 item).
`Rebind` in particular is the concrete mechanism that makes this
project's own headline design claim — *"the MSA can silently relocate an
object without the CPU knowing"* — literally provable in RTL, not just
Sail.

## Ground truth used, not re-derived

`toolchain/sail-riscv/model/extensions/Veda/veda_bind_insts.sail`'s own
`VEDA_BINDINST` execute clause, read in full before writing any RTL:

- **`Bind` (mode=00)**: on an ODT hit, populate every field fresh from the
  ODT entry, `Offset=0`, `otype=UNSEALED_OTYPE`, `Tag=1`. On a miss,
  **hard-traps** (`veda_trap`, cause `0x05`).
- **`Bind-NoTrap` (mode=01)**: identical to `Bind` on a hit. On a miss,
  writes `zero_capability` + `Tag=0` instead of trapping (soft-fail).
- **`Rebind` (mode=10)**: reads the capability register's OWN current
  contents (`rd`, not `rs1`) first. If already sealed
  (`isSealedCap`, i.e. `otype != 0xFFFF`), soft-fails: `Tag=0`, no other
  field touched (`wC` is never called on this path at all). Otherwise, on
  an ODT hit, refreshes `Object_ID`/`Base`/`Length`/`Perms`/`otype`
  (`=UNSEALED_OTYPE`)/`Reserved` (`=`generation) from the ODT, **but
  leaves `Offset` completely untouched** — this is the entire reason
  `Rebind` exists (`VEDA_CORE_SPEC.md` Section 4: *"Offset preserved
  across relocation"*). On an ODT miss, soft-fails the same way as the
  sealed case: `Tag=0`, every other field left exactly as it was.
- **`Bind-Reserved` (mode=11)**: `Illegal_Instruction()` in Sail.

## A real, previously-undetected gap closed as part of this milestone

`$veda_bind_mode` was decoded back in Milestone 1 (`$instr[21:20]`) but
never actually checked anywhere — `$bind_wr_en` fired for *any*
`$is_veda_bind`, regardless of mode. This meant every mode value,
including `10` (`Rebind`) and `11` (reserved), silently executed as plain
`Bind` the entire time RTL Milestones 1–7 existed. A `veda.rebind`
instruction issued against this RTL would have wrongly reset the target
capability's `Offset` to `0` exactly like a fresh `Bind` — defeating
`Rebind`'s entire purpose before this milestone even started. Found by
re-reading the file's own decode comment (*"Decoded but not yet
consumed... this milestone only implements plain Bind"*) against what the
write-enable logic actually gated on, not by a failing test — closed by
splitting `$is_veda_bind` into `$is_veda_bind_plain`/
`$is_veda_bind_notrap`/`$is_veda_rebind`, and restricting `$bind_wr_en` to
only the first two.

## Implementation

- **`Bind` vs `Bind-NoTrap`**: this RTL has no trap infrastructure at all
  (the same honest floor stated in every milestone since the first) — a
  violation has only ever suppressed the write, which is *already*
  exactly `Bind-NoTrap`'s own soft-fail convention. The two modes are
  decoded as distinct signals (`$is_veda_bind_plain`/
  `$is_veda_bind_notrap`, for documentation clarity and so real trap
  infrastructure could later split them for real), but share
  `$bind_wr_en`'s existing write path unchanged.
- **`Rebind`**: a genuinely new write shape, not a variant of an existing
  one. Reads the destination register's own current `otype` at decode
  time (`$veda_rdcap_otype = /vreg[$veda_rd_cap]$otype`) to compute
  `$veda_rebind_sealed`, and combines it with the ODT hit/miss already
  computed for `Bind` (`$veda_odt_valid` — Sail performs the identical
  `odt_lookup(object_id)` unconditionally for every mode, so no separate
  ODT read was needed) into one `$veda_rebind_ok` success signal.
  `$tag` is written unconditionally by `$rebind_wr_en` (`1` only when
  `$veda_rebind_ok`); every other field except `Offset` is gated on
  `$rebind_wr_en && $veda_rebind_ok` specifically, so a failing `Rebind`
  (sealed rd, or ODT miss) clears only `Tag` and leaves every other field
  — including `Offset` — completely untouched, matching Sail's own
  "`wCTag(false)` only, `wC` never called" failure path exactly.
  `$offset` has **no `Rebind` branch added at all**, success or failure —
  it simply falls through to `$RETAIN` every cycle, which is the cleanest
  possible RTL expression of "this instruction never touches this field."

## Real, working RTL, first try — no bugs found this milestone

Both the positive test (`sim/veda_smoke_m8.S`) and the negative test
(`sim/veda_smoke_m8_neg.S`) passed on the first real simulation run for
the actual `Rebind` logic itself. One real bug *was* found and fixed, but
it was in the positive test's own memory-access assumptions, not the RTL:

**Test bug (not RTL)**: the positive test's proof design read an AMO's
"old value" from a byte range `elfmem[]` had never been written to
(`$readmemh` only defines the bytes the ELF's own `.text` section
supplies — every other byte in the 512 KiB `elfmem[]` array is genuine
Icarus Verilog `x` (undefined), not implicitly zero). The first run showed
`x14`/`x21`/`x20` all reading back as `x` instead of their expected
values — diagnosed by checking `elfmem[]`'s own declaration and initial
block directly (`veda_core.tlv` lines 405–435: `tag_mem[]` has an explicit
zero-init loop, `elfmem[]` does not), not assumed. This is the exact same
real reason `MILESTONE_V-B_RESULTS.md`'s own `vc_nmc_add_w_and_atomic8.S`
test always issues a plain store immediately before every AMO it reads a
value back from — a pattern this test's first draft forgot to repeat.
Fixed by adding a deterministic `OCS.D` seed-store immediately before each
of the two AMOs whose old value the test checks.

## What this milestone actually proves

The positive test is not a metadata-only check — it exercises one
capability register (`c1`) and one object (`Object_ID=20`) through a full,
physically-verified relocation:

1. `Object_ID=20` is populated at `Base=0x80010500`; `c1` is bound to it
   and its `Offset` walked to `8` via `OCA`. A real `AMO` write/read
   through `c1` round-trips through the real physical address
   `0x80010508`.
2. `Object_ID=20` is **re-populated** at a new `Base=0x80010600` (same
   `Length`/`Perms`) — simulating the MSA silently relocating the object.
   This also bumps the ODT slot's generation counter, exactly like every
   other real `ODT-Populate` in this file already does for a still-valid
   slot.
3. `c1`, not yet rebound, is proven **stale**: a real `AMO` attempt
   through it is correctly rejected (`$veda_gen_stale`), leaving a
   sentinel register untouched — the real security property that exists
   precisely so an unrefreshed capability can't be silently exploited
   after a relocation.
4. `veda.rebind c1, x1` is issued. `CGetOffset`/`CGetBase`/`CGetTag`
   confirm: `Offset` is **still 8** (untouched), `Base` is now
   `0x80010600` (the new location), `Tag=1` (real success).
5. A fresh `AMO` write/read through `c1`'s own **still-8, never
   recomputed** `Offset` now round-trips through the real physical
   address `0x80010608` — a byte range distinct from step 1's — proving
   the relocation is functionally real, not just a metadata artifact.
   Software never recomputed anything; the same `Offset` value now
   correctly addresses the new location because `Base` moved underneath
   it.

The negative test (`sim/veda_smoke_m8_neg.S`) separately proves the three
real failure/no-op paths: `Rebind` on an already-sealed capability
register soft-fails without touching any other field (verified via
`CGetType`, which still shows the original seal, and `CGetBase`, which is
unchanged — proof `wC` was genuinely never called, not just that `Tag`
happened to end up `0`); `Rebind` against a never-populated `Object_ID`
soft-fails the same way; and the reserved mode field (`11`) is now a true
no-op — a real regression check for the exact gap this milestone closed,
targeting a *different* `Object_ID` in the reserved-mode instruction than
the one the register was originally bound to, so a reintroduced version of
the old bug (mode ignored, falls through to `Bind`) would be caught by a
changed `Base`, not just a changed `Tag`.

## Full regression: zero impact

All of Milestones 1–7's own tests (13 positive/negative programs) and the
base RV64I core's own unmodified 81-instruction smoke test were re-run
against the final build — **15 real test programs through one script**
(`run_veda_smoke_test.sh`), zero regressions.

## Not yet built

Real trap infrastructure (violations still suppress writes, not Sail's
own hard trap — this is the one remaining reason `Bind` and `Bind-NoTrap`
are still behaviorally identical in this RTL, and would be the first
place that stops being true if trap infrastructure were ever added),
`CInvoke`-equivalent domain transition, and capability-authority-gated
`ODT-Populate`/`ODT-Destroy` (still ordinary-privilege-gated) — all real,
previously-named, still-deferred items, unaffected by this milestone.
With this milestone, RTL now has real, working parity with every Sail
Object-Bind mode (`NEXT_STEPS_ROADMAP.md`'s Tier 1 is now fully closed).
