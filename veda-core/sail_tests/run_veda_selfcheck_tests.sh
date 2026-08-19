#!/bin/bash
# Milestone V-C: batch runner for Veda-Core's self-checking Sail-model
# tests. Mirrors this project's own real rtl/run_act4_tests.sh pattern
# (assemble, link, run, collect PASS/FAIL, print a summary table) but
# targets sail_riscv_sim directly instead of the RTL testbench, using
# sail_riscv_sim's own real, built-in HTIF support (confirmed working
# this pass: "SUCCESS"/exit 0 on tohost=1, "FAILURE"/exit 1 on tohost=3)
# rather than a custom watcher.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$(dirname "$0")"

TC=$REPO_ROOT/toolchain/riscv-collab-gcc/riscv/bin
AS=$TC/riscv64-unknown-elf-as
LD=$TC/riscv64-unknown-elf-ld
SIM=$REPO_ROOT/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=./veda_test_sail.json
LDS=./veda_selfcheck.ld

pass_count=0
fail_count=0
declare -a results

for src in vc_*.S; do
  name="${src%.S}"
  obj="/tmp/${name}.o"
  elf="/tmp/${name}.elf"

  if ! "$AS" -march=rv64i_zicsr -I. -o "$obj" "$src" 2>/tmp/"${name}".aserr; then
    results+=("ASM-FAIL  $name")
    fail_count=$((fail_count+1))
    continue
  fi
  if ! "$LD" -T "$LDS" -o "$elf" "$obj" 2>/tmp/"${name}".lderr; then
    results+=("LD-FAIL   $name")
    fail_count=$((fail_count+1))
    continue
  fi

  out=$(timeout 20 "$SIM" --config "$CFG" "$elf" 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; then
    results+=("PASS      $name")
    pass_count=$((pass_count+1))
  else
    results+=("FAIL      $name  (exit=$code)")
    fail_count=$((fail_count+1))
  fi
done

echo "=== Veda-Core Milestone V-C self-check results ==="
for r in "${results[@]}"; do echo "$r"; done
echo "---"
echo "$pass_count/$((pass_count+fail_count)) passed"

[ "$fail_count" -eq 0 ]
