# S-09 — Luanti base game and reusable mods (2026-10-10)

## Findings

Access (tested today): `git clone` and `git ls-remote` work for most public GitHub repos; apt works; the ContentDB list API works (`content.luanti.org/api/packages/?q=`) but omits licences and its per-package endpoint errored. Codeberg is blocked for WebFetch (robots) and for the shell, so Codeberg-hosted mods were read through Guix and Debian metadata. S-05's note that GitHub is blocked is out of date.

Engine: the latest GitHub tag is 5.17.0 (5.14.0 exists too). Ubuntu noble ships only 5.6.1, so a headless 5.14+ server needs a source build from the tags.

**Base games**

| | Minetest Game | VoxeLibre | Mineclonia |
|---|---|---|---|
| URL tested | github.com/luanti-org/minetest_game (HEAD c42e4d0) | github.com/VoxeLibre/VoxeLibre (HEAD 4492ce6) | codeberg.org/mineclonia/mineclonia; no GitHub mirror found |
| Last activity | 2026-08-16 | 2026-09-15 | 2026-10-10, v0.123.1 |
| Code / media licence | LGPL-2.1 / CC BY-SA 3.0, original art | GPL-3.0 / textures from Pixel Perfection (Minecraft resource pack), CC BY-SA 4.0 | GPL-3.0 / Minecraft-derived lineage, not verified |
| Size (shallow clone) | 20.7k Lua lines, 34 mods, 448 PNG, 11 MB | 140k Lua lines, 233 mods, 2,907 PNG, 122 MB | not cloned |
| Mobs | none | mcl_mobs (Mobs Redo fork, MIT); capture disabled | same lineage |
| Villages / structures | mapgen dungeons only | mcl_villages, structures, strongholds, raids, zombie sieges | same |
| Weather / sky | weather mod (rain, snow, MIT); engine day/night | mcl_weather (rain, snow, lightning), mcl_moon | same |
| Sound / HUD | env_sounds, fireflies; default HUD | vl_cavesounds, vl_hudbars, hunger, sprint | same |
| Min Luanti | not checked | 5.7 (ContentDB) | 5.10 (Codeberg) |
| Low-end / Android evidence | none; lightest code | none; README states a "performant" goal only | none |

**Mods**

| Mod | Use | Licence (code / media) | Last commit | Reached via |
|---|---|---|---|---|
| Mobs Redo (TenPlus1 "mobs") | mob API: monster/animal/npc types, passive flag, attack_type, feed_tame, capture_mob with hand/net/lasso chance, spawn limit; no hard deps | Expat / CC0, CC-BY-3.0 (Debian) | Debian 1.56 (2021); upstream on Codeberg | apt-get download minetest-mod-mobs-redo |
| Creatura (ElCeejo) | modern API: pathfinding, boids, animation, ABM spawn, punch, follow-items; no combat AI | MIT / not checked | 2025-12-25 | git OK |
| Animalia (ElCeejo) | animals on Creatura | MIT / not checked | 2026-03-04 | git OK |
| Stalker (adikalon) | scary cave monster; needs Mobs | MIT / not checked | 2024-10-29 | git OK |
| Banshee, Wisp (ElCeejo) | eerie mobs | MIT / not checked | 2021 | git OK |
| Grave (ElCeejo) | eerie biome; needs mobkit, mob_core | GPL-3 | 2020-10-28 | git OK |
| Scary Ambience (StarNinjas) | night and cave scares | GPL-3 / not checked | 2022-10-24 | git OK |
| Ambience (TenPlus1) | ambient sound API | not verified | ContentDB only | none |
| HUD Bars (Wuzzy) | HP and breath bars | MIT / CC BY-SA 3.0 icons | 2026-03-31 | zff.dev page only |
| Quests (TeTpaAka) | quest framework for town missions | MIT / CC BY 3.0 | 2025-03-22 | git OK |
| Simple Dialogs (Kilarin) | NPC dialogue from text | MIT / not checked | 2025-04-01 | git OK |
| NPC Core (8a7l) | NPC dialogue, trade, teleport; depends default | GPL-3 / not checked | 2026-09-18 | git OK |
| mg_villages (Sokomine) | village generator | no licence stated: all rights reserved | 2023-07-11 | git OK; reference only |
| Creatures World (m16b) | three evolution lines; CaptureBall, God CaptureBall; XP in progress | not stated | ContentDB only | source not found |

No Pokémon mod exists on ContentDB: the "pokemon" search returned zero packages. Engine settings on master include dynamic shadows, bloom, auto-exposure, water reflections and fog. Volumetric light was not found in the settings file, so do not depend on it.

## Recommendation

**Base: Minetest Game** (`luanti-org/minetest_game`). It is the only candidate that is not Minecraft-derived, and the lightest for a 6 GB Vega 8 and Android. VoxeLibre saves the most work (villages, mobs, lightning, sieges, HUD), but it carries 14x the Lua and textures derived from a Minecraft resource pack. That conflicts with the Mojang-asset exclusion (S-05, D-021). Keep VoxeLibre as the fallback only if the Vega 8 gate fails and we accept replacing its textures.

**Vendor (licence-compatible):** Mobs Redo (Expat), Quests (MIT), Simple Dialogs (MIT), HUD Bars (MIT plus CC BY-SA icons), Scary Ambience (GPL-3) and Stalker (MIT) as a cave-monster template. Creatura is the modern alternative to Mobs Redo; choose one.

**We write ourselves:** species data and the capture-after-defeat gate (Mobs Redo capture is chance-only); real-time combat; levels and bond; the aggression rule "only when no Pokémon is out"; lives and permadeath; the eldritch tier; villages and towns (mg_villages needs permission or we place schematics ourselves); Pokéball items and odds; procedural stand-in creatures; the night, fog and sound pass; the texture atlas (D-021).

## Confidence
- Licences where a LICENSE file was read from a GitHub clone, or Debian copyright was read: high.
- Activity: medium (commit dates only).
- Mobs Redo upstream: medium (Debian 2021 copy only).
- ContentDB-only mods: low (licences not returned).
- Performance on Vega 8 or Android: low (nothing measured).

## Sources
- git ls-remote and shallow clones: github.com/luanti-org/luanti, luanti-org/minetest_game, VoxeLibre/VoxeLibre, Mineclone2/Mineclone2, ElCeejo/creatura, ElCeejo/animalia, ElCeejo/grave, ElCeejo/banshee, ElCeejo/wisp, TeTpaAka/quests, mt-mods/mobkit, mt-mods/mob_core, 8a7l/npc_core, Kilarin/simple_dialogs, SFENCE/advanced_fight, StarNinjas/scary_ambience, adikalon/stalker, Comet712/lategame_amulets, Sokomine/mg_villages (commit 11dbd55)
- ContentDB list API: content.luanti.org/api/packages/?q=pokemon, capture, pet, tame, monster, mobs, hud, weather, ambience, npc, lightning, hardcore, ball, shader, fog, quest, village, town
- Codeberg (WebFetch): codeberg.org/mineclonia/mineclonia (page text only)
- Debian copyright and docs: apt-get download minetest-mod-mobs-redo, -throwing, -nether, -ethereal, -3d-armor, -unified-inventory, -protector
- Guix: packages.guix.gnu.org/packages/luanti-mobs-monster, luanti-mobs-animal
- Luanti docs: docs.luanti.org/for-creators/mobile/
- Engine settings: raw.githubusercontent.com/luanti-org/luanti/master (builtin/settingtypes.txt, minetest.conf.example)

## Open questions
1. Target Luanti version: the brief says 5.14, but 5.17.0 is the latest tag. Which pin?
2. Permission from Sokomine for mg_villages, or should we write our own village placer?
3. Mobs Redo upstream is on Codeberg, which the shell cannot reach. Vendor the Debian 2021 copy, or find a GitHub mirror?
4. Do Mobs Redo and Quests load on Luanti 5.14 or 5.17? Needs a headless smoke test.
5. Who owns Creatures World, and what is its licence?
6. Does Minetest Game pass the Vega 8 performance gate? Needs measurement.
