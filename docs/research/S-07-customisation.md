# S-07 — What we can change without compiling (Cobblemon)

**Version:** Cobblemon **1.8.1** (2026-09-12), **Minecraft 1.21.1**, Fabric. Items marked *unverified* need a test world.

## 1. Spawn control — yes (data). Confidence: high keys, medium species filter.
- `data/<ns>/spawn_pool_world/*.json`: `enabled`, `spawns[]` with `id`, `pokemon`, `presets`, `type`, `context`, `bucket` (common/uncommon/rare/ultra-rare), `level` (`"5-32"`), `weight` (about 0.1–10), `condition`, `anticondition`.
- Conditions: `biomes` (ids or `#tags`), `dimensions`, `timeRange` (`day`/`night` or tick ranges), `isRaining`, `isThundering`, `moonPhase` (0–7), `minSkyLight`, `minX`…`maxZ`, `structures`, `neededBaseBlocks`.
- Level curves by region: coordinate bounds tile the map into bands (no distance key).
- Kanto+Johto only: a later datapack filters out `cobblemon` `spawn_pool_world/.*` (`pack.mcmeta` `filter`), then ships our Gen 1–2 files.
```json
{ "enabled": true, "spawns": [ { "id": "minemon-rattata-1", "pokemon": "rattata", "presets": ["natural"],
  "type": "pokemon", "context": "grounded", "bucket": "common", "level": "3-6", "weight": 6.0,
  "condition": { "biomes": ["#cobblemon:is_forest"], "timeRange": "night" } } ] }
```

## 2. Wild behaviour — partly. Confidence: medium.
- Species `behaviour` covers movement and sleep only. No attack key.
- Native 1.8 Alphas are "more aggressive" and fight back. Unprovoked attacks: *unverified*.
- **CobblemonBehaviours** (Fabric, 1.21.1, code, `config/cobblemonbehaviours.json`): aggressive wild Pokémon hunt players within 16 blocks. No "party empty" gate. 1.8.1 compatibility unverified.
- "Attack only when no Pokémon is out" needs code.

## 3. Capture rules — partly. Confidence: medium.
- Per-species `catchRate` in `data/<ns>/species/...` (example 100). Data-driven.
- Per-ball multipliers are formula constants on the wiki (Poké 1×, Great 1.5×, Ultra 2×). No datapack key found.
- "Defeat first" or HP-gated capture: no data key. Needs code.
- **Catch Ball Rules** (Java, Cobblemon 1.7.3 to below 1.8.0) restricts species to listed balls. Not for 1.8.1.

## 4. Big/eldritch Pokémon — yes for size and stats. Confidence: medium-high.
- **Native 1.8 Alphas**: bigger, lead herds, `alpha=true` spawn entries, `alpha_eyes` glow, size 1.1×–1.8×, +4 to +20 levels. Config keys: *unverified*.
- Species `baseScale` and `hitbox`; `/reload` does not refresh Cobblemon data.
- **CobbleBoss** (1.21.1, paid team bosses): `data/cobbleboss/bosses/*.json`, `random_configs.scale` for giants. Cobblemon version not stated.
- **Cobblemon Alpha Project** (built for 1.7.3): `alphaSizeModifier` 2.0. Overlaps native Alphas; pick one.
- Boss bar: vanilla `bossbar`; a function must set its value.

## 5. NPCs and missions — partly. Confidence: low-medium.
- Dialogue: datapack JSON opened by `/opendialogue`; pages and option actions.
- Flows: `data/cobblemon/flows/battle_victory/*.json` (path seen in a community datapack). Schema: *unverified*.
- MoLang (server): `q.player.data()` is a persistent per-player store (quest flags, `save_data()`). `run_command(command)` can run `give`. Also `party()`, `pokedex()`, `in_battle()`, `teleport()`.
- Feasible: "go there", "deliver item", flags. "Catch X" and "defeat Y" hooks unconfirmed.
- Mods: **KantoNPCs** (Java, 1.7.1+; config text dialogue). **Cobblemon Quests** (FTB Quests bridge). Unverified on 1.8.1.

## 6. Lives / permadeath — yes (vanilla). Confidence: high mechanics, medium Cobblemon interaction.
- Criterion `deathCount` counts deaths per player, so it works in multiplayer.
- `scoreboard objectives add deaths deathCount`; `scoreboard objectives setdisplay sidebar deaths`.
- `data/minecraft/tags/function/tick.json` (`{"values": ["minemon:lives"]}`); `lives.mcfunction`: `execute as @a if score @s deaths matches 4.. run gamemode spectator @s`.
- Operators can reverse gamemode. Test respawn interplay.

## 7. Difficulty knobs — partly. Confidence: medium.
- `config/cobblemon/main.json` (wiki may lag 1.8): `experienceMultiplier` (2), `maxPokemonLevel` (100), `shinyRate` (8192), `battleWildMaxDistance` (12), `defaultFleeDistance` (32; -1 blocks fleeing), `captureCalculator`. 1.8 adds `awardExperienceOnBattleLoss` and a per-world spawn disable.
- Battle AI level: no key found; use spawn and NPC levels.
- Vanilla: `/difficulty hard`, gamerule `keepInventory`.

## 8. Atmosphere — yes. Confidence: high biome keys, medium Cobblemon sounds.
- Biome JSON `data/<ns>/worldgen/biome/*.json`, `effects`: `fog_color`, `water_fog_color`, `sky_color`, `ambient_sound`, `mood_sound`, `additions_sound`, `music`. Removed in 1.21.11, so valid on 1.21.1. Fog density: not settable.
- Custom sounds: `assets/<ns>/sounds.json` plus `.ogg`.
- Giant proximity: tick function with `execute as @a at @s if entity @e[type=cobblemon:pokemon, distance=..20]` and `effect give @a minecraft:darkness`. Entity id and alpha filter: *unverified*.

## Recommendation
- Text now: spawns (1), lives (6), atmosphere (8), difficulty config (7), native Alphas (4).
- Prototype missions (5) with flows and MoLang on a test world.
- Code or existing mod: capture gating (3) and empty-party hunting (2). Small Java add-on per D-022 fallback (b) if mods fail on 1.8.1.

## Sources
wiki.cobblemon.com (spawns, behaviour, species, config, dialogues, MoLang, 1.8.0); api.modrinth.com; cobbledex.info; mod pages (CobblemonBehaviours, Catch Ball Rules, KantoNPCs, CobbleBoss, Alpha Project); minecraft.wiki (Pack.mcmeta, Biome definition, Scoreboard).

## Open questions
1. Native 1.8.1 Alpha config keys; do they attack unprovoked?
2. Flow schema, NPC class paths, any "catch X" or "defeat X" trigger.
3. Do CobblemonBehaviours, KantoNPCs, CobbleBoss and Alpha Project load on 1.8.1?
4. Data and resource `pack_format` for 1.21.1 (believed 48 and 34).
