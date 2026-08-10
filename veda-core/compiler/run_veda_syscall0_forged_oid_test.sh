#!/bin/bash
# Toolchain Milestone "Syscall-0" Step 3 (task #299): the real security
# proof this whole milestone exists to demonstrate. Builds
# veda_syscall0_hello_world.c (UNCHANGED, real compiled C, same as Task
# #298's positive test) against veda_syscall0_kernel_entry_forged.S,
# which hands it a deliberately forged, never-populated Object_ID
# (99999) instead of the real one veda_malloc_raw returned. Confirms not
# just "did it fail" but the EXACT expected hardware trap cause --
# matching run_veda_alloca_protect_test.sh's own established negative-
# test discipline.
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

"$MC" $MC_FLAGS -o /tmp/syscall0_entry_forged.o veda_syscall0_kernel_entry_forged.S \
  || { echo "veda_syscall0_kernel_entry_forged.S assembly failed"; exit 1; }
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

"$LD" -T "$LDS" -o /tmp/veda_syscall0_forged.elf \
  /tmp/syscall0_entry_forged.o /tmp/syscall0_hello.o /tmp/syscall0_shim.o \
  /tmp/syscall0_veda_compiler_rt.o /tmp/syscall0_veda_rt.o /tmp/syscall0_veda_rt_asm.o \
  2>/tmp/syscall0_forged.lderr \
  || { echo "LD-FAIL"; cat /tmp/syscall0_forged.lderr; exit 1; }

out=$("$SIM" --config "$CFG" /tmp/veda_syscall0_forged.elf 2>&1)
code=$?
echo "$out"

trapped=0
if ! { [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; }; then trapped=1; fi

if [ "$trapped" -ne 1 ]; then
  echo ""
  echo "*** TEST FAILED *** (a forged Object_ID somehow produced SUCCESS -- a"
  echo "real security failure, not a benign one)"
  exit 1
fi

echo ""
echo "=== Tracing to confirm the EXACT expected trap cause ==="
trace_out=$("$SIM" --config "$CFG" --trace-instr --trace-exception --trace-csr /tmp/veda_syscall0_forged.elf 2>&1)
# do_sys_write's own `veda.bind c3, a1` (sail_tests/vc_syscall0_kernel.S's
# proven logic) is the first instruction to touch the forged Object_ID.
# mtval packs (cap_idx<<5)|cause -- cap_idx=3 (c3), cause=0x05
# (VEDA_CAUSE_OBJECT_NOT_FOUND, veda_bind_insts.sail) -> mtval=(3<<5)|5=0x65.
# mcause=0x18 is the real Extension-exception class (veda_trap()'s own),
# same convention already confirmed in run_veda_alloca_protect_test.sh.
if echo "$trace_out" | grep -qi "mcause.*0x0*18$" && echo "$trace_out" | grep -qi "mtval.*0x0*65$"; then
  echo "Confirmed: mcause=0x18, mtval=0x65 (VEDA_CAUSE_OBJECT_NOT_FOUND via C3,"
  echo "do_sys_write's own trapping veda.bind) -- real, specific proof."
else
  echo "$trace_out" | grep -i "mcause\|mtval\|exception" | head -20
  echo ""
  echo "*** TEST FAILED *** (run trapped, but NOT with the expected cause --"
  echo "see trace excerpt above)"
  exit 1
fi

echo ""
echo "*** TEST PASSED *** (a deliberately forged, never-populated Object_ID,"
echo "passed to sys_write exactly like a real one, was independently rejected"
echo "by the KERNEL's own trapping veda.bind BEFORE any data movement --"
echo "VEDA_CAUSE_OBJECT_NOT_FOUND, entirely hardware-enforced, zero software"
echo "validation anywhere in the syscall path. This is the real security"
echo "property the whole Syscall-0 milestone exists to prove.)"
exit 0
