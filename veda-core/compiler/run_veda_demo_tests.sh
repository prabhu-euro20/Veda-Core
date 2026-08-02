#!/bin/bash
# Toolchain Milestone 9: build + run the real, end-to-end positive
# (linked list) and negative (out-of-bounds) demos -- real C source,
# compiled via `clang -fpass-plugin=...` through the actual backend, real
# Veda-Core OCL.D/OCS.D instructions the whole way, running under
# sail_riscv_sim. Mirrors this project's own established assemble/link/
# run/PASS-FAIL pattern (sail_tests/run_veda_selfcheck_tests.sh,
# runtime/run_veda_rt_tests.sh).
set -u
cd "$(dirname "$0")"

LLVM=/home/prabhu/makerchip/rva23-core/toolchain/llvm-project/build/bin
CLANG=$LLVM/clang
MC=$LLVM/llvm-mc
LLVM_CONFIG=$LLVM/llvm-config
LD=/home/prabhu/makerchip/rva23-core/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-ld
SIM=/home/prabhu/makerchip/rva23-core/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=../sail_tests/veda_test_sail.json
LDS=../runtime/veda_rt.ld
PLUGIN=/tmp/VedaShadowPropagation.so

CC_FLAGS="--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -O0 -I."
MC_FLAGS="-triple=riscv64 -mattr=+xveda -filetype=obj -I../sail_tests"

# Build the plugin (system clang++-21 as compiler, our own checkout's
# headers for ABI match with our own custom-built opt/clang -- see
# TOOLCHAIN_MILESTONE_9_RESULTS.md for the full real reasoning).
CXXFLAGS=$($LLVM_CONFIG --cxxflags)
if ! clang++-21 $CXXFLAGS -fPIC -shared -o "$PLUGIN" VedaShadowPropagation.cpp; then
  echo "plugin build FAILED"; exit 1
fi

# Shared runtime objects.
"$CLANG" $CC_FLAGS -c -o /tmp/demo_veda_compiler_rt.o veda_compiler_rt.c || { echo "veda_compiler_rt.c failed"; exit 1; }
"$CLANG" $CC_FLAGS -c -o /tmp/demo_veda_rt.o ../runtime/veda_rt.c || { echo "veda_rt.c failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/demo_veda_rt_asm.o ../runtime/veda_rt_asm.S || { echo "veda_rt_asm.S failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/demo_crt0.o ../runtime/crt0.S || { echo "crt0.S failed"; exit 1; }

pass_count=0
fail_count=0
declare -a results

run_one() {
  local name="$1"; shift
  local elf="/tmp/${name}.elf"
  if ! "$LD" -T "$LDS" -o "$elf" "$@" 2>/tmp/"${name}".lderr; then
    results+=("LD-FAIL   $name"); fail_count=$((fail_count + 1)); return
  fi
  local out; out=$("$SIM" --config "$CFG" "$elf" 2>&1); local code=$?
  if [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; then
    results+=("PASS      $name"); pass_count=$((pass_count + 1))
  else
    results+=("FAIL      $name  (exit=$code)"); fail_count=$((fail_count + 1))
  fi
}

# Positive: 3-node linked list, built and traversed via ordinary C pointer
# syntax, transparently redirected through real OCL.D/OCS.D.
"$CLANG" $CC_FLAGS -fpass-plugin="$PLUGIN" -c -o /tmp/demo_ll.o veda_demo_linked_list.c \
  || { echo "veda_demo_linked_list.c failed"; exit 1; }
run_one veda_demo_linked_list /tmp/demo_crt0.o /tmp/demo_ll.o /tmp/demo_veda_compiler_rt.o /tmp/demo_veda_rt.o /tmp/demo_veda_rt_asm.o

# Negative: deliberate out-of-bounds field access, must genuinely hard
# -trap (real hardware bounds check) with the correct mcause/mtval.
"$CLANG" $CC_FLAGS -fpass-plugin="$PLUGIN" -c -o /tmp/demo_oob.o veda_demo_oob_neg.c \
  || { echo "veda_demo_oob_neg.c failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/demo_trap_catcher.o veda_demo_trap_catcher.S \
  || { echo "veda_demo_trap_catcher.S failed"; exit 1; }
run_one veda_demo_oob_neg /tmp/demo_crt0.o /tmp/demo_oob.o /tmp/demo_trap_catcher.o /tmp/demo_veda_compiler_rt.o /tmp/demo_veda_rt.o /tmp/demo_veda_rt_asm.o

echo "=== Toolchain Milestone 9 (real end-to-end demo) test results ==="
for r in "${results[@]}"; do echo "$r"; done
echo "---"
echo "$pass_count/$((pass_count + fail_count)) passed"

[ "$fail_count" -eq 0 ]
