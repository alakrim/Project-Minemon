# S-14 M2 shortcut scout: capture, growth, healing, party UI

Scope: M2 (balls and catch rate, capture after defeat, party and PC UI, exp and levels, evolution, Pokémon Center healing, shop). Read-only. Nothing was downloaded, copied or committed. GitHub search is blocked (HTTP 403). WebSearch returned no usable Luanti capture mod.

## Verdict

- **No reusable Luanti capture, evolution or PC mod was found.** Our capture, exp and evolution code has to be written. Reuse VoxeLibre's public APIs and patterns, and keep attribution where a pattern is copied.
- **Cobblemon (local clone, HEAD 52dacb0) is MPL-2.0 code with an unstated asset licence.** Use it for design and data facts only.
- **Owner decision needed before any import.** Poké Ball models and textures, capture sounds and Pokémon cries are Nintendo/Game Freak assets. CLAUDE.md's hard content rule forbids them. D-029 covers creature models, not balls or cries. Recommended: project-owned primitive balls (like `gen_standins.py`) and synthesised sounds.

## Table

| Shortcut | M2 value | Licence | Where | Verdict |
|---|---|---|---|---|
| Cobblemon `common/.../pokeball/catching/calculators/*.kt` (Gen1 to Gen9, `BattleCaptureAction.kt`) | Catch formula variants, shake count, critical catch | MPL-2.0 | `.tools/cobblemon-java` | Design reference. Implement from the public formula (Bulbapedia link in the Gen6 file header) |
| Cobblemon species JSON `common/src/main/resources/data/cobblemon/species/**` (1207 files) | catchRate, experienceGroup, baseExperienceYield, evolutions, baseScale, hitbox | MPL-2.0 data; values are facts | local | Our `species.json` already has catch_rate, growth_rate, base_exp and evolutions (113 species). Use baseScale and hitbox only through a one-off extract script, if sizes need fixing |
| Cobblemon evolution schema (`pokemon/evolution`; 528 level_up, 65 item_interact, 26 trade; requirements include level, held_item, friendship, time_range, has_move, biome, negate) | Richer evolution conditions | MPL-2.0 | local | Schema reference. Ours is `{conditions:{min_level}, to}`, so plan a `requirements` list |
| Cobblemon ball models, textures, particles (`client/render/models/blockbench/pokeball`, `particles/balls/*`) | 3D balls and shake effects | Nintendo design; asset licence not stated | local | **Do not import.** Build primitive balls |
| Cobblemon cries (`sounds/pokemon/*/*_cry.ogg`) | Cries | Nintendo/Game Freak audio | local | **Do not import** |
| Cobblemon PC and healer blocks (`models/block/pc*.json`, `blockstates/pc.json`) | Healing machine shape | MPL-2.0 assets; not stated | local | Design only. Build our own |
| VoxeLibre `mcl_beds` plus `mcl_spawn` (`mcl_spawn.set_player_spawn_pos(player, pos, true, true)`, called from `functions.lua:88`) | Pokémon Center respawn checkpoint | mcl_beds MIT; VoxeLibre root GPL-3.0 | `.tools/voxelibre` (a523240) | Call the public function from our healer node. Do not copy code |
| VoxeLibre `mcl_throwing` (`get_player_throw_function`, `ender_pearl.lua` collide pattern) | Ball throw | MIT (README) | local | Call the API, or copy the pattern with attribution |
| VoxeLibre `mcl_mobs` (`tamed` flag, owner checks) | Owned flag | MIT (license.txt) | local | Reference only. T-22 owns the logic |
| VoxeLibre `mcl_experience` (`add_xp`, `register_on_add_xp`) | Player XP only | GPL-3.0 | local | Do not use for creature exp. Exp belongs in the instance |
| VoxeLibre `mcl_title` (`layout`, `defaults`) | Capture and level-up messages | No licence file found; VoxeLibre root GPL-3.0 | local | Optional |
| VoxeLibre `mcl_chests` (formspec), `mobs_mc/villager.lua` (trade) | PC box, party and shop formspec patterns | LGPL-2.1; GPL-3.0 | local | Pattern only |
| tenplus1 `mobs_redo` (Codeberg), isaiah658 Zoonami (Codeberg) | Follow and owner; capture formula and exp milestone | MIT code; Zoonami media CC-BY-SA | S-13 | Already listed in S-13. Zoonami stays a design reference |

## How to use

1. **Capture:** write `catch_chance` from the public Gen 3+ formula, matching the PLAN contract. Use the Cobblemon calculators only as a cross-check.
2. **Healing checkpoint:** a healer node calls `mcl_spawn.set_player_spawn_pos`. Test that respawn still works with `enable_bed_respawn` off, since that setting gates the bed code path.
3. **Evolution:** move `species.json` evolutions to a `requirements` list that matches the Cobblemon variants we need (level, held_item, friendship, time_range, has_move). Record the change in a D-entry.
4. **Shop and PC:** build formspecs from our own code, using the VoxeLibre chest layout as a pattern only.

## Asks

- **Owner (blocking for balls and cries):** may we use Nintendo-derived ball models and cries? Recommended: no. The M2 balls then use primitives and synth sounds.
- **Owner or Opus:** trade evolution "via link cable" needs a second player, and multiplayer is M6. Choose an NPC trade for M2, or defer the mechanic to M6.
- **Opus:** approve the `species.json` evolution schema change as a D-entry.
