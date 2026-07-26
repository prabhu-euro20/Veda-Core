# Veda-Core Formal Model — Milestone V-A Results

**Date:** 2026-07-22
**Scope:** capability struct, 16-register Capability Register File, Object
Descriptor Table (flat, system-wide), Object-Bind (`Bind`/`Bind-NoTrap`/
`Rebind`), `OCL.D`/`OCS.D`. Built as a real Sail extension
(`toolchain/sail-riscv/model/extensions/Veda/`) inside this project's own
already-verified `sail-riscv` checkout, compiled into a real, working
`sail_riscv_sim` binary and run against a real hand-assembled test program
— not a paper design.

## Result: PASS, both positive and negative paths verified empirically

**Positive path** (`veda.bind c0, ra` binding the test-seeded `Object_ID=1`,
`ocs.d c0, sp, gp` storing `0x1234`, `ocl.d tp, c0, sp` loading it back):

```
[1] veda.bind c0, ra
[5] ocs.d c0, sp, gp
[7] ocl.d tp, c0, sp
    tp <- 0x0000000000001234
```

Exact round-trip, no traps — Object-Bind's ODT lookup, the local bounds/
permission/tag checks, and the real physical `read_ram`/`write_ram` access
all worked correctly together.

**Negative control** (`ocs.d c1, sp, gp` on `c1`, a capability register
never bound — `Tag` should read false):

```
CSR mcause (0x342) <- 0x0000000000000018   // 24 -- exactly VEDA_CORE_SPEC.md
                                            //  Section 3's committed mcause
CSR mtval  (0x343) <- 0x0000000000000022   // decodes to cause=0x02 (Tag
                                            //  Violation) cap_idx=1 (c1) --
                                            //  exactly right on both counts
```

Confirms the real trap mechanism (`E_Extension(())`, Section 3's `xtval`
layout) fires with the exact right top-level code and the exact right
sub-detail payload, not just "some trap happened."

## Real bugs found and fixed while building this (via actual compiler
errors and a real build, not assumed):

1. **A genuine spec gap, found before writing any Sail code**: `OCA`'s
   existing description referenced a capability `Offset` field that
   `VEDA_CORE_SPEC.md` Section 2's field table never defined, and the fixed
   128-bit budget had no room to simply add one. Resolved by replacing the
   inconsistent 32-bit `Limit` field with `Length`(16)+`Offset`(16) —
   documented in `VEDA_CORE_SPEC.md` Section 2 before any code was written,
   not patched around silently.
2. **Name collision**: `cregidx`/`Cregidx` already exist in the base
   `sail-riscv` (RVC's compressed-register index) — used `vcapidx`/
   `Vcapidx` instead, found by reading `core/regs.sail` before writing new
   code.
3. **`dec_str` used inside a `mapping clause assembly`**: invalid — Sail
   requires bidirectional (parseable) mappings there, and `dec_str` is a
   one-way function. Fixed with a real bidirectional lookup table, modeled
   on `core/regs.sail`'s own `reg_abi_name_raw`.
4. **Hardcoded `bits(64)` instead of `xlenbits`**: `physaddrbits` is
   `bits(34)` on RV32, `bits(64)` on RV64 — a hardcoded 64-bit width fails
   to typecheck generically. Fixed to use `xlenbits`/`xlen_bytes`
   throughout and gated `OCL.D`/`OCS.D`'s encoding on `xlen == 64`,
   mirroring the real base ISA's own `ADDIW`/`RTYPEW` convention for
   RV64-only instructions.
5. **Multi-pattern match arms don't exist in Sail** (`A, B => ...` is
   invalid; needs a wildcard or separate arms) — found via a real syntax
   error, fixed with a documented catch-all pattern.
6. **Invalid single-bit literal syntax** (`bits(1, 0b1)` isn't a real
   constructor) and **unconstrained-`int` bitvector indexing isn't
   statically provable** (`perms[b]` needs `b : range(0,15)`, not `int`) —
   both found via real type errors, fixed using the working precedent
   found in `core/misa_ext.sail` (`misa[C] == 0b1`).
7. **Extending the shared config schema breaks every existing config
   file that doesn't know about the new extension** — adding `Ext_Veda`
   made `sail_riscv_sim`'s build-time schema-conformance check fail against
   all 16 default configs and this project's own ACT4 `sail.json` (RVA23
   base core config). Fixed by adding `"Veda": {"supported": ...}` to the
   shared `config.json.in` template (propagates to all 16 generated
   configs) and to the RVA23 core's own ACT4 `sail.json`. **Not yet fixed**:
   ~34 other DUT configs elsewhere in `act4-verify/config/` (other teams'
   cores, not exercised by this project's own testing) would need the same
   fix before anyone builds against them with this modified `sail_riscv_sim`
   — a real, known consequence, flagged rather than silently left for
   someone else to discover.

## Test-scaffold caveat, explicitly temporary

No real ODT-population instruction exists yet (deliberately deferred to
Milestone V-B, `VEDA_CORE_SPEC.md` Section 5.1). This test seeds one ODT
entry directly in `postlude/step_ext.sail`'s real `ext_reset()` extension
hook (`veda_test_seed_odt()`, `extensions/Veda/veda_regs.sail`) — clearly
marked as temporary scaffolding, to be replaced once Milestone V-B designs
the real instruction/mechanism.

## Not yet built (Milestone V-B)

`NMC_ADD`, Veda-Atomic, `OCA`, the Veda-Cap query family, `CSeal`/
`CUnseal` and the sealed-capability enforcement split, and a real
ODT-population mechanism.

## Addendum, 2026-07-22: re-verified after `Object_ID` widening

Following `SCALING_BARRIERS_RESEARCH.md`'s scaling-barrier research pass,
`Object_ID` was widened 16→23 bits and the generation counter narrowed
15→8 bits (`VEDA_CORE_SPEC.md` §2). The Sail model (`veda_types.sail`,
`veda_regs.sail`, `veda_bind_insts.sail`) was updated to match, rebuilt
(`cmake --build build`, clean pass, no errors), and **both tests above
were re-run against the widened model and produced byte-identical
results** — the positive test still ends with `tp <- 0x0000000000001234`,
the negative control still traps with `mcause=0x18`/`mtval=0x22`. Real
regression found and fixed during this re-verification, not a code bug:
the first re-run used `act4-verify/config/cores/veda/rva23-base-rv64i/sail.json`,
which deliberately sets `Veda.supported: false` to protect the RVA23 base
core's own ACT4 conformance testing from this experimental extension —
using it caused every `VEDA_BINDINST` to decode as illegal (confirmed via
`--trace-exception`). Fixed by using a dedicated, Veda-enabled test config,
now checked into `veda-core/sail_tests/veda_test_sail.json` (a copy of the
ACT4 config with only `Veda.supported` flipped to `true`) alongside the
test sources (`veda_test.S`/`.ld`, `veda_neg.S`, `veda_encode.py`) — moved
out of the ephemeral scratchpad since Milestone V-B's own test suite will
need this same config repeatedly.
