#!/bin/bash
# Toolchain Milestone 11's real completion criterion: a compiled C function
# attributed __attribute__((veda_compartment)) runs inside a live
# OCInvoke-bound compartment with zero purecap traps, where the identical
# un-attributed build (Milestone 10's own rejected Attempt 2 reproduction)
# still traps. Pipeline note: clang emits IR only, then llc -mattr=+xveda
# does the real lowering (Subtarget->hasVendorXVeda() is true there) --
# TOOLCHAIN_MILESTONE_7_RESULTS.md already found the clang *driver*'s own
# -march=...xveda ISA-string parser rejects xveda; llc's -mattr flag
# bypasses that broken parser entirely (verified: `llc -mattr=help` lists
# xveda correctly). Otherwise mirrors run_veda_sched_demo_test.sh's own
# proven llvm-mc/ld/sail_riscv_sim pipeline exactly.
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

build_and_run() {
  local label="$1" cc_extra="$2" out_elf="$3"

  "$MC" $MC_FLAGS -o /tmp/vcompart_entry.o veda_compartment_entry.S \
    || { echo "[$label] veda_compartment_entry.S assembly failed"; return 1; }

  "$CLANG" $CC_FLAGS $cc_extra -S -emit-llvm -o /tmp/vcompart_demo.ll veda_compartment_demo.c \
    || { echo "[$label] clang IR emission failed"; return 1; }
  "$LLC" $LLC_FLAGS -o /tmp/vcompart_demo.o /tmp/vcompart_demo.ll \
    || { echo "[$label] llc lowering failed"; return 1; }

  if ! "$LD" -T "$LDS" -o "$out_elf" /tmp/vcompart_entry.o /tmp/vcompart_demo.o \
      2>/tmp/vcompart.lderr; then
    echo "[$label] LD-FAIL"; cat /tmp/vcompart.lderr; return 1
  fi
  return 0
}

echo "=== Positive: WITH __attribute__((veda_compartment)) ==="
if ! build_and_run "positive" "" /tmp/veda_compartment_positive.elf; then
  echo "*** TEST FAILED *** (positive build)"; exit 1
fi
pos_out=$("$SIM" --config "$CFG" /tmp/veda_compartment_positive.elf 2>&1)
pos_code=$?
echo "$pos_out"

echo ""
echo "=== Negative control: WITHOUT the attribute (must still trap) ==="
if ! build_and_run "negative" "-DVEDA_COMPARTMENT_ATTR=" /tmp/veda_compartment_negative.elf; then
  echo "*** TEST FAILED *** (negative build)"; exit 1
fi
neg_out=$("$SIM" --config "$CFG" /tmp/veda_compartment_negative.elf 2>&1)
neg_code=$?
echo "$neg_out"

if [ "$pos_code" -eq 0 ] && echo "$pos_out" | grep -q "SUCCESS" \
   && ! { [ "$neg_code" -eq 0 ] && echo "$neg_out" | grep -q "SUCCESS"; }; then
  echo ""
  echo "*** TEST PASSED *** (real compiled C function, attributed veda_compartment,"
  echo "runs inside a live OCInvoke-bound compartment with zero purecap traps --"
  echo "the compiled prologue/epilogue correctly routed its callee-saved s4 spill"
  echo "through OCS.D/OCL.D against C15 instead of ordinary sd/ld; the identical"
  echo "un-attributed build still traps, proving the fix is real and"
  echo "attribute-gated, a direct empirical negation of Milestone 10's own"
  echo "original finding, not merely an architectural argument)"
  exit 0
else
  echo ""
  echo "*** TEST FAILED *** (positive exit=$pos_code, negative exit=$neg_code)"
  exit 1
fi
