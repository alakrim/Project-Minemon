# CRITIC: Minemon architecture

## BLOCKER (fix before building)

1. **No creature or save schema** (PLAN l.116). Missing CreatureInstance (uid, species, level, exp, IVs 0-15, stat_exp, bond, moves+PP, hp, ball, status), a `save_version` key, and migrations. Fix: add one schema block before M1.
2. **Damage/type contract is not Gen 2** (l.92, l.94-95, l.106). Gen 2 picks physical/special by type (Fire, Water, Grass, Ice, Electric, Psychic, Dragon special), not per move. Gen 2 has 17 types (Dark, Steel, no Fairy); `types.json` is undefined and `species.types` never states its element type. `Stats.calc` lacks stat_exp. `CombatantView` and `DamageResult` are undefined. Fix: state the rule, add types.json and stat_exp.
3. **Evolutions cannot express Gen 2** (l.105). Needs stat-based Tyrogue (Atk vs Def), time-of-day (Espeon/Umbreon), trade-holding-item (Slowking), and AND conditions (friendship AND day). Fix: `evolutions:[{to, conditions:[{method,value}]}]`, extended enum, before species.json is written.
4. **Mesher returns a render resource from a worker** (l.101). `ArrayMesh` is built off-thread, and `neighbours` passes live Chunks, which races with `set_block`. Fix: return packed-array MeshData from a copied snapshot; the main thread builds ArrayMesh and trimesh collision only within 1 chunk of the player.
5. **M0 gate is not reproducible** (l.122 "default view distance"; D-015 "4-chunk radius"; l.31 renderer "chosen by spike" vs invariant 6 hard-coding Compatibility). Fix: one benchmark spec: radius, vertical chunks, 720p, both renderers, 1% low fps, RAM, ms per chunk.

## MAJOR

6. **Pack loading untested until M2** (l.102). `load()` does not read runtime files in exports. Fix: GLTFDocument, Image.load_from_file, AudioStreamOggVorbis.load_from_file; test in the M0 export.
7. **Move `effect` too narrow** (l.106). No fixed damage, OHKO, multi-hit, drain, recoil, recharge, weather. M4's "every move maps to an archetype" fails. Fix: closed effect-op list; archetype drives VFX only.
8. **Missing contracts**: missions/dialogue (brief needs missions per town), RegionData, items and balls, blocks, `exp_for_level`, bond ranges. Fix: one-line schema each before M2.
9. **Milestone order** (l.45, l.121-129). M1 respawns at a Pokémon Center that arrives in M3. M3 bundles six systems. M4's result is "data validation 100%", not runnable (D-010). Fix: stub spawn in M1; split M3; M4 ends with an owner-visible species browser.
10. **Chunk draw calls unbudgeted** (l.100). 16³ chunks, radius 4, undefined vertical range means hundreds of draw calls on a 2021 driver. Fix: set vertical range, add a draw-call budget, consider greedy meshing.
11. **Haiku scope and checks** (l.123-126). Species validation checks shape, not values. Fix: value-check against a committed snapshot; Opus reviews threading and collision tasks; cap tasks at 3 files.

## MINOR

12. **Doc contradictions**: PLAN l.3 "awaiting Gate 1" vs l.58 "approved"; CONVENTIONS l.24 allows only CC0/CC-BY/OFL, yet GUT and Godot are MIT. Fix: one-line edits.
