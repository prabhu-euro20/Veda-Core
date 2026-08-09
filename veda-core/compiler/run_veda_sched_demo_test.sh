#!/bin/bash
# Real, compiled C driver for the Veda-Core cooperative scheduler.
# Mirrors run_veda_demo_tests.sh's own real, proven pipeline exactly:
# llvm-mc assembles the .S files (real Veda-Core mnemonics, -mattr=+xveda),
# clang compiles the .c files (plain, no xveda -- confirmed unaffected by
# the clang-driver xveda registration gap since these contain no custom
# mnemonics), riscv64-unknown-elf-ld links against the shared runtime
# linker script, sail_riscv_sim runs the result.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$(dirname "$0")"

LLVM=$REPO_ROOT/toolchain/llvm-project/build/bin
CLANG=$LLVM/clang
MC=$LLVM/llvm-mc
LD=$REPO_ROOT/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-ld
SIM=$REPO_ROOT/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=../sail_tests/veda_test_sail.json
LDS=../runtime/veda_rt.ld

CC_FLAGS="--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -O0 -I. -I../runtime"
MC_FLAGS="-triple=riscv64 -mattr=+xveda -filetype=obj -I../sail_tests"

"$MC" $MC_FLAGS -o /tmp/sched_crt0.o ../runtime/crt0.S || { echo "crt0.S failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/sched_veda_sched_asm.o ../runtime/veda_sched_asm.S || { echo "veda_sched_asm.S failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/sched_demo_threads.o veda_sched_demo_threads.S || { echo "veda_sched_demo_threads.S failed"; exit 1; }
"$CLANG" $CC_FLAGS -c -o /tmp/sched_veda_sched.o ../runtime/veda_sched.c || { echo "veda_sched.c failed"; exit 1; }
"$CLANG" $CC_FLAGS -c -o /tmp/sched_demo.o veda_sched_demo.c || { echo "veda_sched_demo.c failed"; exit 1; }

if ! "$LD" -T "$LDS" -o /tmp/veda_sched_demo.elf \
    /tmp/sched_crt0.o /tmp/sched_demo.o /tmp/sched_veda_sched.o \
    /tmp/sched_veda_sched_asm.o /tmp/sched_demo_threads.o 2>/tmp/veda_sched_demo.lderr; then
  echo "LD-FAIL"; cat /tmp/veda_sched_demo.lderr; exit 1
fi

out=$("$SIM" --config "$CFG" /tmp/veda_sched_demo.elf 2>&1)
code=$?
echo "$out"
if [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; then
  echo "*** TEST PASSED *** (real compiled C main() drives the real switcher/scheduler mechanism -- OCInvoke/OCRETURN/OSpecialRW-TSC-swap/CSealEntry the whole way, hand-written zero-memory-traffic thread bodies, both threads' counters reach 2 after 4 real yields)"
  exit 0
else
  echo "*** TEST FAILED *** (exit=$code)"
  exit 1
fi
