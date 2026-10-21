#!/usr/bin/env bash
# Acceptance run: everything that has to be green before the project is called
# finished, in one report.
#
#   1. full test suite (tests/run_tests.gd)          - logic and rules
#   2. boot smoke   (tools/run_boot_smoke.sh)        - the app starts cleanly
#   3. screen smoke (tools/run_screen_smoke.sh)      - every screen opens cleanly
#   4. net smoke    (tools/run_net_smoke.sh)         - two-process online match
#                                                     (Durak, hidden information)
#
# The suite's exit code counts failed checks; this script additionally fails the
# suite phase when the log contains a raw SCRIPT ERROR, which check counts
# cannot see.
#
# Usage: tools/run_acceptance.sh
# Exit code: 0 only when all four phases pass.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
LOG_DIR="${TMPDIR:-/tmp}/gh-acceptance"
mkdir -p "$LOG_DIR"

SUITE_OK=0
BOOT_OK=0
SCREEN_OK=0
NET_OK=0

echo "════════════════════════════════════════════════════════════"
echo " acceptance run  ·  logs in $LOG_DIR"
echo "════════════════════════════════════════════════════════════"

echo "── 1/4 test suite"
"$GODOT_BIN" --headless --path "$ROOT" --script tests/run_tests.gd >"$LOG_DIR/suite.log" 2>&1
SUITE_CODE=$?
SUITE_OK=$SUITE_CODE
grep -E "^ (PASS|FAIL)" "$LOG_DIR/suite.log" | tail -1 || true
if grep -q "SCRIPT ERROR" "$LOG_DIR/suite.log"; then
	echo "   suite log contains SCRIPT ERROR lines:"
	grep -n "SCRIPT ERROR" "$LOG_DIR/suite.log" | head -10
	SUITE_OK=1
fi

echo "── 2/4 boot smoke"
if tools/run_boot_smoke.sh 300 >"$LOG_DIR/boot.log" 2>&1; then
	BOOT_OK=0
else
	BOOT_OK=1
fi
grep -E "^(PASS|FAIL)|SMOKE: (PASS|FAIL)" "$LOG_DIR/boot.log" | tail -1 || true

echo "── 3/4 screen smoke"
if tools/run_screen_smoke.sh >"$LOG_DIR/screen.log" 2>&1; then
	SCREEN_OK=0
else
	SCREEN_OK=1
fi
grep -E "^(PASS|FAIL)|SMOKE: (PASS|FAIL)" "$LOG_DIR/screen.log" | tail -1 || true

echo "── 4/4 net smoke"
if tools/run_net_smoke.sh 47120 durak 2 1 >"$LOG_DIR/net.log" 2>&1; then
	NET_OK=0
else
	NET_OK=1
fi
grep -E "^(PASS|FAIL)|SMOKE: (PASS|FAIL)" "$LOG_DIR/net.log" | tail -1 || true

echo "════════════════════════════════════════════════════════════"
printf " suite   %s\n" "$([ "$SUITE_OK" -eq 0 ] && echo PASS || echo "FAIL ($SUITE_CODE failed checks; see $LOG_DIR/suite.log)")"
printf " boot    %s\n" "$([ "$BOOT_OK" -eq 0 ] && echo PASS || echo "FAIL")"
printf " screen  %s\n" "$([ "$SCREEN_OK" -eq 0 ] && echo PASS || echo "FAIL")"
printf " net     %s\n" "$([ "$NET_OK" -eq 0 ] && echo PASS || echo "FAIL")"
if [ "$SUITE_OK" -eq 0 ] && [ "$BOOT_OK" -eq 0 ] && [ "$SCREEN_OK" -eq 0 ] && [ "$NET_OK" -eq 0 ]; then
	echo " ACCEPTANCE PASS"
	echo "════════════════════════════════════════════════════════════"
	exit 0
fi
echo " ACCEPTANCE FAIL"
echo "════════════════════════════════════════════════════════════"
exit 1
