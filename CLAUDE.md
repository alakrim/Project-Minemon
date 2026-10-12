# Minemon

A private, free Pokémon game for the owner and one friend: Luanti 5.17.0 + the VoxeLibre game (Minecraft-like) + our Lua mods in `mods/minemon/`. Hard, scary, alive: real-time creature combat, capture after defeat, 3 lives then permadeath, Kanto + Johto towns and missions, eldritch giants. See docs/PLAN.md (v3) and D-024/D-025.

## Who reads what
- **Opus (orchestrator):** docs/PROTOCOL.md, docs/STATE.md, then the docs/PROGRESS.md summary.
- **Workers (Haiku, high effort):** this file, docs/CONVENTIONS.md and your task brief. Follow the brief exactly.

## Key commands
- `bash scripts/setup.sh`: apt deps, builds luantiserver 5.17.0 into `.tools/`, clones VoxeLibre (pinned) into `.tools/voxelibre`, installs luacheck and busted. Idempotent.
- `bash scripts/assemble_game.sh`: builds `.games/minemon` (VoxeLibre plus our mods).
- `bash scripts/check.sh`: luacheck, busted unit tests, headless integration tests.
- `bash scripts/build_windows.sh`: portable Windows build in `builds/`.

## File map
- `mods/minemon/`: our modpack (one folder per mod)
- `tests/unit/`: busted specs; `tests/integration/<name>/`: headless test mods
- `tools/`: Python generators (data, stand-in models)
- `scripts/`: setup, check, assembly, test runner, build
- `docs/`, `tasks/`: project memory (docs/PROTOCOL.md)
- `.tools/` (git-ignored): luantiserver, VoxeLibre clone, assembled game

## Hard content rule
Never create, draw, model or download Pokémon art, models, textures or sounds. Creature visuals are our own procedural stand-ins, or files the owner supplies. Private use only.
Exceptions by owner directive: D-029 (Cobblemon models converted at setup into `.tools/`, never committed) and D-030 (our own generated 16×16 item icons for balls and items are allowed).
