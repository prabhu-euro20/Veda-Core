#!/bin/bash
# Toolchain Milestone 9: build + run the real, end-to-end positive
# (linked list) and negative (out-of-bounds) demos -- real C source,
# compiled via `clang -fpass-plugin=...` through the actual backend, real
# Veda-Core OCL.D/OCS.D instructions the whole way, running under
# sail_riscv_sim. Mirrors this project's own established assemble/link/
# run/PASS-FAIL pattern (sail_tests/run_veda_selfcheck_tests.sh,
# runtime/run_veda_rt_tests.sh).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$(dirname "$0")"

LLVM=$REPO_ROOT/toolchain/llvm-project/build/bin
CLANG=$LLVM/clang
MC=$LLVM/llvm-mc
LLVM_CONFIG=$LLVM/llvm-config
LLC=$LLVM/llc
LD=$REPO_ROOT/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-ld
SIM=$REPO_ROOT/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=../sail_tests/veda_test_sail.json
LDS=../runtime/veda_rt.ld
PLUGIN=/tmp/VedaShadowPropagation.so

CC_FLAGS="--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -O0 -I."
MC_FLAGS="-triple=riscv64 -mattr=+xveda -filetype=obj -I../sail_tests"
LLC_FLAGS="-mtriple=riscv64 -mattr=+xveda -O1 -filetype=obj"

# Build the plugin (system clang++-21 as compiler, our own checkout's
# headers for ABI match with our own custom-built opt/clang -- see
# TOOLCHAIN_MILESTONE_9_RESULTS.md for the full real reasoning).
CXXFLAGS=$($LLVM_CONFIG --cxxflags)
if ! clang++-21 $CXXFLAGS -fPIC -shared -o "$PLUGIN" VedaShadowPropagation.cpp; then
  echo "plugin build FAILED"; exit 1
fi

# Toolchain Milestone 12: veda_compiler_rt.c/veda_rt.c now ALSO carry
# __attribute__((veda_compartment)) on their own stack-helper functions
# (see those files' own header comments) -- compiling them via the old
# single-stage `clang -c` (with no -mattr=+xveda reaching the backend)
# crashes RISCVAsmPrinter outright on any veda_compartment-attributed
# function's own C15 prologue codegen, a real regression this milestone's
# own full-regression pass found empirically. Fixed by switching both to
# the same two-stage pipeline run_veda_alloca_protect_test.sh (Toolchain
# Milestone 12) already established: `clang -S -emit-llvm` then
# `llc -mattr=+xveda -filetype=obj`. Safe for every OTHER (non-attributed)
# function in these same translation units too -- -mattr=+xveda only
# enables the backend to emit XVeda instructions when needed, never forces
# it.
"$CLANG" $CC_FLAGS -S -emit-llvm -o /tmp/demo_veda_compiler_rt.ll veda_compiler_rt.c || { echo "veda_compiler_rt.c IR emission failed"; exit 1; }
"$LLC" $LLC_FLAGS -o /tmp/demo_veda_compiler_rt.o /tmp/demo_veda_compiler_rt.ll || { echo "veda_compiler_rt.c llc lowering failed"; exit 1; }
"$CLANG" $CC_FLAGS -S -emit-llvm -o /tmp/demo_veda_rt.ll ../runtime/veda_rt.c || { echo "veda_rt.c IR emission failed"; exit 1; }
"$LLC" $LLC_FLAGS -o /tmp/demo_veda_rt.o /tmp/demo_veda_rt.ll || { echo "veda_rt.c llc lowering failed"; exit 1; }
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

# Positive: real Linux container_of() pattern -- BACKWARD reconstruction of
# an enclosing struct's base address via pointer subtraction from an
# EMBEDDED field's own address (the pattern the Linux-port feasibility
# research flagged as the structural blocker). Confirms, unmodified, that
# Clang lowers `(char*)p - offsetof(...)` to a plain negative-index GEP --
# the same instruction kind the pass's existing GEP-propagation rule
# already handles generically -- and that Veda-Core's whole-object (not
# CHERI-style subobject) bounds model has no narrowed boundary to walk
# back past.
"$CLANG" $CC_FLAGS -fpass-plugin="$PLUGIN" -c -o /tmp/demo_container_of.o veda_demo_container_of.c \
  || { echo "veda_demo_container_of.c failed"; exit 1; }
run_one veda_demo_container_of /tmp/demo_crt0.o /tmp/demo_container_of.o /tmp/demo_veda_compiler_rt.o /tmp/demo_veda_rt.o /tmp/demo_veda_rt_asm.o

# Positive: container_of() across a real function-call boundary (Toolchain
# Milestone 20's own real reason to exist) -- a helper RECONSTRUCTS via
# container_of and RETURNS the pointer; main() dereferences it AFTER the
# call returns. Requires return-value shadow propagation (the trailing
# return-shadow out-param VedaShadowPropagation.cpp's rewriteSignatures
# now appends to any pointer-returning function) -- without it, this
# exact program previously read back a silent zero
# (TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md Test 2).
"$CLANG" $CC_FLAGS -fpass-plugin="$PLUGIN" -c -o /tmp/demo_container_of_param.o veda_demo_container_of_param.c \
  || { echo "veda_demo_container_of_param.c failed"; exit 1; }
run_one veda_demo_container_of_param /tmp/demo_crt0.o /tmp/demo_container_of_param.o /tmp/demo_veda_compiler_rt.o /tmp/demo_veda_rt.o /tmp/demo_veda_rt_asm.o

echo "=== Toolchain Milestone 9 (real end-to-end demo) test results ==="
for r in "${results[@]}"; do echo "$r"; done
echo "---"
echo "$pass_count/$((pass_count + fail_count)) passed"

[ "$fail_count" -eq 0 ]
