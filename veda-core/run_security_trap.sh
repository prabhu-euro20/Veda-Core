#!/usr/bin/env bash
# Real, live A/B security-trap demonstration for a LinkedIn screenshot --
# same shape of attack (a corrupted/forged return capability), run against
# two real cores from this project:
#
#   1. rtl/rv64i_core.tlv       -- plain RV64I, no capability checking
#   2. veda-core/rtl/veda_core.tlv -- Veda-Core, OCJALR capability-checked
#
# Both demo programs are hand-assembled RISC-V (.S), transpiled from the
# real, committed TL-Verilog sources via SandPiper, and simulated with
# Icarus Verilog. The Veda-Core program's setup mirrors the committed,
# tested rtl/sim/veda_smoke_m17_neg.S exactly (Seal Violation scenario),
# modified only to store mcause/mtval/mepc into GPR markers for display
# rather than compare-and-branch. Nothing here is fabricated or simulated
# output copy-pasted from elsewhere -- run this yourself to reproduce it.
set -uo pipefail

cd "$(dirname "$0")/security_trap_demo"
ROOT=/home/prabhu/makerchip/rva23-core
TC="$ROOT/toolchain/riscv-collab-gcc/riscv/bin"
export PATH="$PATH:$HOME/.local/bin"

if ! command -v iverilog >/dev/null 2>&1; then
  source "$HOME/anaconda3/etc/profile.d/conda.sh"
  conda activate base
fi

echo "=================================================="
echo "  Veda-Core — Real Security Trap Demonstration"
echo "  $(date '+%Y-%m-%d %H:%M %Z')"
echo "=================================================="
echo

mkdir -p sim_trad sim_veda

strip_viz() {
  python3 - "$1" "$2" <<'EOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    lines = f.readlines()
viz = next(i for i, l in enumerate(lines) if '\\viz_js' in l)
tail = next(i for i, l in enumerate(lines) if 'PASS / FAIL' in l)
with open(dst, 'w') as f:
    f.writelines(lines[:viz] + lines[tail-1:])
EOF
}

for d in sim_trad sim_veda; do
  cat > "$d/sp_m4out.vh" <<'VHEOF'
module pseudo_rand #(parameter WIDTH = 1) (input clk, input reset, output logic [WIDTH-1:0] out);
  assign out = '0;
endmodule
VHEOF
  : > "$d/sandpiper_gen.vh"
done

echo "--> Assembling demo programs (real riscv64-unknown-elf toolchain)"
"$TC/riscv64-unknown-elf-as" -march=rv64i -mabi=lp64 -o trad_hijack.o trad_hijack.S
"$TC/riscv64-unknown-elf-ld" -T veda_smoke_test.ld -o trad_hijack.elf trad_hijack.o
"$TC/riscv64-unknown-elf-objcopy" -O verilog trad_hijack.elf trad_hijack.hex

"$TC/riscv64-unknown-elf-as" -march=rv64i_zicsr -mabi=lp64 -o veda_prot_fixed.o veda_prot_fixed.S
"$TC/riscv64-unknown-elf-ld" -T veda_smoke_test.ld -o veda_prot_fixed.elf veda_prot_fixed.o
"$TC/riscv64-unknown-elf-objcopy" -O verilog veda_prot_fixed.elf veda_prot_fixed.hex

"$TC/riscv64-unknown-elf-as" -march=rv64i_zicsr -mabi=lp64 -o veda_prot_fast_bounds.o veda_prot_fast_bounds.S
"$TC/riscv64-unknown-elf-ld" -T veda_smoke_test.ld -o veda_prot_fast_bounds.elf veda_prot_fast_bounds.o
"$TC/riscv64-unknown-elf-objcopy" -O verilog veda_prot_fast_bounds.elf veda_prot_fast_bounds.hex
echo "    done"
echo

echo "--> Transpiling both cores (SandPiper cloud service)"
strip_viz "$ROOT/rtl/rv64i_core.tlv" sim_trad/_novz.tlv
strip_viz "$ROOT/veda-core/rtl/veda_core.tlv" sim_veda/_novz.tlv
sandpiper-saas -i sim_trad/_novz.tlv -o rv64i_core.sv --outdir sim_trad -p m4out >/dev/null 2>&1
[ $? -gt 1 ] && { echo "SandPiper failed on rv64i_core.tlv" >&2; exit 1; }
sandpiper-saas -i sim_veda/_novz.tlv -o veda_core.sv --outdir sim_veda -p m4out >/dev/null 2>&1
[ $? -gt 1 ] && { echo "SandPiper failed on veda_core.tlv" >&2; exit 1; }
echo "    done"
echo

echo "--> Compiling with Icarus Verilog"
iverilog -g2012 -I sim_trad -o sim_trad/sim.vvp sim_trad/rv64i_core.sv tb_trad_hijack.sv
iverilog -g2012 -I sim_veda -o sim_veda/sim.vvp sim_veda/veda_core.sv tb_veda_prot_fixed.sv
iverilog -g2012 -I sim_veda -o sim_veda/sim_fastbounds.vvp sim_veda/veda_core.sv tb_veda_prot_fast_bounds.sv
echo "    done"
echo

echo "=================================================="
echo "  Scenario 1: attacker corrupts/forges a return address"
echo "=================================================="
echo
echo "[1/2] Traditional RV64I core (rtl/rv64i_core.tlv)"
vvp sim_trad/sim.vvp +elf_hex=trad_hijack.hex | grep -v "^tb_"
echo
echo "[2/2] Veda-Core (veda-core/rtl/veda_core.tlv) -- OCJALR capability-checked return"
vvp sim_veda/sim.vvp +elf_hex=veda_prot_fixed.hex | grep -v "^tb_"
echo
echo "=================================================="
echo "  Scenario 2: does the Milestone 18 speed optimization"
echo "  (VEDA_ODT_POPULATE_FAST) weaken security?"
echo "=================================================="
echo
vvp sim_veda/sim_fastbounds.vvp +elf_hex=veda_prot_fast_bounds.hex | grep -v "^tb_"
echo
echo "=================================================="
