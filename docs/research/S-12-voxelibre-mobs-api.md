# S-12: VoxeLibre 0.92.3 mob API digest

Paths are relative to `.tools/voxelibre/mods/`. `mcl_mobs` = `ENTITIES/mcl_mobs/`. Read-only source check.

## Gotchas (read first)
1. Health is custom: mobs keep `self.health`; the engine HP is never updated (only `ENTITIES/mcl_mobs/breeding.lua:61`). `get_hp()` checks (`combat.lua:927`) do not detect mob death.
2. Avoid `mcl_mobs.custom_biomecheck`: its id counter never increments (`spawning.lua:550,557-558`), so all custom biomes get id 0 and share the spawn-list cache (`spawning.lua:801,1001`).
3. A projectile with no `damage_groups` passes `0` as damage groups (`ITEMS/vl_projectile/init.lua:522,527`) and errors in `combat.lua:576` (`pairs(0)`). Always pass a table. Snowballs do no damage to mobs (`combat.lua:579`).
4. No capture: `mcl_mobs:capture_mob` is a stub returning false (`breeding.lua:19-21`).
5. `mobs_mc` is a hard dependency of many mods (e.g. mcl_farming, mcl_raids). Disable its spawns by setting, not by removing it.

## 1. `mcl_mobs.register_mob(name, def)` (`init.lua:115`)
Requires `spawn_class` (`:116`). Raw def fields:
- **HP:** `initial_properties.hp_min/hp_max` (defaults 5/10), scaled by `mob_difficulty` (`:124-130,208-209`). Rolled at activation (`api.lua:216`).
- **Armor:** default 100 (`:242`); table form allowed, `immortal` forced (`api.lua:229-238`). Damage taken = sum of group dmg x armor[group]/100 (`combat.lua:576-580`).
- **Numbers:** `damage` (`:232`), `reach` 3 (`:277`), `view_range` 16 (`:229`), `walk_velocity` 1 / `run_velocity` 2 / `follow_velocity` 2.4 (`:230-231,327`), `jump_height` 4 (`:204`), `stepheight` 0.6 (`:219`).
- **attack_type:** `dogfight` melee (`combat.lua:1036-1149`); `shoot`/`dogshoot` with `arrow`, `shoot_interval` (`:1151-1227`); `explode` (`:971-1033`); `custom` + `attack_state` (`:1228`). `on_attack` runs after each attack step (`:1232`). `attack_frequency` default 1 (`:1116`).
- **Temperament:** `type` = `monster`/`animal`/`npc` (`:192`). `passive` defaults false (`:255`); `passive ~= false` blocks auto-attack (`combat.lua:293`). Monsters target players (`:330`).
- **Flee:** `runaway` flees 5 s (`movement.lua:706-718`), set on player hit (`combat.lua:776-790`). `runaway_from` = name list (`movement.lua:411-451`).
- **Pets:** `follow` (item list, `movement.lua:330-346`), `nofollow`, `owner`, `tamed`, `order` (`sit`/`roam`/`follow`), `owner_loyal` (`combat.lua:837-839`). Taming: `feed_tame(clicker, count, breed, tame)` (`breeding.lua:31-45`). Owner rightclick toggles sit (`init.lua:60`, `breeding.lua:365-403`).
- **Visuals:** `visual`, `mesh` (.glb ok since Luanti 5.10, `lua_api.md:380,409`), `textures` (alternatives, one picked, `api.lua:145-148`), `visual_size`, `collisionbox`, `selectionbox` (`init.lua:172,207-222`).
- **Animation:** `<name>_start`, `_end`, `_speed`, `_loop` for stand, walk, run, fly, punch, punch2, shoot, fuse, sit, jump, die (+`die_speed`). Default speed 15 (`effects.lua:256-310`; die `physics.lua:568-571`).
- **Sounds:** keys `random, damage, death, attack, shoot_attack, fuse, eat, jump, distance` (`effects.lua:95-135`).
- **Drops:** `{name, chance, min, max, looting, looting_factor}` (`init.lua:161-170`, `physics.lua:104-137`).
- **Water:** `floats` default 1 (`init.lua:259`, `physics.lua:971`); `fly` (`init.lua:195`, `physics.lua:932`); `fly_in` (`:132-147`); `breathes_in_water` (`:227`). No swim field.
- **Nametag:** `nametag` (`api.lua:264`); `ignores_nametag` (`init.lua:316`).
- **Hooks:**
  - `do_custom(self, dtime)`: every step, even with no player near (`api.lua:403`). Return `false` to skip `do_states`; engage logic (`:379-384`) still runs.
  - `on_spawn(self)`: once, after first activation (`api.lua:277`).
  - `on_die(self, pos, cmi_cause)`: return `true` to skip default death and drops (`physics.lua:513-527`).
  - `deal_damage(self, damage, reason)`: replaces default (`init.lua:351-378`). `do_punch(self, hitter, tflp, tool_caps, dir)`: `false` cancels (`combat.lua:538-542`).
  - `on_rightclick(self, clicker)`: nametag handled first (`init.lua:56-89`). `after_activate` at `api.lua:290`.
  - No `on_step` field; `mob_class:on_step` is pcall-wrapped (`api.lua:438-444`).
- **Persistence:** `get_staticdata` saves every non-function field (`api.lua:84-98`). Despawn-eligible mobs return "remove" on unload (`api.lua:73-77`).
- **Despawn:** `can_despawn` defaults to `spawn_class ~= "passive"` (`init.lua:121-122`). Blocked by nametag, tamed, persistent, attacking or following (`spawning.lua:1230-1239`). Lifetime 57.73 (`init.lua:206`), refreshed near players (`api.lua:8,454-469`).

## 2. Spawning
- `mcl_mobs:spawn_setup(def)` (`spawning.lua:259-307`): `name`, `dimension` (overworld/nether/end), `type_of_spawning` (overworld/ground/water/lava, `:270,586-592`), `biomes` (`:296-304,583`), `min_height`/`max_height` (`:272-273,606`), `chance` default 1000 (`:267`), `check_position(pos)` (`:609`), `soft_cap` (`:1085,1132`).
- Ignored for natural spawns: `min_light`/`max_light` (spawners only, `:310-359`), `aoc`, `interval`, `day_toggle`. Hostile needs artificial light 0 and sky light <= 7 (`:766-771`); passive needs light >= 7 (`:775`); passive is 30% of attempts (`:986`).
- Group size: `spawn_in_group` default 4; set 0 for singles (`:1123-1149`).
- **Disable VoxeLibre mobs:** per mob, `minetest.conf` line `<entity name> = 0` (`spawning.lua:278-286`). All natural spawns: `mobs_spawn = false` (`settingtypes.txt:142`, `spawning.lua:102-110`). Peaceful only: `only_peaceful_mobs` (`settingtypes.txt:147`, `api.lua:119-123`).
- **Biome names** (`MAPGEN/mcl_biomes/init.lua`, exact strings): Plains, SunflowerPlains, Forest, FlowerForest, BirchForest, Taiga, ColdTaiga, MegaTaiga, MegaSpruceTaiga, IcePlains, ExtremeHills, Desert, Savanna, Mesa*, Jungle*, Swampland, MangroveSwamp, MushroomIsland, RoofedForest, Nether*, End*. Beach/ocean variants add a suffix.
- **Village restriction:** `check_position` against our own village list (`:609`).
- **Caps** (`settingtypes.txt:180-210`, `spawning.lua:67-93`): total 500; hostile 300 global, 75 per player; hostile 70 within 128 nodes; animal 10; 10 per class within 32 nodes (`:924-956`). Nametagged mobs are not counted (`:187-188`). Spawn ring 24-128 nodes (`:60-64`). Attempts budgeted at 500 us per game second (`:34,1191-1220`).

## 3. AI and targeting
- `monster_attack` runs every 0.2 s while a player is within 48 nodes (`api.lua:372-383`, `physics.lua:45`).
- Candidates: players when `type == "monster"` or `_aggro` (`combat.lua:330`). Entities named in `specific_attack` (`:243-252,347`) also need: `animal` + `attack_animals`, `npc` + `attack_npcs`, or any type with `extra_hostile` (and not `attack_exception`, `:350`, default at `init.lua:401`). Nearest with line of sight (`:362-365`, `movement.lua:67`).
- Our creature vs. other creatures: `specific_attack = {names}` plus `extra_hostile = true`, or `type = "animal"` plus `attack_animals = true`.
- Forced attack: `do_attack(obj)` (`combat.lua:38-47`). Retaliation when hit and `passive == false` (`:796-806`). Pack alert via `group_attack` (`:820-833`).
- Target forgotten after 15 s out of sight (`:14,942-951`). Melee reach `:1086-1108`; swing when timer exceeds `attack_frequency` (`:1116-1118`), damage `self.damage` (`:1136-1139`).
- No built-in low-HP flee: `do_custom` must set `state = "runaway"` and `runaway_timer = 0` (`movement.lua:706`, `combat.lua:788-789`).
- Owner follow: `check_follow` only follows held items, or `npc` with `order = "follow"` (`movement.lua:455-486`). Teleport-to-owner exists only in mobs_mc (`mobs_mc/init.lua:20`): we write our own.

## 4. Damage
- Melee: `target:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = damage}})` (`combat.lua:1136-1139`).
- Target `on_punch` (`combat.lua:504`): 0.5 s invulnerability per target (`:10,511-513`); no reach check for non-player hitters (`:516-520`); damage scaled by punch timing (`:576-580`); critical when hitter falls (`:649-680`); knockback (`:715-772`).
- Bypass: `mcl_util.deal_damage(target, dmg, {type, direct, source})` calls `damage_mob` directly (`mcl_util/init.lua:361-386`, `physics.lua:884-896`), skipping invulnerability and knockback. Death: `physics.lua:466-588`.
- Player reason types: `mcl_damage.types` (`CORE/mcl_damage/init.lua:5-30`), `register_type` (`:163-165`). `from_punch` sets type `mob` for mobs (`:99-114`).
- Projectiles punch any `is_mob` or `_hittable_by_projectile` entity (`ITEMS/vl_projectile/init.lua:514-527,578-590`).

## 5. Throwables (Poke Ball base)
- `mcl_throwing.register_throwable_object(item, entity, velocity)` (`ITEMS/mcl_throwing/init.lua:14-19`; entity needs `_vl_projectile`).
- Item `on_use = mcl_throwing.get_player_throw_function(entity)` (`init.lua:38-49`, punch key per `egg.lua:5`). Launch via `mcl_throwing.throw` (`init.lua:21-36`): drag 3, owner set. Default speed 22 (`:2-3`).
- Entity: `vl_projectile.register(name, def)` (`ITEMS/vl_projectile/init.lua:655-690`). Behaviors `collides_with_solids`/`collides_with_entities`; hooks `on_collide_with_solid`/`on_collide_with_entity` (`ITEMS/vl_projectile/api.md`). Reference: `mcl_throwing/snowball.lua`, `egg.lua:20-82` (`mcl_mobs.spawn_child`, `breeding.lua:107`).
- Launch API: `vl_projectile.create(entity, {pos, dir, velocity, drag, owner, extra})` (`init.lua:622-653`). Mob arrows: `mcl_mobs.register_arrow` (`init.lua:463-595`).

## 6. Performance
- Per mob per step: despawn/fall/fire checks, `player_in_active_range` (`physics.lua:67-73`), `do_custom`, `do_states` (`api.lua:346-404`). Timers: engage 0.2 s (`api.lua:379`); states and occasional 1 s (`:313,392`).
- Spawn attempts scan all luaentities (`spawning.lua:114-178`). Lifetime loop: every 1 s (`api.lua:454-469`).
- Typical active count: not in source; use the caps above.

## 7. Villages and NPCs
- Generation is mapgen-only (`MAPGEN/mcl_villages/init.lua:82-107`, height limit 56 in `const.lua:72`). No position list or query API. Global `settlements` table is public (`init.lua:1`). Villagers spawn on red bed bottoms (`buildings.lua:211-224`): the only per-village marker.
- Custom placement: emerge the area, then replicate `build_a_settlement` (`init.lua:56-71`): `settlements.create_site_plan(maxp, minp, pr)` (`buildings.lua:78`), `terraform`, `paths`, `place_schematics` (`buildings.lua:253`). Area = pos +/- `half_map_chunk_size` (40, `const.lua:76`). Manual tool needs the "server" priv (`init.lua:124-138`).
- Villagers: `mobs_mc:villager` (`ENTITIES/mobs_mc/villager.lua:2088-2221`): type `npc`, passive, `can_despawn = false`. Professions and trade tables are local (`villager.lua:77,1515`): no registration API. Quest givers: our own mcl_mobs NPC with `on_rightclick` opening our own `minetest.show_formspec` (pattern `villager.lua:1602-1666,1783`).

## 8. HUD and formspec
- `vl_hudbars.register_hudbar{...}` (`HUD/vl_hudbars/init.lua:608`), `init_hudbar` (`:660`), `change_value(player, id, value, max, part)` (`:772`), compound parts. Spec: `HUD/vl_hudbars/API.md`. Example: `HUD/mcl_hbarmor/init.lua:65`.
- Formspecs: `mcl_formspec.get_itemslot_bg(x, y, w, h)` and `_v4` (`HUD/mcl_formspec/init.lua:11,45`). Last formspec version only (`FORMSPEC_GUIDE.md`).

## 9. Interface points
- One data-driven `register_mob` def per species; temperament = `passive` + `type`.
- Battle, level and HP state on the entity via `do_custom`/`on_spawn`; party creatures `can_despawn = false`, `persistent = true`.
