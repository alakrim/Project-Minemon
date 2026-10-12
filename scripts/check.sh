#!/usr/bin/env bash
# Full check: luacheck, busted unit specs, game assembly, headless integration tests.
# Stops on the first failing step and exits non-zero. Exits 0 only after CHECK PASSED.
set -euo pipefail

cd "$(dirname "$0")/.."

step() {
	echo
	echo "=== $1 ==="
}

if [ ! -x .tools/luanti/bin/luantiserver ] || [ ! -f .tools/voxelibre/game.conf ]; then
	echo "FAIL: tools missing; run scripts/setup.sh first"
	exit 1
fi

step "(1) luacheck mods/ tests/"
luacheck mods/ tests/

step "(2) busted tests/unit"
if compgen -G "tests/unit/*_spec.lua" >/dev/null; then
	busted tests/unit
else
	echo "skip: no specs in tests/unit yet"
fi

if [ -d tools/tests ]; then
	step "(3) python unittest tools/tests"
	python3 -m unittest discover -s tools/tests
fi

step "(4) assemble game"
bash scripts/assemble_game.sh

step "(5) headless integration tests"
shopt -s nullglob
PASSED=()
FAILED=()
for dir in tests/integration/*/; do
	name=${dir%/}
	if bash scripts/run_luanti_test.sh "$name" 120; then
		PASSED+=("$name")
	else
		FAILED+=("$name")
	fi
done
if [ "${#PASSED[@]}" -eq 0 ] && [ "${#FAILED[@]}" -eq 0 ]; then
	echo "FAIL: no integration tests found in tests/integration/"
	exit 1
fi

step "summary"
echo "integration passed: ${PASSED[*]:-none}"
echo "integration failed: ${FAILED[*]:-none}"
if [ "${#FAILED[@]}" -gt 0 ]; then
	echo "CHECK FAILED"
	exit 1
fi

echo
echo "CHECK PASSED"
