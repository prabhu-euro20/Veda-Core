# Veda-Core Toolchain Milestone 3: Minimal GDB Stub (Standard GPRs)

**Date:** 2026-07-31
**Scope:** a real, interactive GDB Remote Serial Protocol (RSP) server built
into the official `riscv/sail-riscv` C emulator, enabling `riscv64-unknown-elf-gdb`
to `target remote` into a running `sail_riscv_sim` session, set breakpoints,
step/continue, and read registers/memory of a real Veda-Core test program.

## A plan assumption invalidated before any code was written

The plan's own first required task for this milestone was to validate, not
assume, that RVFI-DII could serve as the debugger's underlying control channel.
Both `rvfi_dii.cpp`/`.h` were read in full: RVFI-DII is an **instruction
-injection** protocol for differential testing (an external harness picks a
raw instruction encoding, the model executes exactly that one instruction and
reports a retire-trace packet back) — it has no concept of a loaded program
fetching its own instructions from its own PC, no ad-hoc register/memory read
outside of instruction-triggered telemetry, and no breakpoints. This is not
what a live debugger needs, and building an "RSP-to-RVFI-DII translator" as
originally sketched would not have worked.

**Real, better foundation found instead**, by reading the C emulator's own
harness in full (`riscv_sim.cpp`, `riscv_model_impl.h`, `riscv_callbacks_if.h`,
`riscv_callbacks_stop_at_pc.h`): `ModelImpl::try_step()` is the real,
already-existing single-instruction step primitive the main `run_sail()` loop
itself calls; `stop_at_pc_callbacks` is a real, already-existing single
-address breakpoint pattern (a `pc_write_callback` override checked every
iteration); `callbacks_if` is a clean, already-established virtual interface
for register/memory-write visibility. The GDB stub is built as a sibling to
`rvfi_handler`/`rvfi_callbacks`, not a translator on top of them.

## What was built

- `gdb_stub_callbacks` (`riscv_callbacks_gdbstub.{h,cpp}`): a `callbacks_if`
  subclass that shadow-tracks all 32 GPRs and PC via `xreg_full_write_callback`/
  `pc_write_callback` (there is no direct "read register N now" getter on
  `ModelImpl`, only write-notification hooks, so a live shadow copy is the
  correct mechanism, not a workaround), and a settable multi-address software
  breakpoint set (generalizing `stop_at_pc_callbacks`'s own single-address
  pattern).
- `gdb_handler` (`gdbstub.{h,cpp}`): the real RSP server — socket setup
  reusing `rvfi_handler::setup_socket()`'s exact, proven pattern (adapted to
  non-blocking mode via `select()`, needed to support both a blocking-style
  wait for the next GDB command and a genuine non-blocking poll for an async
  Ctrl-C during free-run); full RSP packet framing (`$...#checksum`, `+`/`-`
  acks); command dispatch for `?`, `g`, `G` (declared unsupported — no
  "set register" primitive exists, a real, stated scope limit), `m`, `M`,
  `s`, `c`, `Z0`/`z0`, `qSupported`.
- A three-state machine (`WaitingForCommand`/`StepPending`/`Running`) wired
  into `run_sail()`'s main loop exactly where `rvfi->pre_step()` is already
  checked each iteration — a new `--gdbstub <port>` CLI flag (mirroring
  `--rvfi-dii` exactly) and `--trace-gdbstub` for diagnostics.
- Landed as new commits on top of the real, official `riscv/sail-riscv` clone
  (`toolchain/sail-riscv/`, `origin = github.com/riscv/sail-riscv.git`),
  following the exact same local-commit pattern already used for every prior
  Veda-Core Sail addition — confirmed via `git log` before starting, not
  assumed.

## Two real bugs found and fixed during verification, not assumed away

1. **Initial PC read as 0, not the real entry point.** `pc_write_callback`
   only fires once an instruction actually retires, so before the very first
   `try_step()` call the shadow PC still held its zero-initialized default —
   a real GDB session connecting and immediately reading state (`g`, or
   simply attaching) would have shown PC 0 instead of the program's real
   entry point. Caught by an end-to-end protocol test, not by inspection.
   Fixed by adding `gdb_stub_callbacks::set_initial_pc()`, called from
   `init_model()` right after the real entry address is computed.
2. **Test-harness ELF entry point bug (not a gdbstub bug, but genuinely
   invalidated the first test run).** A hand-written `link.ld` for the
   standalone verification program placed a second, empty `.text` output
   section after `.text.init`; GNU `ld` silently fell back to that section's
   own start address as the ELF's `e_entry` field (`0x80000028`) instead of
   the correctly-defined `_start` symbol (`0x80000000`, confirmed via
   `readelf -s`) — even though `_start` was marked `.global`. Fixed by
   passing `--entry=_start` explicitly to `ld` rather than relying on
   default entry-point inference. This is a real, documented `ld` gotcha,
   not a Veda-Core-specific issue, but is worth remembering for every future
   hand-linked test program in this initiative.

## The `libpython3.12` fix, resolved properly (not with the earlier-flagged snap-symlink workaround)

Milestone 2 deferred this real, previously-broken dependency
(`riscv64-unknown-elf-gdb`'s `NEEDED libpython3.12.so.1.0`, absent because
this machine's apt repository has moved past Python 3.12 entirely). Resolved
this milestone, from genuinely official sources only, per explicit
instruction to use official tools/sources:

- Identified, via `packages.ubuntu.com`, that Ubuntu 24.04 LTS ("noble") is
  the real release carrying `libpython3.12t64`/`libpython3.12-stdlib`
  (`3.12.3-1ubuntu0.15`), still on Canonical's regular (non-archived)
  security mirror since noble remains in support until 2029.
- Downloaded both `.deb` packages directly from `security.ubuntu.com`,
  verified each one's real SHA256 against `packages.ubuntu.com`'s own
  published checksum before use (both matched exactly).
- Deliberately did **not** `dpkg -i` either package (that would register a
  foreign-release package in this machine's own dpkg database and pull in
  its full `Depends` chain against a different, incompatible release) —
  instead extracted just the real files and placed them outside package
  -manager control: `libpython3.12.so.1.0` into `/usr/local/lib/x86_64-linux
  -gnu/` (the standard, correct Linux convention for a manually-supplied
  shared library, confirmed present in `/etc/ld.so.conf.d/x86_64-linux-gnu
  .conf`'s own search path) plus `ldconfig`; the stdlib tree pointed to via
  `PYTHONHOME` at invocation time rather than installed system-wide.
- **Real, honest residual gap**: with only `LD_LIBRARY_PATH`/`PYTHONHOME` set
  (no full install), `riscv64-unknown-elf-gdb` still prints "Python failed to
  initialize with PYTHONHOME set... failed to get the Python codec of the
  filesystem encoding" — GDB's own embedded-Python bootstrap doesn't fully
  succeed cross-release, but GDB's own fallback behavior degrades gracefully
  rather than crashing, and every RSP-based feature this milestone actually
  needs (target remote, breakpoints, step/continue, register/memory read)
  works correctly regardless, verified below. **Not yet resolved**: real
  Python scripting support (needed for Toolchain Milestone 4's own planned
  capability-register pretty-printers, following the real CHERI-GDB
  precedent) — flagged explicitly as open work for that milestone, not
  silently assumed fixed here.

## Verification (real, end-to-end, both a protocol-level self-check and the real client)

**Zero regression**: `sail_riscv_sim` was rebuilt with the new files added to
`c_emulator/CMakeLists.txt`; the full pre-existing Sail self-check suite
(`sail_tests/run_veda_selfcheck_tests.sh`) was re-run afterward — **30/30
passed, unchanged**.

**Protocol-level self-check** (a disposable Python/stdlib-only RSP client,
scratchpad, not committed — used as a fast debugging aid before the real
client, not as the milestone's own final verification): register read,
memory read matching the real first-instruction encoding, single-step
correctly advancing `x1`/PC, breakpoint set+continue+hit all passed against
a real, freshly assembled+linked standalone RV64I test program.

**The real, plan-specified verification — the actual `riscv64-unknown-elf-gdb`
client** (GDB 17.1), run against the same test program and a live
`sail_riscv_sim --gdbstub` session:

```
target remote :9998            -> 0x0000000080000000 in _start ()
break *0x80000024               -> Breakpoint 1 at 0x80000024
continue                        -> Breakpoint 1, 0x0000000080000024 in done ()
info registers ra sp gp t0 ...   -> ra=0xf sp=0x14 gp=0x23 t0=0x600d
print/x $pc                     -> $1 = 0x80000024
```

Every value cross-checked by hand against the test program's own real
semantics (`ra`/x1 = 15 after the loop's exit condition; `sp`/x2 = 20,
untouched; `gp`/x3 = 10+20+5 = 35 = `0x23`; `t0`/x5 = the `0x600D` sentinel
set just before `done`; `$pc` = the exact breakpoint address) — all matched
exactly. This is the real, independent, non-scratchpad confirmation the
milestone's own verification method called for.

## What remains open, honestly

- Full Python scripting support for `riscv64-unknown-elf-gdb` is not yet
  properly resolved (works via manual `LD_LIBRARY_PATH`/`PYTHONHOME`
  env-vars pointed at extracted, official noble packages; a clean, permanent
  fix — e.g. building gdb from source against the system's current Python
  3.14, or a properly registered/isolated noble Python install — is real,
  scoped work for Toolchain Milestone 4, which needs it for capability
  -register pretty-printers).
- `G` (write registers) is unsupported — no direct "set register" primitive
  exists on `ModelImpl`; a real, stated scope limit, not silently omitted.
- Async Ctrl-C handling during free-run (`c`) is implemented but not yet
  exercised by an explicit test (the verification above used a breakpoint
  -triggered stop, not a manual interrupt) — a real, small gap to close in
  a follow-up test, not assumed working.
- Only standard 32 GPRs are visible — the 16-entry, 128-bit capability
  register file is Toolchain Milestone 4's own explicit scope.

## Reproducing this

Real files, committed to `toolchain/sail-riscv/c_emulator/`: `gdbstub.{h,cpp}`,
`riscv_callbacks_gdbstub.{h,cpp}`, plus the `cli_options.{h,cpp}`/
`riscv_sim.{h,cpp}`/`CMakeLists.txt` wiring described above. Rebuild via
`cd toolchain/sail-riscv/build && make sail_riscv_sim`. Invoke with
`sail_riscv_sim --config <cfg> --gdbstub <port> <elf>`, then connect with
`riscv64-unknown-elf-gdb -ex "target remote :<port>" ...` (with
`LD_LIBRARY_PATH`/`PYTHONHOME` set per the libpython3.12 fix above, until
Toolchain Milestone 4 resolves it properly).
