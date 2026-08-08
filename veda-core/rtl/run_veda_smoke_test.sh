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

echo "==> Milestone 14: Compiling (PCC compartment bounding, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m14.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m14.sv"
echo "==> Simulating (Milestone 14 positive)"
vvp "$SIM/sim_m14.vvp" +elf_hex="$SIM/veda_smoke_m14.hex"

echo "==> Milestone 14: Compiling (compartment escape hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m14neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m14_neg.sv"
echo "==> Simulating (Milestone 14 negative)"
vvp "$SIM/sim_m14neg.vvp" +elf_hex="$SIM/veda_smoke_m14_neg.hex"

echo "==> Milestone 18: Compiling (VEDA_ODT_POPULATE_FAST + veda_attr CSR, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m18.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m18.sv"
echo "==> Simulating (Milestone 18 positive)"
vvp "$SIM/sim_m18.vvp" +elf_hex="$SIM/veda_smoke_m18.hex"

echo "==> Milestone 18: Compiling (veda_attr-sourced Length bounds enforcement, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m18neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m18_neg.sv"
echo "==> Simulating (Milestone 18 negative)"
vvp "$SIM/sim_m18neg.vvp" +elf_hex="$SIM/veda_smoke_m18_neg.hex"

echo "==> Milestone 19: Compiling (Veda-Purecap Enforcement, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19.sv"
echo "==> Simulating (Milestone 19 positive)"
vvp "$SIM/sim_m19.vvp" +elf_hex="$SIM/veda_smoke_m19.hex"

echo "==> Milestone 19: Compiling (global purecap bit blocks ordinary ld/sd, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19_neg.sv"
echo "==> Simulating (Milestone 19 negative 1)"
vvp "$SIM/sim_m19neg.vvp" +elf_hex="$SIM/veda_smoke_m19_neg.hex"

echo "==> Milestone 19: Compiling (OCInvoke compartment blocks ordinary ld/sd, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19neg2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19_neg2.sv"
echo "==> Simulating (Milestone 19 negative 2)"
vvp "$SIM/sim_m19neg2.vvp" +elf_hex="$SIM/veda_smoke_m19_neg2.hex"

echo "==> Milestone 20: Compiling (compartment-state CSR gate, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20.sv"
echo "==> Simulating (Milestone 20 positive)"
vvp "$SIM/sim_m20.vvp" +elf_hex="$SIM/veda_smoke_m20.hex"

echo "==> Milestone 20: Compiling (veda_pcc_length self-escape, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20_neg.sv"
echo "==> Simulating (Milestone 20 negative 1)"
vvp "$SIM/sim_m20neg.vvp" +elf_hex="$SIM/veda_smoke_m20_neg.hex"

echo "==> Milestone 20: Compiling (veda_mode self-escape, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20neg2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20_neg2.sv"
echo "==> Simulating (Milestone 20 negative 2)"
vvp "$SIM/sim_m20neg2.vvp" +elf_hex="$SIM/veda_smoke_m20_neg2.hex"

echo "==> Compiling (Veda-Atomic aq/rl invariance)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_aqrl.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_aqrl_invariance.sv"
echo "==> Simulating (aq/rl invariance)"
vvp "$SIM/sim_aqrl.vvp" +elf_hex="$SIM/veda_smoke_aqrl_invariance.hex"

echo "==> Milestone 22: Compiling (OCJALR compartment-boundary scope, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m22.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m22.sv"
echo "==> Simulating (Milestone 22)"
vvp "$SIM/sim_m22.vvp" +elf_hex="$SIM/veda_smoke_m22.hex"

echo "==> Minimal OS kernel Milestone A: Compiling (TSC round-trip via OSpecialRW selector, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosA_tsc.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosA_tsc.sv"
echo "==> Simulating (minimal OS kernel Milestone A)"
vvp "$SIM/sim_mosA_tsc.vvp" +elf_hex="$SIM/veda_smoke_mosA_tsc.hex"

echo "==> Minimal OS kernel Milestone B: Compiling (CSealEntry + OCRETURN, positive, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosB_sentry.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosB_sentry.sv"
echo "==> Simulating (minimal OS kernel Milestone B positive)"
vvp "$SIM/sim_mosB_sentry.vvp" +elf_hex="$SIM/veda_smoke_mosB_sentry.hex"

echo "==> Minimal OS kernel Milestone B: Compiling (CSeal forgery blocked + OCRETURN tag violation, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosB_sentry_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosB_sentry_neg.sv"
echo "==> Simulating (minimal OS kernel Milestone B negative)"
vvp "$SIM/sim_mosB_sentry_neg.vvp" +elf_hex="$SIM/veda_smoke_mosB_sentry_neg.hex"

echo "==> Milestone 23: Compiling (real ECALL support, baseline unbounded context)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_ecall.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_ecall.sv"
echo "==> Simulating (Milestone 23 ECALL baseline)"
vvp "$SIM/sim_m23_ecall.vvp" +elf_hex="$SIM/veda_smoke_m23_ecall.hex"

echo "==> Milestone 23: Compiling (real ECALL support, from inside a live OCInvoke compartment)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_ecall_compartment.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_ecall_compartment.sv"
echo "==> Simulating (Milestone 23 ECALL compartment)"
vvp "$SIM/sim_m23_ecall_compartment.vvp" +elf_hex="$SIM/veda_smoke_m23_ecall_compartment.hex"

echo "==> Milestone 23: Compiling (RTL mirror of Sail Milestone C: real cooperative scheduler)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_scheduler.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_scheduler.sv"
echo "==> Simulating (Milestone 23 cooperative scheduler)"
vvp "$SIM/sim_m23_scheduler.vvp" +elf_hex="$SIM/veda_smoke_m23_scheduler.hex"

echo "==> SSC: Compiling (Stack-Spill Capability round-trip, third SCR independent of ODA/TSC)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_roundtrip.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_roundtrip.sv"
echo "==> Simulating (SSC roundtrip)"
vvp "$SIM/sim_ssc_roundtrip.vvp" +elf_hex="$SIM/veda_smoke_ssc_roundtrip.hex"

echo "==> SSC: Compiling (OCInvoke clears SSC on every compartment-boundary crossing)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_ocinvoke_clear.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_ocinvoke_clear.sv"
echo "==> Simulating (SSC OCInvoke clear)"
vvp "$SIM/sim_ssc_ocinvoke_clear.vvp" +elf_hex="$SIM/veda_smoke_ssc_ocinvoke_clear.hex"

echo "==> SSC: Compiling (real spill/reload sequence inside a compartment)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_spill_reload.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_spill_reload.sv"
echo "==> Simulating (SSC spill/reload)"
vvp "$SIM/sim_ssc_spill_reload.vvp" +elf_hex="$SIM/veda_smoke_ssc_spill_reload.hex"

echo "==> SSC: Compiling (out-of-bounds access, real Bounds Violation)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_oob.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_oob.sv"
echo "==> Simulating (SSC OOB)"
vvp "$SIM/sim_ssc_oob.vvp" +elf_hex="$SIM/veda_smoke_ssc_oob.hex"

echo "==> SSC: Compiling (cross-thread isolation via the real scheduler)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_cross_thread.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_cross_thread.sv"
echo "==> Simulating (SSC cross-thread isolation)"
vvp "$SIM/sim_ssc_cross_thread.vvp" +elf_hex="$SIM/veda_smoke_ssc_cross_thread.hex"

echo "==> Milestone 24: Compiling (real DRAM-latency stall FSM, no-op-at-E=0 regression check)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24lat.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_latency.sv"
echo "==> Simulating (Milestone 24 latency)"
vvp "$SIM/sim_m24lat.vvp" +elf_hex="$SIM/veda_smoke_m24_latency.hex"

echo "==> Milestone 24 Stage 2: Compiling (TCM ODT tier, no-op-at-E=0 regression check)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24odttcm.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_odt_tcm.sv"
echo "==> Simulating (Milestone 24 Stage 2 ODT TCM tier)"
vvp "$SIM/sim_m24odttcm.vvp" +elf_hex="$SIM/veda_smoke_m24_odt_tcm.hex"

echo "==> Milestone 24 Stage 3: Compiling (TCM capability-spill scratch, OCL.C/OCS.C address-range mux)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24ocsctcm.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_ocsc_tcm.sv"
echo "==> Simulating (Milestone 24 Stage 3 OCL.C/OCS.C TCM scratch)"
vvp "$SIM/sim_m24ocsctcm.vvp" +elf_hex="$SIM/veda_smoke_m24_ocsc_tcm.hex"

echo "==> Regression: base RV64I 81-instruction smoke test (unmodified)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_base.vvp" "$SIM/veda_core.sv" "$SIM/tb_smoke.sv"
vvp "$SIM/sim_base.vvp"
