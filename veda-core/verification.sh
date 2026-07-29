#!/usr/bin/env bash
# Real, live verification run for a LinkedIn screenshot -- prints a
# clean, condensed summary of the three real suites this project's own
# claims are grounded in. Run this from a fresh terminal in
# /home/prabhu/makerchip/rva23-core and screenshot the final output.
set -uo pipefail
ROOT=/home/prabhu/makerchip/rva23-core
cd "$ROOT"

echo "=================================================="
echo "  Veda-Core — Real Verification Run"
echo "  $(date '+%Y-%m-%d %H:%M %Z')"
echo "=================================================="
echo

echo "--> Sail formal self-check suite"
SAIL_OUT=$(veda-core/sail_tests/run_veda_selfcheck_tests.sh 2>&1)
echo "$SAIL_OUT" | tail -3
echo

echo "--> RTL milestone regression suite"
RTL_OUT=$(veda-core/rtl/run_veda_smoke_test.sh 2>&1)
RTL_PASS=$(echo "$RTL_OUT" | grep -c "TEST PASSED")
RTL_FAIL=$(echo "$RTL_OUT" | grep -c "TEST FAILED")
echo "$((RTL_PASS + RTL_FAIL)) programs run — ${RTL_PASS} passed, ${RTL_FAIL} failed"
echo

echo "--> RISC-V International ACT4 RV64I conformance suite"
ACT4_OUT=$(veda-core/rtl/run_act4_tests.sh 2>&1)
echo "$ACT4_OUT" | tail -1
echo

echo "=================================================="
echo "  Summary"
echo "=================================================="
echo "  Sail self-check   : $(echo "$SAIL_OUT" | grep -oE '[0-9]+/[0-9]+ passed')"
echo "  RTL milestones    : ${RTL_PASS}/$((RTL_PASS + RTL_FAIL)) passed"
echo "  ACT4 conformance  : $(echo "$ACT4_OUT" | tail -1 | grep -oE '[0-9]+/[0-9]+ passed')"
echo "=================================================="
