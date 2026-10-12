# S-15 M2 wave 2 shortcut scout

Scope: read-only. Nothing downloaded or copied into the repo. Local checks used `.tools/` (git-ignored). Outside checks: content.luanti.org, a GitHub mirror, WebSearch. GitHub search is blocked.

## Verdict table

| Shortcut | Value | Licence | Path | Verdict |
|---|---|---|---|---|
| Cobblemon cries `sounds/pokemon/NNNN_name/cry.ogg` | 247 of 251 species, mono | none stated (Game Freak audio) | `.tools/cobblemon-bedrock/development_resource_packs/cobblemon/sounds/pokemon/` | Blocked: owner decision (hard content rule) |
| Cobblemon ball SFX `sounds/poke_ball/*.ogg` | 30 mono 44.1 kHz | none stated | same, `sounds/poke_ball/` | Blocked: owner decision |
| Kenney Interface Sounds (Calinou mirror) | 100 UI sounds | CC0 1.0 | github.com/Calinou/kenney-interface-sounds | Adopt for throw, shake and catch UI |
| Cobblemon ball geo `models/entity/poke_ball/poke_ball.geo.json` (+ textures, 48 item PNGs) | 3D ball | none stated | same, `models/entity/poke_ball/`, `textures/items/poke_balls/` | Defer: owner decision |
| Our `tools/gen_icons.py` ball icons | poke_ball, great, ultra, master | ours | `tools/gen_icons.py` | Keep (already done) |
| Luanti `get_player_control()` | edge-free key state | MIT (Luanti) | `.tools/luanti/src/script/lua_api/l_object.cpp:1804` | Adopt |
| Luanti `get_wield_index()` plus hotbar keys 1-9 | move selector | MIT | `l_object.cpp:321`, `defaultsettings.cpp:188` | Adopt (read-only on server) |
| `hud_add` ability bar | 4-slot bar | ours | `mods/minemon/minemon_party/ui.lua:53` | Adopt |
| VoxeLibre `CORE/controls` press edges | edge detection | LGPL-2.1 | `.tools/voxelibre/mods/CORE/controls/init.lua` | Pattern only; write our own |
| hudbars (Wuzzy) | HP-style bars | MIT (media unstated) | content.luanti.org/packages/Wuzzy/hudbars | Skip (not needed) |
| K Wider Hotbar | more hotbar rows | GPL-3.0+ | content.luanti.org/packages/ketwaroo/k_wider_hotbar | Reject (GPL, not needed) |
| `set_texture_mod` with `^[multiply`, `^[brighten`, `^[colorize` | Dread tint, per entity | Luanti docs | `lua_api.md:822,960,998`; VoxeLibre `mobs_mc/wither.lua:160` | Adopt |
| Entity `glow` | self-lit eyes | Luanti docs | `lua_api.md:10149`; VoxeLibre `mobs_mc/stalker.lua:253` | Adopt on an eye sprite |
| `add_particlespawner` with `attached` | smoke follows creature | Luanti docs | `lua_api.md:12255`; `mcl_sprint/init.lua:186`, `mcl_playerplus/init.lua:732` | Adopt |
| Entity light emission | none in engine | n/a | n/a | Reject; use an invisible light node if world light is needed |

## 1. Cobblemon audio and ball visuals

- Cries: 900 `cry.ogg` files plus 903 `ambient.ogg`. Dex 1..251 coverage is 247. Missing: 243, 244, 245, 251 (no folder).
- Format: every cry is mono Vorbis (637 at 44.1 kHz, 263 at 48 kHz). Mono is right for positional sound: `playing_sound.cpp:232` sets a world position, and OpenAL spatialises mono buffers only (OpenAL spec).
- Ball and other sounds: `sounds/poke_ball/`, `sounds/evolution/`, `sounds/pc/`, all mono. The 15 stereo files are GUI, ride loops and one NPC set.
- Mapping: `sounds/sound_definitions.json` (2201 keys, for example `cobblemon.bulbasaur.cry`).
- Licence: no licence file in any sound folder. The 529 `models/entity/*/license` files are CC BY-NC legal code (no ShareAlike, no NoDerivatives). The repo root LICENSE is MIT for code only.
- Importer reuse: `tools/cobblemon_import.py` has `choose_geometry` (line ~839), `build_model` (279) and `write_glb` (420). `discover()` takes only NNNN_ folders, so a ball converter calls `build_model` and `write_glb` directly with an empty `tracks` list and an identity rest.

Verdict: D-029 covers Pokémon models only. Cries and ball models have no owner directive, and CLAUDE.md forbids Pokémon sounds. Do not import them. Use the CC0 Kenney sounds for ball UI, and keep our generated ball icons.

## 2. Manual move selection

- `get_player_control()` returns up, down, left, right, jump, aux1, sneak, dig, place, zoom, plus the LMB and RMB aliases and movement_x/y. Default keys: aux1 = E, zoom = Z, hotbar next N, previous B (`defaultsettings.cpp:144-162`).
- No press callback exists in 5.17. Detect edges in `register_globalstep` by storing the previous state per player.
- `get_wield_index()` is 1-based and read-only on the server. The client changes it with keys 1-9 or the mouse wheel. Mods cannot force it.
- The hotbar can show up to 32 slots (`HUD_HOTBAR_ITEMCOUNT_MAX`).

Recommendation: while a creature is out, hotbar slots 1-4 pick moves (the wield index is read each tick), a `hud_add` bar draws the four moves, and aux1 (E) fires. Keep the Party Ball in slot 5 or later during combat, because the held item changes with the slot.

## 3. Dread variants

- Texture mods are set per entity at runtime. Use `^[colorize` for the dark tint and `^[multiply` for the flicker. Reset with `""`.
- Glow eyes: `glow` adds light to the texture only. It does not light the world. Put a small eye sprite on the creature with `set_attach` and `glow = 14`.
- Smoke: `add_particlespawner` with `attached = ObjectRef` follows the creature.
- World light: entities cannot emit it. For a real lit patch, use an invisible light node near the creature.

## Asks

- **Owner (blocking for cries and ball models):** may we import Pokémon cries and Poké Ball 3D models? Recommended: no. M2 uses the CC0 Kenney sounds and our generated icons.
- **Opus:** approve the hotbar move selector and the Party Ball slot rule as a D-entry.
