# Veda-Core Milestone 18 Results (Sail + RTL): VEDA_ODT_POPULATE_FAST + `veda_attr` CSR — Fixing RV64I's 12-Bit Immediate Tax on Descriptor Construction

**Date:** 2026-07-28
**Scope:** A new instruction, `veda.odt.populate.fast`, and a new
persistent CSR, `veda_attr` (0x7C4), closing the real, measured cost
`IMMEDIATE_LIMIT_INVESTIGATION` (scratchpad, not committed) found by
testing rather than assuming: RV64I's 12-bit immediate limit forces
plain `ODT-Populate`'s packed 64-bit descriptor to be built via a full
6-instruction `li`, and a real, dedicated benchmark showed a
software-only `la`-based workaround saves only ~5% — because `Base`
still has to be shifted into the descriptor's upper 32 bits regardless
of how it is loaded, canceling out most of `la`'s own savings. This
milestone is the real ISA-level fix that software alone could not
deliver.

## Design, reasoned before writing any code

The packed-descriptor format (`Base<<32 | Length<<16 | Perms`) is the
*cause* of the tax, not `ODT-Populate` itself — `Base` only needs
shifting because it shares a single 64-bit immediate with two other
fields. The fix is to stop packing: give `Base` its own operand
(`rs2`, loadable via a clean, real 2-instruction `la`/`li`, no
shift/pack), and move `Length`/`Perms` — the genuinely *reusable* half
of a descriptor, shared by every object minted from the same template —
into a new, persistent CSR, set once via the real, already-working,
unmodified `csrw`/CSRRW (Milestone 9's own Zicsr-lite infrastructure).
No new "set" instruction was needed at all.

**Operands**: `rs1` = Object_ID (unchanged from plain `ODT-Populate`,
mirrors Object-Bind's own `rs1` convention exactly), `rs2` = Base
directly (no packing). `rd` = status/handle output (written 0 on
success, matching plain `ODT-Populate`'s own convention).

**Encoding**: Custom-0, `funct3 = 000` (grouping with the Populate
family — plain `ODT-Populate` is also `funct3=000`), `funct7 =
0000100` — the next genuinely free slot, verified by grepping every
existing `$is_veda_*`/`VEDA_ODT_*` decode condition in both
`veda_core.tlv` and `veda_ocl_insts.sail` before adopting it (Custom-0's
full existing allocation at the time: OCL 011/0000000, OCS 011/0000001,
OCL.C 100/0000000, OCS.C 100/0000001, ODT-Populate 000/0000011,
ODT-Destroy 001/0000011, NMC_ADD.W 010/0000010, NMC_ADD.D 011/0000010,
Bind 101/any) — the same discipline this project adopted after the
earlier real OCJALR/OSpecialRW encoding collision (Milestone 17).

**`veda_attr` CSR**: address `0x7C4`, the real, standard RISC-V
"Machine-level Custom read/write" range (riscv-spec.pdf Table 91,
p.664: 0x7C0-0x7FF) — the next free slot after Milestone 14's four
(`veda_pcc_base`/`veda_pcc_length`/`veda_mepcc_base`/`veda_mepcc_length`).
Layout: `Length` in bits[31:16], `Perms` in bits[15:0] — the identical
sub-field layout plain `ODT-Populate`'s own packed descriptor already
uses for these two fields, just relocated out of the 64-bit immediate.
Resets to zero (harmless: an all-zero Length/Perms just makes the first
fast-populated object real but permission-less until software actually
sets this CSR, not a crash/undefined-behavior risk).

**Semantics**: identical to plain `VEDA_ODT_POPULATE` in every other
respect — same privilege gate (`cur_privilege == Machine |
veda_oda_authorized()`), same retired-slot refusal, same
generation-counter saturate-and-retire logic (Milestone 16's fix) —
deliberately mirrored rather than refactored into a shared helper,
matching this codebase's own established style of keeping each
instruction's execute clause self-contained and independently
auditable (the same real reason `VEDA_ODT_DESTROY` already duplicates
rather than shares logic with `VEDA_ODT_POPULATE`).

## Sail implementation and verification

`veda_ocl_insts.sail` gained `VEDA_ODT_POPULATE_FAST : (regidx, regidx,
regidx)` (encdec, execute, assembly clauses), inserted directly after
`VEDA_ODT_POPULATE`/`VEDA_ODT_DESTROY`. `veda_regs.sail` gained
`register veda_attr : bits(32)` plus the CSR wiring (`csr_name_map`,
`is_CSR_accessible`, `read_CSR`, `write_CSR`), mirroring the exact
scattered-clause pattern already established for `veda_pcc_base` at
`0x7C0`. `postlude/step_ext.sail`'s `ext_reset()` gained an explicit
`veda_attr = zeros();` line, matching that function's own existing
explicit-reset style for the other Veda-Core CSRs.

Two new self-check tests, both passing on the first real run:
- **`vc_odt_populate_fast.S`** (positive): sets `veda_attr`
  (Length=0x40, Perms=Load|Store) with a CSR read-back sanity check,
  mints Object_ID=60 with Base given directly (no packing), binds it,
  and proves two real write-then-read round trips — an ordinary
  position (offset 0) and a boundary position (offset 0x38, width 8,
  `offset+width == Length` exactly) — both landing correctly.
- **`vc_odt_populate_fast_neg.S`** (negative): sets `veda_attr` with a
  deliberately small Length (0x8), mints Object_ID=61, and proves a
  real out-of-range access (offset 0x10, width 8) genuinely hard-traps
  with `mcause=0x18`/`mtval=0x21` (cause=0x01 Bounds Violation,
  cap_idx=1) — proving `Length` sourced from `veda_attr` is actually
  load-bearing, not just plumbed through and ignored.

**Full Sail self-check suite: 30/30 passed** (28 pre-existing + 2 new),
zero regressions.

## RTL implementation and verification

`veda_core.tlv` gained `$is_veda_odt_populate_fast` and
`$csr_is_veda_attr`, joined the existing `$veda_odt_populate_violation`
signal (now shared by both Populate variants, identical privilege/
retired gate), extended the existing `$veda_odtpd_new_base`/
`$veda_odtpd_new_length`/`$veda_odtpd_new_perms` three-way mux (Base
from `rs2` directly, Length/Perms from the new `$veda_attr` register),
extended `$reg_write`/`$wr_data`'s existing Populate/Destroy handling,
and joined the existing `odt_mem[]` write-back `always_ff` block's
condition. `$veda_attr[31:0]` is a plain read/write CSR register (no
other write source, unlike `veda_pcc_base`/`length`, which are also
written by a successful `OCInvoke`/trap) — mirrors `$mtvec`'s own
simple reset/CSRRW-only pattern exactly.

Two new RTL smoke tests, mirroring the Sail scenarios field-for-field
(same objects, same encodings, identical bit layout in both layers),
both passing on the first real Icarus Verilog run:
- **`veda_smoke_m18.S`/`tb_veda_smoke_m18.sv`** (positive): CSR
  readback exact (`x21=0x40100c`), ordinary round trip correct
  (`x6=0x1234567890ABCDEF`), boundary round trip correct (`x9=0x66`).
- **`veda_smoke_m18_neg.S`/`tb_veda_smoke_m18_neg.sv`** (negative): the
  out-of-range access genuinely hard-traps with the correct
  `mcause`/`mtval`/`mepc`, `MRET` correctly resumes past the fault
  (`x21=0x600D`, `x22=0x900D`).

**Full regression**: the pre-existing Milestone 1–14 aggregate suite
plus the two new Milestone 18 tests — **27 real RTL test programs
total (`run_veda_smoke_test.sh`), zero regressions**. The full real
ACT4 RV64I conformance suite: **51/51 passed, zero regressions**.

## Real, measured savings — not projected

A dedicated benchmark, built specifically to answer the question this
milestone set out to answer: `N` objects sharing one Length/Perms
template, comparing plain `ODT-Populate` (raw 6-instruction `li`
descriptor per object — the exact pattern every real test/demo in this
project already used) against `VEDA_ODT_POPULATE_FAST` (`veda_attr` set
once, `la`+`li`+`populate.fast`+`li`+`bind` per object), run at
`N`=1,2,4,8,16 against the real, unmodified, committed `veda_core.tlv`,
each point independently assembled and simulated:

| N | Plain `ODT-Populate` (cycles) | `POPULATE_FAST` (cycles) | Savings |
|---|---|---|---|
| 1 | 10 | 9 | 10.0% |
| 2 | 20 | 15 | 25.0% |
| 4 | 40 | 27 | 32.5% |
| 8 | 80 | 51 | 36.3% |
| 16 | 160 | 99 | 38.1% |

Exact closed form, matching every row: **`naive_cycles = 10N`**,
**`populate_fast_cycles = 6N + 3`** — real, `objdump`-verified
instruction counts explain both constants exactly: plain `ODT-Populate`
costs **10 instructions/object** (`li ObjID` + 6-instruction `li
descriptor` + `populate` + `li ObjID` + `bind`); `POPULATE_FAST` costs
**6 instructions/object** (`la Base` [2] + `li ObjID` + `populate.fast`
+ `li ObjID` + `bind`), a real **40% per-object instruction-count
reduction** — matching the projection made before this milestone was
built almost exactly. The `+3` is the one-time `veda_attr` setup cost
(`li t4` [2 instructions, a 32-bit constant] + `csrw` [1]), which
amortizes away as `N` grows, so the real, measured savings converges
toward the full 40% asymptotically (already 38.1% by `N`=16) while
staying strictly positive at every `N` tested, including `N`=1 — unlike
Milestone 10's `OCInvoke`-vs-software-gate benchmark, this optimization
has **no crossover point to wait for**; it wins from the very first
object.

**This closes the gap the software-only workaround could not**: the
earlier `IMMEDIATE_LIMIT_INVESTIGATION` measured only a 5% (2-cycle)
improvement for the same `N`=4 case from a pure-software `la`-based
fix, because `Base` still had to be shifted into the descriptor's upper
32 bits regardless of how it was loaded. The real ISA fix — removing
the pack requirement entirely, not just changing how `Base` is loaded —
delivers **32.5% at the same `N`=4**, a genuine ~6.5x larger real,
measured improvement over the best achievable software-only fix.

## What remains open, honestly

- `POPULATE_FAST` only helps when multiple objects genuinely share one
  Length/Perms template — an object needing a unique size or
  permission set every time still pays the full descriptor cost (via
  plain `ODT-Populate`, unchanged and still available). This is a real,
  stated scope boundary, not a general replacement.
- No compiler exists to automatically choose between the two Populate
  variants for a real allocator's own object-minting pattern — every
  test in this project remains hand-assembled, the same honest,
  already-stated limit as every other milestone.
- The `veda_attr` CSR is a single, unbanked register — a real
  interrupt or trap handler that itself calls `POPULATE_FAST` with a
  different template must save/restore `veda_attr` around that call,
  exactly like any other live CSR under real RISC-V's own standard
  software-managed-context convention. Not a new problem this
  milestone introduces, but worth stating rather than leaving implicit.
