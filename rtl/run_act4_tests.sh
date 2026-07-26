#!/usr/bin/env bash
# Runs the real ACT4 RV64I test suite against rv64i_core.tlv: transpiles
# and compiles the core ONCE (the core itself doesn't change per-ELF, only
# the memory image does), then for each generated ELF: objcopies it to a
# $readmemh-compatible hex image, resolves its real (per-ELF-varying)
# `tohost` symbol address via readelf, and re-invokes the same compiled
# sim.vvp with +elf_hex/+tohost_addr plusargs. Collects PASS/FAIL/TIMEOUT
# per test and prints a summary, mirroring run_test.sh's/run_smoke_test.sh's
# proven SandPiper+Icarus invocation pattern.
set -euo pipefail

cd "$(dirname "$0")"
export PATH="$PATH:$HOME/.local/bin"
GCC_BIN=/home/prabhu/makerchip/rva23-core/toolchain/riscv-collab-gcc/riscv/bin
OBJCOPY="$GCC_BIN/riscv64-unknown-elf-objcopy"
READELF="$GCC_BIN/riscv64-unknown-elf-readelf"
# NOTE: elfs/rv64i/I/*.elf (NOT build/rv64i/I/*.sig.elf) is the real
# self-checking artifact -- confirmed by reading framework/src/act/build_plan.py
# in full: .sig.elf is compiled with -DSIGNATURE (no compare, always halts
# PASS, used only to generate the golden signature via the Sail ref model at
# build time); elfs/*.elf is "final_elf", compiled separately with
# -DRVTEST_SELFCHECK and the baked-in Sail-derived reference signature, and
# is the only variant that can actually detect a wrong DUT result.
ELF_DIR="${1:-/home/prabhu/makerchip/rva23-core/act4-verify/work/rva23-base-rv64i/elfs/rv64i/I}"

# Icarus Verilog lives in the conda base env.
if ! command -v iverilog >/dev/null 2>&1; then
  source "$HOME/anaconda3/etc/profile.d/conda.sh"
  conda activate base
fi

SIM=sim
TLV=rv64i_core.tlv
STRIPPED=$SIM/_novz.tlv
mkdir -p "$SIM"

python3 - "$TLV" "$STRIPPED" <<'EOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    lines = f.readlines()
viz = next(i for i, l in enumerate(lines) if '\\viz_js' in l)
tail = next(i for i, l in enumerate(lines) if 'PASS / FAIL' in l)
with open(dst, 'w') as f:
    f.writelines(lines[:viz] + lines[tail-1:])
EOF

echo "==> Transpiling TL-Verilog -> SystemVerilog (SandPiper cloud service, once)"
set +e
sandpiper-saas -i "$STRIPPED" -o rv64i_core.sv --outdir "$SIM" -p m4out
sp_status=$?
set -e
if [ "$sp_status" -gt 1 ]; then
  echo "SandPiper transpile failed (exit $sp_status)" >&2
  exit "$sp_status"
fi

echo "==> Compiling with Icarus Verilog (once)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim.vvp" "$SIM/rv64i_core.sv" "$SIM/tb_act4.sv"

echo "==> Running ELFs from $ELF_DIR"
declare -i n_pass=0 n_fail=0 n_timeout=0 n_total=0
FAIL_LIST=()

for elf in "$ELF_DIR"/*.elf; do
  [ -e "$elf" ] || { echo "No .elf files found in $ELF_DIR" >&2; exit 1; }
  name=$(basename "$elf" .elf)
  n_total+=1

  hexfile="$SIM/${name}.hex"
  "$OBJCOPY" -O verilog "$elf" "$hexfile"

  tohost_addr=$("$READELF" -s "$elf" 2>/dev/null | awk '$8=="tohost"{print $2; exit}')
  if [ -z "$tohost_addr" ]; then
    echo "  ${name}: SKIP (no tohost symbol found)"
    continue
  fi
  # readelf's symbol value is a full 64-bit hex string (e.g.
  # 0000000080037920); our plusarg reader wants a plain hex value.
  tohost_addr_short=${tohost_addr: -8}

  out=$(vvp "$SIM/sim.vvp" +elf_hex="$hexfile" +tohost_addr="$tohost_addr_short" 2>&1)
  result_line=$(echo "$out" | grep -m1 "^RESULT:" || echo "RESULT: NO_OUTPUT")

  case "$result_line" in
    *PASS*)    n_pass+=1;    echo "  ${name}: PASS" ;;
    *FAIL*)    n_fail+=1;    echo "  ${name}: FAIL -- $result_line"; FAIL_LIST+=("$name") ;;
    *TIMEOUT*) n_timeout+=1; echo "  ${name}: TIMEOUT" ; FAIL_LIST+=("$name") ;;
    *)         n_fail+=1;    echo "  ${name}: NO_OUTPUT (unexpected)"; FAIL_LIST+=("$name") ;;
  esac
done

echo ""
echo "==> Summary: $n_pass/$n_total passed, $n_fail failed, $n_timeout timed out"
if [ ${#FAIL_LIST[@]} -gt 0 ]; then
  echo "Failures: ${FAIL_LIST[*]}"
fi

[ "$n_pass" -eq "$n_total" ]
