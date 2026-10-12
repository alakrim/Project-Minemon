# S-13 shortcut scout: Cobblemon models, animation, capture and party

Scope: T-25a/b (Bedrock to glTF), T-25c (idle/walk), T-21b/T-22 (wild AI, party follow), M2 (capture, exp, evolution, party UI).

## Verdict

- **No existing Bedrock geo.json to glTF converter was found.** npm and PyPI have no `bedrock-model`, `bbmodel`, `geo2gltf`, `blockbench`, `mcblend` or `bedrock-geo` packages. GitHub search is blocked (HTTP 403), so discovery was limited to named repos. T-25a must be written by us.
- **Luanti 5.17 loads glTF natively** (`.glb` preferred). No Blender needed.
- **Pure-Python libraries cover the build:** `trimesh` for meshes, `pygltflib` for skins and animation channels, `molang` for baking.
- **Cobblemon's poser data gives the clip names** for idle, walk, sleep, fly, swim and faint (below).
- **Zoonami is a useful design reference** for capture chance, EXP curve and party storage. It has no evolution code.

## Table

| Shortcut | Saves | Licence | How reached | Use |
|---|---|---|---|---|
| kirbycope/cobblemon-bedrock (`main`) | 1977 geo.json, 2670 animation files, textures; `port.py` Molang fixers; `pose_audit.py` | MIT code; per-model CC non-commercial | `git clone --depth 1 https://github.com/kirbycope/cobblemon-bedrock.git` | Data source; no glTF code in it |
| gitlab.com/cable-mc/cobblemon (`main`) | 758 poser JSON files: clip names per pose | MPL-2.0 code; asset licence not stated at root | `git clone --depth 1 https://gitlab.com/cable-mc/cobblemon.git` (worked, 33k files) | Read data only |
| PyPI `trimesh` 5.1.1 | Cube meshes, GLB export | MIT | `pip download --no-deps trimesh` | Mesh build |
| PyPI `pygltflib` 1.16.5 | Joints, skins, animation samplers | MIT (LICENSE file in wheel; not printed) | `pip download --no-deps pygltflib` | glTF writer |
| PyPI `molang` 1.0.1 | Baking `q.`/`v.` expressions | MIT | `pip download --no-deps molang` | Bake clips |
| npm `molang` 2.0.1 | Same, JS | MIT | `npm view molang` | Alternative |
| npm `three` 0.186.1 | GLTFExporter with animation tracks | MIT | `npm view three` | JS fallback |
| npm `@gltf-transform/cli` 4.5.1 | Dedupe, prune, weld, texture resize | MIT | `npm view` | Shrink output |
| npm `gltf-pipeline` 4.3.1 | Same, alternative | Apache-2.0 | `npm view` | Alternative |
| Luanti glTF loader (`.tools/luanti`, `irr/src/CGLTFMeshFileLoader.cpp`, `doc/lua_api.md` ~L380-440) | Runtime loader, skinned animation | LGPL (Luanti) | Local | Target format |
| luanti-org/modtools (`main`) | `gltfutil.py` strips or extracts embedded images | Not checked | `git ls-remote` ok | Optional |
| TenPlus1 mobs_redo (codeberg `tenplus1/mobs_redo`) | `follow_holding`, owner, tamed, `follow_target` | MIT code; media MIT (ContentDB) | `git clone --depth 1 https://codeberg.org/tenplus1/mobs_redo.git` | Follow and owner reference |
| isaiah658 Zoonami (codeberg `isaiah658/zoonami`) | Capture formula (`battle.lua:701`), EXP milestone (`backpack.lua:380`), party storage | MIT code; media CC-BY-SA-4.0 | `git clone --depth 1 https://codeberg.org/isaiah658/zoonami.git` | Design reference |
| m16b/m16b_creaturesworld (ContentDB) | Creatures and capture balls | GPL-3.0-only | No repo link; not inspected | Avoid copying code |

## How to use

1. **Luanti format check.** `lua_api.md` says: nodes with matrix transforms must not be animated, so convert Bedrock bones to TRS. `CUBICSPLINE` is unsupported. Only base-colour textures work. Buffers must be embedded or in `.glb`. Time is in seconds, so set animation speed 1.0.
2. **Converter (T-25a).** Walk the geo.json bones, add cubes (inflate, mirror, pivots, rotations), emit `.glb`. Port the NaN and Molang fixes from `port.py`. Bake animation.json with `molang` at 20 fps.
3. **Procedural parts.** Cobblemon's `q.look`, `q.pitch_tilt`, `q.biped_walk`, `q.quadruped_walk` and `q.sine_wing_flap` are not Bedrock clips. `poses.py` `to_bedrock()` turns them into generated clips. It reads `ROOT/java/common/...`, so symlink `java` to the Cobblemon clone to run it.
4. **Clip mapping for T-25c.** Idle: `ground_idle` (771 uses), `battle_idle`, `water_idle`. Walk: `ground_walk` (466), `ground_run`. Sleep: `sleep` (443). Fly: `air_fly`, `air_glide`. Swim: `water_swim`. Faint: `faint` (a `bedrock_primary` clip, 172 uses). Quirks: `blink`, `cry`.
5. **Capture, EXP and party (M2).** Use Zoonami's `next_level^2 * exp_per_level` milestone and its taming chance (health, level, rarity). Copy the logic, not the code or media, unless we accept CC-BY-SA. Use mobs_redo's owner and follow model for the party.

## Caveats and asks

- **Licence.** Cobblemon's asset licence is not stated at the repo root. D-029 covers the kirbycope CC non-commercial terms. Keep the attribution and credits pipeline.
- **New dependencies.** `trimesh`, `pygltflib` and `molang` are new Python dependencies. The brief must permit them before T-25a. Otherwise use `three` in Node.
- **Still open.** Verify the `pygltflib` licence text and the modtools `gltfutil.py` licence.
