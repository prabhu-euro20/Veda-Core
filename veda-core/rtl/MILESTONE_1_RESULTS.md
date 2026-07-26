# Veda-Core RTL — Milestone 1 Results

**Date:** 2026-07-22
**Scope:** Capability Register File, Object-Bind, `OCL.D`/`OCS.D` — real,
working TL-Verilog RTL (`veda_core.tlv`), layered onto a real copy of the
already-verified RVA23 base core (`rtl/rv64i_core.tlv`, 51/51 ACT4 RV64I
conformance), transpiled via SandPiper, compiled with Icarus Verilog, and
simulated against real hand-assembled ELF test programs — not asserted
from the source alone. See `MILESTONE_PLAN.md` for the full scope decision
and the three real architectural calls this milestone required.

## Result: PASS — both positive and negative paths verified empirically

**Positive path** (`sim/veda_smoke_test.S`: bind Object_ID=1, `ocs.d`
`0x1234`, `ocl.d` it back):

```
cyc=1  bind fires  -> c0: tag=1 base=0x80010000 length=0x40 perms=0x100c otype=0xffff
cyc=4  ocs=1, viol=0
cyc=6  ocl=1, viol=0
cyc=7  x4 = 0x1234
*** TEST PASSED *** (x4 == 0x1234, real round trip through Veda-Core RTL)
```

The Capability Register File's real state exactly matches the seeded ODT
entry the cycle after `Object-Bind` fires, and the full store→load round
trip through the real, memory-mapped ODT and `elfmem` produces the exact
expected value — the identical positive-path shape already proven twice
before this (Sail Milestone V-A, and Milestone V-C's self-checking
version), now proven a third time in actual synthesizable RTL.

**Negative control** (`sim/veda_smoke_neg.S`: bind an `Object_ID` that was
never populated, attempt `ocs.d` through it):

```
cyc=1  bind fires  -> c0: tag=0  (ODT entry invalid, correctly propagated)
cyc=4  ocs=1, viol=1
*** TEST PASSED *** (illegal OCS.D correctly suppressed, memory untouched)
```

The real security property this milestone can enforce without trap
infrastructure (see below) held: the illegal value never reached memory,
verified by directly inspecting `elfmem` at the target address rather than
trusting the violation signal alone.

**Zero regression on the base RV64I core**: the exact same 81-instruction
Milestone A/B smoke test (`rtl/sim/tb_smoke.sv`, unmodified) was run
against this file's own generated `veda_core.sv` and produced
byte-identical register values to the original, untouched
`rv64i_core.tlv`'s own results — confirming the new Veda-Core logic didn't
disturb the base ISA's already-verified behavior. (Low risk by
construction: `veda_core.tlv` is a real, separate file, not an edit to
`rv64i_core.tlv` itself — but verified directly rather than assumed safe.)

## Three real architectural decisions (see `MILESTONE_PLAN.md` for full
reasoning)

1. **The ODT is memory-mapped** (`odt_mem[]`, a real byte-addressable
   array read/written exactly like `elfmem`/`dmem`), not a register array
   — the first concrete hardware realization of `VEDA_CORE_SPEC.md` §5.1's
   own stated design intent. Scoped to 256 entries this milestone (real
   silicon-area consciousness), `Object_ID` masked to its low 8 bits for
   indexing — a real, stated boundary, not silent truncation.
2. **Violations suppress writes; they do not trap.** This core's RTL has
   no privileged/trap architecture at all yet. `$veda_violation` is a real,
   exposed, testable signal; `OCL.D`'s register write-back and `OCS.D`'s
   memory write are both gated off on violation — a real, honest floor
   given what infrastructure actually exists, not a placeholder.
3. **The generation-staleness check is included from the start** (a fresh
   ODT re-lookup by the capability's own cached `Object_ID`, compared
   against its cached `generation`), rather than reproducing the real gap
   found and fixed in Sail Milestone V-B. Structurally correct now; not
   independently testable until a real `ODT-Destroy` exists in RTL (a
   later milestone) — the identical, honest caveat Sail V-A/V-B had.

## Real, predicted-then-confirmed detail worth recording

SandPiper's signal-mangling convention (`|cpu` → `CPU_`, `@0` → `_a0`,
array-of-registers → `CPU_<Group>_<field>_a0[idx]`) was predicted from the
existing file's own precedent (`$is_store` → `CPU_is_store_a0`, etc.)
*before* generating the file, used to write the new trailing `\SV`
`always_ff` block for `OCS.D`'s `elfmem` write, and then confirmed correct
by inspecting the real generated `veda_core.sv` — a genuine prediction that
held, not a guess left unverified. One real, harmless surprise: a `/vreg`
field (`$offset`) that's written but never read elsewhere doesn't get
promoted to a top-level signal at all (stays an internal generate-loop
variable) — caught immediately via a real "signal not found" reference,
not assumed.

One real warning found and fixed: `$veda_ocs_value` (used only by the
trailing raw `\SV` block, invisible to SandPiper's own TLV-level
dependency tracking) needed an explicit `` `BOGUS_USE ``, the same real
idiom this file already used for `$is_fence`.

## Not yet built

`NMC_ADD`, Veda-Atomic, `OCA`, the query family, `CSetBounds`/`CSeal`/
`CUnseal`, `ODT-Populate`/`ODT-Destroy`, sealed-capability enforcement (no
capability can be sealed in RTL yet), and any real trap/exception
infrastructure to replace violation-suppresses-write with genuine hard
traps. All real, deferred, later RTL milestones — the same phased scope
already used successfully for both the base core's own RTL and the entire
Sail formal-model effort (V-A → V-B → V-C).
