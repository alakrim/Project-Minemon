# STATE

- **Phase:** C build loop. **M2 built** (Windows build Minemon-M2 sent to the owner). Next: owner playtest of M2, then M3 (dread and atmosphere).
- **Stack:** Luanti 5.17.0 + VoxeLibre 0.92.3 + mods/minemon; Pokémon models converted from Cobblemon (D-029; generated in .tools, never committed).
- **Last session:** 2026-10-11

## Done in M1
Core API, 251-species data, Cobblemon models and animations (247 species), creature registration and spawning by biome and distance level, runtime hooks (single damage path, exhausted and faint), real-time combat (6 archetypes, statuses), wild brain (temperaments, aggression gate, danger tuning), party (starters, Party Ball, owned brain, HUD), lives.

## Blockers
- none

## Done in M2
Capture (thrown balls, odds HUD, shakes, break-free enrage), growth (exp, levels, moves, bond, evolution with cinematic, stones, Link Cable), Sanctuaries (altar heal + respawn, ward, PC, shop, coins, potions), move command bar (Z cycles), status-move pass, Dread variants (night eldritch forms, shards, Umbral Ball). D-030, D-031.

## Next action
1. Owner playtest of M2. Owner decision pending: Cobblemon cries/ball sounds/ball models (D-031).
2. M3 (dread and atmosphere: fog, ambience, rare scares, graphics presets). Start with a Haiku shortcut scout. BACKLOG has M2 follow-ups.
3. Max 3 workers; one cross-mod verifier per wave.

## Notes
- 2026-10-12: the project moved to github.com/alakrim/Project-Minemon (full history), and the Godot prototype leftovers were removed.
- check.sh: luacheck, busted, Python tests, 9 integration suites (headless luantiserver). Screenshots: scripts/screenshot.sh (real client under Xvfb).
- Build: `bash scripts/build_windows.sh` (MINEMON_VERSION=Mx). Deliver the parts via SendUserFile, then device_commit_files (100 MB per call limit).
