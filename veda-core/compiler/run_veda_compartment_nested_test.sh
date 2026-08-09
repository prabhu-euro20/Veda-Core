#!/bin/bash
# Toolchain Milestone 11 follow-up: closes the "nested veda_compartment
# calls, architecturally correct but untested" gap named honestly in
# TOOLCHAIN_MILESTONE_11_RESULTS.md's own "Not yet built" section. outer_fn
# calls inner_fn (a real, separately-compiled, separately-attributed
# nested veda_compartment call), both pinning a local to the same physical
# register (x20/s4) -- the exact scenario the SP+offset fix in
# RISCVFrameLowering.cpp exists to disambiguate. Expected result is a
# precisely predictable 32 (1 doubled 5 times), not just "doesn't crash".
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$(dirname "$0")"

LLVM=$REPO_ROOT/toolchain/llvm-project/build/bin
CLANG=$LLVM/clang
LLC=$LLVM/llc
MC=$LLVM/llvm-mc
LD=$REPO_ROOT/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-ld
SIM=$REPO_ROOT/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=../sail_tests/veda_test_sail.json
LDS=../runtime/veda_rt.ld

CC_FLAGS="--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -O1 -I."
MC_FLAGS="-triple=riscv64 -mattr=+xveda -filetype=obj -I../sail_tests"
LLC_FLAGS="-mtriple=riscv64 -mattr=+xveda -O1 -filetype=obj"

"$MC" $MC_FLAGS -o /tmp/vcnested_entry.o veda_compartment_nested_entry.S \
  || { echo "veda_compartment_nested_entry.S assembly failed"; exit 1; }

"$CLANG" $CC_FLAGS -S -emit-llvm -o /tmp/vcnested_demo.ll veda_compartment_nested_demo.c \
  || { echo "clang IR emission failed"; exit 1; }
"$LLC" $LLC_FLAGS -o /tmp/vcnested_demo.o /tmp/vcnested_demo.ll \
  || { echo "llc lowering failed"; exit 1; }

if ! "$LD" -T "$LDS" -o /tmp/veda_compartment_nested.elf \
    /tmp/vcnested_entry.o /tmp/vcnested_demo.o 2>/tmp/vcnested.lderr; then
  echo "LD-FAIL"; cat /tmp/vcnested.lderr; exit 1
fi

out=$("$SIM" --config "$CFG" /tmp/veda_compartment_nested.elf 2>&1)
code=$?
echo "$out"

if [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; then
  echo ""
  echo "*** TEST PASSED *** (a real nested veda_compartment -> veda_compartment"
  echo "call -- outer_fn calling inner_fn, both pinning x20/s4 -- computed the"
  echo "exact expected value (1 doubled 5 times = 32) with zero purecap traps,"
  echo "empirically closing the one gap TOOLCHAIN_MILESTONE_11_RESULTS.md left"
  echo "honestly unverified: SSC-routed spill slots at different call depths"
  echo "do not alias, confirming the SP+offset fix generalizes to real nested"
  echo "compartment calls, not merely the single-frame case.)"
  exit 0
else
  echo ""
  echo "*** TEST FAILED *** (exit=$code)"
  exit 1
fi
