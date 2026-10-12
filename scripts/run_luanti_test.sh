#!/usr/bin/env bash
# Runs one headless integration test mod inside the assembled Minemon game.
# A fresh world is created, the test mod is copied into its worldmods/ and trusted (secure.trusted_mods),
# and the server runs until the mod writes <world>/test_result.txt (PASS n | FAIL <reason>) or the timeout expires.
#
# Usage: scripts/run_luanti_test.sh <test_mod_dir> [timeout_seconds]
#   test_mod_dir     directory with mod.conf and init.lua (e.g. tests/integration/smoke)
#   timeout_seconds  wall-clock limit for the run (default 120)
# Env overrides (optional): LUANTI_BIN, MINEMON_GAMES_DIR (default .games), GAMEID (default minemon).
# Exit: 0 on PASS; 1 on FAIL, a crash, a timeout or a missing binary.
set -u

cd "$(dirname "$0")/.."
ROOT=$(pwd)

TEST_DIR=${1:-}
TIMEOUT=${2:-120}
BIN=${LUANTI_BIN:-$ROOT/.tools/luanti/bin/luantiserver}
GAMES_DIR=${MINEMON_GAMES_DIR:-$ROOT/.games}
GAMEID=${GAMEID:-minemon}
RUNS_DIR=$ROOT/.tools/runs

if [ -z "$TEST_DIR" ] || [ ! -f "$TEST_DIR/mod.conf" ] || [ ! -f "$TEST_DIR/init.lua" ]; then
	echo "usage: scripts/run_luanti_test.sh <test_mod_dir> [timeout_seconds]"
	echo "FAIL: '$TEST_DIR' is not a mod directory (needs mod.conf and init.lua)"
	exit 1
fi
[ -x "$BIN" ] || { echo "FAIL: server binary missing: $BIN (run scripts/setup.sh)"; exit 1; }
[ -f "$GAMES_DIR/$GAMEID/game.conf" ] || { echo "FAIL: game $GAMEID not found in $GAMES_DIR (run scripts/assemble_game.sh)"; exit 1; }

# The mod's name comes from its mod.conf; Luanti needs the folder to match it.
MOD_NAME=$(sed -n 's/^name[[:space:]]*=[[:space:]]*//p' "$TEST_DIR/mod.conf" | head -n 1 | tr -d '[:space:]')
[ -n "$MOD_NAME" ] || { echo "FAIL: no name in $TEST_DIR/mod.conf"; exit 1; }

mkdir -p "$RUNS_DIR"
RUN_DIR=$(mktemp -d "$RUNS_DIR/run.XXXXXX")
WORLD="$RUN_DIR/world"
LOG="$RUN_DIR/server.log"
RESULT="$WORLD/test_result.txt"

# Fresh world for the assembled game, with the test mod enabled.
mkdir -p "$WORLD/worldmods"
cp -r "$TEST_DIR" "$WORLD/worldmods/$MOD_NAME"
printf '%s\n' "gameid = $GAMEID" "backend = sqlite3" "player_backend = sqlite3" "auth_backend = sqlite3" \
	"load_mod_$MOD_NAME = true" > "$WORLD/world.mt"

# Container has no IPv6: bind IPv4 only. Test mods that read files need to be trusted.
printf '%s\n' "ipv6_server = false" "bind_address = 127.0.0.1" "enable_mod_channels = false" \
	"secure.trusted_mods = $MOD_NAME" > "$RUN_DIR/luanti.conf"

# A random free port in 30000-39999, so runs in parallel (other worktrees) do not collide. Free means a UDP bind on
# 127.0.0.1 succeeds (Luanti serves UDP only; the container has no IPv6).
PORT=$(python3 -I -c '
import random, socket, sys
rng = random.SystemRandom()
for _ in range(400):
    port = rng.randint(30000, 39999)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind(("127.0.0.1", port))
    except OSError:
        continue
    finally:
        sock.close()
    print(port)
    sys.exit(0)
sys.exit(1)
' 2>/dev/null) || PORT=""
[ -n "$PORT" ] || { echo "FAIL: no free port"; exit 1; }

START=$(date +%s.%N)
LUANTI_GAME_PATH="$GAMES_DIR" "$BIN" --config "$RUN_DIR/luanti.conf" --gameid "$GAMEID" \
	--world "$WORLD" --port "$PORT" --logfile "$RUN_DIR/debug.txt" >"$LOG" 2>&1 &
PID=$!

PEAK_RSS_KB=0
STATUS="timeout"
while :; do
	if [ -f "$RESULT" ]; then STATUS="result"; break; fi
	if ! kill -0 "$PID" 2>/dev/null; then STATUS="crashed"; break; fi
	RSS=$(awk '/^VmRSS/{print $2}' "/proc/$PID/status" 2>/dev/null || true)
	if [ -n "${RSS:-}" ] && [ "$RSS" -gt "$PEAK_RSS_KB" ]; then PEAK_RSS_KB=$RSS; fi
	NOW=$(date +%s.%N)
	if awk -v n="$NOW" -v s="$START" -v t="$TIMEOUT" 'BEGIN { exit !(n - s > t) }'; then break; fi
	sleep 0.2
done
RESULT_AT=$(date +%s.%N)

# Give the server time to exit after request_shutdown, then stop it.
for _ in $(seq 1 50); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
if kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null || true; sleep 1; kill -9 "$PID" 2>/dev/null || true; fi
wait "$PID" 2>/dev/null
SERVER_RC=$?
END=$(date +%s.%N)

printf 'timings: result_after_s=%s total_wall_s=%s peak_rss_mb=%s server_exit=%s\n' \
	"$(awk -v a="$RESULT_AT" -v s="$START" 'BEGIN { printf "%.2f", a - s }')" \
	"$(awk -v a="$END" -v s="$START" 'BEGIN { printf "%.2f", a - s }')" \
	"$(awk -v k="$PEAK_RSS_KB" 'BEGIN { printf "%.1f", k / 1024 }')" "$SERVER_RC"

case "$STATUS" in
	result)
		echo "result: $(cat "$RESULT")"
		if grep -q '^PASS' "$RESULT"; then
			echo "RESULT: PASS $MOD_NAME (run dir $RUN_DIR)"
			exit 0
		fi
		echo "--- server log (tail) ---"; tail -n 15 "$LOG"
		echo "RESULT: FAIL $MOD_NAME (run dir $RUN_DIR)"
		exit 1 ;;
	crashed)
		echo "--- server log (tail) ---"; tail -n 15 "$LOG"
		echo "RESULT: FAIL $MOD_NAME - server exited before writing a result (rc=$SERVER_RC)"
		exit 1 ;;
	timeout)
		echo "--- server log (tail) ---"; tail -n 15 "$LOG"
		echo "RESULT: FAIL $MOD_NAME - timed out after ${TIMEOUT}s"
		exit 1 ;;
esac
