#!/bin/bash
# Toolchain Milestone 8: build the VedaShadowPropagation out-of-tree pass
# plugin and run its FileCheck-based .ll test suite.
#
# Real, deliberate compiler choice: the plugin is compiled with the
# SYSTEM's official Ubuntu-packaged clang++-21 (apt package `clang-21`,
# installed in Toolchain Milestone 2), NOT the custom llvm-project checkout
# built in toolchain/llvm-project/build/ -- that custom build only
# registered the RISCV backend (LLVM_TARGETS_TO_BUILD=RISCV), so its own
# clang/clang++ genuinely cannot emit native x86_64 code at all (a real,
# verified "unknown target triple 'unknown'" build failure, not assumed).
# The plugin itself must be a native x86_64 shared object, since it is
# dlopen'd into the HOST opt/clang process. Correctness/ABI compatibility
# with our own custom-built `opt` (used to load and run it) comes from
# compiling against OUR OWN checkout's LLVM headers (`llvm-config
# --cxxflags`, which points at toolchain/llvm-project/llvm/include and
# .../build/include) -- system clang++-21 is used purely as an x86_64
# -capable C++ compiler frontend here, not as the source of the LLVM API
# definitions being compiled against. Both are the exact same real,
# upstream-released 21.1.8, so this is a same-version build, not a
# cross-version guess.
set -u
cd "$(dirname "$0")"

MY_LLVM_BUILD=/home/prabhu/makerchip/rva23-core/toolchain/llvm-project/build
OPT=$MY_LLVM_BUILD/bin/opt
FILECHECK=$MY_LLVM_BUILD/bin/FileCheck
LLVM_CONFIG=$MY_LLVM_BUILD/bin/llvm-config
PLUGIN=/tmp/VedaShadowPropagation.so

CXXFLAGS=$($LLVM_CONFIG --cxxflags)
if ! clang++-21 $CXXFLAGS -fPIC -shared -o "$PLUGIN" VedaShadowPropagation.cpp; then
  echo "plugin build FAILED"
  exit 1
fi

pass_count=0
fail_count=0
declare -a results

for f in test/*.ll; do
  name=$(basename "$f" .ll)
  if ! "$OPT" -load-pass-plugin="$PLUGIN" -passes=veda-shadow-prop -S "$f" \
        > /tmp/"${name}".out 2>/tmp/"${name}".experr; then
    results+=("OPT-FAIL  $name")
    fail_count=$((fail_count + 1))
    continue
  fi
  if "$FILECHECK" "$f" < /tmp/"${name}".out > /tmp/"${name}".fc 2>&1; then
    results+=("PASS      $name")
    pass_count=$((pass_count + 1))
  else
    results+=("FAIL      $name")
    fail_count=$((fail_count + 1))
  fi
done

echo "=== Toolchain Milestone 8 (veda-shadow-prop) test results ==="
for r in "${results[@]}"; do echo "$r"; done
echo "---"
echo "$pass_count/$((pass_count + fail_count)) passed"

[ "$fail_count" -eq 0 ]
