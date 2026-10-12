#!/usr/bin/env bash
# Builds the M0 Windows demo. Installs the Godot 4.7.2 export templates once, exports Minemon.exe,
# writes the four launcher .bat files and the README (CRLF), then zips the folder.
# Output: builds/Minemon-M0/ and builds/Minemon-M0-windows.zip.
set -euo pipefail

cd "$(dirname "$0")/.."

GODOT=${GODOT:-.tools/godot}
GODOT_VERSION="4.7.2"
TPZ_NAME="Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
TPZ=".tools/${TPZ_NAME}"
TPZ_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${TPZ_NAME}"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
BUILD_NAME="Minemon-M0"
BUILD_DIR="builds/${BUILD_NAME}"
ZIP_PATH="builds/${BUILD_NAME}-windows.zip"
EXE_PATH="${BUILD_DIR}/Minemon.exe"

step() {
	echo
	echo "=== $1 ==="
}

[ -x "$GODOT" ] || { echo "FAIL: Godot not found at $GODOT, run scripts/setup.sh"; exit 1; }

step "(a) export templates"
if [ -f "$TEMPLATES_DIR/windows_release_x86_64.exe" ]; then
	echo "templates already in $TEMPLATES_DIR, skipping"
else
	if [ ! -f "$TPZ" ]; then
		echo "downloading $TPZ_URL"
		curl -fL --retry 3 --max-time 3000 -o "$TPZ.part" "$TPZ_URL"
		mv "$TPZ.part" "$TPZ"
	fi
	extract_dir=".tools/templates-extract"
	rm -rf "$extract_dir"
	mkdir -p "$extract_dir" "$TEMPLATES_DIR"
	unzip -q -o "$TPZ" -d "$extract_dir"
	mv "$extract_dir/templates/"* "$TEMPLATES_DIR/"
	rm -rf "$extract_dir"
	echo "templates installed to $TEMPLATES_DIR"
fi

step "(b) import"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || {
	echo "FAIL: Godot import failed, run scripts/check.sh for details"
	exit 1
}

step "(c) export: $GODOT --headless --path . --export-release \"Windows Desktop\" $EXE_PATH"
rm -rf "$BUILD_DIR" "$ZIP_PATH"
mkdir -p "$BUILD_DIR"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$EXE_PATH"
if [ ! -s "$EXE_PATH" ]; then
	echo "FAIL: export did not produce $EXE_PATH"
	exit 1
fi
echo "exported $EXE_PATH ($(stat -c %s "$EXE_PATH") bytes)"

step "(d) launchers and README (CRLF)"
write_crlf() {
	# Reads LF text on stdin and writes it to $1 with CRLF line endings.
	sed 's/$/\r/' > "$1"
}
write_crlf "$BUILD_DIR/Play (low-end).bat" <<'EOF'
start "" "%~dp0Minemon.exe" --rendering-method gl_compatibility
EOF
write_crlf "$BUILD_DIR/Play (Vulkan).bat" <<'EOF'
start "" "%~dp0Minemon.exe" --rendering-method mobile
EOF
write_crlf "$BUILD_DIR/Benchmark (low-end).bat" <<'EOF'
start "" "%~dp0Minemon.exe" --rendering-method gl_compatibility -- --benchmark
EOF
write_crlf "$BUILD_DIR/Benchmark (Vulkan).bat" <<'EOF'
start "" "%~dp0Minemon.exe" --rendering-method mobile -- --benchmark
EOF
write_crlf "$BUILD_DIR/LEIA-ME README.txt" <<'EOF'
MINEMON M0 - WINDOWS DEMO
=========================

Passo 1 - Descompactar
----------------------
Unzip the .zip: right-click it and choose "Extract All". Do not run the game from inside the zip.

Passo 2 - Benchmark (60 segundos)
---------------------------------
1. Double-click "Benchmark (low-end)".
2. Do not touch the mouse or keyboard for 60 seconds. The game closes by itself.
3. Find the new file benchmark_gl_compatibility_....txt in this folder and send it to me.
   If this folder is read-only, the file is in %APPDATA%\Godot\app_userdata\Minemon instead.
4. Do the same with "Benchmark (Vulkan)". Send the new benchmark_mobile_....txt file.

Passo 3 - Andar pelo mundo
--------------------------
Double-click "Play (low-end)" to walk around.
- W A S D: walk
- Mouse: look around
- Shift: sprint
- Space: jump. While flying, go up.
- Ctrl: while flying, go down
- F: toggle fly
- F3: show or hide the debug overlay (fps, memory, position)
- Esc: frees the mouse. Click the game to capture it again.

Aviso
-----
Windows SmartScreen may warn about an unknown app. Click "More info", then "Run anyway".
EOF

step "(e) zip: $ZIP_PATH"
python3 - "$BUILD_DIR" "$ZIP_PATH" <<'PY'
import os
import shutil
import sys

build_dir, zip_path = sys.argv[1], sys.argv[2]
base = zip_path[: -len(".zip")]
archive = shutil.make_archive(base, "zip", root_dir=os.path.dirname(build_dir),
                              base_dir=os.path.basename(build_dir))
print("zipped", archive)
PY
echo "zip size: $(stat -c %s "$ZIP_PATH") bytes"
unzip -l "$ZIP_PATH"

echo
echo "EXPORT PASSED"
