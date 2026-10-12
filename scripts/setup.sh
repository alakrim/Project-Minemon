#!/usr/bin/env bash
# Idempotent dev-tool setup for Minemon. Quiet when there is nothing to do.
#   - apt packages (build deps for Luanti, LuaJIT, luacheck, busted)
#   - luantiserver (server only) at LUANTI_TAG into .tools/luanti (skipped if the version matches)
#   - with --client: luanti (client) at LUANTI_TAG from the same source, built in .tools/luanti-client-build
#     (skipped if bin/luanti already reports LUANTI_TAG). Used by scripts/screenshot.sh.
#   - VoxeLibre at VOXELIBRE_TAG into .tools/voxelibre (skipped if the tag matches)
# Versions come from scripts/versions.env.
# Usage: scripts/setup.sh [--client]
set -euo pipefail

cd "$(dirname "$0")/.."

WANT_CLIENT=0
for arg in "$@"; do
	case "$arg" in
		--client) WANT_CLIENT=1 ;;
		*) echo "usage: scripts/setup.sh [--client]"; echo "FAIL: unknown argument '$arg'"; exit 2 ;;
	esac
done

# shellcheck source=versions.env
. scripts/versions.env
: "${LUANTI_TAG:?LUANTI_TAG is not set in scripts/versions.env}"
: "${VOXELIBRE_TAG:?VOXELIBRE_TAG is not set in scripts/versions.env (pin the newest working release)}"

APT_PKGS="g++ make cmake libc6-dev libsqlite3-dev zlib1g-dev libgmp-dev libjsoncpp-dev libzstd-dev \
libluajit-5.1-dev libcurl4-openssl-dev gettext git lua-check lua-busted luajit lua5.1"

# Client (--client): Luanti 5.17 client deps (SDL2 window and input, Mesa GL, OpenAL, Vorbis, FreeType, PNG, JPEG),
# plus Xvfb and ImageMagick for headless screenshots.
CLIENT_APT_PKGS="libgl1-mesa-dev libgl1-mesa-dri libx11-dev libxi-dev libxxf86vm-dev libpng-dev libjpeg-dev \
libfreetype-dev libopenal-dev libvorbis-dev libogg-dev libsdl2-dev xvfb xauth mesa-utils imagemagick"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

PKGS_TO_CHECK="$APT_PKGS"
if [ "$WANT_CLIENT" -eq 1 ]; then PKGS_TO_CHECK="$PKGS_TO_CHECK $CLIENT_APT_PKGS"; fi

missing=()
for pkg in $PKGS_TO_CHECK; do
	if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
		missing+=("$pkg")
	fi
done
if [ "${#missing[@]}" -gt 0 ]; then
	echo "[setup] installing apt packages: ${missing[*]}"
	$SUDO apt-get update -qq
	DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "${missing[@]}"
fi

mkdir -p .tools

LUANTI_DIR=.tools/luanti
LUANTI_BUILD=.tools/luanti-build
LUANTI_BIN="$LUANTI_DIR/bin/luantiserver"
LUANTI_VER=""
if [ -x "$LUANTI_BIN" ]; then
	LUANTI_VER=$("$LUANTI_BIN" --version 2>/dev/null || true)
fi
if [ -x "$LUANTI_BIN" ] && [[ "$LUANTI_VER" == *"$LUANTI_TAG"* ]]; then
	: # already built at the pinned tag
else
	echo "[setup] building luantiserver $LUANTI_TAG (server only, about 4 min)"
	rm -rf "$LUANTI_DIR" "$LUANTI_BUILD"
	git clone --depth 1 --branch "$LUANTI_TAG" https://github.com/luanti-org/luanti "$LUANTI_DIR"
	cmake -S "$LUANTI_DIR" -B "$LUANTI_BUILD" -DBUILD_CLIENT=FALSE -DBUILD_SERVER=TRUE -DRUN_IN_PLACE=TRUE \
		-DCMAKE_BUILD_TYPE=Release -DBUILD_UNITTESTS=FALSE -DBUILD_BENCHMARKS=FALSE \
		-DBUILD_DOCUMENTATION=FALSE -DENABLE_GETTEXT=0
	cmake --build "$LUANTI_BUILD" -j"$(nproc)"
	[ -x "$LUANTI_BIN" ] || { echo "FAIL: build did not produce $LUANTI_BIN"; exit 1; }
	echo "[setup] built: $("$LUANTI_BIN" --version 2>/dev/null || true)"
fi

if [ "$WANT_CLIENT" -eq 1 ]; then
	# Separate build dir, so the server build above is never touched. RUN_IN_PLACE puts the client in
	# $LUANTI_DIR/bin/luanti next to luantiserver. Source is the same tag clone as the server.
	CLIENT_BIN="$LUANTI_DIR/bin/luanti"
	CLIENT_BUILD=.tools/luanti-client-build
	CLIENT_VER=""
	if [ -x "$CLIENT_BIN" ]; then
		CLIENT_VER=$("$CLIENT_BIN" --version 2>/dev/null || true)
	fi
	if [ -x "$CLIENT_BIN" ] && [[ "$CLIENT_VER" == *"$LUANTI_TAG"* ]]; then
		: # client already built at the pinned tag
	else
		echo "[setup] building luanti client $LUANTI_TAG (about 6-10 min on 2 cores)"
		rm -rf "$CLIENT_BUILD"
		cmake -S "$LUANTI_DIR" -B "$CLIENT_BUILD" -DBUILD_CLIENT=TRUE -DBUILD_SERVER=FALSE -DRUN_IN_PLACE=TRUE \
			-DCMAKE_BUILD_TYPE=Release -DBUILD_UNITTESTS=FALSE -DBUILD_BENCHMARKS=FALSE \
			-DBUILD_DOCUMENTATION=FALSE -DENABLE_GETTEXT=0
		cmake --build "$CLIENT_BUILD" -j"$(nproc)"
		[ -x "$CLIENT_BIN" ] || { echo "FAIL: build did not produce $CLIENT_BIN"; exit 1; }
		echo "[setup] built: $("$CLIENT_BIN" --version 2>/dev/null || true)"
	fi
fi

VOX_DIR=.tools/voxelibre
if [ -f "$VOX_DIR/game.conf" ] && [ "$(git -C "$VOX_DIR" describe --tags --exact-match 2>/dev/null || true)" = "$VOXELIBRE_TAG" ]; then
	: # already present at the pinned tag
else
	echo "[setup] cloning VoxeLibre $VOXELIBRE_TAG"
	rm -rf "$VOX_DIR"
	git clone --depth 1 --branch "$VOXELIBRE_TAG" https://github.com/VoxeLibre/VoxeLibre "$VOX_DIR"
fi

# Cobblemon Bedrock models (T-25a, D-029): the clone is fetched at COBBLEMON_BEDROCK_COMMIT, then the converter
# writes the generated pack mod to .tools/pack_cobblemon. Both live in .tools/ and are never committed.
: "${COBBLEMON_BEDROCK_COMMIT:?COBBLEMON_BEDROCK_COMMIT is not set in scripts/versions.env}"
CBR_DIR=.tools/cobblemon-bedrock
if [ -d "$CBR_DIR/development_resource_packs/cobblemon/models/entity" ] \
	&& [ "$(git -C "$CBR_DIR" rev-parse HEAD 2>/dev/null || true)" = "$COBBLEMON_BEDROCK_COMMIT" ]; then
	: # already present at the pinned commit
else
	echo "[setup] cloning cobblemon-bedrock at ${COBBLEMON_BEDROCK_COMMIT:0:12}"
	rm -rf "$CBR_DIR"
	git init -q "$CBR_DIR"
	git -C "$CBR_DIR" remote add origin https://github.com/kirbycope/cobblemon-bedrock
	git -C "$CBR_DIR" fetch -q --depth 1 origin "$COBBLEMON_BEDROCK_COMMIT"
	git -C "$CBR_DIR" checkout -q FETCH_HEAD
fi

# Converter dev dependency (D-029, T-25b): the molang evaluator.
python3 -c "import molang" 2>/dev/null || pip install -q --break-system-packages molang

# Conversion is skipped while the stamp (source commit plus converter sources) is unchanged.
PACK_DIR=.tools/pack_cobblemon
CONV_HASH=$(cat tools/cobblemon_import.py tools/gen_standins.py | sha256sum | cut -d' ' -f1)
PACK_STAMP="$COBBLEMON_BEDROCK_COMMIT $CONV_HASH"
if [ -f "$PACK_DIR/minemon_pack_cobblemon/init.lua" ] && [ "$(cat "$PACK_DIR/.stamp" 2>/dev/null || true)" = "$PACK_STAMP" ]; then
	: # pack is current
else
	echo "[setup] converting Cobblemon models into $PACK_DIR"
	python3 tools/cobblemon_import.py --src "$CBR_DIR" --out "$PACK_DIR" --commit "$COBBLEMON_BEDROCK_COMMIT"
	printf '%s\n' "$PACK_STAMP" > "$PACK_DIR/.stamp"
fi

