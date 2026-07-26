# RVA23 Base Core — Phase 1 Milestone Log

## Milestone A — Toolchain-proving minimal subset (done)

`rv64i_core.tlv` implementing ADDI/ADD/SUB/BEQ/JAL. Transpiled via `sandpiper-saas`,
compiled with Icarus Verilog, simulated to `*** TEST PASSED ***`. Manual trace review
confirmed both a taken branch (correct next-PC) and a not-taken branch (correct
sequential fallthrough), plus a JAL self-loop.

## Milestone B — Complete RV64I base ISA, all 50 encodings (done)

All 50 RV64I encodings implemented (the 38 RV32I-equivalent instructions including
FENCE, excluding ECALL/EBREAK which are deferred, plus the 12 RV64-only `*W`
encodings). Byte-addressable data memory built on a doubleword-granular `/dmem` array
with explicit byte-lane shift/mask/merge logic. 81-instruction hand-assembled smoke
test exercises every encoding at least once; every hand-derived expected value was
cross-checked against the real simulation trace and matched exactly, including:

- AUIPC's self-address (x7 == the instruction's own PC, 160)
- JAL's link value (x29 == 152, the correct return address)
- `*W` truncate+sign-extend behavior: `ADDW` on operands that overflow the 32-bit sign
  bit produces a large negative 64-bit result (x26 = -2147483647), dramatically
  different from a plain 64-bit `ADD` on the same bit pattern (x27 = +2147483649)
- An unaligned, same-doubleword, different-byte-lane store/load round trip with no
  cross-byte corruption (x22 = 42, x31 unchanged at -5)
- JALR's register-relative jump landing correctly past a decoy instruction

Two real bugs were found and fixed via this process, not assumed away:
1. `$signed(...)` is misparsed by SandPiper as a TL-Verilog signal reference (the `$`
   sigil collides with TLV's own syntax) — replaced with a manual sign-bit-replication
   technique for both signed comparison and arithmetic right shift.
2. The `JAL` encoder function had the `imm[19:12]` and `imm[10:1]` fields swapped
   relative to the real J-type instruction bit layout — caught by a wildly wrong PC
   jump in the simulation trace, not by inspection.

First `\viz_js` visualization block added (status/disassembly line, register grid,
datapath activity indicators). Verified: SandPiper accepts the file both with the
block stripped (headless simulation path) and unstripped (confirms the block itself
is syntactically valid TL-Verilog+JS) with zero errors. A real bug was caught here
too: SandPiper's preprocessor scans for `/scope[N]$sig` syntax even inside JS string
literals, so a dynamically-interpolated `'/xreg[' + i + ']$val'` string breaks the
headless transpile — fixed by reading each of the 31 registers via its own
literal-index string, matching `arm_single_cycle.tlv`'s own proven pattern.
Live rendering inside Makerchip's real web IDE (Verilator + VIZ panel) was
subsequently confirmed directly by the user, including a `'*passed'` VIZ read that
doesn't resolve top-level `*name` assertions (Makerchip's VIZ signal-string
convention only resolves `$name`/`/scope[n]$name`) — fixed by computing `passed`
locally in the viz JS from already-read register values instead.

## Milestone C — ACT4 DUT config + real ELF-based testbench (done)

Created `act4-verify/config/cores/veda/rva23-base-rv64i/` (5 files, pruned from the
`cvw-rv64gc` template): `test_config.yaml`, `rva23-base-rv64i.yaml` (UDB config,
I/Zicsr/Zifencei/Sm only), `rvmodel_macros.h`, `link.ld` (base `0x80000000`),
`sail.json` (all non-I extensions disabled, several required schema fields added
that only surfaced via real validation errors — `medeleg`/`mideleg` delegatable
bits, `privileged_isa_version`, `F.fflags_dirty_policy`, `mstatus.fs_legal_states`
corrected to `ExtContext_Off`). `CONFIG_FILES=... EXTENSIONS=I make` succeeds: 204
tasks, 102 real ELFs generated.

Extended `rv64i_core.tlv` with an `elfmem`/`act4_mode` path: `$readmemh`-loadable
byte-addressable memory (`+elf_hex=` plusarg), instruction-fetch and load-data muxes
that switch between the Milestone A/B ROM and the loaded ELF image, and a trailing
`\SV` `always_ff` block driving stores into `elfmem` (referencing SandPiper's real
mangled signal names directly — new wide top-level `*name[N:0]` signals were tried
first but SandPiper generates a bare `assign` with no matching net declaration for
those, a confirmed transpiler bug, not a workaround for a design choice).

Wrote `rtl/sim/tb_act4.sv` (loads the ELF image, polls `tohost`, PASS/FAIL/TIMEOUT
after a 200k-cycle backstop) and `rtl/run_act4_tests.sh` (transpile+compile once,
loop ELFs, resolve each test's own `tohost` address via `readelf` since it shifts
per-test).

**Three real bugs found and fixed, all via full execution — not assumed away:**

1. **RTL bug** — SLLI/SRLI/SRAI used the full `funct7` as their opcode
   discriminator, but bit 25 of that field is actually `shamt[5]` for RV64
   shift-immediates with shamt >= 32, not part of the discriminator. Fixed with a
   dedicated `funct6` field. Verified against Sail's own reference trace (exact
   SP/GP match after a chained-shift boot sequence).
2. **Testbench bug** — naive "tohost low word != 0" polling misfires on the first
   byte of a diagnostic string this DUT config's `RVMODEL_IO_WRITE_STR` writes to
   the same address (confirmed: `0x0000000a` = `'\n'`). Even "high word == 0" alone
   wasn't sufficient — a race between the two-word write sequence. Fixed by
   requiring the candidate halt value to remain stable for several cycles (the real
   halt code spins forever; character prints move on within 1-2 cycles).
3. **Process bug** — `run_act4_tests.sh` defaulted to the wrong ELF directory
   (`build/rv64i/I/*.sig.elf`, the intermediate non-self-checking build used only to
   generate the golden signature; it never compares anything and always halts PASS).
   The real self-checking artifact is `elfs/rv64i/I/*.elf`. Caught via a
   negative-control test: a deliberately-broken ALU op still reported PASS against
   the wrong artifact. Fixed the default path; re-validated the same broken core
   against the correct artifact now correctly reports `FAIL (tohost=3)`.

Done criteria: config build succeeds (✓, 204 tasks / 102 ELFs); representative subset
passes against the real self-checking artifacts (✓, 6/6 including a negative
control); deliberately-broken core correctly fails, not just via TIMEOUT but via a
clean `FAIL` with the real halt-fail code (✓).

## Milestone D — Full RV64I ACT4 suite (done)

`run_act4_tests.sh` full-suite run: **51/51 PASS**, zero exceptions. See
`rtl/docs/ACT4_RESULTS.md` for the full per-test list, toolchain versions, and bug
log. Milestone A/B smoke test re-verified passing after all Milestone C/D RTL and
process changes. This closes Phase 1.
