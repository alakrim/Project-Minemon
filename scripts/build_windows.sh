#!/usr/bin/env bash
# Builds the portable Windows package of Minemon (M0).
#   builds/Minemon/            Luanti win64 release (bin/luanti.exe), games/minemon, presets/, minetest.conf,
#                              Play Minemon.bat, Quick Play.bat, LEIA-ME README.txt
#   builds/Minemon-M0-windows.zip           the folder zipped (top folder: Minemon/)
#   builds/Minemon-M0-windows.zip.001 ...   the zip split into parts of at most 25 MB
#   builds/JUNTAR-JOIN Minemon.bat          joins the parts back into the zip (copy /b)
# Needs scripts/setup.sh (VoxeLibre) and network access to GitHub for the Luanti zip (cached in .tools/cache/).
# Usage: bash scripts/build_windows.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

. scripts/versions.env

CACHE_DIR=$ROOT/.tools/cache
ZIP_TOP=luanti-$LUANTI_TAG-win64
ZIP_CACHE=$CACHE_DIR/$ZIP_TOP.zip
ZIP_URL=https://github.com/luanti-org/luanti/releases/download/$LUANTI_TAG/$ZIP_TOP.zip
BUILDS=$ROOT/builds
BUILD=$BUILDS/Minemon
VERSION=${MINEMON_VERSION:-M1}
PACKAGE=Minemon-${VERSION}-windows
PART_BYTES=25000000
MENU_GAME=minemon
JOIN_BAT="JUNTAR-JOIN Minemon.bat"

mkdir -p "$CACHE_DIR" "$BUILDS"
TMP=$(mktemp -d "$CACHE_DIR/tmp.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

step() {
	echo
	echo "=== $1 ==="
}

fail() {
	echo "FAIL: $1"
	exit 1
}

# Writes stdin to $1 with Windows line endings (CRLF).
write_crlf() {
	sed 's/$/\r/' > "$1"
}

# Every "key = value" line in scripts/presets/*.conf must name a setting in settingtypes.txt ($1).
check_preset_keys() {
	local st=$1 conf key bad=0 n=0
	for conf in scripts/presets/*.conf; do
		while IFS= read -r key; do
			n=$((n + 1))
			if ! awk -v k="$key" '$1 == k { found = 1 } END { exit !found }' "$st"; then
				echo "FAIL: $(basename "$conf"): '$key' is not a setting in settingtypes.txt"
				bad=1
			fi
		done < <(sed -n -E 's/^([a-z_0-9]+)[[:space:]]*=.*/\1/p' "$conf")
	done
	[ "$bad" -eq 0 ] || return 1
	echo "OK: $n preset keys, all found in settingtypes.txt (Luanti $LUANTI_TAG)"
}

step "(a) Luanti $LUANTI_TAG win64 release (cached in .tools/cache)"
if ! unzip -tq "$ZIP_CACHE" >/dev/null 2>&1; then
	rm -f "$ZIP_CACHE"
	curl -fL --retry 3 -o "$ZIP_CACHE.part" "$ZIP_URL"
	mv "$ZIP_CACHE.part" "$ZIP_CACHE"
	unzip -tq "$ZIP_CACHE" >/dev/null || fail "downloaded zip is corrupt: $ZIP_CACHE"
fi
echo "zip: $ZIP_CACHE ($(stat -c %s "$ZIP_CACHE") bytes)"

step "(b) unpack into builds/Minemon (top folder flattened)"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$TMP/unzip"
unzip -q "$ZIP_CACHE" -d "$TMP/unzip"
cp -a "$TMP/unzip/$ZIP_TOP/." "$BUILD/"
[ -f "$BUILD/bin/luanti.exe" ] || fail "bin/luanti.exe missing after unpack"
echo "unpacked: $BUILD/bin/luanti.exe"

step "(c) Minemon game: assemble_game.sh, copied to builds/Minemon/games/minemon"
bash scripts/assemble_game.sh
mkdir -p "$BUILD/games"
cp -a "${MINEMON_GAMES_DIR:-$ROOT/.games}/minemon" "$BUILD/games/minemon"
[ -f "$BUILD/games/minemon/game.conf" ] || fail "game.conf missing in the copied game"

step "(c2) headless sanity: smoke test against the copied game"
MINEMON_GAMES_DIR="$BUILD/games" bash scripts/run_luanti_test.sh tests/integration/smoke 120

step "(d) presets, minetest.conf and presets/ folder"
unzip -p "$ZIP_CACHE" "$ZIP_TOP/builtin/settingtypes.txt" > "$TMP/settingtypes.txt"
check_preset_keys "$TMP/settingtypes.txt" || fail "preset keys do not match settingtypes.txt"
mkdir -p "$BUILD/presets"
cp scripts/presets/*.conf "$BUILD/presets/"
cp scripts/presets/vega8.conf "$BUILD/minetest.conf"
# Luanti 5.17 keeps the menu's last game outside settingtypes.txt, so the build adds it to every shipped config.
for conf in "$BUILD/minetest.conf" "$BUILD"/presets/*.conf; do
	printf '\n# Added by scripts/build_windows.sh: the main menu opens on Minemon.\nmenu_last_game = %s\n' \
		"$MENU_GAME" >> "$conf"
done
echo "minetest.conf and presets/ written"

step "(e) launchers and README"
write_crlf "$BUILD/Play Minemon.bat" <<'EOF'
@echo off
rem Starts Minemon. The main menu opens with Minemon selected (menu_last_game in minetest.conf).
start "" "%~dp0bin\luanti.exe"
EOF

write_crlf "$BUILD/Quick Play.bat" <<'EOF'
@echo off
rem Starts Minemon straight in the world "Minemon". The world is created on the first run.
start "" "%~dp0bin\luanti.exe" --go --world "%~dp0worlds\Minemon" --gameid minemon
EOF

write_crlf "$BUILD/LEIA-ME README.txt" <<EOF
MINEMON - (Windows)
===================

Como começar
------------
1. If you received the zip in parts (.zip.001, .zip.002, ...), double-click
   "JUNTAR-JOIN Minemon.bat" in the same folder first. It makes the Minemon zip.
2. Right-click the Minemon zip and choose "Extrair Tudo" (Extract All).
3. Open the new "Minemon" folder.
4. Double-click "Play Minemon.bat". The main menu opens with Minemon selected.
5. Or double-click "Quick Play.bat" to go straight into the world "Minemon".
6. Windows SmartScreen may show a warning ("Windows protected your PC").
   Click "More info", then "Run anyway". This happens because the build is not signed.

Controles / Controls
--------------------
W A S D      move
Mouse        look around
Left click   dig, hit
Right click  place, use
Space        jump
Shift        sneak (hold)
I            inventory
F5           debug info, with the FPS at the top-left

Teste de FPS / FPS test
-----------------------
1. Walk into a forest, in the daytime.
2. Press F5. Look at the top-left corner.
3. Tell Claude the FPS number shown at the top-left after pressing F5, in a forest during the day.

Se o FPS estiver abaixo de 30 / If the FPS is below 30
-----------------------------------------------------
If FPS is below 30, replace minetest.conf with presets\low.conf.
1. Close the game.
2. Open the "presets" folder inside the Minemon folder.
3. Copy low.conf into the Minemon folder and rename the copy to minetest.conf
   (replace the old one).
4. Start the game again and do the FPS test.

Como jogar / How to play
------------------------
- On your first visit you choose a partner Pokemon (6 starters). You also get the Party Ball,
  5 Poke Balls, 3 Potions and 10 coins.
- Party Ball in hand:
    Right click           send out / call back your Pokemon
    Left click a wild     order your Pokemon to attack it with the SELECTED move
    Z                     cycle the selected move (the move bar sits above the hotbar)
    Shift + left click    (on air) also cycles the move
    Shift + right click   party screen (choose the lead)
- CAPTURE: beat a wild Pokemon until it is "exhausted" (it sits for 20 s). Then hold a
  Poke Ball, look at it (the catch chance shows near the crosshair) and LEFT CLICK to throw.
  If it breaks free it comes for YOU, enraged, for 30 seconds.
  Balls are crafted: Poke Ball = gold nugget / redstone / gold nugget (column), gives 2.
  Great Ball = Poke Ball + lapis. Ultra Ball = Poke Ball + gold ingot + obsidian.
- GROWTH: your Pokemon out gets exp from every defeat, levels up, learns moves and evolves.
  Stones and the Link Cable (trade evolutions) are used with right click while it is out.
- SANCTUARIES (Pokemon Centers): lantern shrines. One stands near the start. The altar heals
  your party and becomes your respawn point. Wild Pokemon will not enter. Inside: a PC to
  store Pokemon and a counter that sells items for coins.
- COINS drop from defeated wild Pokemon (double at night). They are items: you lose them
  when you die.
- THE NIGHT: rarely, a DREAD Pokemon walks in the dark. Corrupted, stronger, red eyes, it
  hunts you. It drops Dread Shards (Ultra Ball + 4 shards = Umbral Ball, made to catch them)
  and melts away at dawn.
- Fainted partners revive after 10 minutes, or at a Sanctuary altar.
- Chat commands: /party, /lives, /starter, /exp

Regra das vidas / The rule
--------------------------
You have 3 lives. On the 4th death your journey ends forever (ghost mode).
Type /lives in the chat to check how many lives you have.

Sobre / About
-------------
Private use only. Please do not share or upload this build.
Luanti 5.17.0 + VoxeLibre 0.92.3 + Minemon ${VERSION}.
Pokemon models and textures: Cobblemon (cobblemon.com) via kirbycope/cobblemon-bedrock,
CC BY-NC, converted for Minemon. See games/minemon/mods/minemon_pack_cobblemon/CREDITS.txt.
EOF
echo "launchers and README written"

step "(f) zip, split into parts of at most 25 MB, join .bat"
rm -f "$BUILDS/$PACKAGE.zip" "$BUILDS/$PACKAGE.zip."[0-9][0-9][0-9] "$BUILDS/$JOIN_BAT"
(cd "$BUILDS" && zip -qr -X "$PACKAGE.zip" Minemon)
ZIP="$BUILDS/$PACKAGE.zip"
ZIP_MD5=$(md5sum "$ZIP" | cut -d' ' -f1)
(cd "$BUILDS" && split -b "$PART_BYTES" --numeric-suffixes=1 -a 3 "$PACKAGE.zip" "$PACKAGE.zip.")

shopt -s nullglob
PART_PATHS=("$BUILDS/$PACKAGE.zip."[0-9][0-9][0-9])
shopt -u nullglob
[ "${#PART_PATHS[@]}" -gt 0 ] || fail "no zip parts were written"

PARTS_MD5=$(cat "${PART_PATHS[@]}" | md5sum | cut -d' ' -f1)
[ "$PARTS_MD5" = "$ZIP_MD5" ] || fail "cat of the parts does not match the zip (md5)"

COPY_SRC=""
for part in "${PART_PATHS[@]}"; do
	name=$(basename "$part")
	if [ -z "$COPY_SRC" ]; then COPY_SRC="\"$name\""; else COPY_SRC="$COPY_SRC+\"$name\""; fi
done
FIRST_PART=$(basename "${PART_PATHS[0]}")

write_crlf "$BUILDS/$JOIN_BAT" <<EOF
@echo off
rem Joins the Minemon zip parts in this folder into the Minemon zip. Keep all the .zip.0xx files here.
cd /d "%~dp0"
if not exist "$FIRST_PART" (
	echo Nao encontrei as partes do zip nesta pasta.
	pause
	exit /b 1
)
copy /b /y $COPY_SRC "$PACKAGE.zip"
if errorlevel 1 (
	echo Erro ao juntar as partes.
	pause
	exit /b 1
)
echo.
echo Pronto: o arquivo $PACKAGE.zip foi criado nesta pasta.
echo Agora clique com o botao direito nele e escolha "Extrair Tudo" (Extract All).
echo Depois abra a pasta Minemon e clique duas vezes em "Play Minemon.bat".
pause
EOF

step "summary"
TOTAL=0
for part in "${PART_PATHS[@]}"; do
	size=$(stat -c %s "$part")
	TOTAL=$((TOTAL + size))
	printf '%-40s %12d bytes  %6.2f MB\n' "$(basename "$part")" "$size" "$(awk -v s="$size" 'BEGIN { print s / 1000000 }')"
done
printf '%-40s %12d bytes  %6.2f MB\n' "parts total" "$TOTAL" "$(awk -v s="$TOTAL" 'BEGIN { print s / 1000000 }')"
printf '%-40s %12d bytes  %6.2f MB\n' "$PACKAGE.zip" "$(stat -c %s "$ZIP")" "$(awk -v s="$(stat -c %s "$ZIP")" 'BEGIN { print s / 1000000 }')"
echo "md5 $ZIP_MD5 (cat of parts matches)"
echo "join: $BUILDS/$JOIN_BAT"
echo
echo "BUILD WINDOWS PASSED"
