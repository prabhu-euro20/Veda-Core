# Veda-Core Toolchain Milestone 4: Capability-Register Visibility in the Debugger

**Date:** 2026-07-31
**Scope:** extend Toolchain Milestone 3's GDB stub so `riscv64-unknown-elf-gdb`
can display Veda-Core's own 16-entry, 128-bit capability register file
(`c0`-`c15`) plus each register's real, out-of-band tag bit, following the
real, production CHERI/Morello precedent (a GDB target-description XML,
served over `qXfer:features:read`, not core GDB modification).

## A real design question, resolved by reading the formal model in full, not assumed

Milestone 3's GPR shadow-tracking (via `xreg_full_write_callback`) does
**not** transfer to capability registers. Reading `veda_regs.sail` in full
showed why: `cr0`-`cr15` are plain Sail `register` declarations of type
`capability`, written through a hand-written, match-based `wC()` accessor —
a completely separate mechanism from the base RISC-V model's `wX`/register
-write path that `xreg_full_write_callback` hooks into. Confirmed by also
re-checking `riscv_callbacks_if.h` in full: no capability-register-write
callback exists anywhere in the base model's callback interface (it predates
Veda-Core and was never extended for this).

Two real options existed: (a) modify `veda_regs.sail`'s own `wC()`/`wCTag()`
to call a brand-new C++ callback, replicating the base model's own
write-notification pattern — real, working, but a real, invasive change to
the single most safety-critical file in the project, and (b) read capability
-register state **directly and on demand**, since Sail's own C backend
compiles every `register` declaration into a directly-addressable global
(confirmed for GPRs/PC already via `mepc()`'s own existing implementation:
`return zmepc.bits;`, a direct field read, no callback involved) — and,
critically, that the Sail-generated per-model header
(`build/sail_riscv_model.h`) already exposes `hart::Model::zrC(int64_t)` and
`hart::Model::zrCTag(int64_t)` as real, compiled, callable accessor
functions (the direct C++ compilation of `veda_regs.sail`'s own `rC`/`rCTag`
functions).

**Chose (b)**: zero changes to `veda_regs.sail`, the formal model stays
completely untouched. A pull-based read (via `zrC`/`zrCTag`, called fresh
every time GDB asks) rather than a push-based shadow, architecturally
simpler than the GPR case, not just safer.

## What was built

- `ModelImpl::pack_veda_capability_reg(int, uint8_t[16])` and
  `ModelImpl::read_veda_capability_tag(int)` (new public methods,
  `riscv_model_impl.{h,cpp}`) — thin wrappers exposing the otherwise
  privately-inherited `hart::Model::zrC`/`zrCTag` to the rest of the C++
  harness, following the exact same public-wrapper pattern this project's
  own `mepc()`/`xlen()` already establish.
- **The packed 128-bit value is the real, already-verified hardware
  encoding**, not a hand-rolled re-serialization: `pack_veda_capability_reg`
  calls `zveda_cap_pack()` — the *same* Sail function `OCL.C`/`OCS.C`
  themselves use for capability-width memory access (found already compiled
  and available in the generated header; reused directly, matching this
  project's own "never re-derive what's already real and verified"
  discipline, the same reasoning already applied to `read_mem`/`write_mem`).
- `gdb_handler::build_target_description_xml()` (`gdbstub.cpp`): a real GDB
  target-description XML, two `<feature>` blocks — `org.gnu.gdb.riscv.cpu`
  restating the exact GPR/pc register order Milestone 3 already had working
  via GDB's own built-in default (so serving *any* target.xml at all does
  not silently change already-verified base behavior), and a new
  `org.veda-core.capabilities` feature: `c0`-`c15` as 128-bit `<vector
  id="v128" type="uint8" count="16"/>` registers (regnum 33-48), plus
  `c0_tag`-`c15_tag` as separate 8-bit registers (regnum 49-64) — the tag
  modeled as its own pseudo-register rather than folded into the 128-bit
  value, matching real CHERI-GDB's own documented `.t` pseudo-register
  convention (already researched this session) and VEDA_CORE_SPEC.md's own
  explicit statement that the tag is "not counted in the 128."
- `gdb_handler::handle_qxfer()`: real `qXfer:features:read:target.xml`
  chunked-transfer handling (`offset,length` parsing, `m`/`l` continuation
  markers per the real RSP spec), plus a `qSupported` reply now honestly
  advertising exactly the one real feature implemented
  (`qXfer:features:read+`), not a blanket claim.
- `handle_read_registers()` (the `g` command) extended to append all 16
  packed capability values and all 16 tag bytes after the existing 33
  base registers.

## Verification (real, both independent-path-agreement checks the plan required)

**Zero regression**: `sail_riscv_sim` rebuilt; the full Sail self-check
suite re-run — **30/30 passed, unchanged**. (RTL/ACT4 suites are unaffected
by this milestone — they exercise `veda_core.tlv` via Icarus Verilog, a
completely separate toolchain from the Sail C emulator this milestone
touches; not re-run for that reason, not overlooked.)

**Real end-to-end test**: a fresh standalone RV64I program
(`cap_test.S`, assembled/linked with the real toolchain) performs a real
`veda.bind c0, x1` against the seeded `Object_ID=1` (`Base=0x80010000`,
`Length=0x40`, `Perms=0x100C`), then independently reads the same capability
back via `cgetbase`/`cgetlen`/`cgetperm`/`cgettag` into GPRs `a0`-`a3` — the
exact second, independent read path the plan's own verification method
specified.

The real `riscv64-unknown-elf-gdb` client, connected to a live
`sail_riscv_sim --gdbstub` session, at the breakpoint after all five
instructions:

```
a0  0x80010000   (cgetbase)
a1  0x40         (cgetlen)
a2  0x100c       (cgetperm)
a3  0x1          (cgettag)
c0  {0x0, 0xfe, 0xff, 0x19, 0x20, 0x0, 0x0, 0x80, 0x0, 0x0, 0x0, 0x2, 0x0, 0x3, 0x0, 0x0}
c0_tag  0x1
```

**Two independent-path checks, both confirmed to agree**:
1. `c0_tag` (read via the new target-description-XML pseudo-register) `= 1`,
   exactly matching `a3` (`cgettag`'s own independent GPR readback) `= 1`.
2. The raw `c0` bytes were independently hand-computed from
   VEDA_CORE_SPEC.md's own documented packed-capability bit layout
   (`Object_ID(23) @ Base(32) @ Length(16) @ Offset(16) @ Perms(16) @
   otype(16) @ Reserved(8) @ padding(1)`, with `Object_ID=1`,
   `Base=0x80010000`, `Length=0x0040`, `Offset=0` [Bind always resets
   Offset], `Perms=0x100C`, `otype=0xFFFF` [the unsealed sentinel],
   `Reserved=0` [fresh generation]) via an independent Python script — all
   **16 of 16 bytes matched exactly** what GDB displayed.

## What remains open, honestly

- GDB's own embedded-Python bootstrap is still not fully resolved (Toolchain
  Milestone 3's own noted gap) — this milestone's XML-based approach was
  deliberately chosen specifically because it needs **no** Python support at
  all, so this gap did not block M4, but real Python-based pretty-printing
  (showing `c0` as named `Base=...`/`Length=...`/`Perms=...` fields instead
  of a raw 16-byte vector, matching CHERI-GDB's own fuller display) remains
  future work, not attempted here — a deliberate, stated scope choice (the
  earlier debugger-precedent research explicitly named fancy Python
  pretty-printers as a lower-priority "Phase 3," not needed for real
  capability-value visibility, which this milestone's raw-byte `<vector>`
  type already delivers in full, verified fidelity).
- Only a positive (`Tag=1`) case was exercised end-to-end above; a real
  negative case (an unbound/never-populated capability register correctly
  showing `Tag=0`) was not separately re-verified this milestone, though the
  same `zrCTag` accessor is used regardless of tag value, so no separate
  code path exists to diverge.

## Reproducing this

New/modified files: `riscv_model_impl.{h,cpp}` (capability accessors),
`gdbstub.{h,cpp}` (target-description XML, `qXfer` handling, extended `g`
reply). Rebuild via `cd toolchain/sail-riscv/build && make sail_riscv_sim`.
Connect exactly as Toolchain Milestone 3 describes; `info registers c0
c0_tag` (or `p $c0`) now shows real, live capability state after any real
`veda.bind`.
