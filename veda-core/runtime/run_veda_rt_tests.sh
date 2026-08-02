#!/bin/bash
# Toolchain Milestone 7: build + run veda_rt's own positive and negative
# tests. Mirrors sail_tests/run_veda_selfcheck_tests.sh's own real
# assemble/link/run/PASS-FAIL pattern, but assembles with the real LLVM
# toolchain built in Toolchain Milestones 2/5a/5b-M6 (llvm-mc for the
# Veda-Core-mnemonic .S files, clang for the plain-RV64I .c files) instead
# of GNU `as`+`.insn` -- the first real software in this project to use
# that toolchain for something beyond its own MC-layer unit tests.
set -u
cd "$(dirname "$0")"

LLVM=/home/prabhu/makerchip/rva23-core/toolchain/llvm-project/build/bin
MC=$LLVM/llvm-mc
CLANG=$LLVM/clang
LD=/home/prabhu/makerchip/rva23-core/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-ld
SIM=/home/prabhu/makerchip/rva23-core/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=../sail_tests/veda_test_sail.json
LDS=veda_rt.ld
INC=../sail_tests

CC_FLAGS="--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -O1 -Wall -I."
MC_FLAGS="-triple=riscv64 -mattr=+xveda -filetype=obj -I$INC"

pass_count=0
fail_count=0
declare -a results

run_one() {
  local name="$1"; shift
  local elf="/tmp/${name}.elf"
  if ! "$LD" -T "$LDS" -o "$elf" "$@" 2>/tmp/"${name}".lderr; then
    results+=("LD-FAIL   $name")
    fail_count=$((fail_count + 1))
    return
  fi
  local out
  out=$("$SIM" --config "$CFG" "$elf" 2>&1)
  local code=$?
  if [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; then
    results+=("PASS      $name")
    pass_count=$((pass_count + 1))
  else
    results+=("FAIL      $name  (exit=$code)")
    fail_count=$((fail_count + 1))
  fi
}

# Shared object files.
"$MC" $MC_FLAGS -o /tmp/rt_crt0.o crt0.S || { echo "crt0.S assemble failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/rt_veda_rt_asm.o veda_rt_asm.S || { echo "veda_rt_asm.S assemble failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/rt_trap_catcher.o veda_rt_trap_catcher.S || { echo "veda_rt_trap_catcher.S assemble failed"; exit 1; }

# Positive test: default VEDA_RT_MAX_OBJECTS=8.
"$CLANG" $CC_FLAGS -c -o /tmp/rt_veda_rt_8.o veda_rt.c || { echo "veda_rt.c (MAX=8) compile failed"; exit 1; }
"$CLANG" $CC_FLAGS -c -o /tmp/rt_positive_test.o veda_rt_positive_test.c || { echo "positive test compile failed"; exit 1; }
run_one veda_rt_positive_test /tmp/rt_crt0.o /tmp/rt_veda_rt_8.o /tmp/rt_veda_rt_asm.o /tmp/rt_positive_test.o

# Negative test: built with VEDA_RT_MAX_OBJECTS=1 so the one slot's real
# retirement empties the whole pool (see veda_rt_retire_neg_test.c's own
# header comment for why).
"$CLANG" $CC_FLAGS -DVEDA_RT_MAX_OBJECTS=1 -c -o /tmp/rt_veda_rt_1.o veda_rt.c || { echo "veda_rt.c (MAX=1) compile failed"; exit 1; }
"$CLANG" $CC_FLAGS -DVEDA_RT_MAX_OBJECTS=1 -c -o /tmp/rt_retire_neg_test.o veda_rt_retire_neg_test.c || { echo "negative test compile failed"; exit 1; }
run_one veda_rt_retire_neg_test /tmp/rt_crt0.o /tmp/rt_veda_rt_1.o /tmp/rt_veda_rt_asm.o /tmp/rt_trap_catcher.o /tmp/rt_retire_neg_test.o

echo "=== Toolchain Milestone 7 (veda_rt) test results ==="
for r in "${results[@]}"; do echo "$r"; done
echo "---"
echo "$pass_count/$((pass_count + fail_count)) passed"

[ "$fail_count" -eq 0 ]
