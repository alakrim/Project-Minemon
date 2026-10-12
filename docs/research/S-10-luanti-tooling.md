# S-10 — Luanti headless build and Lua test tooling (spike)

Engine: Luanti 5.14.0 (`6d1a208`). Scratch: `scratchpad/s10/`.

## Findings
- **Build works.** Server-only `luantiserver` from the 5.14.0 tag. Configure 3.5 s; build 3 min 17 s on 2 vCPU. Binary 4.3 MB, system LuaJIT 2.1.
- **RUN_IN_PLACE puts output in the source tree** (`bin/luantiserver`), not the build dir. The clone stayed clean.
- **Headless run works end to end** with `--gameid devtest` and with `minetest_game` (`c42e4d0`). The test mod runs 7 checks (nodes, metadata, JSON, entity spawn, punch damage, `on_punch`); all pass. `core.safe_file_write` works from an untrusted mod. Server exits rc 0 after `core.request_shutdown`.
- **Failure paths verified:** a sabotaged assertion, a crash and a timeout all exit 1.
- **Gotchas found:**
  1. `--server` is not a valid flag for `luantiserver`.
  2. The container has no IPv6. The server aborts with "Failed to create socket" unless the config sets `ipv6_server = false` and `bind_address = 127.0.0.1`.
  3. `core.emerge_area` called from `register_on_mods_loaded` logs "disallowed during script init" and its callback never fires. Defer it with `core.after(0, ...)`.
- **Lua tooling:** `lua-check` 1.1.2 and `lua-busted` 2.2.0 from apt. luacheck passes on the sample, the test mod and upstream devtest unittests; an unused-local control exits 1. busted runs on Lua 5.1 and LuaJIT. luarocks not needed or tested.
- **Timings** (0.2 s polling): startup probe (no map) 0.43 s, about 75 MB RSS; devtest full run 0.64–0.85 s, 112–120 MB peak; minetest_game 0.63–0.65 s, about 65 MB peak; wall about 1.05 s with shutdown.
- **Windows client:** `luanti-5.14.0-win64.zip` is 16,926,278 bytes (16.1 MiB), per `curl -sIL`.

## Commands that worked
```bash
sudo apt-get install -y g++ make cmake libc6-dev libsqlite3-dev zlib1g-dev libgmp-dev \
  libjsoncpp-dev libzstd-dev libluajit-5.1-dev libcurl4-openssl-dev gettext git lua-check lua-busted
git clone --depth 1 --branch 5.14.0 https://github.com/luanti-org/luanti SRC
cmake -S SRC -B BUILD -DBUILD_CLIENT=FALSE -DBUILD_SERVER=TRUE -DRUN_IN_PLACE=TRUE \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_UNITTESTS=FALSE -DBUILD_BENCHMARKS=FALSE \
  -DBUILD_DOCUMENTATION=FALSE -DENABLE_GETTEXT=0
cmake --build BUILD -j2          # binary: SRC/bin/luantiserver
bash scratchpad/s10/run_luanti_test.sh [mods_dir] [timeout_s]   # GAMEID=minetest_game to switch
bash scratchpad/s10/lua_tooling/lua_check.sh <dir>              # luacheck + busted (5.1 and LuaJIT)
```

## Recommendation
- **scripts/setup.sh:** run the apt line above (Ubuntu 24.04). Clone 5.14.0 into `.tools/luanti-src` (confirm `.tools/` is gitignored). Skip the build if `bin/luantiserver --version` already reports 5.14.0. Otherwise run the CMake flags above (about 3.5 min). Install `lua-check` and `lua-busted`.
- **scripts/check.sh:** (a) luacheck with a repo-root `.luacheckrc` (globals `core`, `minetest`) over `mods/`; (b) busted over `tests/unit` on Lua 5.1 and LuaJIT; (c) headless integration via the runner over `tests/integration/mods` with a 120 s timeout. Move the runner into `scripts/` and make its paths repo-relative. Every mod must pass luacheck.
- **Mod convention:** defer map work with `core.after(0)`, write results with `core.safe_file_write`, call `core.request_shutdown`.

## Confidence
High that the build, headless run, failure detection and Lua lint/unit path work here. Medium-high on timings (single 2-vCPU box, small sample). Not yet verified on the owner's Windows PC or on Android.

## Open questions
1. Which base game (S-09 picks minetest_game) ships in `.tools`? Only devtest and minetest_game ran here; Mineclonia is Codeberg-only (unreachable); VoxeLibre not cloned.
2. Client checks (rendering, Android) not covered. Devtest's own unittests need a connected client; not attempted.
3. Word limits: CLAUDE.md caps scout digests at 250 words. This file follows the brief's 500-word cap. The orchestrator should decide which applies.
