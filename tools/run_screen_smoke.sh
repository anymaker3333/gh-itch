#!/usr/bin/env bash
# Screen smoke test: boot the real application headless and drive the router
# through every screen route (library, details, setup, settings, diagnostics,
# online, lobby, game, ...). Screens are built lazily, so this is the guard
# that catches a screen that only blows up when it is actually opened.
#
# Fails when:
#   * any route produced no visible screen in the tree, or
#   * the log contains a SCRIPT ERROR.
#
# Steam is not required (same policy as the boot smoke: the "Steam is probably
# not running" line is a normal error log, not a script error).
#
# Usage: tools/run_screen_smoke.sh
# Exit code: 0 only when every available screen came up cleanly.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
LOG="${TMPDIR:-/tmp}/gh-screen-smoke.log"

echo "════════════════════════════════════════════════════════════"
echo " screen smoke  ·  every route  ·  log $LOG"
echo "════════════════════════════════════════════════════════════"

cd "$ROOT"
"$GODOT_BIN" --headless --path "$ROOT" --script tools/screen_smoke.gd >"$LOG" 2>&1
CODE=$?

if grep -q "SCRIPT ERROR" "$LOG"; then
	echo "FAIL  script errors while visiting screens:"
	grep -n "SCRIPT ERROR" "$LOG" | head -20
	exit 1
fi

if [ "$CODE" -ne 0 ]; then
	echo "FAIL  screen smoke exited with code $CODE"
	grep -E "^(OK|SKIP|FAIL) |SCREEN SMOKE" "$LOG" || tail -25 "$LOG"
	exit 1
fi

grep -E "^(SKIP) " "$LOG" || true
echo "PASS  every available screen came up without script errors"
