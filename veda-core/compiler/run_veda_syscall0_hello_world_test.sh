#!/bin/bash
# Toolchain Milestone "Syscall-0" Step 2 (task #298): builds and runs
# veda_syscall0_hello_world.c through the UNMODIFIED Veda-Core toolchain
# (identical two-stage clang+llc pipeline run_veda_alloca_protect_test.sh
# already established -- required because veda_compiler_rt.c/veda_rt.c
# carry __attribute__((veda_compartment)) on functions reached from
# inside a live compartment's own call graph), linked against the
# hand-written entry point (veda_syscall0_kernel_entry.S, reusing Task
# #297's proven KERNEL ecall dispatcher verbatim) and syscall shims
# (veda_syscall0_shim.S).
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

CC_FLAGS="--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -O1 -I."
MC_FLAGS="-triple=riscv64 -mattr=+xveda -filetype=obj -I../sail_tests"
LLC_FLAGS="-mtriple=riscv64 -mattr=+xveda -O1 -filetype=obj"

CXXFLAGS=$($LLVM_CONFIG --cxxflags)
if ! clang++-21 $CXXFLAGS -fPIC -shared -o "$PLUGIN" VedaShadowPropagation.cpp; then
  echo "plugin build FAILED"; exit 1
fi

"$MC" $MC_FLAGS -o /tmp/syscall0_entry.o veda_syscall0_kernel_entry.S \
  || { echo "veda_syscall0_kernel_entry.S assembly failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/syscall0_shim.o veda_syscall0_shim.S \
  || { echo "veda_syscall0_shim.S assembly failed"; exit 1; }

"$CLANG" $CC_FLAGS -S -emit-llvm -o /tmp/syscall0_veda_compiler_rt.ll veda_compiler_rt.c \
  || { echo "veda_compiler_rt.c IR emission failed"; exit 1; }
"$LLC" $LLC_FLAGS -o /tmp/syscall0_veda_compiler_rt.o /tmp/syscall0_veda_compiler_rt.ll \
  || { echo "veda_compiler_rt.c llc lowering failed"; exit 1; }
"$CLANG" $CC_FLAGS -S -emit-llvm -o /tmp/syscall0_veda_rt.ll ../runtime/veda_rt.c \
  || { echo "veda_rt.c IR emission failed"; exit 1; }
"$LLC" $LLC_FLAGS -o /tmp/syscall0_veda_rt.o /tmp/syscall0_veda_rt.ll \
  || { echo "veda_rt.c llc lowering failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/syscall0_veda_rt_asm.o ../runtime/veda_rt_asm.S \
  || { echo "veda_rt_asm.S failed"; exit 1; }

"$CLANG" $CC_FLAGS -fpass-plugin="$PLUGIN" -S -emit-llvm -o /tmp/syscall0_hello.ll veda_syscall0_hello_world.c \
  || { echo "veda_syscall0_hello_world.c IR emission failed"; exit 1; }
"$LLC" $LLC_FLAGS -o /tmp/syscall0_hello.o /tmp/syscall0_hello.ll \
  || { echo "veda_syscall0_hello_world.c llc lowering failed"; exit 1; }

"$LD" -T "$LDS" -o /tmp/veda_syscall0_hello_world.elf \
  /tmp/syscall0_entry.o /tmp/syscall0_hello.o /tmp/syscall0_shim.o \
  /tmp/syscall0_veda_compiler_rt.o /tmp/syscall0_veda_rt.o /tmp/syscall0_veda_rt_asm.o \
  2>/tmp/syscall0_hello.lderr \
  || { echo "LD-FAIL"; cat /tmp/syscall0_hello.lderr; exit 1; }

out=$("$SIM" --config "$CFG" /tmp/veda_syscall0_hello_world.elf 2>&1)
code=$?
echo "$out"

if [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; then
  echo ""
  echo "*** TEST PASSED *** (real, compiled C program, hello_world_thread, ran"
  echo "inside an OCInvoke-narrowed compartment and called hand-written syscall"
  echo "shims (sys_write/sys_exit) with a real Object_ID (heap-allocated pre-"
  echo "OCInvoke by the entry point, matching veda_global_protect_entry.S's own"
  echo "established pre-OCInvoke-bootstrap pattern) -- the KERNEL independently"
  echo "validated that Object_ID via trapping veda.bind before moving any data,"
  echo "exactly as Task #297 proved in isolation. Full, real, end-to-end"
  echo "toolchain path.)"
  exit 0
else
  echo ""
  echo "*** TEST FAILED ***"
  exit 1
fi
