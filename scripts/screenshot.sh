#!/usr/bin/env bash
# Headless client screenshots of the Minemon world (T-19), for visual review in the container.
# A fresh world (gameid minemon, fixed seed 1337) is created, the helper mod tests/screenshot/minemon_shots is
# added to its worldmods/ (never to mods/minemon, so it never ships), and the real Luanti client runs under Xvfb
# with Mesa software GL. For each shot the helper teleports the player and writes shot_<name>.ready; this script
# captures the X display with ImageMagick and deletes the marker so the next shot can start.
#
# Usage: scripts/screenshot.sh <shots.json> <out_dir>
#   shots.json  [{name, pos:[x,y,z], yaw_deg, pitch_deg, time_of_day:0..1, wait_s}] (see tests/screenshot/default_shots.json)
#               name: [a-z0-9_]+, unique. yaw_deg 0 looks along +Z. pitch_deg positive looks UP. wait_s: whole seconds.
#   out_dir     receives <name>.png for each shot (1280x720) and contact.png (labelled grid, half size)
# Paths are relative to the repo root unless absolute.
# Needs: scripts/setup.sh --client, scripts/assemble_game.sh (run once after setup). Env overrides:
#   LUANTI_CLIENT_BIN (default .tools/luanti/bin/luanti), MINEMON_GAMES_DIR (default .games).
# Exit: 0 when every shot and the contact sheet are written; 1 on any failure (client crash, timeout, bad input).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

# The client needs an X display and import needs to read it: run this script again under a virtual X server.
if [ "${MINEMON_SHOTS_INNER:-0}" != "1" ]; then
	command -v xvfb-run >/dev/null 2>&1 || { echo "FAIL: xvfb-run missing (run scripts/setup.sh --client)"; exit 1; }
	MINEMON_SHOTS_INNER=1 exec xvfb-run -a -s "-screen 0 1280x720x24" bash scripts/screenshot.sh "$@"
fi

SHOTS=${1:-}
OUT=${2:-}
if [ -z "$SHOTS" ] || [ -z "$OUT" ]; then
	echo "usage: scripts/screenshot.sh <shots.json> <out_dir>"
	exit 1
fi

BIN=${LUANTI_CLIENT_BIN:-$ROOT/.tools/luanti/bin/luanti}
GAMES_DIR=${MINEMON_GAMES_DIR:-$ROOT/.games}
GAMEID=minemon
SEED=1337
HELPER=$ROOT/tests/screenshot/minemon_shots
PRESET=$ROOT/scripts/presets/vega8.conf
RUNS_DIR=$ROOT/.tools/shot-runs
CLIENT_PID=""
RUN_DIR=""

fail() {
	echo "FAIL: $*"
	if [ -n "$RUN_DIR" ] && [ -f "$RUN_DIR/client.log" ]; then
		echo "--- client log (tail) ---"
		tail -n 20 "$RUN_DIR/client.log"
	fi
	exit 1
}

stop_client() {
	if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
		kill "$CLIENT_PID" 2>/dev/null || true
		for _ in $(seq 1 50); do kill -0 "$CLIENT_PID" 2>/dev/null || break; sleep 0.2; done
		kill -9 "$CLIENT_PID" 2>/dev/null || true
	fi
	if [ -n "$CLIENT_PID" ]; then wait "$CLIENT_PID" 2>/dev/null || true; fi
	CLIENT_PID=""
}
trap stop_client EXIT

[ -f "$SHOTS" ] || fail "shot list not found: $SHOTS"
[ -x "$BIN" ] || fail "client binary missing: $BIN (run scripts/setup.sh --client)"
[ -f "$GAMES_DIR/$GAMEID/game.conf" ] || fail "game $GAMEID not found in $GAMES_DIR (run scripts/assemble_game.sh)"
[ -f "$HELPER/init.lua" ] && [ -f "$HELPER/mod.conf" ] || fail "helper mod missing: $HELPER"
[ -f "$PRESET" ] || fail "client preset missing: $PRESET"
for tool in import identify montage python3; do
	command -v "$tool" >/dev/null 2>&1 || fail "$tool missing (run scripts/setup.sh --client)"
done

# Validate the shot list; print "name wait_s" per shot.
SHOT_LINES=$(python3 -I - "$SHOTS" <<'PY'
import json, re, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        shots = json.load(f)
except (OSError, ValueError) as e:
    sys.exit(f"cannot read {path}: {e}")
if not isinstance(shots, list) or not shots:
    sys.exit("shot list must be a non-empty JSON array")
seen = set()
for i, s in enumerate(shots):
    where = f"shot {i}"
    if not isinstance(s, dict):
        sys.exit(f"{where}: not an object")
    name = s.get("name")
    if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9_]+", name):
        sys.exit(f"{where}: name must match [a-z0-9_]+")
    if name in seen:
        sys.exit(f"{where}: duplicate name {name}")
    seen.add(name)
    pos = s.get("pos")
    if not (isinstance(pos, list) and len(pos) == 3 and all(isinstance(v, (int, float)) for v in pos)):
        sys.exit(f"{name}: pos must be [x, y, z] numbers")
    for key in ("yaw_deg", "pitch_deg"):
        if key in s and not isinstance(s[key], (int, float)):
            sys.exit(f"{name}: {key} must be a number")
    t = s.get("time_of_day", 0.5)
    if not isinstance(t, (int, float)) or not 0 <= t <= 1:
        sys.exit(f"{name}: time_of_day must be a number in 0..1")
    wait = s.get("wait_s", 20)
    if not isinstance(wait, int) or isinstance(wait, bool) or not 1 <= wait <= 600:
        sys.exit(f"{name}: wait_s must be an integer 1..600")
    print(name, wait)
PY
) || fail "invalid shot list $SHOTS"

mkdir -p "$RUNS_DIR"
RUN_DIR=$(mktemp -d "$RUNS_DIR/run.XXXXXX")
WORLD="$RUN_DIR/world"
mkdir -p "$WORLD/worldmods" "$OUT"
OUT=$(cd "$OUT" && pwd)

# Fresh world: the game, the helper mod (trusted, for io), and the shot list the helper reads.
cp -r "$HELPER" "$WORLD/worldmods/minemon_shots"
printf '%s\n' "gameid = $GAMEID" "backend = sqlite3" "player_backend = sqlite3" "auth_backend = sqlite3" \
	"load_mod_minemon_shots = true" > "$WORLD/world.mt"
cp "$SHOTS" "$WORLD/minemon_shots.json"

# Optional extra test mods (T-18 lineup): MINEMON_SHOT_EXTRA_MODS is a space-separated list of mod dirs
# (relative to the repo root). Each is copied with its symlinks resolved and loaded in the throwaway world.
for EXTRA in ${MINEMON_SHOT_EXTRA_MODS:-}; do
	[ -f "$EXTRA/mod.conf" ] || fail "extra mod has no mod.conf: $EXTRA"
	EXTRA_NAME=$(basename "$EXTRA")
	cp -rL "$EXTRA" "$WORLD/worldmods/$EXTRA_NAME"
	printf '%s\n' "load_mod_$EXTRA_NAME = true" >> "$WORLD/world.mt"
done

# A random free port in 30000-39999, so runs in parallel (other worktrees) do not collide. Luanti serves the game on
# UDP, so a port is free only when a UDP bind on 127.0.0.1 succeeds and no TCP listener holds it.
PORT=$(python3 -I -c '
import random, socket, sys
rng = random.SystemRandom()
for _ in range(400):
    port = rng.randint(30000, 39999)
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        udp.bind(("127.0.0.1", port))
    except OSError:
        continue
    finally:
        udp.close()
    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        if tcp.connect_ex(("127.0.0.1", port)) == 0:
            continue
    finally:
        tcp.close()
    print(port)
    sys.exit(0)
sys.exit(1)
' 2>/dev/null) || PORT=""
[ -n "$PORT" ] || fail "no free port"

# Client config: the repo preset, copied so Luanti cannot rewrite the tracked file on exit, plus run overrides.
cp "$PRESET" "$RUN_DIR/client.conf"
printf '%s\n' "" "# Screenshot run overrides (scripts/screenshot.sh)" "fixed_map_seed = $SEED" "time_speed = 0" \
	"enable_damage = false" "secure.trusted_mods = minemon_shots" "ipv6_server = false" "bind_address = 127.0.0.1" \
	"port = $PORT" "enable_mod_channels = false" "fullscreen = false" "screen_w = 1280" "screen_h = 720" \
	>> "$RUN_DIR/client.conf"

echo "[shots] run dir $RUN_DIR, port $PORT, $(wc -l <<<"$SHOT_LINES") shots"
LIBGL_ALWAYS_SOFTWARE=1 LUANTI_GAME_PATH="$GAMES_DIR" "$BIN" --config "$RUN_DIR/client.conf" --go \
	--world "$WORLD" --gameid "$GAMEID" --name tester --password "" --port "$PORT" \
	--logfile "$RUN_DIR/debug.txt" >"$RUN_DIR/client.log" 2>&1 &
CLIENT_PID=$!

NAMES=()
while read -r NAME WAIT; do
	MARKER="$WORLD/shot_${NAME}.ready"
	ALLOW=$((WAIT + 180)) # world generation at the first shot can be slow under software GL
	DEADLINE=$(($(date +%s) + ALLOW))
	until [ -f "$MARKER" ]; do
		kill -0 "$CLIENT_PID" 2>/dev/null || fail "client exited before shot $NAME"
		[ "$(date +%s)" -lt "$DEADLINE" ] || fail "timed out after ${ALLOW}s waiting for shot $NAME"
		sleep 0.5
	done
	import -window root "$OUT/$NAME.png" || fail "import failed for $NAME"
	rm -f "$MARKER"
	NAMES+=("$OUT/$NAME.png")
	echo "[shots] wrote $OUT/$NAME.png"
done <<<"$SHOT_LINES"

stop_client
trap - EXIT

montage "${NAMES[@]}" -label '%t' -geometry 640x360+8+8 -tile 3x -pointsize 22 \
	-background '#1e1e1e' -fill white "$OUT/contact.png" || fail "montage failed"
echo "[shots] wrote $OUT/contact.png"
identify -format '%f: %wx%h, %k distinct colours\n' "${NAMES[@]}" "$OUT/contact.png"
echo "SHOTS DONE: ${#NAMES[@]} shots in $OUT"
