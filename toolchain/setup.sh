#!/bin/bash
# Veda-Core toolchain setup: a single-file, from-scratch-to-verified-demo
# automation script, following the real architectural approach of CHERI's
# own cheribuild.py (https://github.com/CTSRD-CHERI/cheribuild) -- not its
# content. Adopted from it: named, independently-invokable targets; each
# target's real output on disk (not a separate bookkeeping marker) decides
# whether it's already done, so re-running this script never redoes
# multi-minute work unless asked to; --dry-run to preview; --force to
# rebuild anyway; one default "do everything" path so a new contributor
# never has to assemble the right command sequence by hand. Kept as a
# single bash script (not a new Python dependency) to match every other
# automation script already established in this project
# (run_veda_selfcheck_tests.sh, run_veda_demo_tests.sh, run_act4_tests.sh).
#
# Usage:
#   toolchain/setup.sh [options] [target...]
#
# Targets (run in this order if none given -- "all"):
#   deps            system packages (clang/cmake/ninja/opam) -- Toolchain Milestone 2
#   gnu-toolchain   prebuilt riscv64-unknown-elf-{gcc,as,ld,gdb} (Bootlin release)
#   sail-compiler   the Sail compiler itself, via opam -- prerequisite for sail-riscv
#   sail-riscv      clone + build the Veda-Core Sail simulator/gdbstub
#   llvm            clone + build the Veda-Core LLVM/clang fork
#   demo            compile + run the real end-to-end linked-list demo (Toolchain Milestone 9)
#   debug           print the exact commands to debug the demo with real gdb + capability registers
#
# Options:
#   -n, --dry-run   print what would run, do nothing
#   -f, --force     rebuild a target even if its output already exists
#   -j, --jobs N    parallelism for the two real builds (default: 4, deliberately
#                   conservative -- this project's own build history found this
#                   necessary on tight-RAM machines, not chosen arbitrarily)
#   -h, --help      print this usage and exit
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../toolchain
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"                    # the cloned Veda-Core repo

LLVM_REPO="https://github.com/prabhu-euro20/Veda-Core-LLVM.git"
SAIL_RISCV_REPO="https://github.com/prabhu-euro20/Veda-Core-sail-riscv.git"
# The real, official riscv-collab/riscv-gnu-toolchain GitHub release --
# NOT Bootlin (a different, unrelated, glibc/Linux-userspace toolchain
# with completely different binary names, riscv64-linux-*/riscv64
# -buildroot-linux-gnu-*, not the riscv64-unknown-elf-* bare-metal/newlib
# toolchain this project's own scripts actually need). Pinned to a
# specific release tag, not "latest", for reproducibility. Confirmed via
# `tar tf` before ever trusting this URL: the tarball's own top-level
# directory is already `riscv/`, matching this project's own established
# `toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-*` path
# exactly -- no --strip-components needed.
GNU_TOOLCHAIN_TAG="2026.07.15"
GNU_TOOLCHAIN_URL="https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${GNU_TOOLCHAIN_TAG}/riscv64-elf-ubuntu-24.04-gcc.tar.xz"
BRANCH=veda-core

DRY_RUN=0
FORCE=0
JOBS=4

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[setup] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
# Aborts the whole script the moment any real (non-dry-run) command
# fails -- confirmed necessary: an earlier version of this script let a
# failed `cmake`/`make` (e.g. sail-riscv's own "Sail not found" case)
# fall through silently into later steps and finally print "done.",
# giving a false impression of success.
run()  {
  printf '\033[2m+ %s\033[0m\n' "$*"
  [ "$DRY_RUN" -eq 1 ] && return 0
  "$@"
  local status=$?
  [ "$status" -eq 0 ] || die "command failed (exit $status): $*"
}

usage() { sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------------------
# deps -- Toolchain Milestone 2's own real, verified apt command, plus the
# Sail compiler's own standard opam-based prerequisite.
# ---------------------------------------------------------------------------
step_deps() {
  # opam packages (sail) only land on PATH after `eval $(opam env)` --
  # opam itself warns about this ("the environment is not in sync...
  # run eval $(opam env)") and does NOT update a non-interactive
  # script's own PATH automatically, even if sail was opam-installed in
  # a PRIOR script/session. Confirmed empirically on this project's own
  # dev machine: `opam install -y sail` immediately followed by `cmake`
  # (sail-riscv's own Sail-detection check) fails with "Sail not found"
  # in the SAME shell/script run without this -- eval'd unconditionally
  # here, before the presence check, so the check itself (and every
  # later step in this script run) sees a correct PATH.
  command -v opam >/dev/null 2>&1 && eval "$(opam env)" 2>/dev/null
  if [ "$FORCE" -eq 0 ] && command -v clang >/dev/null 2>&1 && command -v cmake >/dev/null 2>&1 \
     && command -v ninja >/dev/null 2>&1 && command -v opam >/dev/null 2>&1 \
     && command -v sail >/dev/null 2>&1; then
    log "deps: clang/cmake/ninja/opam/sail already present -- skipping (--force to redo)"
    return 0
  fi
  log "deps: installing system packages + Sail compiler"
  run sudo apt-get install -y clang llvm-dev cmake ninja-build build-essential opam
  run opam init -y
  run opam install -y sail
  eval "$(opam env)"
}

# ---------------------------------------------------------------------------
# gnu-toolchain -- real, unmodified, prebuilt riscv64-unknown-elf-{gcc,as,ld,gdb}.
# Confirmed this session: `.insn` pseudo-ops already assemble every real
# Veda-Core encoding unmodified, so no patched binutils are needed at all.
# ---------------------------------------------------------------------------
step_gnu_toolchain() {
  local dir="$REPO_ROOT/toolchain/riscv-collab-gcc"
  # Real binaries live under $dir/riscv/bin/ (the tarball's own top-level
  # layout) -- confirmed directly, not assumed, before writing this check.
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/riscv/bin/riscv64-unknown-elf-gcc" ]; then
    log "gnu-toolchain: already present at $dir/riscv -- skipping (--force to redo)"
    return 0
  fi
  log "gnu-toolchain: downloading real riscv-collab/riscv-gnu-toolchain release $GNU_TOOLCHAIN_TAG (~550MB)"
  run mkdir -p "$dir"
  local tarball="/tmp/riscv64-elf-gcc.tar.xz"
  run wget -O "$tarball" "$GNU_TOOLCHAIN_URL"
  run tar xf "$tarball" -C "$dir"
}

# ---------------------------------------------------------------------------
# sail-riscv -- clone the real public fork (Milestones 1-22, including the
# GDB stub and every real security fix this project has made), build.
# ---------------------------------------------------------------------------
step_sail_riscv() {
  local dir="$REPO_ROOT/toolchain/sail-riscv"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/build/c_emulator/sail_riscv_sim" ]; then
    log "sail-riscv: sail_riscv_sim already built -- skipping (--force to redo)"
    return 0
  fi
  if [ ! -d "$dir/.git" ]; then
    log "sail-riscv: cloning $SAIL_RISCV_REPO (branch $BRANCH)"
    run git clone --branch "$BRANCH" "$SAIL_RISCV_REPO" "$dir"
  fi
  # Defensive: covers `./toolchain/setup.sh sail-riscv` invoked standalone,
  # in a shell/script run that never went through step_deps' own eval
  # above -- see step_deps' comment for the full real reasoning.
  command -v opam >/dev/null 2>&1 && eval "$(opam env)" 2>/dev/null
  log "sail-riscv: configuring + building (this can take several minutes)"
  run mkdir -p "$dir/build"
  ( cd "$dir/build" && run cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo -DDOWNLOAD_GMP=FALSE -DENABLE_RISCV_TESTS=TRUE .. ) || exit 1
  ( cd "$dir/build" && run make -j"$JOBS" ) || exit 1
}

# ---------------------------------------------------------------------------
# llvm -- clone the real public fork (36 Veda-Core instructions, capability
# register class, disassembler, MC tests), build clang + llvm-mc.
# ---------------------------------------------------------------------------
step_llvm() {
  local dir="$REPO_ROOT/toolchain/llvm-project"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/build/bin/clang" ]; then
    log "llvm: clang already built -- skipping (--force to redo)"
    return 0
  fi
  if [ ! -d "$dir/.git" ]; then
    log "llvm: cloning $LLVM_REPO (branch $BRANCH)"
    run git clone --branch "$BRANCH" "$LLVM_REPO" "$dir"
  fi
  log "llvm: configuring + building (this is the longest step -- can take 30+ minutes)"
  run mkdir -p "$dir/build"
  ( cd "$dir/build" && run cmake -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD=RISCV \
      -DLLVM_PARALLEL_LINK_JOBS=1 -G Ninja ../llvm ) || exit 1
  ( cd "$dir/build" && run ninja -j"$JOBS" ) || exit 1
}

# ---------------------------------------------------------------------------
# demo -- the real, end-to-end, positive+negative Toolchain Milestone 9 demo:
# ordinary C, compiled through the SoftBound-style pass, run on the real
# capability-checked hardware model. Just delegates to the project's own
# already-established script rather than re-deriving its command sequence.
# ---------------------------------------------------------------------------
step_demo() {
  local demo_dir="$REPO_ROOT/veda-core/compiler"
  if [ ! -x "$REPO_ROOT/toolchain/llvm-project/build/bin/clang" ] || \
     [ ! -x "$REPO_ROOT/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim" ]; then
    log "demo: llvm/sail-riscv not built yet -- running those targets first"
    step_llvm
    step_sail_riscv
    step_gnu_toolchain
  fi
  log "demo: compiling + running the real linked-list (positive) and OOB (negative) demos"
  run bash "$demo_dir/run_veda_demo_tests.sh"
}

# ---------------------------------------------------------------------------
# debug -- this step is inherently interactive (a live GDB session), so it
# prints the exact, real, already-verified commands (Toolchain Milestones
# 3+4) rather than trying to script an interactive terminal.
# ---------------------------------------------------------------------------
step_debug() {
  local sim="$REPO_ROOT/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim"
  local gdb="$REPO_ROOT/toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-gdb"
  local cfg="$REPO_ROOT/veda-core/sail_tests/veda_test_sail.json"
  cat <<EOF

To debug the compiled demo with real capability-register visibility:

  1) Start the simulator with a live GDB stub:
     $sim --config $cfg --gdbstub 9998 /tmp/veda_demo_linked_list.elf &

  2) Connect the real, unmodified debugger:
     $gdb -ex "target remote :9998"

  3) Inside gdb, standard commands work (break, continue, step, info registers),
     PLUS Veda-Core's own 16 capability registers are directly visible:
       (gdb) info registers c0 c0_tag

  (Run '$0 demo' first if /tmp/veda_demo_linked_list.elf doesn't exist yet.)
EOF
}

step_all() {
  step_deps
  step_gnu_toolchain
  step_sail_riscv
  step_llvm
  step_demo
  step_debug
}

# ---------------------------------------------------------------------------
targets=()
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -f|--force)   FORCE=1 ;;
    -j|--jobs)    shift; JOBS="$1" ;;
    -h|--help)    usage; exit 0 ;;
    deps|gnu-toolchain|sail-compiler|sail-riscv|llvm|demo|debug|all)
      targets+=("$1") ;;
    *) echo "unknown option/target: $1" >&2; usage; exit 1 ;;
  esac
  shift
done
[ ${#targets[@]} -eq 0 ] && targets=(all)

for t in "${targets[@]}"; do
  case "$t" in
    deps)          step_deps ;;
    gnu-toolchain) step_gnu_toolchain ;;
    sail-compiler) step_deps ;;   # sail itself is installed as part of deps
    sail-riscv)    step_sail_riscv ;;
    llvm)          step_llvm ;;
    demo)          step_demo ;;
    debug)         step_debug ;;
    all)           step_all ;;
  esac
done

log "done."
