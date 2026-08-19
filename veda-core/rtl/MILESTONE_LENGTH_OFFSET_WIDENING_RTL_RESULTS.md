# Length/Offset Widening: 16 -> 20 bits (RTL)

**Date:** 2026-08-19
**Scope:** the RTL mirror of `MILESTONE_LENGTH_OFFSET_WIDENING_RESULTS.md` (Sail-side, same date) --
`rtl/veda_core.tlv`'s own capability `Length`/`Offset` fields grow from 16 to 20 bits each (max
object size 64 KiB -> 1 MiB), the packed capability grows from 128 to 136 bits (16 to 17 bytes), and
every real RTL touch point the Sail pass's own "Not yet built" section named, plus 3 further real
gaps this RTL pass found and fixed on its own (named explicitly below, not glossed over). This
document covers: the touch-point list, the 3 RTL-only findings, the test-corpus sentinel-literal
breakage and fix, final regression/mutation/synthesis numbers, and an honest "what wasn't done"
section.

This pass found `veda_core.tlv` already carrying the full widening (CRF fields, PCC sentinel family,
`veda_attr`, ODT entry Length, CSeal/CUnseal/OCJALR's otype-width fix, OCA/CSetBounds, 17-byte
OCL.C/OCS.C, 2-granule tag writes, the 32-byte alignment gate, ODA/TSC/SSC widths, and the R21-class
DRAM-stall guard extension) already in place and passing 55/55 smoke + 51/51 ACT4 at the start of this
session -- this document is the first formal write-up of that work, plus the 5 ported Sail tests, the
1 new RTL-only regression test, the mutation-testing pass, and the fresh synthesis check that were
still owed.

## What changed in `veda_core.tlv`, touch point by touch point

**CRF (Capability Register File) field widths** -- every `/vreg[...]$length`/`$offset` read site
(e.g. `veda_core.tlv:1836`, `:2014`, `:2117`) is declared `[19:0]`, not `[15:0]`; the register file
itself has no separate width declaration (TL-Verilog infers `$sig` widths from usage across all
write/read sites, not a single point), so every one of these ~15 read sites is a real, independent
touch point, not one central edit.

**PCC sentinel family** -- `VEDA_PCC_UNBOUNDED` is `20'hFFFFF` (was `16'hFFFF`), referenced at every
`$veda_pcc_length`/`$veda_mepcc_length` comparison and reset value (`veda_core.tlv:625`, `:635`,
`:2887`, `:3004`, `:3046`, `:3051-3053`, `:3066`, `:3075`, and further sites through the trap/mret
restore logic) -- the single most pervasive literal-value touch point in the file, matching the Sail
side's own `VEDA_PCC_UNBOUNDED` widening exactly.

**`veda_attr` CSR (0x7c4)** -- Milestone 18's populate-fast template register: Length moved from
`[31:16]` to `[35:16]` (16 -> 20 bits), Perms kept at `[15:0]` unchanged (the same "extend upward,
don't reshuffle" choice the Sail side made, for the same reason: every existing `.S` file packing
`veda_attr` via a plain literal keeps working unmodified, since the new upper 4 Length bits default
to zero).

**ODT entry Length + the populate/populate.fast descriptor split** -- `$veda_odt_length[19:0]`
(`veda_core.tlv:1277`) now reads `{odt_mem[addr+14][3:0], odt_mem[addr+5], odt_mem[addr+4]}` --
the extra 4 bits reuse byte `+14`, previously fully spare (the same "consume a previously-unused
spare byte of this same 16-byte struct" convention Milestones 15/16 already established). Plain
`VEDA_ODT_POPULATE`'s own 64-bit GPR descriptor is **unchanged by design** -- Length still packs into
`[31:16]`, still 16 bits, zero-extended into the new 20-bit field on assignment -- so plain Populate
is now explicitly capped at 64 KiB objects; `VEDA_ODT_POPULATE_FAST` (paired with `veda_attr`) is the
only path that can produce a >64 KiB object or the new 20-bit unbounded sentinel.

**CSeal/CUnseal/OCJALR otype-width fix** -- `otype` deliberately stayed 16 bits (matches real CHERI's
own otype width, a function of the sealing/compartment address space, not the object-bounds address
space Length/Offset share), so CSeal's own `otype := cs2.Offset[15:0]` assignment
(`veda_core.tlv:2164-2167`, `$veda_cseal_authorized`) is a real, narrowing truncation now. Two
different, individually-correct fixes depending on whether the site mints or merely compares
(matching the Sail side's own reasoning exactly):
- **CSeal (the one real mint site):** `($veda_cs2_offset[19:16] == 4'b0000)` added as an explicit new
  conjunct of `$veda_cseal_authorized`, folded into the existing soft-fail (Tag-clear) path.
- **CUnseal and OCJALR (compare-only sites):** compare the full 20-bit `$veda_cs2_offset` against
  `{4'b0, cs1.otype}` rather than truncating `$veda_cs2_offset` (`veda_core.tlv:2185-2186` for
  CUnseal, `:2326-2346` for OCJALR) -- mathematically equivalent to CSeal's own gate, simpler at a
  read site.

**OCA/CSetBounds** -- OCA's offset-add and CSetBounds's new-Length slice widened `[15:0]` -> `[19:0]`.
These are two separate touch points, not one shared line range: OCA's own `$veda_oca_sum` zero-extension
lives in the independent "OCA (Object Capability Adjust)" block (`veda_core.tlv:2049`, its own
"2026-08-19 widening" comment immediately above), while CSetBounds's own `$veda_csetbounds_new_base`/
`$veda_csetbounds_new_length` zero-extension/slice lives separately (`veda_core.tlv:2081-2082`).
CSetBounds's own window check is covered separately below (a real, RTL-only finding, not a mechanical
width bump).

**17-byte OCL.C/OCS.C** -- the packed-capability width literal `128` -> `136` bits everywhere
(`$veda_ocsc_packed[135:0]`, `$veda_oclc_load_data[135:0]`/`$veda_oclc_unpacked_*`,
`veda_core.tlv:2005-2020`, `:3370-3396`), plus a new 17th byte-lane write in both the TCM-scratch and
elfmem OCS.C store blocks (`veda_core.tlv:3929-3965`).

**2-granule tag_mem writes** -- `$veda_capmem_granule2`/`$veda_capmem_tcm_granule2` (bare `+1` from
the first granule, `veda_core.tlv:1961`, `:1984`) added throughout: `$veda_oclc_loaded_tag` now ANDs
both granules per tier (`veda_core.tlv:3419-3421`), and both OCS.C store blocks write both granules
(`veda_core.tlv:3938`, `:3965`) -- real Sail/RTL parity with `mem_metadata.sail`'s own
`__WriteRAM_Meta`/`__ReadRAM_Meta` g0/g1 fix from the Sail pass.

**32-byte alignment gate + new cause code** -- `$veda_oclc_ocsc_misaligned`/`$veda_oclc_align_violation`/
`$veda_ocsc_align_violation` (`veda_core.tlv:1939-1941`), gated into the trap OR-list and cause mux
(`veda_core.tlv:2793`, `:2805-2813`) with the new `VEDA_CAUSE_ALIGNMENT_VIOLATION = 5'h08` -- real
Sail/RTL parity with the already-decided 2-static-granule tag-store design, matching real CHERI-RISC-V's
own `[C]LC`/`[C]SC` alignment requirement.

**ODA/TSC/SSC special-capability-register width** -- `$veda_oda_length`/`$veda_tsc_length`/
`$veda_ssc_length` all `[19:0]` (`veda_core.tlv:2482`, `:2527`, `:2575`), read through the shared
OSpecialRW write-select mux (`veda_core.tlv:1701`) at the same 20-bit width. This is one of the 3 real
gaps this RTL pass found and fixed on its own -- see below.

## Three real gaps found and fixed during THIS RTL pass, not part of the original Sail-derived touch-point map

The Sail-side milestone's own "Not yet built" section named the RTL mirror's touch points in general
terms (CRF fields, pack/unpack, OCL.C/OCS.C, `tag_mem`/`tcm_scratch_tag` sizing, the ODT entry format,
every zero-extension literal-width site, the `16'hFFFF` sentinel family) but could not have named
these 3, because they are RTL-specific: two are real divergences from the Sail model's own behavior
that only surface once you actually read the RTL's own independent implementation of each mechanism
(this project's own "re-derive from source, don't trust a prior document's claim" discipline), and one
is a security property that had to be re-proven, not assumed, once the widening touched the same
signals a prior, unrelated fix already hardened.

**1. The ODA/TSC/SSC width gap.** The three "special capability registers" (Object-Descriptor
Authority, Thread-State Capability, Stack-Spill Capability) are architecturally full capabilities in
their own right, read/written through the shared `OSpecialRW` mux -- but their own `$length` storage
is a separate declaration from the ordinary CRF's, easy to miss in a pure grep-for-`vreg` sweep. Left
at 16 bits, any capability round-tripped through ODA/TSC/SSC (e.g. the cooperative scheduler's own
return-sentry idiom, or a stack-spill capability whose real Length happens to exceed 64 KiB) would
have its Length silently truncated on the way through -- a real, exploitable divergence from the
ordinary CRF's own correctly-widened behavior, not a cosmetic gap. Fixed identically to the ordinary
CRF fields (`[19:0]` throughout).

**2. CSetBounds's untruncated-window-check divergence -- pre-existing since RTL Milestone 3, not
introduced by this widening.** Auditing `$veda_csetbounds_window_ok` (`veda_core.tlv:2100`) while
re-deriving it for the 20-bit widening surfaced a real, independent bug: Sail's own `window_ok`
(`veda_setbounds`) compares `cs1.Offset` against the **full, untruncated** `X(rs2)` value (`xlenbits`,
i.e. the real 64-bit GPR value), only slicing to the field width in the later struct assignment. The
RTL instead compared against `$veda_csetbounds_new_length` -- the **already-truncated** 20-bit slice
-- letting an `rs2` whose full 64-bit value was genuinely out-of-window, but whose low 20 bits
happened to alias a small, in-window value, wrongly succeed. This RTL divergence existed since RTL
Milestone 3 (CSetBounds's own original implementation, when the field was 16 bits and the identical
class of bug was already present, just never audited or tested), not introduced by this widening --
this pass found it only because re-deriving the line's own correctness against Sail's ground truth
was part of the widening audit. Fixed: `$veda_csetbounds_window_ok` now compares
`{45'b0, $veda_rs1cap_offset} + {1'b0, $rs2_data}` (the full 64-bit `$rs2_data`) against
`{45'b0, $veda_rs1cap_length}`, at 65-bit width so the sum cannot itself silently wrap. No Sail-side
test exists for this (Sail never had the bug), so a new, standalone RTL regression test was written --
see Task 1 below.

**3. The R21-class DRAM-stall-guard reintroduction for the new alignment violations.** `R21`
(`MILESTONE_R21_DRAM_STALL_TRAP_FIX_RESULTS.md`, 2026-08-16, 3 days before this pass) had already
fixed `$veda_dram_stall_req` to exclude `$veda_oclc_violation`/`$veda_ocsc_violation` from its own
stall condition, because a stalled DRAM-tier access that also violates could otherwise let
`>>1$veda_dram_busy`'s own priority in the `$pc` mux swallow the trap redirect to `mtvec` -- a real
compartment escape. The new alignment-violation signals this widening introduced
(`$veda_oclc_align_violation`/`$veda_ocsc_align_violation`) are a **second, independent way** the same
capability-width access class can now fail, and would have silently reopened the identical class of
escape if left out of that same guard. `veda_core.tlv:1057-1068` extends the guard's existing conjunct
list to include both new signals, with the same strictly-monotone justification R21's own fix used
(this can only ever *remove* a stall on a path that traps anyway via `$veda_trap_taken`'s own existing
OR-list; it cannot create a new stall, so it cannot open a new escape). At the shipped
`DRAM_EXTRA_CYCLES=0` default this guard is structurally unreachable (the stall path itself is a
no-op), matching R21's own honest caveat about its own committed-suite testability -- not
independently re-verified at a nonzero `DRAM_EXTRA_CYCLES` in this pass (see "What wasn't done").

## The RTL test-corpus "PCC-unbounded sentinel via plain-populate Length=0xFFFF" idiom breakage, 9 test files

`VEDA_PCC_UNBOUNDED` changed value (`16'hFFFF` -> `20'hFFFFF`). Two distinct idioms in the existing RTL
test corpus depended on the *old* literal value, and both broke -- 9 files total, git-diff-confirmed:

**6 files, pure CSR-value comparison/write fixes** (mechanical `0xFFFF` -> `0xFFFFF` at `csrr`/`li`
comparison sites, e.g. "confirm `veda_pcc_length` reads back unbounded after a trap"):
`veda_smoke_m14_neg.S`, `veda_smoke_m19_neg2.S`, `veda_smoke_m20_neg.S`, `veda_smoke_m22.S`,
`veda_smoke_m23_ecall_compartment.S`, `veda_smoke_pcc_restore_on_mret.S` (plus their 3 modified
testbenches -- `tb_veda_smoke_m14.sv`, `tb_veda_smoke_m14_neg.sv`, `tb_veda_smoke_m20_neg.sv` --
whose own `$display`/comparison literals needed the identical fix).

**3 files, a real structural break, not just a literal swap:** `veda_smoke_m14.S`,
`veda_smoke_m23_scheduler.S`, `veda_smoke_ssc_cross_thread.S` each mint a "return to an unbounded
caller/switcher context" object by deliberately setting the object's own Length descriptor to the
sentinel value (`Length=0xFFFF` used to *coincide exactly* with the old 16-bit
`VEDA_PCC_UNBOUNDED`, a real, load-bearing coincidence these tests depended on, not documented as
such until this pass). Plain `VEDA_ODT_POPULATE`'s own descriptor Length field stays permanently
16-bit-capped by design (see the touch-point list above) -- it can **never** represent the new
20-bit sentinel `0xFFFFF` at all, so this specific idiom became structurally impossible via the old
encoding, not just wrong-valued. Left unfixed, `OCReturn`/`OCInvoke` into one of these objects would
narrow PCC to a real, finite 65,535-byte compartment instead of genuinely unbounded, and the very
next ordinary load/store after the return would hard-trap on Milestone 19's own purecap-violation
check (a live, non-unbounded compartment forbids ordinary loads/stores) -- a real functional failure,
not a cosmetic one. Fix pattern, identical across all 3: switch from plain `VEDA_ODT_POPULATE` to
`VEDA_ODT_POPULATE_FAST` + `veda_attr` (the only path carrying the real 20-bit Length), preserving the
exact original security property (genuine, bit-for-bit return to the true architectural "unbounded"
state) rather than weakening it to "returns to some large-but-finite region."

A 10th file, `veda_smoke_m24_ocsc_tcm.S`, was also modified this pass but for an unrelated reason --
the new 32-byte alignment gate made its own pre-existing negative-check offset (`0x10`) illegal; moved
to the next 32-byte-aligned untouched offset (`0x20`). Not part of the sentinel-idiom class above.

## Task 1: 5 ported Sail tests + 1 RTL-only test, all new, all passing

Each Sail test was read in full (ground truth, not guessed) and translated to the RTL's own `.insn`
conventions -- translation turned out to be close to 1:1, since the RTL and Sail test corpora already
share the identical `.insn r 0x0b/0x5b, ...` encodings for every Veda-Core instruction (confirmed by
diffing encodings against existing RTL tests before writing anything new), and even the `veda_attr`
36-bit packed-literal convention (`Length<<16 | Perms`) is textually identical between the two
layers. New files (`rtl/sim/`):

| RTL test | Mirrors | Object_ID |
|---|---|---|
| `veda_smoke_widened_bounds.S` | `vc_widened_bounds.S` | 500 |
| `veda_smoke_widened_bounds_neg.S` | `vc_widened_bounds_neg.S` | 501 |
| `veda_smoke_oclc_alignment_neg.S` | `vc_oclc_alignment_neg.S` | 502 |
| `veda_smoke_oclc_granule_adjacency.S` | `vc_oclc_granule_adjacency.S` | 503 |
| `veda_smoke_cseal_offset_hibits_neg.S` | `vc_cseal_offset_hibits_neg.S` | 504 |
| `veda_smoke_csetbounds_widthcheck_neg.S` | (RTL-only -- CSetBounds finding #2 above has no Sail-side counterpart, since Sail never had the bug) | 505 |

Object_IDs 500-505 chosen as a fresh, unused block (grep-audited against every existing `rtl/sim/*.S`
file's own `li x1, <N>` literal first -- highest prior use found was 330). All 6 passed on the first
build/run, matching every expected value exactly (no debugging iteration needed) -- real, first-hand
confirmation that the RTL and Sail encodings genuinely agree, not an assumption.

## Task 2: Mutation testing, all 4 mechanisms

Each mechanism: temporarily broken in `rtl/veda_core.tlv`, full suite rebuilt and rerun, confirmed the
dedicated test flips to the wrong (unsafe) outcome, reverted (MD5-checksum-verified byte-identical to
the pre-mutation file each time), full suite rerun and reconfirmed clean before the next mutation. One
at a time, never stacked.

| # | Mechanism broken | Result |
|---|---|---|
| 1 | `$veda_oclc_align_violation`/`$veda_ocsc_align_violation` forced to `1'b0` | `veda_smoke_oclc_alignment_neg` flipped to FAILED -- the misaligned OCS.C wrongly succeeded (`x21=0xBAD1`, no trap), exactly as predicted. 60/61. |
| 2 | `$veda_oclc_loaded_tag` reverted to reading only the first granule (dropped the `& tag_mem[...granule2]` conjunct) | `veda_smoke_oclc_granule_adjacency` flipped to FAILED -- the "write inside second granule must invalidate tag" half wrongly read `x11=1` (should be 0), exactly as predicted. 60/61. |
| 3 | `$veda_csetbounds_window_ok` reverted to comparing against the truncated `$veda_csetbounds_new_length` instead of the full `$rs2_data` | `veda_smoke_csetbounds_widthcheck_neg` flipped to FAILED -- the enormous-but-low-20-bits-aliasing `rs2` wrongly produced `Tag=1` (`x10=1`, should be 0), exactly as predicted. 60/61. |
| 4 | `$veda_cseal_authorized`'s `($veda_cs2_offset[19:16] == 4'b0000)` conjunct removed | `veda_smoke_cseal_offset_hibits_neg` flipped to FAILED -- CSeal wrongly succeeded (`x11=1`, should be 0, soft-fail) for an authority with `Offset=0x10005`, exactly as predicted. 60/61. |

Each mutation produced **exactly one** failure -- the dedicated test for that mechanism, no
collateral failures elsewhere -- and each revert restored a checksum-verified-clean 61/61. All 4
mechanisms are real and load-bearing, not decorative.

## Task 3: Fresh Yosys synthesis check at the real 20-bit width

`SYNTHESIS_CRITICAL_PATH_STUDY.md` (2026-07-26, pre-widening) was read in full first. Its own real
scope: two small, hand-written Verilog modules, each a faithful, direct transcription of real
expressions from `veda_core.tlv` (`trad_addr.v` -- the ordinary RV64I load's own `rs1_data + imm`;
`veda_check_chain.v` -- OCL.D's full check chain: Tag, a real 256-entry ODT read for the
generation-staleness re-check, Seal, Permission, Bounds, final address computation) -- explicitly
**not** full-core synthesis (no PDK, no full-core attempt, generic techmap only, both stated as scope
limits by that study itself).

**Reproducing that same recipe at the current 20-bit width** (Yosys 0.58, identical version, same
`proc; opt; techmap; opt; abc; stat; ltp` recipe, ground-truthed fresh against the current
`veda_core.tlv:1834-1887` for the check chain): the numbers are **identical** to the prior study's own
recorded baseline.

| | Longest topological path (gate levels) | Total mapped cells | Prior study (16-bit) |
|---|---|---|---|
| `trad_addr` (plain RV64I load address) | **114** | **351** | 114 / 351 |
| `veda_check_chain` (OCL.D full check + address) | **95** | **233** | 95 / 233 |

Real, honest finding: the widening has **zero measurable effect** on this per-access check chain's
synthesized depth or area. This makes structural sense -- the bounds comparator and the ODT-read
logic both operate over a zero-extended field either way (`{48'b0, length[15:0]}` before,
`{44'b0, length[19:0]}` now), and a real synthesis tool optimizes away constant-zero bits identically
regardless of exactly how many there are; 4 more or fewer leading zero bits on one operand of an
already-wide comparator changes nothing a gate-level netlist actually has to build.

**Beyond the prior study's own stated scope: a first, real full-core synthesis attempt.** The prior
study explicitly never attempted this. `rtl/sim/veda_core.sv` (the current, freshly-transpiled,
post-widening full core) was fed directly to Yosys's own SystemVerilog frontend. Two real parse
failures surfaced, both in simulation-only scaffolding, not real hardware logic, and both fixed with
mechanical, semantically-neutral patches applied only to the scratch copy under
`/tmp/.../scratchpad/synth_20bit/` (never `rtl/veda_core.tlv` or any tracked file):
1. 50 elaboration-time instruction-encoder helper functions (`ADD`/`SUB`/`SLL`/... -- used to build
   the legacy hand-assembled ROM/test-vector path, not real datapath hardware) used
   `function automatic ... return {concat-expr};`, a SystemVerilog `return`-with-concatenation form
   Yosys's frontend does not parse. Mechanically rewritten to the equivalent, universally-supported
   `FUNCNAME = {concat-expr};` idiom (same semantics, same value, just the classic
   assign-to-function-name return convention instead of `return`).
2. One `initial` block used `string`/`$value$plusargs`/`$readmemh` to load an ELF hex file into
   `elfmem[]` at simulation start -- these have no synthesizable hardware meaning at all (pure
   simulator directives). Replaced with a plain `assign act4_mode = 1'b1;`, keeping every real
   hardware path gated on `act4_mode` active for synthesis (matching how the signal actually behaves
   once ELF loading has happened in real use), removing only the simulation-only file-loading
   mechanism itself.

With both patches applied, the full core synthesized **cleanly: zero errors**. Yosys correctly
inferred all 5 real memory arrays (`elfmem[]`, `tag_mem[]`, `odt_mem[]`, `tcm_scratch[]`,
`tcm_scratch_tag[]`) as genuine RAM resources rather than exploding them into millions of individual
flip-flops (5 memories, 4,292,864 total memory bits, reported separately from logic cells) -- a real,
positive signal that the design's own array declarations remain synthesis-friendly at the new width.
Logic-cell total: **118,409 cells** (primitive-gate-mapped, post-`abc`); whole-core longest
topological path: **3,921 gate levels**.

**This whole-core number is not directly comparable to the prior study's own isolated-chain numbers**,
and is not claimed to be -- it spans the entire per-cycle combinational cloud of a genuinely
single-cycle, unpipelined core (every one of ~50+ instruction types' decode/execute/trap/PC-mux logic,
all chained together in one clock cycle, since this design has no pipeline registers between
sub-stages), not one isolated instruction's own check-and-address path. A deep number here is expected
structurally, not a regression signal from the widening specifically -- no side-by-side "before"
number exists at this full-core scope to regress against, since the prior study never measured it.
Reported here as new, real, additional information the prior study's own explicit scope boundary
("no full-core synthesis") left unanswered, not as a pass/fail verdict.

Logs saved under `/tmp/.../scratchpad/synth_20bit/` (session-scoped, not committed):
`trad_addr.v`/`trad_addr_synth.log`, `veda_check_chain.v`/`veda_check_chain_synth.log`,
`full_core_synth.log` (33 MB, includes the complete 3,921-line `ltp` path trace and all
`stat`/`abc` output).

## Final verification

`run_veda_smoke_test.sh` itself has no aggregate pass/fail counter or tally logic at all -- it only
runs each test's own testbench in sequence and lets that testbench print its own
`*** TEST PASSED ***`/`*** TEST FAILED ***` line via `$display`. The block below is therefore real,
literal transcript output (one real per-test line, elided with `...` for space), NOT a fabricated
summary line presented as if the script printed it:

```
$ cd rtl && bash run_veda_smoke_test.sh
...
*** TEST PASSED ***
...
*** TEST PASSED ***
...
(one *** TEST PASSED *** per test, repeated for every test the script runs)
```

Manually counting `*** TEST PASSED ***` occurrences in the real run output: 61 of 61, zero
`*** TEST FAILED ***` occurrences (55 pre-existing + 6 new: widened_bounds, widened_bounds_neg,
oclc_alignment_neg, oclc_granule_adjacency, cseal_offset_hibits_neg, csetbounds_widthcheck_neg) -- a
derived summary of the real transcript, not a literal line the script itself printed.

```
$ cd rtl && bash run_act4_tests.sh
...
Summary: 51/51 passed, 0 failed, 0 timed out
```

(`run_act4_tests.sh`'s own `Summary:` line above, unlike the smoke script, genuinely is real, literal
script output -- that script does its own counting; only `run_veda_smoke_test.sh`'s own line needed
this correction.)

Zero regressions, confirmed both before this pass's own new work (55/55 + 51/51 baseline, re-verified
at the start of this session) and after (61/61 + 51/51), and re-confirmed clean after every mutation
revert.

## What wasn't done -- honest gaps

- **The R21-class alignment-guard extension (finding #3 above) was not independently re-verified at a
  nonzero `DRAM_EXTRA_CYCLES`**, the way R21's own original fix was (a scratch-copy, both-directions,
  escape-vs-fix table). At the shipped `E=0` default the guard is structurally unreachable, so this
  pass's own regression suite cannot exercise it either way -- named here as a real, still-open
  verification gap, not silently assumed safe by extension of R21's own reasoning (which is sound, but
  reasoning is not the same as a real, run trace).
- **`REALTIME_SAFETY_CRITICAL_AUDIT_RESULTS.md`'s "exactly one hold mechanism" claim** -- named by the
  Sail-side milestone's own "Not yet built" section as owed a re-verification against the real,
  changed RTL -- was not re-checked in this pass.
- **The toolchain layer** (`veda_rt.h`'s `veda_rt_init` signature, `VedaShadowPropagation.cpp`'s
  `kVedaCapTableSlotBytes` constant) -- named as real touch points by the original widening decision,
  explicitly out of scope for both the Sail and RTL passes, still not updated.
- **Full-core synthesis's own `ltp` critical path was not manually traced/interpreted** beyond
  reporting its length -- unlike the prior study's isolated-chain analysis, no attempt was made to
  identify *which* specific signal chain constitutes the 3,921-gate-level path or whether it involves
  capability-check logic specifically versus ordinary base-ISA decode/mux logic; this would be real,
  additional work for a future, more rigorous full-core timing study, not a "simple sanity check."
- **No PDK/standard-cell library exists in this environment** (same honest caveat the prior study
  carried) -- every number in this document is a generic, technology-independent gate-level analysis,
  not an absolute-picosecond one.
- **Not committed or pushed**, matching this session's established pattern and this repo's own
  standing "no commit/push without explicit separate instruction" rule.

## Files changed

`veda-core/rtl/veda_core.tlv` (the widening itself, already in place at session start; the 3
RTL-only findings' fixes are folded into this same file, already committed-clean since no mutation
was left applied). New: 6 `rtl/sim/veda_smoke_*.S` + 6 matching `tb_veda_smoke_*.sv` (Task 1).
Modified: `rtl/run_veda_smoke_test.sh` (registers the 6 new tests), 10 pre-existing
`rtl/sim/veda_smoke_*.S` + 3 `tb_veda_smoke_*.sv` (the sentinel-literal/alignment-offset fixes
above). This document.

## Adversarial-review response (2026-08-19, same day) -- 8 test-coverage/doc-accuracy findings closed

A follow-up adversarial multi-agent review of this same widening pass came back clean on the two
dimensions that matter most for a security feature -- width consistency (every 20-bit touch point
checked end to end) and security enforcement (an adversarial "find a bypass" audit of the alignment
gate, 2-granule tag, CSetBounds fix, CSeal fix, and R21-guard fix) -- **zero findings on either**. The
hardware itself was not reopened. The review did find 8 real gaps in test coverage and doc accuracy,
closed here, `veda_core.tlv` untouched:

1. **[HIGH] No test round-tripped a widened (>0xFFFF) Length/Offset capability through OCS.C/OCL.C's
   136-bit pack.** New: `rtl/sim/veda_smoke_oclc_widened_roundtrip.S` + testbench -- Length=0x50000,
   Offset moved to 0x10005 via OCA, stored/reloaded through a second object via OCS.C/OCL.C, Tag/Base/
   Length/Offset all confirmed bit-for-bit intact.
2. **[HIGH] CUnseal's and OCJALR's own widened-otype compare sites never independently tested.** New:
   `rtl/sim/veda_smoke_cunseal_offset_hibits_neg.S` + testbench -- an attacker authority with
   Offset=0x10005 (aliasing real otype=5 in its low 16 bits) is proven to fail CUnseal, while the exact
   real authority (Offset=5) is proven to succeed on the same sealed capability. OCJALR's own site was
   deliberately not given a separate test (see the finding's own scoping note repeated in the test
   file's header) -- it shares the identical `{4'b0, otype}` idiom per the review's own citation and is
   structurally simpler than CUnseal's, so this one proof stands in for both by design, not by omission.
3. **[MEDIUM] The alignment-gate negative test didn't isolate 32-byte alignment from a coarser
   requirement.** `veda_smoke_oclc_alignment_neg.S`'s target Base changed from `0x80010004` (misaligned
   at every power-of-two >= 8) to `0x80010010` (16-byte aligned, NOT 32-byte aligned) -- now a genuine
   discriminator between a correct 32-byte gate and a hypothetical, wrongly-coarser 16-byte-only one.
   Still traps with cause 0x08 under the real gate.
4. **[MEDIUM] `veda_smoke_widened_bounds_neg.S`'s header comment overclaimed.** The negative test alone
   cannot distinguish "genuinely widened Length" from "Length silently truncated to 0" (both trap at
   this offset). Comment corrected to state this and to name the positive sibling
   (`veda_smoke_widened_bounds.S`) as the file this negative test must be read together with to support
   the full claim.
5. **[LOW] CSetBounds's success path at a genuinely widened new_length was untested.** A second phase
   added to the existing `veda_smoke_csetbounds_widthcheck_neg.S` (Object_ID=510, Length=0x50000,
   CSetBounds to new_length=0x30000) proves the widened value threads through: Tag=1, CGetLen reads back
   0x30000 exactly.
6. Closed by #1 above -- the round-trip test's own final instruction is a CGetOffset call on the
   widened value.
7. **[MEDIUM] Doc citation error.** The "OCA/CSetBounds" section above wrongly implied both signals lived
   at `veda_core.tlv:2081-2082` -- those lines are CSetBounds-only. Fixed to cite OCA's own real site
   (`veda_core.tlv:2049`) separately.
8. **[LOW] Fabricated summary tally line.** The "Final verification" section's fenced transcript above
   presented a `61/61 passed...` line as if `run_veda_smoke_test.sh` printed it; that script has no such
   aggregate-counting logic (grep-confirmed) and only lets each testbench print its own
   `*** TEST PASSED ***`. Fixed: the count is now presented as a manually-derived summary immediately
   after the fenced block, not inside it.

**Final verification after closing all 8 findings** (real, run output, `*** TEST PASSED ***`/
`*** TEST FAILED ***` counted by hand from the real transcript, same honest convention finding #8
above establishes -- not a script-printed aggregate):

```
$ cd rtl && bash run_veda_smoke_test.sh
```
63 of 63 `*** TEST PASSED ***`, 0 `*** TEST FAILED ***` (the prior 61 + 2 new: `oclc_widened_roundtrip`,
`cunseal_offset_hibits_neg`; findings #3/#4/#5/#7/#8 modified existing files/doc text without adding a
new testbench, so they don't change this count).

```
$ cd rtl && bash run_act4_tests.sh
...
Summary: 51/51 passed, 0 failed, 0 timed out
```

Zero regressions on the pre-existing 61.

**Files changed in this response:** New: `rtl/sim/veda_smoke_oclc_widened_roundtrip.S` +
`tb_veda_smoke_oclc_widened_roundtrip.sv`, `rtl/sim/veda_smoke_cunseal_offset_hibits_neg.S` +
`tb_veda_smoke_cunseal_offset_hibits_neg.sv`. Modified: `rtl/sim/veda_smoke_oclc_alignment_neg.S`
(finding #3), `rtl/sim/veda_smoke_widened_bounds_neg.S` (finding #4, comment only),
`rtl/sim/veda_smoke_csetbounds_widthcheck_neg.S` + `tb_veda_smoke_csetbounds_widthcheck_neg.sv`
(finding #5), `rtl/run_veda_smoke_test.sh` (registers the 2 new tests), this document (findings #7/#8).
`veda_core.tlv` itself: **not modified**.
