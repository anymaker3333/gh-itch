#!/usr/bin/env bash
# Two-process multiplayer smoke test: host + client over the *real* transport
# stack (ENet loopback), exercising handshake -> seat assignment -> start match
# -> action forwarding -> resign -> match end.
#
# This runs the local test transport, NOT Steam. Steam networking cannot be
# automated without two Steam accounts; see docs/STEAM_INTEGRATION.md.
#
# Usage: tools/run_net_smoke.sh [port] [game_id] [players] [expect_private]
#   port            default 47120
#   game_id         default chess (any catalog game with enough seats)
#   players         default 2 (host + one client; the client is always the last
#                   seat and resigns)
#   expect_private  1 when the game has hidden information: the client then
#                   asserts that the replicated snapshot carries a non-empty
#                   private slice
# Logs: $TMPDIR/gh-net-smoke/<game>/host.log and client.log
# Exit code: 0 only when BOTH roles pass.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
PORT="${1:-47120}"
GAME="${2:-chess}"
PLAYERS="${3:-2}"
EXPECT_PRIVATE="${4:-0}"
LOGDIR="${TMPDIR:-/tmp}/gh-net-smoke/"
RUNDIR="${LOGDIR%/}/$GAME"
mkdir -p "$RUNDIR"

HOST_LOG="$RUNDIR/host.log"
CLIENT_LOG="$RUNDIR/client.log"

EXTRA_ARGS=()
if [ "$EXPECT_PRIVATE" != "0" ]; then
	EXTRA_ARGS+=(--expect-private)
fi

echo "════════════════════════════════════════════════════════════"
echo " net smoke  ·  game $GAME  ·  $PLAYERS seat(s)  ·  port $PORT"
echo " logs: $RUNDIR"
echo "════════════════════════════════════════════════════════════"

"$GODOT_BIN" --headless --path "$ROOT" --script tools/net_smoke.gd -- \
	--role host --port "$PORT" --game "$GAME" --players "$PLAYERS" \
	${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} >"$HOST_LOG" 2>&1 &
HOST_PID=$!

# Give the server a moment to bind before clients dial in.
sleep 2

CLIENT_PIDS=()
CLIENT_CODES=()
CLIENT_COUNT=$((PLAYERS - 1))
if [ "$CLIENT_COUNT" -lt 1 ]; then
	CLIENT_COUNT=1
fi
for i in $(seq 1 "$CLIENT_COUNT"); do
	CLIENT_LOG_I="$RUNDIR/client_${i}.log"
	"$GODOT_BIN" --headless --path "$ROOT" --script tools/net_smoke.gd -- \
		--role client --port "$PORT" --game "$GAME" --players "$PLAYERS" \
		${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} >"$CLIENT_LOG_I" 2>&1 &
	CLIENT_PIDS+=($!)
done

wait "$HOST_PID"
HOST_CODE=$?
for pid in "${CLIENT_PIDS[@]}"; do
	wait "$pid"
	CLIENT_CODES+=($?)
done
# Keep CLIENT_LOG pointing at the first client for the summary below.
CLIENT_LOG="$RUNDIR/client_1.log"
CLIENT_CODE=${CLIENT_CODES[0]:-1}

echo
echo "── host (exit $HOST_CODE) ───────────────────────────────────"
sed -n '/net smoke/,$p' "$HOST_LOG" | grep -E "✓|✗|PASS|FAIL|•|summary|transport=|timed out|ERROR|SCRIPT ERROR" || true
echo
echo "── client (exit $CLIENT_CODE) ───────────────────────────────"
sed -n '/net smoke/,$p' "$CLIENT_LOG" | grep -E "✓|✗|PASS|FAIL|•|summary|transport=|timed out|ERROR|SCRIPT ERROR" || true
echo
echo "full logs: $HOST_LOG  $CLIENT_LOG"

ALL_CLIENTS_OK=0
for code in "${CLIENT_CODES[@]}"; do
	if [ "$code" -ne 0 ]; then
		ALL_CLIENTS_OK=1
	fi
done
if [ "$HOST_CODE" -eq 0 ] && [ "$ALL_CLIENTS_OK" -eq 0 ]; then
	echo "════════════════════════════════════════════════════════════"
	echo " NET SMOKE: PASS"
	echo "════════════════════════════════════════════════════════════"
	exit 0
fi
echo "════════════════════════════════════════════════════════════"
echo " NET SMOKE: FAIL (host=$HOST_CODE client=$CLIENT_CODE)"
echo "════════════════════════════════════════════════════════════"
exit 1
