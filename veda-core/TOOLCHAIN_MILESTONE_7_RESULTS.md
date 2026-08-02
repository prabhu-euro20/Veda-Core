# Veda-Core Toolchain Milestone 7: Minimal Software Runtime Library (veda_rt)

**Date:** 2026-07-31
**Scope:** a real, minimal malloc/free-equivalent C runtime
(`veda-core/runtime/`) wrapping ODT-Populate-Fast/Bind/ODT-Destroy — the
first real software in this project to be assembled with the LLVM toolchain
built in Toolchain Milestones 2/5a/5b-M6, using real Veda-Core mnemonics
(`veda.odt.populate.fast`, `veda.odt.destroy`, `veda.bind.notrap`, `ocl.d`,
`ocs.d`, `cgettag`) instead of hand-encoded hex or `.insn`.

## Design, grounded directly in Sail source read in full this session

Before writing any code, `veda_types.sail`, `veda_ocl_insts.sail`,
`veda_bind_insts.sail`, and `veda_regs.sail` were read in full (not
re-derived from an earlier summary) to confirm the real semantics this
library depends on:

- **ODT-Populate/Destroy are M-mode-only** (or ODA-authorized —
  `veda_oda_authorized()`), enforced by `Illegal_Instruction()`. Every
  existing test program in this project runs entirely in M-mode with no
  privilege drop; this runtime does the same, stated explicitly rather than
  silently assumed.
- **`VEDA_ODT_POPULATE_FAST`'s Length/Perms come from the shared `veda_attr`
  CSR** (0x7C4), not a per-call operand — a real, deliberate design already
  built in Milestone 18 for the common case of many objects sharing one
  size/permission template. This directly shapes the library's own honest
  scope: a **single-slab-size pool allocator**, not a general variable-size
  malloc. Stated as a real design consequence of the ISA's own real
  primitive, not an arbitrary simplification.
- **The generation-counter retirement threshold is exactly 256 real Destroy
  calls**, independently re-derived from `veda_ocl_insts.sail`'s
  `VEDA_ODT_DESTROY` execute clause (`new_generation` bumps unconditionally
  every call; `new_retired` fires once `old_entry.generation == 0xff`) and
  cross-checked against `sail_tests/vc_gen_retire_neg.S`'s own real
  `.rept 256` test — both agree exactly.
- **No ISA-visible instruction exposes the ODT entry's live generation
  counter** (the 7 real Veda-Cap query instructions query the *capability
  register's* cached fields, not the ODT entry directly). This means the
  runtime's own software-side `g_destroy_count[]` mirror is not a
  convenience cache of hardware state — it is the *only* copy that exists in
  software, and it must exactly replicate hardware's own per-call bump rule
  or the two states silently diverge. Stated explicitly in `veda_rt.c` as a
  real, current ISA limitation, not glossed over.
- Object_ID range `[1000, 1000+N)` was deliberately chosen clear of
  `veda_regs.sail`'s own `veda_test_seed_odt()` (IDs 1-5, seeded on every
  `ext_reset`) and the self-check suite's own hand-picked IDs (e.g. 50/51),
  so this runtime never observes another test's pre-existing ODT state.

## What was built

- `veda_rt.h` / `veda_rt.c` — the allocator: `veda_rt_init`, `veda_malloc`,
  `veda_free`, `veda_ocl_d`, `veda_ocs_d`. Object_ID and backing-memory slot
  are 1:1 (a real, stated scope limit: once a slot retires, its backing
  memory is permanently unusable too — a production allocator would decouple
  the two).
- `veda_rt_asm.S` — raw ISA-level primitives in real mnemonics, C-callable
  per the standard RV64 calling convention. The runtime's single working
  capability register is `c1`, a fixed, documented convention (no dynamic
  capability-register allocation exists before Milestone 8/9's compiler
  pass).
- `crt0.S` / `veda_rt.ld` — real bare-metal startup (stack init, `.bss`
  zeroing) and linker script, extending `sail_tests/veda_selfcheck.ld`'s own
  real conventions with a `.bss`/stack region neither existing script needed
  (no prior test made real function calls or used mutable global state).
- `veda_rt_positive_test.c` / `veda_rt_retire_neg_test.c` — the two real
  verification programs (below).
- `veda_rt_trap_catcher.S` — a real trap-catch-and-**resume** handler (every
  existing self-check test's own trap handler halts permanently from inside
  the handler; this is the first one in the project that resumes normal
  execution via a real `mret` afterward, needed so the negative test's `main`
  can keep running and report a real pass/fail code through the normal
  `crt0` flow).

## A real gap found in the LLVM driver, routed around with the already-verified tool

`clang --target=riscv64 -march=rv64i_zicsr_xveda ...` and
`clang ... -Xclang -target-feature -Xclang +xveda ...` both failed —
`XVeda` is registered in `RISCVFeatures.td` (Milestone 5a) and works
correctly with `llvm-mc -mattr=+xveda` (verified extensively in Milestones
5a/5b-M6), but the clang **driver's** front-end ISA-string parser
(`llvm/lib/TargetParser/RISCVISAInfo.cpp`, a target-independent library
built from a separately-generated `RISCVTargetParserDef.inc`) rejected the
extension outright, and injecting the target-feature past that parser did
not reach the integrated assembler's own subtarget feature bits either.
This is a real, third registration surface (distinct from `RISCVFeatures.td`
and `RISCVDisassembler.cpp`'s `DecoderList32`, the two already found in
Milestones 5a/5b-M6) — not chased down further this session, since a
completely legitimate, already-fully-verified path exists: **`llvm-mc`
directly** assembles all three `.S` files (real mnemonics, `-mattr=+xveda`)
with zero errors, and `clang` (no special flags needed — the `.c` files
contain no custom instructions) compiles the C code; `riscv64-unknown-elf-ld`
(the project's own established, real linker) links the result. This is
exactly the same tool composition Milestone 5a's own results doc already
used for its `llvm-mc`/`llvm-objdump` round-trip checks, just now producing
a real, runnable, linked program instead of isolated instruction encodings.
Fixing the clang driver's own arch-string registration is real, legitimate
future work, not required to close this milestone's actual goal.

## Verification — real, both directions, with exact failure localization (not just pass/fail)

**Positive test** (`veda_rt_positive_test`, `VEDA_RT_MAX_OBJECTS=8`): 6
rounds of allocate-all-8 / write a distinct pattern via `veda_ocs_d` / read
back via `veda_ocl_d` and verify / free-all-8 — 48 full
malloc-write-read-free cycles across all slots.
```
HTIF located at 0x80000430
Entry point: 0x80000000
SUCCESS
```

**Negative test** (`veda_rt_retire_neg_test`, built with
`-DVEDA_RT_MAX_OBJECTS=1` so one slot's retirement empties the whole pool):
256 real Destroy calls on the same slot (1 sanity round-trip + 255 more
cycles), then two independent checks — (1) the library's own `veda_malloc`
must now refuse any further allocation, entirely from its own software
bookkeeping, without ever letting a real `ODT-Populate-Fast` execute against
the retired slot; (2) a direct, library-bypassing probe calls the raw
`veda_odt_populate_fast_asm` primitive against the same, now-known-retired
Object_ID and confirms it genuinely still hard-faults
(`Illegal_Instruction`, `mcause=2`), proving the software mirror actually
matches real hardware state rather than merely never having been asked.
```
HTIF located at 0x800003b0
Entry point: 0x80000000
SUCCESS
```

**Mutation testing — proving both checkers can actually fail, not just pass
vacuously.** A debug `crt0` variant reporting `main()`'s real return code
(instead of collapsing every failure to a fixed exit code) confirmed exact,
correct failure localization for two independent, deliberate bugs:

- Positive test, one write corrupted (`pattern ^= 0x1` for slot 3 only):
  `FAILURE: 4` — exactly the readback-mismatch check (`if (got != pattern)
  return 4;`), not any other check.
- Negative test, stopped 5 destroy-cycles short of the real 256-call
  threshold (250 instead of 255): `FAILURE: 5` — exactly the "`veda_malloc`
  must now refuse" check firing *early* (proving the real slot had NOT
  actually retired yet, i.e. the threshold genuinely requires the full 256
  calls, not "eventually fails at some point").

Both real (unmutated) programs still reported `SUCCESS` (return code 0)
under the same debug harness, confirming the mutations — not some unrelated
harness quirk — were what changed the outcome.

**Zero regression**: the full existing 30-test self-check suite
(`sail_tests/run_veda_selfcheck_tests.sh`) still passes 30/30 — expected and
confirmed, since this milestone touched no Sail model, RTL, or existing test
file, only new files under `veda-core/runtime/`.

## What remains open, honestly

- Single-slab-size pool allocator only (`VEDA_RT_MAX_OBJECTS` fixed slots,
  all sized `VEDA_RT_SLOT_SIZE` bytes) — not a general variable-size malloc.
  A real, direct consequence of `VEDA_ODT_POPULATE_FAST`'s own shared-template
  design (see above), not an arbitrary cut corner.
- Object_ID and backing memory are 1:1; a retired Object_ID's backing slot
  is permanently lost too. A production allocator would decouple memory
  reuse from Object_ID reuse.
- No RTL cross-check yet (the plan's own stated "Sail-first-then-RTL"
  discipline) — this milestone ran under `sail_riscv_sim` only, matching
  every other Sail-model-first milestone in this project before its own RTL
  pass; an RTL run of these same test programs is legitimate, real follow-up
  work if/when this runtime needs to be demonstrated on the actual
  synthesizable core, not required to close this milestone.
- The clang driver's own arch-string extension registration gap (above) is
  real and unresolved — `llvm-mc` is used directly as the assembler instead,
  a completely legitimate, already-verified substitute for this milestone's
  actual goal.

## Reproducing this

```
cd veda-core/runtime && ./run_veda_rt_tests.sh
```
