# Veda-Core Developer Workflow Guide: Write, Build, Run, Debug Your Own Program

**Scope:** a real, reproducible path from zero to a working, self-debugged Veda-Core program,
for anyone who wants to write their own high-level C code against this architecture rather than
just read about it. Every command below is exactly what was run, on this machine, to produce the
results quoted -- nothing here is aspirational.

**Last verified:** 2026-08-09, against commit `985c958` -- re-run end to end in a fresh directory
(`/home/prabhu/test`), all six sections, after fixing two real bugs this pass found (missing
`+xveda` in `CC_FLAGS`, missing `compiler/my_trap_demo.c`) and updating the scope note below,
which had fallen behind Toolchain Milestones 11-17. If you hit a command that doesn't match this
guide, that almost certainly means more milestones have landed since -- check `git log` for
commits touching `runtime/`, `compiler/`, or `toolchain/llvm-project/` after this date.

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
`veda_ocl_d`/`veda_ocs_d` (8-byte hardware-checked load/store), and `VEDA_RT_MAX_OBJECTS`
(compile-time override for the object-pool size, default 8). `Object_ID` is an opaque handle --
never a raw address -- and bounds/permission/tag/generation checking is real hardware, not a
software wrapper.

`veda_rt.h` also exports two later, narrower protection APIs: `veda_ocl_stack_d`/`veda_ocs_stack_d`
(Toolchain Milestone 12, hardware bounds-checking for ordinary C stack-local/array variables) and
`veda_rt_init_globals` + `veda_ocl_global_d`/`veda_ocs_global_d` (Toolchain Milestones 13/15, the
same for C globals/statics). **Unlike everything else in this section**, these are not drop-in
calls from ordinary code -- both require a `veda_compartment`-attributed function and the more
advanced compiler-plugin build pipeline. See Section 7 below before reaching for either.

---

## 2. Build it (works from any directory)

`VEDA_CORE` below (and `LLVM`/`LD`/`SIM`/`GDB` later) is the real, literal path on the machine
this guide was verified against -- its own top-level directory happens to be named `rva23-core`,
predating this repo's current `Veda-Core` name on GitHub. If you cloned via the top-level
`README.md`'s own one-command setup, your checkout is named `Veda-Core/`, not `rva23-core/` --
substitute your own clone's actual path here (e.g. `~/Veda-Core/veda-core`) before running these.

```bash
VEDA_CORE=/home/prabhu/makerchip/rva23-core/veda-core

LLVM=/home/prabhu/makerchip/rva23-core/toolchain/llvm-project/build/bin
CLANG=$LLVM/clang
MC=$LLVM/llvm-mc
LD=/home/prabhu/makerchip/rva23-core/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-ld
SIM=/home/prabhu/makerchip/rva23-core/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=$VEDA_CORE/sail_tests/veda_test_sail.json

# -Xclang -target-feature -Xclang +xveda is required: without it, clang's backend crashes
# ("Attempting to emit VEDA_OCS instruction but the Feature_HasVendorXVeda predicate(s) are
# not met") the moment it has to codegen a Veda-Core custom instruction, e.g. inside veda_rt.c.
# This is the clang-driver equivalent of MC_FLAGS' own -mattr=+xveda below.
CC_FLAGS="--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -O0 -g -I$VEDA_CORE/runtime -Xclang -target-feature -Xclang +xveda"
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

**Note on c15** (Toolchain Milestone 11 and later): for a function compiled with
`__attribute__((veda_compartment))`, the LLVM backend conditionally reserves `c15` as a
compiler-owned scratch register for routing ABI callee-saved-register spills through the SSC
(Stack-Spill Capability) mechanism -- it is not available for your own general-purpose use inside
such a function, and `info registers c15 c15_tag` there reflects compiler-managed spill state, not
anything you wrote. This reservation is per-function and conditional: ordinary C outside a
`veda_compartment`-attributed function -- including every example in this guide -- is unaffected,
and `c15` remains a fully free general-purpose capability register.

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
`runtime/veda_rt_retire_neg_test.c`). The worked example below is a personal copy, extended to
also capture `mtval`/`mepc` (the original only needed `mcause`) -- copy it as-is, or adapt it for
your own programs. Like `my_program.c` in Section 1, this is *your* file: put it in the same
directory you chose there, not inside this repo (e.g. `~/my_veda_projects/my_trap_catcher.S`).

`my_trap_catcher.S`:
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

A demo program that deliberately violates an object's real hardware bound. Same directory,
`my_trap_demo.c`:
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
MY_TRAP_CATCHER=~/my_veda_projects/my_trap_catcher.S   # wherever you saved it
MY_TRAP_DEMO=~/my_veda_projects/my_trap_demo.c         # wherever you saved it

$MC $MC_FLAGS -o /tmp/tc_my_trap_catcher.o $MY_TRAP_CATCHER
$CLANG $CC_FLAGS -c -o /tmp/tc_demo.o $MY_TRAP_DEMO
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

Step through the catcher with `stepi`. Counting *source lines* it looks like ~7 steps (`mcause`/
`mtval`/`mepc` reads, `g_trap_fired` set, `mepc+4`, `mret`), but each `la` pseudo-instruction
expands to two real machine instructions (`auipc`+`addi`, `medany` code model) -- the routine is
actually **~20 real instructions**, and `stepi` steps one real instruction at a time. Stopping at
7 `stepi`s only gets you as far as `g_trap_mcause` being stored; `g_trap_mtval`/`g_trap_mepc`/
`g_trap_fired` will still read back as `0` and can look like a broken mechanism. Step through all
~20 (or just `stepi 20`) before reading the results. **Use `x` (examine memory), not `print`** --
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

## 7. Protecting stack-locals and globals, not just malloc'd objects (advanced)

Sections 1-6 only protect objects you explicitly `veda_malloc`. Two later milestones protect
ordinary C variables too -- `veda_ocl_stack_d`/`veda_ocs_stack_d` (Toolchain Milestone 12, C
stack-locals/arrays) and `veda_rt_init_globals` + `veda_ocl_global_d`/`veda_ocs_global_d`
(Toolchain Milestone 13/15, C globals/statics). Both are real and verified, but **do not fit this
guide's simple build recipe** -- unlike everything above, both require:

1. A function marked `__attribute__((veda_compartment))` (Section 4's "Note on c15" and the Honest
   scope note below explain what this means and its real, current limits).
2. A **two-stage** compile pipeline -- `clang -S -emit-llvm` (so `VedaShadowPropagation.cpp`'s
   compiler pass can rewrite your locals'/globals' loads and stores into `OCL.D`/`OCS.D` calls) then
   `llc -mattr=+xveda -filetype=obj` for the actual backend lowering -- not the single-stage
   `clang -c` Section 2 uses.
3. A hand-written compartment entry point (`.S`) that establishes `OCInvoke` and the SSC region
   before your compiled C ever runs -- there is no C-level `main()` entry point into a compartment
   yet.

Rather than inventing a simplified example that would hide this real complexity, run the project's
own existing, verified demos directly -- `compiler/veda_alloca_protect_demo.c` (stack-locals) and
`compiler/veda_global_protect_demo.c` (globals), each with a matching hand-written entry `.S` and a
`run_*.sh` script that builds both a positive (in-bounds) and negative (deliberate cross-variable
overflow) version and traces the negative one to confirm the exact expected trap:

```bash
cd $VEDA_CORE/compiler
bash run_veda_alloca_protect_test.sh   # stack-locals (Milestone 12)
bash run_veda_global_protect_test.sh   # globals/statics (Milestone 13/15)
```

Both re-run clean today (2026-08-09): positive build returns the correct in-bounds value (113,
`lower[3]+upper[0]` / `g_lower[3]+g_upper[0]`); negative build (one array element deliberately
written past its own bound) hard-traps with `mcause=0x18`, and the exact `mtval` differs by design
between the two milestones -- `0x1a1` for stack-locals (Milestone 12's single shared region,
narrowed per-access via `C13`) vs. `0x141` for globals (Milestone 13's individually-bounded
per-symbol capabilities, so the trap fires at the boundary of the specific global being written,
via `C10`, a strictly stronger isolation property). Both end with `*** TEST PASSED ***`.

If you want to write your *own* program against these two APIs rather than just run the existing
demos, read `TOOLCHAIN_MILESTONE_12_RESULTS.md`/`_13_RESULTS.md` and copy the real entry-point
pattern from `veda_alloca_protect_entry.S`/`veda_global_protect_entry.S` -- there is no shortcut
version of that ceremony yet.

---

## Honest scope note: what this guide does *not* cover

Everything above is ordinary compiled C. As of Toolchain Milestone 11 (2026-08-07), ordinary
compiled C functions marked `__attribute__((veda_compartment))` (`compiler/veda_compartment_demo.c`
is a real, working example, exercised by `compiler/run_veda_compartment_test.sh` and
`run_veda_compartment_nested_test.sh`) **can** run *inside* a narrow OCInvoke-bound compartment: the
compiler automatically routes ABI-mandated callee-saved-register prologue/epilogue spills through
`OCS.D`/`OCL.D` against the reserved SSC-shadow capability register `c15` instead of ordinary
`sd`/`ld`, so they no longer hard-trap under Milestone 19's purecap rule (the actual enforcement
mechanism; `TOOLCHAIN_MILESTONE_10_RESULTS.md` only diagnosed the symptom, Milestone 19 is what
made it fatal in the first place). Toolchain Milestone 12 extended the same attribute-gated
mechanism to ordinary C stack-local variables (bounds-checked via `OCA`+`CSetBounds`), and Toolchain
Milestone 13 (refined by Milestones 15-17) extended it further to C global/static variables
(per-symbol minted capabilities cached in a compiler-sized table). All three are verified end to
end under `sail_riscv_sim` with positive/negative-control tests.

**This `veda_compartment` mechanism is not yet promoted to a stable, guide-ready feature** -- no
top-level doc (including this one) documents it as a public API you build fresh from scratch.
Section 7 above only points to it via already-existing, fully-verified demos (real entry-point
assembly and all); it is not something Sections 1-6's simple build recipe can produce on its own.
If you want to try writing your own, start from `TOOLCHAIN_MILESTONE_11_RESULTS.md` and its own
"Not yet built" section, which honestly lists the real, narrower gaps that remain: dynamic-size/VLA allocas,
non-entry-block or dynamically-placed allocas, mixed-provenance PHIs (`malloc` vs. `alloca`),
subobject/struct-field-internal bounds, FPR/vector callee-saved spills, extern globals with
incomplete array types (design direction decided in Milestone 16, implementation still deferred),
and multi-function compartment call graphs (every function that itself needs a callee-saved spill
inside a compartment must individually carry the `veda_compartment` attribute -- it is not inferred
transitively).

If you want cooperative scheduling/threading from C rather than hand-written assembly, see
`runtime/veda_sched.h`'s own header comment for the real, narrowly-scoped (2-thread,
cooperative-only, non-preemptive -- read its "SCOPE, STATED PLAINLY" section before using it)
`veda_scheduler_start`/`veda_yield` API. `compiler/veda_sched_demo_threads.S` remains a real,
working hand-written-assembly example of the same mechanism at a lower level; no verified doc yet
shows a `veda_compartment`-attributed C rewrite of scheduler thread bodies specifically -- that
conversion has not been built and tested, and should not be assumed to work without doing so.
