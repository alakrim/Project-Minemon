#!/usr/bin/env bash
# Assembles the Minemon game: a fresh copy of VoxeLibre (without .git) plus our mods/minemon modpack,
# written to .games/minemon (or $MINEMON_GAMES_DIR). game.conf gets title = Minemon. Run scripts/setup.sh first.
set -euo pipefail

cd "$(dirname "$0")/.."

VOXELIBRE_DIR=".tools/voxelibre"
GAMES_DIR="${MINEMON_GAMES_DIR:-.games}"  # per-checkout (worktrees must not share it, LESSONS 2026-10-10)
GAME_DIR="$GAMES_DIR/minemon"

[ -f "$VOXELIBRE_DIR/game.conf" ] || { echo "FAIL: VoxeLibre not found at $VOXELIBRE_DIR (run scripts/setup.sh)"; exit 1; }
[ -f "mods/minemon/modpack.conf" ] || { echo "FAIL: mods/minemon/modpack.conf missing"; exit 1; }

rm -rf "$GAME_DIR"
mkdir -p "$GAME_DIR"

# Everything from VoxeLibre except its .git directory.
tar -C "$VOXELIBRE_DIR" --exclude=./.git -cf - . | tar -C "$GAME_DIR" -xf -

# Title for the game menu; keep every other key.
if grep -q '^title[[:space:]]*=' "$GAME_DIR/game.conf"; then
	sed -i -E 's/^title[[:space:]]*=.*/title = Minemon/' "$GAME_DIR/game.conf"
else
	printf 'title = Minemon\n' | cat - "$GAME_DIR/game.conf" > "$GAME_DIR/game.conf.tmp"
	mv "$GAME_DIR/game.conf.tmp" "$GAME_DIR/game.conf"
fi

# Our modpack.
mkdir -p "$GAME_DIR/mods"
cp -r mods/minemon "$GAME_DIR/mods/minemon"

# The generated Cobblemon pack (T-25a, D-029), when scripts/setup.sh has converted it. Never committed.
COBBLE_PACK=".tools/pack_cobblemon/minemon_pack_cobblemon"
if [ -f "$COBBLE_PACK/init.lua" ]; then
	cp -r "$COBBLE_PACK" "$GAME_DIR/mods/minemon_pack_cobblemon"
fi

MODS=$(find "$GAME_DIR/mods/minemon" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo "assembled $GAME_DIR (title: Minemon, $MODS Minemon mods)"
du -sh "$GAME_DIR" | awk '{print "size: " $1}'
