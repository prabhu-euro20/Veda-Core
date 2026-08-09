#!/bin/bash
# CRF-exhaustion fix, real combined verification test
# (TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md). Mirrors
# run_veda_sched_demo_test.sh's own real, proven pipeline exactly, with
# one extra assembled object (veda_sched_global_combo_entry.S, the
# globals-capability bootstrap) and the combo-specific demo/thread files.
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

"$MC" $MC_FLAGS -o /tmp/combo_crt0.o ../runtime/crt0.S || { echo "crt0.S failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/combo_veda_sched_asm.o ../runtime/veda_sched_asm.S || { echo "veda_sched_asm.S failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/combo_entry.o veda_sched_global_combo_entry.S || { echo "veda_sched_global_combo_entry.S failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/combo_threads.o veda_sched_global_combo_threads.S || { echo "veda_sched_global_combo_threads.S failed"; exit 1; }
"$CLANG" $CC_FLAGS -c -o /tmp/combo_veda_sched.o ../runtime/veda_sched.c || { echo "veda_sched.c failed"; exit 1; }
"$CLANG" $CC_FLAGS -c -o /tmp/combo_demo.o veda_sched_global_combo_demo.c || { echo "veda_sched_global_combo_demo.c failed"; exit 1; }

if ! "$LD" -T "$LDS" -o /tmp/veda_sched_global_combo.elf \
    /tmp/combo_crt0.o /tmp/combo_demo.o /tmp/combo_veda_sched.o \
    /tmp/combo_veda_sched_asm.o /tmp/combo_entry.o /tmp/combo_threads.o 2>/tmp/veda_sched_global_combo.lderr; then
  echo "LD-FAIL"; cat /tmp/veda_sched_global_combo.lderr; exit 1
fi

out=$("$SIM" --config "$CFG" /tmp/veda_sched_global_combo.elf 2>&1)
code=$?
echo "$out"
if [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; then
  echo "*** TEST PASSED *** (globals table-base capability c11 survived a real scheduler yield/resume round-trip -- both threads' second table access, through the restored c11, returned the exact constant each wrote on its first access)"
  exit 0
else
  echo "*** TEST FAILED *** (exit=$code)"
  exit 1
fi
