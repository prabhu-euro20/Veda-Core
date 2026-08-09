#!/bin/bash
# Toolchain Milestone 13's real completion criterion: two module-scope C
# globals (`g_lower[4]`, `g_upper[4]`) inside a veda_compartment function
# are protected from overflowing into each other, via Phase B1's new
# GlobalVariable-recognition logic in VedaShadowPropagation.cpp -- each
# global gets its own INDIVIDUALLY-bounded capability, minted once at
# bootstrap (before the first OCInvoke) via OCA-then-CSetBounds off a
# whole-region source capability, cached into an in-memory table via
# OCS.C, and loaded on demand via OCL.C at every real access -- directly
# modeled on the official CHERI "inter-object stack buffer overflow"
# exercise and on Milestone 12's own veda_alloca_protect_demo.c, and on
# real CHERI's own __cap_relocs mechanism (see
# TOOLCHAIN_MILESTONE_13_DESIGN.md for the full research/design).
#
# Pipeline note: this demo IS __attribute__((veda_compartment)), so
# (Milestone 12's own already-established lesson) both the demo AND
# veda_compiler_rt.c/veda_rt.c (which now ALSO carry the attribute on
# their own global-helper functions) need the two-stage
# `clang -S -emit-llvm` -> `llc -mattr=+xveda` pipeline, not single-stage
# `clang -c` (which crashes RISCVAsmPrinter on any veda_compartment
# -attributed function's own C15 prologue codegen, since the clang
# driver's own -march=...xveda parser rejects xveda).
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

"$MC" $MC_FLAGS -o /tmp/global_entry.o veda_global_protect_entry.S \
  || { echo "veda_global_protect_entry.S assembly failed"; exit 1; }

"$CLANG" $CC_FLAGS -S -emit-llvm -o /tmp/global_veda_compiler_rt.ll veda_compiler_rt.c \
  || { echo "veda_compiler_rt.c IR emission failed"; exit 1; }
"$LLC" $LLC_FLAGS -o /tmp/global_veda_compiler_rt.o /tmp/global_veda_compiler_rt.ll \
  || { echo "veda_compiler_rt.c llc lowering failed"; exit 1; }
"$CLANG" $CC_FLAGS -S -emit-llvm -o /tmp/global_veda_rt.ll ../runtime/veda_rt.c \
  || { echo "veda_rt.c IR emission failed"; exit 1; }
"$LLC" $LLC_FLAGS -o /tmp/global_veda_rt.o /tmp/global_veda_rt.ll \
  || { echo "veda_rt.c llc lowering failed"; exit 1; }
"$MC" $MC_FLAGS -o /tmp/global_veda_rt_asm.o ../runtime/veda_rt_asm.S \
  || { echo "veda_rt_asm.S failed"; exit 1; }

build_and_link() {
  local label="$1" cc_extra="$2" out_elf="$3"
  "$CLANG" $CC_FLAGS $cc_extra -fpass-plugin="$PLUGIN" -S -emit-llvm -o /tmp/global_demo_"$label".ll veda_global_protect_demo.c \
    || { echo "[$label] clang IR emission failed"; return 1; }
  "$LLC" $LLC_FLAGS -o /tmp/global_demo_"$label".o /tmp/global_demo_"$label".ll \
    || { echo "[$label] llc lowering failed"; return 1; }
  "$LD" -T "$LDS" -o "$out_elf" /tmp/global_entry.o /tmp/global_demo_"$label".o \
    /tmp/global_veda_compiler_rt.o /tmp/global_veda_rt.o /tmp/global_veda_rt_asm.o \
    2>/tmp/global_"$label".lderr \
    || { echo "[$label] LD-FAIL"; cat /tmp/global_"$label".lderr; return 1; }
  return 0
}

echo "=== Positive: in-bounds (VEDA_OOB_INDEX=3, the default) ==="
if ! build_and_link "positive" "" /tmp/veda_global_positive.elf; then
  echo "*** TEST FAILED *** (positive build)"; exit 1
fi
pos_out=$("$SIM" --config "$CFG" /tmp/veda_global_positive.elf 2>&1)
pos_code=$?
echo "$pos_out"

echo ""
echo "=== Negative control: deliberate cross-global overflow (VEDA_OOB_INDEX=4) ==="
if ! build_and_link "negative" "-DVEDA_OOB_INDEX=4" /tmp/veda_global_negative.elf; then
  echo "*** TEST FAILED *** (negative build)"; exit 1
fi
neg_out=$("$SIM" --config "$CFG" /tmp/veda_global_negative.elf 2>&1)
neg_code=$?
echo "$neg_out"

pos_ok=0
if [ "$pos_code" -eq 0 ] && echo "$pos_out" | grep -q "SUCCESS"; then pos_ok=1; fi
neg_trapped=0
if ! { [ "$neg_code" -eq 0 ] && echo "$neg_out" | grep -q "SUCCESS"; }; then neg_trapped=1; fi

if [ "$pos_ok" -ne 1 ] || [ "$neg_trapped" -ne 1 ]; then
  echo ""
  echo "*** TEST FAILED *** (positive ok=$pos_ok, negative trapped=$neg_trapped)"
  exit 1
fi

# Real, honest completion criterion (Milestone 12's own established
# discipline): don't just accept "negative build failed to print
# SUCCESS" -- trace the negative run and confirm the EXACT expected
# cause. mtval packs (cap_idx<<5)|cause (veda_xtval, re-verified); the
# OOB write here goes through the PER-ACCESS scratch capability register
# C10 (index 10, this milestone's own real, grep-audited pick -- see
# veda_rt_asm.S's own header comment), and the expected cause is
# VEDA_CAUSE_BOUNDS_VIOLATION=0x01 -- so mtval = (10<<5)|0x01 = 0x141.
# Real, honest distinction from Milestone 12's own equivalent test: this
# trap fires the instant g_lower[4]'s own access_offset(32)+width(8)
# exceeds g_lower's OWN table-resident capability's own Length(32) --
# BEFORE the access could ever reach g_upper's own bytes at all, since
# g_lower and g_upper carry SEPARATE, individually-bounded capabilities
# (not one shared region narrowed per access, Milestone 12's own design).
echo ""
echo "=== Tracing negative run to confirm the EXACT expected trap cause ==="
trace_out=$("$SIM" --config "$CFG" --trace-instr --trace-exception --trace-csr /tmp/veda_global_negative.elf 2>&1)
if echo "$trace_out" | grep -qi "mcause.*0x0*18$" && echo "$trace_out" | grep -qi "mtval.*0x0*141$"; then
  echo "Confirmed: mcause=0x18, mtval=0x141 (VEDA_CAUSE_BOUNDS_VIOLATION via C10) -- real, specific proof."
else
  echo "$trace_out" | grep -i "mcause\|mtval\|exception" | head -20
  echo ""
  echo "*** TEST FAILED *** (negative run trapped, but NOT with the expected cause -- see trace excerpt above)"
  exit 1
fi

echo ""
echo "*** TEST PASSED *** (real compiled C function, attributed veda_compartment,"
echo "with two module-scope globals (g_lower[4], g_upper[4]) -- Phase B1 mints"
echo "each its own individually-bounded capability once at bootstrap (real"
echo "CHERI's own __cap_relocs property) and routes every load/store through"
echo "OCL.C-loaded, already-exact capabilities and real OCL.D/OCS.D. In-bounds"
echo "access completes with the correct value (113); a deliberate cross-global"
echo "overflow genuinely hard-traps with the exact expected"
echo "VEDA_CAUSE_BOUNDS_VIOLATION cause, confirmed via trace, at g_lower's own"
echo "capability boundary -- real, hardware-enforced, per-object isolation"
echo "between separate C global variables.)"
exit 0
