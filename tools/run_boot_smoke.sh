#!/usr/bin/env bash
# Boot smoke test: start the real application headless for a fixed number of
# frames and fail if any script error is printed while the shell builds its
# first screen.
#
# This catches the class of bug that the logic suites cannot see: a widget or
# screen that only blows up when the application is actually launched (for
# example a screen that is never loaded by a unit test).
#
# Steam is not required: the "Steam is probably not running" message is logged
# as a normal error line, not a script error, so it does not fail the run.
#
# Usage: tools/run_boot_smoke.sh [frames]   (default 300 frames ~ 5 seconds)
# Exit code: 0 only when the app runs the frames without a single script error.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
FRAMES="${1:-300}"
LOG="${TMPDIR:-/tmp}/gh-boot-smoke.log"

echo "════════════════════════════════════════════════════════════"
echo " boot smoke  ·  $FRAMES frames  ·  log $LOG"
echo "════════════════════════════════════════════════════════════"

# Automated headless runs skip Steamworks (see steam_service.gd): the
# Steamworks teardown can abort the engine process during scripted shutdown.
export GAMEHUB_DISABLE_STEAM=1

"$GODOT_BIN" --headless --path "$ROOT" --quit-after "$FRAMES" >"$LOG" 2>&1
CODE=$?

if grep -q "SCRIPT ERROR" "$LOG"; then
	echo "FAIL  script errors while booting:"
	grep -n "SCRIPT ERROR" "$LOG" | head -20
	exit 1
fi

if [ "$CODE" -ne 0 ]; then
	echo "FAIL  godot exited with code $CODE"
	tail -20 "$LOG"
	exit 1
fi

echo "PASS  $FRAMES frames, no script errors"
