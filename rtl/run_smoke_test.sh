#!/usr/bin/env bash
# Transpile rv64i_core.tlv -> SystemVerilog (SandPiper cloud service) and
# simulate it with Icarus Verilog, printing a cycle-by-cycle trace and a
# PASS/FAIL verdict based on the design's own *passed assertion.
#
# Adapted from arm_single_cycle/run_test.sh's proven structure, including
# stripping the \viz_js block before transpiling (Makerchip-GUI-only; its
# JS syntax breaks SandPiper's M4 preprocessor when run headless).
#
# Self-contained: the only required input is rv64i_core.tlv next to this
# script. Everything under sim/ is regenerated on every run and safe to delete.
set -euo pipefail

cd "$(dirname "$0")"
export PATH="$PATH:$HOME/.local/bin"

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

# --- Regenerate support files every run (nothing here is user-editable) ---

cat > "$SIM/sp_m4out.vh" <<'VHEOF'
// Minimal local stub replacing Makerchip's simulation-harness include.
// Only provides what the SandPiper-generated top module references before
// its own logic is defined (a randomizer used by Makerchip for uninitialized
// signal fuzzing, unused by this design).
module pseudo_rand #(parameter WIDTH = 1) (input clk, input reset, output logic [WIDTH-1:0] out);
  assign out = '0;
endmodule
VHEOF

cat > "$SIM/sandpiper_gen.vh" <<'VHEOF'
// Minimal local stub replacing Makerchip's simulation-harness include.
// No additional macros are required for this design.
VHEOF

cat > "$SIM/tb_smoke.sv" <<'TBEOF'
`timescale 1ns/1ps
module tb;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    repeat (130) begin
      @(posedge clk);
      #1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h passed=%0b | x1=%0d x2=%0d x3=%0d x4=%0d x5=%0d x6=%0d x7=%0d x8=%0d x9=%0d x10=%0d x11=%0d x12=%0d x13=%0d x14=%0d x15=%0d x16=%0d x17=%0d x18=%0d x19=%0d x20=%0d x21=%0d x22=%0d x23=%0d x24=%0d x25=%0d x26=%0d x27=%0d x28=%0d x29=%0d x30=%0d x31=%0d",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0, passed,
                $signed(dut.CPU_Xreg_val_a0[1]),  $signed(dut.CPU_Xreg_val_a0[2]),  $signed(dut.CPU_Xreg_val_a0[3]),
                $signed(dut.CPU_Xreg_val_a0[4]),  $signed(dut.CPU_Xreg_val_a0[5]),  $signed(dut.CPU_Xreg_val_a0[6]),
                $signed(dut.CPU_Xreg_val_a0[7]),  $signed(dut.CPU_Xreg_val_a0[8]),  $signed(dut.CPU_Xreg_val_a0[9]),
                $signed(dut.CPU_Xreg_val_a0[10]), $signed(dut.CPU_Xreg_val_a0[11]), $signed(dut.CPU_Xreg_val_a0[12]),
                $signed(dut.CPU_Xreg_val_a0[13]), $signed(dut.CPU_Xreg_val_a0[14]), $signed(dut.CPU_Xreg_val_a0[15]),
                $signed(dut.CPU_Xreg_val_a0[16]), $signed(dut.CPU_Xreg_val_a0[17]), $signed(dut.CPU_Xreg_val_a0[18]),
                $signed(dut.CPU_Xreg_val_a0[19]), $signed(dut.CPU_Xreg_val_a0[20]), $signed(dut.CPU_Xreg_val_a0[21]),
                $signed(dut.CPU_Xreg_val_a0[22]), $signed(dut.CPU_Xreg_val_a0[23]), $signed(dut.CPU_Xreg_val_a0[24]),
                $signed(dut.CPU_Xreg_val_a0[25]), $signed(dut.CPU_Xreg_val_a0[26]), $signed(dut.CPU_Xreg_val_a0[27]),
                $signed(dut.CPU_Xreg_val_a0[28]), $signed(dut.CPU_Xreg_val_a0[29]), $signed(dut.CPU_Xreg_val_a0[30]),
                $signed(dut.CPU_Xreg_val_a0[31]));
      cyc_cnt = cyc_cnt + 1;
    end

    if (passed) $display("\n*** TEST PASSED ***");
    else        $display("\n*** TEST FAILED ***");

    $finish;
  end
endmodule
TBEOF

echo "==> Transpiling TL-Verilog -> SystemVerilog (SandPiper cloud service)"
set +e
sandpiper-saas -i "$STRIPPED" -o rv64i_core.sv --outdir "$SIM" -p m4out
sp_status=$?
set -e
# SandPiper exits 1 merely for warnings (e.g. unused-signal notices); only
# treat >1 as a real compile failure.
if [ "$sp_status" -gt 1 ]; then
  echo "SandPiper transpile failed (exit $sp_status)" >&2
  exit "$sp_status"
fi

echo "==> Compiling with Icarus Verilog"
iverilog -g2012 -I "$SIM" -o "$SIM/sim.vvp" "$SIM/rv64i_core.sv" "$SIM/tb_smoke.sv"

echo "==> Simulating"
vvp "$SIM/sim.vvp"
