# Veda-Core Developer Workflow Guide: Write, Build, Run, Debug Your Own Program

**Scope:** a real, reproducible path from zero to a working, self-debugged Veda-Core program,
for anyone who wants to write their own high-level C code against this architecture rather than
just read about it. Every command below is exactly what was run, on this machine, to produce the
results quoted -- nothing here is aspirational.

This guide assumes the toolchain is already built (`./toolchain/setup.sh`, see the top-level
`README.md`).

---

## 1. Write your own program

The safest, fully-supported entry point today is ordinary C against the real `veda_rt` allocator
API (`veda-core/runtime/veda_rt.h`) -- this is genuine, unrestricted compiled C, since it runs
*outside* any narrow OCInvoke-bound compartment (see the honest scope note at the bottom of this
guide for why that distinction matters).

Put your file anywhere you like -- it does not have to live inside this repo. Example,
`~/my_veda_projects/my_program.c`:

```c
#include "veda_rt.h"

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  veda_obj_t a = veda_malloc();
  veda_obj_t b = veda_malloc();
  if (a == VEDA_OBJ_INVALID || b == VEDA_OBJ_INVALID) return 1;

  if (!veda_ocs_d(a, 0, 21)) return 2;   // real hardware-checked store
  if (!veda_ocs_d(b, 0, 21)) return 3;

  uint64_t va = 0, vb = 0;
  if (!veda_ocl_d(a, 0, &va)) return 4;  // real hardware-checked load
  if (!veda_ocl_d(b, 0, &vb)) return 5;

  uint64_t sum = va + vb;
  if (!veda_ocs_d(a, 8, sum)) return 6;  // same object, second 8-byte slot

  uint64_t got = 0;
  if (!veda_ocl_d(a, 8, &got)) return 7;
  if (got != 42) return 8;

  veda_free(a);
  veda_free(b);
  return 0;   // 0 = SUCCESS
}
```

The real API (`runtime/veda_rt.h`): `veda_rt_init`, `veda_malloc`/`veda_free`,
`veda_ocl_d`/`veda_ocs_d` (8-byte hardware-checked load/store). `Object_ID` is an opaque handle --
never a raw address -- and bounds/permission/tag/generation checking is real hardware, not a
software wrapper.

---

## 2. Build it (works from any directory)

```bash
VEDA_CORE=/home/prabhu/makerchip/rva23-core/veda-core

LLVM=/home/prabhu/makerchip/rva23-core/toolchain/llvm-project/build/bin
CLANG=$LLVM/clang
MC=$LLVM/llvm-mc
LD=/home/prabhu/makerchip/rva23-core/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-ld
SIM=/home/prabhu/makerchip/rva23-core/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=$VEDA_CORE/sail_tests/veda_test_sail.json

CC_FLAGS="--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -O0 -g -I$VEDA_CORE/runtime"
MC_FLAGS="-triple=riscv64 -mattr=+xveda -filetype=obj -I$VEDA_CORE/sail_tests"

MY_PROGRAM=~/my_veda_projects/my_program.c   # wherever you saved it

$MC $MC_FLAGS -o /tmp/my_crt0.o $VEDA_CORE/runtime/crt0.S
$MC $MC_FLAGS -o /tmp/my_veda_rt_asm.o $VEDA_CORE/runtime/veda_rt_asm.S
$CLANG $CC_FLAGS -c -o /tmp/my_veda_rt.o $VEDA_CORE/runtime/veda_rt.c
$CLANG $CC_FLAGS -c -o /tmp/my_program.o $MY_PROGRAM

$LD -T $VEDA_CORE/runtime/veda_rt.ld -o /tmp/my_program.elf \
    /tmp/my_crt0.o /tmp/my_program.o /tmp/my_veda_rt.o /tmp/my_veda_rt_asm.o
```

`-g` is included so GDB has real source-level line info for later.

## 3. Run it

```bash
$SIM --config $CFG /tmp/my_program.elf
echo "exit code: $?"
```

**Honest limitation, stated plainly:** this is a bare-metal, freestanding environment -- there is
no `printf`/console/UART (verified directly against `sail_tests/veda_selfcheck_macros.S`: the only
output signal is a binary PASS/FAIL write to `tohost`). `exit code: 0` means `main()` returned 0
(`RVMODEL_HALT_PASS`); anything else means it returned that value (`RVMODEL_HALT_FAIL`). "Seeing
progress" beyond a single pass/fail code means either encoding results into distinct return codes
(as the example above does, one per failed check) or using GDB / a trace file, both below.

---

## 4. Debugging with real capability-register visibility

```bash
GDB=/home/prabhu/makerchip/rva23-core/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-gdb

$SIM --config $CFG --gdbstub 9998 /tmp/my_program.elf &
$GDB -ex "target remote :9998" /tmp/my_program.elf
```

Passing the `.elf` as a positional argument loads its symbol table -- without it, GDB has no idea
what `main` refers to and `break main` fails with "No symbol table is loaded."

Inside `gdb`, ordinary commands work (`break`, `continue`, `step`/`stepi`, `info registers`) plus
Veda-Core's own 16 capability registers are directly visible: `info registers c0 c0_tag` shows the
real, live 128-bit packed capability and its out-of-band tag bit, verified against an independent
second read path (`cgetbase`/`cgetlen`/`cgetperm`/`cgettag`) matching byte-for-byte.

**A known, non-fatal GDB startup warning on this machine**: `riscv64-unknown-elf-gdb` prints
`Python initialization failed: failed to get the Python codec of the filesystem encoding` on
every launch. This is not a new bug -- `TOOLCHAIN_MILESTONE_3_RESULTS.md` documents it: this
machine's apt repository has moved past the `libpython3.12` version this prebuilt GDB needs, so
its embedded-Python bootstrap degrades gracefully instead of fully initializing. Every RSP-based
feature used in this guide (`target remote`, breakpoints, step/continue, register/memory read)
works correctly regardless -- ignore the warning.

## 5. Debugging a real hardware trap -- and why GDB alone can't show you `mcause`/`mtval`

Verified directly against this project's own `gdbstub.cpp` (the GDB Remote Serial Protocol target
description it serves): only the 32 GPRs, `pc`, and Veda-Core's 16 capability registers
(`c0`-`c15`/`c0_tag`-`c15_tag`) are exposed as named GDB registers. There is no CSR access and no
`monitor` command for it -- `print $mcause` or `info registers mcause` will not work. To see
*which* hardware check fired, you need the CSR values captured somewhere GDB *can* read: an
ordinary C/assembly global.

This project already has exactly that pattern, `runtime/veda_rt_trap_catcher.S` (used by
`runtime/veda_rt_retire_neg_test.c`). The worked example below is a personal copy,
`compiler/my_trap_catcher.S`, extended to also capture `mtval`/`mepc` (the original only needed
`mcause`) -- copy it as-is, or adapt it for your own programs. Put it alongside your own program:

`compiler/my_trap_catcher.S` (or anywhere you like -- adjust the build command's path to match):
```asm
.section .text
.global my_trap_catcher_install
my_trap_catcher_install:
    la   t0, my_trap_catcher
    csrw mtvec, t0
    la   t0, g_trap_fired
    sw   x0, 0(t0)
    ret

.balign 4
my_trap_catcher:
    csrr t0, mcause
    la   t1, g_trap_mcause
    sd   t0, 0(t1)
    csrr t0, mtval
    la   t1, g_trap_mtval
    sd   t0, 0(t1)
    csrr t0, mepc
    la   t1, g_trap_mepc
    sd   t0, 0(t1)
    li   t0, 1
    la   t1, g_trap_fired
    sw   t0, 0(t1)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

.section .bss
.balign 8
.global g_trap_fired
g_trap_fired: .word 0
.global g_trap_mcause
g_trap_mcause: .dword 0
.global g_trap_mtval
g_trap_mtval: .dword 0
.global g_trap_mepc
g_trap_mepc: .dword 0
```

A demo program that deliberately violates an object's real hardware bound (`compiler/my_trap_demo.c`):
```c
#include "veda_rt.h"

extern void my_trap_catcher_install(void);
extern volatile unsigned int  g_trap_fired;
extern volatile unsigned long g_trap_mcause;
extern volatile unsigned long g_trap_mtval;
extern volatile unsigned long g_trap_mepc;

int main(void) {
  my_trap_catcher_install();
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  veda_obj_t a = veda_malloc();
  if (a == VEDA_OBJ_INVALID) return 1;

  uint64_t val = 0;
  // VEDA_RT_SLOT_SIZE = 64 -- offset 64 is one byte past the object's real
  // Length bound. Deliberately violates it.
  veda_ocl_d(a, VEDA_RT_SLOT_SIZE, &val);

  veda_free(a);
  return g_trap_fired ? 0 : 1;
}
```

Build (adds `my_trap_catcher.S` and links `my_trap_demo.c` instead of your own program; otherwise
identical to section 2):
```bash
$MC $MC_FLAGS -o /tmp/tc_my_trap_catcher.o $VEDA_CORE/compiler/my_trap_catcher.S
$CLANG $CC_FLAGS -c -o /tmp/tc_demo.o $VEDA_CORE/compiler/my_trap_demo.c
$LD -T $VEDA_CORE/runtime/veda_rt.ld -o /tmp/my_trap_demo.elf \
    /tmp/my_crt0.o /tmp/tc_demo.o /tmp/my_veda_rt.o /tmp/my_veda_rt_asm.o /tmp/tc_my_trap_catcher.o
```

GDB walkthrough:
```
(gdb) break my_trap_catcher
(gdb) continue
```
Hitting this breakpoint is itself direct, GDB-visible proof of a real hardware trap: control
jumped here from deep inside `veda_ocl_d`/`veda_bind_scratch_asm`, with no software `if` anywhere
in the caller's own code triggering it.

Step through the catcher's ~7 instructions (`mcause`/`mtval`/`mepc` reads, `g_trap_fired` set,
`mepc+4`, `mret`) with `stepi`, then read the results. **Use `x` (examine memory), not `print`** --
these globals are defined in raw assembly with no DWARF type info, so `print g_trap_mcause` fails
with `'g_trap_mcause' has unknown type; cast it to its declared type`:
```
(gdb) x/1dw &g_trap_fired
(gdb) x/1xg &g_trap_mcause
(gdb) x/1xg &g_trap_mtval
(gdb) x/1xg &g_trap_mepc
```

**Predicted values, per `VEDA_CORE_SPEC.md`'s Trap Model, confirmed by an actual run**:
- `g_trap_mcause` = `0x18` (24) -- every Veda-Core violation uses this one top-level `mcause`.
- `g_trap_mtval` = `0x21` -- `mtval` packs `cap_idx` (bits 10:5) and `cause` (bits 4:0). `veda_rt`
  always binds through capability register `c1`, so `cap_idx=1`; `cause=0x01` is Bounds (Length)
  Violation. `(1<<5)|0x01 = 0x21`.
- `g_trap_mepc` = the exact address of the `veda.ocl.d` instruction that faulted -- matches
  whatever `$pc` showed right before the last `stepi` into the catcher.

This is a direct, empirical measurement of `P(bypass) = 0` (see the top-level `README.md`): the
hardware checked the real `Length` field and refused the access *before it ever touched memory*,
independent of any software-side bounds check.

## 6. Debugging with trace files (the simplest option, no GDB needed)

```bash
$SIM --config $CFG --trace-instr --trace-exception --trace-csr --use-abi-names \
     --trace-output /tmp/my_trace.log /tmp/my_program.elf
less /tmp/my_trace.log
```

Every instruction executed and every CSR write is logged to the file -- grep it for `mcause`/
`mtval`/`mepc` directly. This is the fallback used throughout this project's own milestone
debugging when a single hardware trace, not an interactive session, is enough.

---

## Honest scope note: what this guide does *not* cover

Everything above is ordinary compiled C running *outside* a narrow OCInvoke-bound compartment.
Compiled C functions **cannot** run *inside* one -- standard RV64 ABI callee-saved-register
prologue spills hard-trap under the purecap rule (`TOOLCHAIN_MILESTONE_10_RESULTS.md`'s own major
finding). If you want to write scheduler thread bodies or other compartment-internal code, those
must currently be hand-written assembly (see `compiler/veda_sched_demo_threads.S` for a real,
working example) -- this is a genuine, open architectural limitation, not a gap in this guide.
