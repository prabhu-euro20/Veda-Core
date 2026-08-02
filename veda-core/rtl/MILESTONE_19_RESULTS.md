# Veda-Core RTL Milestone 19 Results: Veda-Purecap Enforcement

**Date:** 2026-08-02
**Scope:** the real RTL mirror of the Sail-side Milestone 19
(`veda-core/MILESTONE_19_RESULTS.md`) -- closing, in the actual
hardware model (not just the formal model), the real
`CGetBase`-then-ordinary-load/store bypass: a raw `Base` address
extracted via `CGetBase` (a legitimate, spec-required query
instruction) followed by an ordinary RV64I `ld`/`sd` completely skips
every Veda-Core check, because base-ISA loads/stores never went
through any capability-aware path in this file at all before this
milestone. This RTL pass was explicitly deferred (`MILESTONE_22_RESULTS.md`'s
own "Not yet built" section) until a directed subsystem audit
confirmed it as the single most concrete, actionable, highest-priority
gap remaining -- the Sail-side fix already existed and was verified;
the real hardware model did not yet enforce it.

## Design, mirrored field-for-field from the already-verified Sail side

- **New CSR, `veda_mode` at `0x7C5`** (bit 0 = `veda_purecap`) --
  confirmed collision-free against every `$csr_is_veda_*` address
  already decoded in `veda_core.tlv` before adopting it (0x7C0-0x7C4
  already in use, 0x7C5 free). Same simple reset/CSRRW-only pattern
  `veda_attr` (Milestone 18) already established -- no privilege check
  needed beyond what already exists (this core has no S/U-mode
  concept yet; every CSR write in this file is implicitly M-mode-only
  for the identical, already-stated reason MRET's own comment gives).
- **A new violation signal, `$veda_purecap_violation`**, gated on
  `$is_load || $is_store` (the base-ISA opcodes only -- confirmed by
  direct inspection that this can never overlap with any
  `$is_veda_*`-gated signal, since those are mutually exclusive by
  opcode), true when either `$veda_mode[0]` is set (the global switch)
  OR `$veda_pcc_length != 16'hFFFF` (currently inside an OCInvoke
  -entered compartment -- the second real gap this milestone closes:
  code inside a compartment could otherwise still read/write memory
  directly, undermining the isolation Milestone 14's PCC-bounding is
  meant to provide).
- **New trap cause, `cap_idx=17` (`5'b10001`), `cause=0x07`
  (`5'b00111`)** -- built inline into `$mtval`'s own construction, the
  identical "special-cased, not routed through
  `$veda_trap_cap_idx[3:0]`" treatment Milestone 14's own `cap_idx=16`
  PCC sentinel already established (17 doesn't fit a 4-bit field
  either). `mtval = (17<<5)|0x07 = 0x227`, verified by hand before
  writing any test, matching the Sail side's own plan exactly.
- **Write suppression on both real memory-write paths**: `$reg_write`'s
  own `$is_load` term (a blocked load must not write `$rd`) and the
  real `elfmem[]` store's own `always_ff` gate (a blocked store must
  not touch memory at all) -- confirmed, by direct inspection of
  `$veda_purecap_violation`'s own definition, that this shares zero
  code path with any real Veda-Core instruction's own access
  (`$veda_ocl_load_data`, OCS.D's write, etc. are untouched).

## Real verification -- not estimated

Three new RTL test programs (`veda_smoke_m19.S`, `veda_smoke_m19_neg.S`,
`veda_smoke_m19_neg2.S`), assembled with the real, official
`riscv64-unknown-elf-as`/`-ld`/`-objcopy` toolchain (`-march=rv64i_zicsr`,
this project's own already-established toolchain), run against the
real, unmodified, committed `veda_core.tlv`:

| Test | Result |
|---|---|
| `veda_smoke_m19` (positive) | `x9=0x1234` (ordinary ld/sd unaffected at reset, purecap OFF), `x10=1`/`x12=0` (veda_mode CSR round-trips), `x11=0xABCD` (a real OCL.D/OCS.D pair through Object_ID=1 completely unaffected while purecap is ON), `x13=0x5678` (ordinary access resumes once purecap clears) -- **all correct** |
| `veda_smoke_m19_neg` (global purecap trigger) | `mcause=0x18`/`mtval=0x227` correctly captured (`x21=0x600D`); the blocked load's own destination register (`x9`) stays `0xDEAD`, never corrupted with load data; explicit software recovery (clear purecap, `mret`) correctly resumes and ordinary access works again (`x23=0x1234`, `x22=0x900D`) -- **all correct** |
| `veda_smoke_m19_neg2` (compartment trigger) | An ordinary `ld` fetched from *inside* a live, correctly-bounded OCInvoke compartment (the fetch itself is genuinely in-bounds -- structurally distinct from a Milestone 14 PCC fetch-violation) still hard-traps, identical `mcause`/`mtval=0x227`, with `veda_purecap` itself confirmed still `0` throughout (`x21=0x600D`, `x9` stays `0xDEAD`, `x22=0x900D`) -- **all correct**, proving the second trigger condition independently of the first |

Full regression: `run_veda_smoke_test.sh` -- **30/30 passed, 0 failed**
(27 pre-existing milestone tests + these 3 new ones, zero regressions).
`run_act4_tests.sh` -- **51/51 passed, 0 failed, 0 timed out**, confirming
zero behavioral change to the base RV64I ISA (the real correctness
requirement this milestone's own reset-default-off design was built to
guarantee).

## What this closes, stated plainly

Before this milestone, RTL and Sail diverged on the single largest
remaining security-relevant gap: Sail hard-traps a
`CGetBase`-then-ordinary-load/store attempt; the real hardware model
did not check for it at all. That divergence is now closed -- the
actual RTL a real chip would be built from now enforces the identical
property the formal model already proved.

## What remains open, honestly

- RTL mirrors for Milestones 20 (compartment-state CSR self-escape
  gating) and 21 (universal PCC reset on any trap) are separate,
  not-yet-attempted work -- named explicitly, not silently deferred
  (see the subsystem audit that scoped this whole pass).
- Milestone 22 needs no RTL work at all (confirmed directly: it added
  no new Sail mechanism, only documentation + a test; `OCJALR` and
  Milestone 14's own PCC fetch-check already correctly enforce the
  property it describes, in both layers, since Milestones 14/17).
- As on the Sail side, `Perms`-level gating on `veda_mode` writes
  itself remains out of scope (privilege-only, matching every other
  compartment CSR's own already-established, already-documented
  precedent -- not a gap unique to this milestone).
