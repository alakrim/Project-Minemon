# S-11 Creatures pipeline (Luanti 5.14)

Research only. No models, textures, sprites or sounds were created, downloaded or copied.

## Findings

1. **Model formats (verified in luanti-org/luanti 5.14.0 doc/lua_api.md).** Entity and mesh visuals accept `.x`, `.b3d`, `.obj`, `.gltf`, `.glb`. glTF was added in 5.10. Only one animation clip per file is supported, and frame ranges select sub-animations (`set_animation({x=a, y=b}, fps, blend, loop)`). glTF limits: base-colour textures only, no embedded images, no URI references, no CUBICSPLINE, no animating or bone-overriding matrix-transform nodes. Textures come from the entity `textures` property, not from the file. glTF scale is 10 units = 1 node. `visual_size` has no documented cap; collision boxes are separate.
2. **Bones.** `set_bone_override(bone, {position, rotation (radians), scale, interpolation})` works on mesh visuals with bones (clients before 5.9 only honour absolute values).
3. **Runtime media.** `core.dynamic_add_media({filename, filedata, ephemeral})` accepts model files as in-memory strings, so Lua can push a generated model with no file writes and no insecure environment. Limits: not persisted across restarts, a name can be added only once, and a non-ephemeral file must not change afterwards. `filepath` is read by the engine. Whether `core.safe_file_write` or `filepath` accept paths outside the world folder is unverified.
4. **Cobblemon format (docs only).** Bedrock `.geo.json`: `minecraft:geometry[]`, `description.texture_width/height`, `bones[]` with `name`, `parent`, `pivot`, `rotation`, and `cubes[]` with `origin`, `size`, `uv` (box or per-face), `inflate`, `mirror`. `.animation.json` uses keyframes, and Molang expressions are unsupported by Mcblend's converter. Cobblemon's mod code is MPL-2.0, but that licence statement does not cover assets. The Cobblemon wiki and repo were unreachable from here, so the resource layout is unconfirmed.
5. **Converter.** Geometry (bones to glTF nodes, cubes to quads, UV mapping, scale and axis fix) is about 300 lines of Python. Keyframe animation is about 200 more. Molang needs a subset evaluator or baking, about 300 lines. A Lua converter is feasible but worse: it needs `request_insecure_environment` (owner must list the mod in `secure.trusted_mods`), and LuaJIT has no `string.pack` for binary `.glb`.
6. **Data.** PokeAPI CSVs are reachable via raw.githubusercontent.com (HTTP 200). The GitHub API is blocked by the proxy. Our `species.json` maps directly: `capture_rate`, `gender_rate` (as `gender_ratio`), `base_experience` (as `base_exp`). Pidgey checks out (255, 4, 50). Gen 2 sources: `pokemon_species` (251 rows, `capture_rate`, `gender_rate`, `growth_rate_id`, `evolves_from_species_id`), `pokemon` (`base_experience`), `pokemon_stats` + `stats` (ids 1-6; Gen 2 had a single Special, so `spa`/`spd` needs a decision), `pokemon_types` + `types`, `pokemon_moves` (version_group 3 = gold-silver, 4 = crystal; method 1 = level-up; 4420 Gen 2 level-up rows for species 1-251), `moves` (current values only), `pokemon_evolution` (677 rows), `evolution_chains`, `growth_rates` (formulas), `pokemon_species_names` and `pokemon_species_flavor_text`, and `type_efficacy` (modern chart, needs filtering to Gen 2).
7. **Existing mods.** Zoonami (content.luanti.org/packages/isaiah658/zoonami): 50+ 2D monsters with a battle system. Its page does not describe capture, and the licence file was not read. Poke Ball (Java, CC0) is a Minecraft mod and only useful as a concept. mobs_redo and petz could not be fetched, so they are unverified.

## Recommendation

- **Stand-ins:** a committed stdlib-only Python tool (`tools/gen_standins.py`) writes one `.glb` per body plan (`quadruped`, `avian`, `blob` today). Each has 3-4 bones and one clip whose frame ranges are idle, hop and walk. Colour comes from one shipped white PNG plus `^[colorize:#rrggbb` per type. This is our own procedural geometry, and it needs no runtime generation.
- **Owner packs:** an offline Python converter (`tools/pack_convert.py`) turns the owner's Bedrock files into `packs/<pack>/<species>.glb`. Lua only loads `.glb`. Owner-supplied files are never committed.
- **Fallback (no pack):** the stand-in with a procedural bob. A child entity is attached to an anchor, a sine offset is applied in `on_step`, and a hop impulse plays while moving.
- **Capture:** write our own ball item and catch formula, using `capture_rate` from PokeAPI.

```lua
obj:set_properties({visual = "mesh", mesh = "mm_avian.glb",
    textures = {"mm_white.png^[colorize:#c8a030:255"}, visual_size = {x = 1, y = 1}})
obj:set_animation({x = 1, y = 30}, 15, 0.2, true) -- idle range, looped
```

## Confidence

- High: Luanti format, animation and `dynamic_add_media` facts (read from the 5.14.0 doc).
- Medium: converter size estimates.
- Low: Cobblemon asset layout and licence (unreachable).
- Low: existing-mod reuse (only Zoonami page read).

## Sources

- https://raw.githubusercontent.com/luanti-org/luanti/5.14.0/doc/lua_api.md
- https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/ (types, pokemon_species, pokemon_moves, version_groups, growth_rates and others)
- https://learn.microsoft.com/en-us/minecraft/creator/reference/content/schemasreference/schemas/minecraftschema_geometry_1.12.0
- https://mcblend.readthedocs.io/en/latest/limitations/
- https://modrinth.com/mod/cobblemon (MPL-2.0 statement)
- https://content.luanti.org/packages/isaiah658/zoonami/
- https://modrinth.com/mod/poke-ball

## Open questions

1. Can `dynamic_add_media` `filepath` or `core.safe_file_write` reach paths outside the world folder without an insecure environment? Test in the M0 spike.
2. What units does `set_animation` use for glTF frame ranges (indices or seconds)? Test with a generated clip.
3. Do Gen 2 move values (power, accuracy, PP) differ from the current PokeAPI values, and do the JSON `past_values` cover this?
4. Is the owner's pack licence compatible with private use? (Owner's decision.)
5. Zoonami's licence and capture code: read LICENSE.txt before any reuse.
