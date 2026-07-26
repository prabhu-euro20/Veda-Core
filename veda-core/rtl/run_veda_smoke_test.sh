#!/usr/bin/env bash
# Transpile veda_core.tlv -> SystemVerilog (SandPiper) and simulate with
# Icarus Verilog, loading a real ELF via the +elf_hex plusarg (the same
# real mechanism the base core's own ACT4 mode already uses) and dumping
# a cycle trace for manual review -- mirrors rtl/run_smoke_test.sh's own
# proven structure, adapted for ELF loading instead of the hand-assembled
# ROM[] path (Veda-Core's own OCL/OCS only access elfmem, which is only
# populated in act4_mode).
set -euo pipefail

cd "$(dirname "$0")"
export PATH="$PATH:$HOME/.local/bin"

if ! command -v iverilog >/dev/null 2>&1; then
  source "$HOME/anaconda3/etc/profile.d/conda.sh"
  conda activate base
fi

SIM=sim
TLV=veda_core.tlv
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

cat > "$SIM/sp_m4out.vh" <<'VHEOF'
module pseudo_rand #(parameter WIDTH = 1) (input clk, input reset, output logic [WIDTH-1:0] out);
  assign out = '0;
endmodule
VHEOF

cat > "$SIM/sandpiper_gen.vh" <<'VHEOF'
VHEOF

echo "==> Transpiling TL-Verilog -> SystemVerilog (SandPiper cloud service)"
set +e
sandpiper-saas -i "$STRIPPED" -o veda_core.sv --outdir "$SIM" -p m4out
sp_status=$?
set -e
if [ "$sp_status" -gt 1 ]; then
  echo "SandPiper transpile failed (exit $sp_status)" >&2
  exit "$sp_status"
fi

echo "==> Compiling with Icarus Verilog (positive test)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke.sv"
echo "==> Simulating (positive test)"
vvp "$SIM/sim.vvp" +elf_hex="$SIM/veda_smoke_test.hex"

echo "==> Compiling with Icarus Verilog (negative control)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_neg.sv"
echo "==> Simulating (negative control)"
vvp "$SIM/sim_neg.vvp" +elf_hex="$SIM/veda_smoke_neg.hex"

echo "==> Milestone 2: Compiling (OCA + NMC_ADD + Veda-Atomic, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m2.sv"
echo "==> Simulating (Milestone 2 positive)"
vvp "$SIM/sim_m2.vvp" +elf_hex="$SIM/veda_smoke_m2.hex"

echo "==> Milestone 2: Compiling (NMC_ADD missing Permit_NMC_Compute, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m2neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m2_neg.sv"
echo "==> Simulating (Milestone 2 negative: permission)"
vvp "$SIM/sim_m2neg.vvp" +elf_hex="$SIM/veda_smoke_m2_neg.hex"

echo "==> Milestone 2: Compiling (OCA out-of-bounds soft-fail, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ocaneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_oca_neg.sv"
echo "==> Simulating (Milestone 2 negative: OCA soft-fail)"
vvp "$SIM/sim_ocaneg.vvp" +elf_hex="$SIM/veda_smoke_oca_neg.hex"

echo "==> Milestone 3: Compiling (query family + CSetBounds, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m3.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m3.sv"
echo "==> Simulating (Milestone 3 positive)"
vvp "$SIM/sim_m3.vvp" +elf_hex="$SIM/veda_smoke_m3.hex"

echo "==> Milestone 3: Compiling (CSetBounds out-of-window, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_csbneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_csetbounds_neg.sv"
echo "==> Simulating (Milestone 3 negative)"
vvp "$SIM/sim_csbneg.vvp" +elf_hex="$SIM/veda_smoke_csetbounds_neg.hex"

echo "==> Milestone 4: Compiling (privilege gate + ODT-Populate/Destroy lifecycle, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m4.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m4.sv"
echo "==> Simulating (Milestone 4 positive)"
vvp "$SIM/sim_m4.vvp" +elf_hex="$SIM/veda_smoke_m4.hex"

echo "==> Milestone 4: Compiling (dropped-privilege ODT-Populate, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m4neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m4_neg.sv"
echo "==> Simulating (Milestone 4 negative)"
vvp "$SIM/sim_m4neg.vvp" +elf_hex="$SIM/veda_smoke_m4_neg.hex"

echo "==> Milestone 5: Compiling (NMC_ADD.W + 8 untested Veda-Atomic ops, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m5.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m5.sv"
echo "==> Simulating (Milestone 5)"
vvp "$SIM/sim_m5.vvp" +elf_hex="$SIM/veda_smoke_m5.hex"

echo "==> Milestone 6: Compiling (CSeal/CUnseal + sealed-capability enforcement, positive+negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m6.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m6.sv"
echo "==> Simulating (Milestone 6)"
vvp "$SIM/sim_m6.vvp" +elf_hex="$SIM/veda_smoke_m6.hex"

echo "==> Milestone 7: Compiling (OCL.C/OCS.C capability-width memory access, positive+negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m7.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m7.sv"
echo "==> Simulating (Milestone 7)"
vvp "$SIM/sim_m7.vvp" +elf_hex="$SIM/veda_smoke_m7.hex"

echo "==> Milestone 8: Compiling (Rebind, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m8.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m8.sv"
echo "==> Simulating (Milestone 8 positive)"
vvp "$SIM/sim_m8.vvp" +elf_hex="$SIM/veda_smoke_m8.hex"

echo "==> Milestone 8: Compiling (Rebind sealed/ODT-miss/reserved-mode, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m8neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m8_neg.sv"
echo "==> Simulating (Milestone 8 negative)"
vvp "$SIM/sim_m8neg.vvp" +elf_hex="$SIM/veda_smoke_m8_neg.hex"

echo "==> Milestone 9: Compiling (Zicsr-lite + real trap-and-resume, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m9.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m9.sv"
echo "==> Simulating (Milestone 9 positive)"
vvp "$SIM/sim_m9.vvp" +elf_hex="$SIM/veda_smoke_m9.hex"

# Milestone 1/2/6's own negative/sealed-use tests (built earlier above)
# were upgraded in-place to a real trap-handler pattern as part of
# Milestone 9 -- no separate re-run needed here, their earlier
# build/run (near Milestones 1/2/6's own sections above) already
# exercises the upgraded .S/.sv content.

echo "==> Milestone 10: Compiling (OCInvoke, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m10.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m10.sv"
echo "==> Simulating (Milestone 10 positive)"
vvp "$SIM/sim_m10.vvp" +elf_hex="$SIM/veda_smoke_m10.hex"

echo "==> Milestone 10: Compiling (OCInvoke Type/Permit_Execute Violation, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m10neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m10_neg.sv"
echo "==> Simulating (Milestone 10 negative)"
vvp "$SIM/sim_m10neg.vvp" +elf_hex="$SIM/veda_smoke_m10_neg.hex"

echo "==> Milestone 11: Compiling (OSpecialRW + ODA-authorized ODT-Populate, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m11.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m11.sv"
echo "==> Simulating (Milestone 11 positive)"
vvp "$SIM/sim_m11.vvp" +elf_hex="$SIM/veda_smoke_m11.hex"

echo "==> Milestone 11: Compiling (dropped privilege + unauthorized ODA, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m11neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m11_neg.sv"
echo "==> Simulating (Milestone 11 negative)"
vvp "$SIM/sim_m11neg.vvp" +elf_hex="$SIM/veda_smoke_m11_neg.hex"

echo "==> Milestone 12: Compiling (owner-hart ODT enforcement, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m12.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m12.sv"
echo "==> Simulating (Milestone 12 positive)"
vvp "$SIM/sim_m12.vvp" +elf_hex="$SIM/veda_smoke_m12.hex"

echo "==> Milestone 12: Compiling (wrong-owner hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m12neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m12_neg.sv"
echo "==> Simulating (Milestone 12 negative)"
vvp "$SIM/sim_m12neg.vvp" +elf_hex="$SIM/veda_smoke_m12_neg.hex"

echo "==> Milestone 13: Compiling (plain Bind object-not-found hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m13neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m13_neg.sv"
echo "==> Simulating (Milestone 13 negative)"
vvp "$SIM/sim_m13neg.vvp" +elf_hex="$SIM/veda_smoke_m13_neg.hex"

echo "==> Regression: base RV64I 81-instruction smoke test (unmodified)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_base.vvp" "$SIM/veda_core.sv" "$SIM/tb_smoke.sv"
vvp "$SIM/sim_base.vvp"
