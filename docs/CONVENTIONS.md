# Conventions (all workers)

## Lua
- Luanti 5.17 API: use `core.*`, not `minetest.*`. LuaJIT/Lua 5.1 compatible; no `goto` and no 5.2+ features.
- Every mod has a `mod.conf` (`name`, `description`, `depends`, `optional_depends`) and an `init.lua`. Mod names start with `minemon_`.
- Module pattern: `local M = {}` ... return M from helper files loaded with `dofile(core.get_modpath(...) .. "/x.lua")`. Shared public API: the global table `minemon` (created by `minemon_core`), with one sub-table per mod (`minemon.lives`, ...). No other globals; luacheck enforces this.
- **Pure logic goes in separate files that do not touch `core`** (e.g. `lives_logic.lua`), so busted can test it without Luanti. Glue code (callbacks, HUD) stays thin.
- Player state is stored in player meta under keys `minemon:<mod>:<key>`. Mod-global state goes in `core.get_mod_storage()`.
- Performance: no unbounded work in globalsteps. Accumulate dtime and act every ≥0.5 s. Cap radius and object counts.
- Randomness: `PcgRandom` or a seeded RNG from minemon_core, so tests are deterministic.
- Never modify VoxeLibre or Luanti files. Use their public APIs (`mcl_mobs`, `mcl_*`). Read their source in `.tools/voxelibre` to learn the API.
- Formatting: 4-space or tab indentation, consistent within each file. Lines up to 120 characters.

## Tests
- `tests/unit/<mod>_<thing>_spec.lua` (busted): every pure-logic function, with deterministic inputs.
- `tests/integration/<name>/` is a Luanti mod (mod.conf + init.lua). It runs its checks after `core.after(1, ...)`, writes `test_result.txt` (`PASS n` or `FAIL <reason>`) to the world dir, and calls `core.request_shutdown()`. `scripts/run_luanti_test.sh` runs it inside the assembled game.
- Every acceptance criterion maps to a test, or to a command with checked output.
- `bash scripts/check.sh` must exit 0 before a task is BUILT.

## Files and licences
- Never commit `.tools/`, `builds/` or third-party code. VoxeLibre and Luanti are fetched by setup.sh.
- Generated assets (our own stand-in models and textures) are committed with a row in `ASSETS_LICENSES.md`.
- Change only the files your brief allows. Do not git commit or push, unless working in a worktree where the launch prompt says to.
- Reports: builder `tasks/M<n>/T-<nn>.report.md` (max 120 words, plus an "In-game checks" list when relevant); verifier `.verdict.md` (max 100 words). Writing these files is required.
- If your brief is unclear: mark it BLOCKED in your report and ask one specific question.
