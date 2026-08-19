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

echo "==> RTL M21-restore mirror: Compiling (automatic PCC restore-on-mret, 3 real properties)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_pcc_restore.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_pcc_restore_on_mret.sv"
echo "==> Simulating (RTL M21-restore mirror)"
vvp "$SIM/sim_pcc_restore.vvp" +elf_hex="$SIM/veda_smoke_pcc_restore_on_mret.hex"

echo "==> RTL M27-mtvec-gate mirror: Compiling (mtvec self-escape from a live compartment must hard-trap)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mtvec_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mtvec_escape_neg.sv"
echo "==> Simulating (RTL M27-mtvec-gate mirror)"
vvp "$SIM/sim_mtvec_neg.vvp" +elf_hex="$SIM/veda_smoke_mtvec_escape_neg.hex"

echo "==> RTL Part C (Task #297 mirror): Compiling (real KERNEL ecall dispatcher, sys_write/sys_exit)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_s0k.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_syscall0_kernel.sv"
echo "==> Simulating (RTL Part C: syscall0 kernel)"
vvp "$SIM/sim_s0k.vvp" +elf_hex="$SIM/veda_smoke_syscall0_kernel.hex"

echo "==> RTL Part D (Task #299 mirror): Compiling (forged, never-populated Object_ID negative test)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_s0kneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_syscall0_kernel_forged_neg.sv"
echo "==> Simulating (RTL Part D: syscall0 kernel forged-Object_ID negative)"
vvp "$SIM/sim_s0kneg.vvp" +elf_hex="$SIM/veda_smoke_syscall0_kernel_forged_neg.hex"

echo "==> R21 fix: Compiling (DRAM-stall must not swallow a real trap redirect)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r21.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r21_dram_stall_trap_neg.sv"
echo "==> Simulating (R21 fix, shipped DRAM_EXTRA_CYCLES=0 default)"
vvp "$SIM/sim_r21.vvp" +elf_hex="$SIM/veda_smoke_r21_dram_stall_trap_neg.hex"

echo "==> WFI decode: Compiling (must be an explicit, documented NOP -- RISC-V spec p.715)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_wfi.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_wfi_nop.sv"
echo "==> Simulating (WFI NOP decode)"
vvp "$SIM/sim_wfi.vvp" +elf_hex="$SIM/veda_smoke_wfi_nop.hex"

echo "==> Length/Offset widening: Compiling (positive, >64KB object via veda.odt.populate.fast+veda_attr, round trip at the real widened edge)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_widened_bounds.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_widened_bounds.sv"
echo "==> Simulating (Length/Offset widening: widened bounds positive)"
vvp "$SIM/sim_widened_bounds.vvp" +elf_hex="$SIM/veda_smoke_widened_bounds.hex"

echo "==> Length/Offset widening: Compiling (negative, 4 bytes past the real widened Length must hard-trap)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_widened_bounds_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_widened_bounds_neg.sv"
echo "==> Simulating (Length/Offset widening: widened bounds negative)"
vvp "$SIM/sim_widened_bounds_neg.vvp" +elf_hex="$SIM/veda_smoke_widened_bounds_neg.hex"

echo "==> Length/Offset widening: Compiling (OCL.C/OCS.C new 32-byte alignment gate, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_oclc_align_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_oclc_alignment_neg.sv"
echo "==> Simulating (Length/Offset widening: OCL.C/OCS.C alignment negative)"
vvp "$SIM/sim_oclc_align_neg.vvp" +elf_hex="$SIM/veda_smoke_oclc_alignment_neg.hex"

echo "==> Length/Offset widening: Compiling (2-granule tag-store adjacency, both directions)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_oclc_granule_adj.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_oclc_granule_adjacency.sv"
echo "==> Simulating (Length/Offset widening: OCL.C/OCS.C granule adjacency)"
vvp "$SIM/sim_oclc_granule_adj.vvp" +elf_hex="$SIM/veda_smoke_oclc_granule_adjacency.hex"

echo "==> Length/Offset widening: Compiling (CSeal otype-truncation precondition, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_cseal_hibits_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cseal_offset_hibits_neg.sv"
echo "==> Simulating (Length/Offset widening: CSeal offset-hibits negative)"
vvp "$SIM/sim_cseal_hibits_neg.vvp" +elf_hex="$SIM/veda_smoke_cseal_offset_hibits_neg.hex"

echo "==> Length/Offset widening: Compiling (CSetBounds full-width window check, negative + widened-success positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_csetbounds_widthcheck_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_csetbounds_widthcheck_neg.sv"
echo "==> Simulating (Length/Offset widening: CSetBounds full-width window check negative + widened-success positive)"
vvp "$SIM/sim_csetbounds_widthcheck_neg.vvp" +elf_hex="$SIM/veda_smoke_csetbounds_widthcheck_neg.hex"

echo "==> Adversarial-review Finding #1: Compiling (widened capability round trip through OCS.C/OCL.C's 136-bit pack)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_oclc_widened_roundtrip.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_oclc_widened_roundtrip.sv"
echo "==> Simulating (Finding #1: OCL.C/OCS.C widened round trip)"
vvp "$SIM/sim_oclc_widened_roundtrip.vvp" +elf_hex="$SIM/veda_smoke_oclc_widened_roundtrip.hex"

echo "==> Adversarial-review Finding #2: Compiling (CUnseal's own widened-otype compare site, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_cunseal_hibits_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cunseal_offset_hibits_neg.sv"
echo "==> Simulating (Finding #2: CUnseal offset-hibits negative)"
vvp "$SIM/sim_cunseal_hibits_neg.vvp" +elf_hex="$SIM/veda_smoke_cunseal_offset_hibits_neg.hex"

echo "==> TRAP_QUARANTINE_DESIGN.md (task #351): Compiling (repeated-trap DoS containment, negative -- must hard-refuse after threshold)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_tq_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_trap_quarantine_neg.sv"
echo "==> Simulating (trap quarantine: repeated-trap DoS negative)"
vvp "$SIM/sim_tq_neg.vvp" +elf_hex="$SIM/veda_smoke_trap_quarantine_neg.hex"

echo "==> TRAP_QUARANTINE_DESIGN.md (task #351): Compiling (decay earns forgiveness, positive -- must NOT be quarantined)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_tq_pos.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_trap_quarantine_decay_pos.sv"
echo "==> Simulating (trap quarantine: decay positive)"
vvp "$SIM/sim_tq_pos.vvp" +elf_hex="$SIM/veda_smoke_trap_quarantine_decay_pos.hex"

echo "==> TRAP_QUARANTINE_RESULTS.md (adversarial RTL-mirror review): Compiling (eviction-starvation-bypass fix, positive -- a saturated table must never evict a quarantined victim)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_tq_starvation_pos.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_trap_quarantine_starvation_pos.sv"
echo "==> Simulating (trap quarantine: eviction-starvation-bypass positive)"
vvp "$SIM/sim_tq_starvation_pos.vvp" +elf_hex="$SIM/veda_smoke_trap_quarantine_starvation_pos.hex"

echo "==> TRAP_QUARANTINE_RESULTS.md (adversarial RTL-mirror review): Compiling (veda_trap_quarantine_clear CSR 0x7C6 round trip, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_tq_csr_clear_pos.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_trap_quarantine_csr_clear_pos.sv"
echo "==> Simulating (trap quarantine: CSR clear positive)"
vvp "$SIM/sim_tq_csr_clear_pos.vvp" +elf_hex="$SIM/veda_smoke_trap_quarantine_csr_clear_pos.hex"

echo "==> LOCAL_FAULT_RECOVERY_DESIGN.md: Compiling (VEDA_LOCAL_HANDLER, positive -- redirect to registered handler, PCC preserved, clean OCRETURN exit)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_lh_pos.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_local_handler_pos.sv"
echo "==> Simulating (local handler: positive)"
vvp "$SIM/sim_lh_pos.vvp" +elf_hex="$SIM/veda_smoke_local_handler_pos.hex"

echo "==> LOCAL_FAULT_RECOVERY_DESIGN.md: Compiling (VEDA_LOCAL_HANDLER, negative -- no handler registered, unchanged global fallback)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_lh_neg_no_handler.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_local_handler_neg_no_handler.sv"
echo "==> Simulating (local handler: no-handler negative)"
vvp "$SIM/sim_lh_neg_no_handler.vvp" +elf_hex="$SIM/veda_smoke_local_handler_neg_no_handler.hex"

echo "==> LOCAL_FAULT_RECOVERY_DESIGN.md: Compiling (VEDA_LOCAL_HANDLER, negative -- quarantine-composition, self-faulting handler must be bounded)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_lh_neg_quarantine.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_local_handler_neg_quarantine.sv"
echo "==> Simulating (local handler: quarantine-composition negative)"
vvp "$SIM/sim_lh_neg_quarantine.vvp" +elf_hex="$SIM/veda_smoke_local_handler_neg_quarantine.hex"

echo "==> LOCAL_FAULT_RECOVERY_DESIGN.md: Compiling (VEDA_LOCAL_HANDLER, negative -- confused-deputy bounds guard)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_lh_neg_bounds_guard.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_local_handler_neg_bounds_guard.sv"
echo "==> Simulating (local handler: confused-deputy bounds-guard negative)"
vvp "$SIM/sim_lh_neg_bounds_guard.vvp" +elf_hex="$SIM/veda_smoke_local_handler_neg_bounds_guard.hex"

echo "==> LOCAL_FAULT_RECOVERY_DESIGN.md: Compiling (VEDA_LOCAL_HANDLER, negative -- cross-compartment handler-table collision via shared UNSEALED_OTYPE, real bug found by adversarial review)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_lh_neg_unsealed_otype.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_local_handler_neg_unsealed_otype.sv"
echo "==> Simulating (local handler: shared-UNSEALED_OTYPE collision negative)"
vvp "$SIM/sim_lh_neg_unsealed_otype.vvp" +elf_hex="$SIM/veda_smoke_local_handler_neg_unsealed_otype.hex"

echo "==> Regression: base RV64I 81-instruction smoke test (unmodified)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_base.vvp" "$SIM/veda_core.sv" "$SIM/tb_smoke.sv"
vvp "$SIM/sim_base.vvp"
