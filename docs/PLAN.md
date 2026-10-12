# PLAN v3: Luanti + VoxeLibre + Minemon mods (D-024, D-025)
Earlier plans are superseded: Godot (branch `godot-prototype`) and Cobblemon (D-022/D-023).

## Brief (owner goals, unchanged)
A private Pokémon game in a Minecraft-like world for the owner and one friend.
- **Look and performance:** hard, alive, scary and beautiful; runs on an AMD Vega 8 with 6 GB RAM; Android later.
- **Pokémon:** all 251 Kanto + Johto species, each aggressive or peaceful, fought with real-time combat in the world.
- **Catching and growth:** wild Pokémon must be defeated before capture, balls have different catch rates, and levels come from battling and bonding.
- **Danger:** wild Pokémon attack the player when no Pokémon of theirs is out. 3 lives, then permadeath.
- **World and story:** missions in Kanto + Johto towns; eldritch giants; free, with no purchases.

## Architecture
- **Engine:** Luanti 5.17.0 (client: the official win64 zip; testing: luantiserver built from source in `.tools/`).
- **Base game:** VoxeLibre, pinned to a release tag, cloned into `.tools/voxelibre` and never edited.
- **Our code:** `mods/minemon/` is a modpack (modpack.conf) of small mods, each with its own `mod.conf` and `depends`:
  - `minemon_core`: shared utilities (rng, data loading, logging), species/move data in `minemon_core/data/*.json`, and a public API table `minemon`;
  - `minemon_lives`: 3 lives, then ghost mode;
  - later: `minemon_creatures` (entities via mcl_mobs), `minemon_combat`, `minemon_capture`, `minemon_progress` (exp, levels, bond), `minemon_party` (UI), `minemon_dread`, `minemon_towns`, `minemon_titans`, `minemon_packs` (owner visual packs).
- **Game assembly:** `scripts/assemble_game.sh` writes `.tools/games/minemon/`. It contains game.conf (`title = Minemon`), VoxeLibre's `mods/*`, our `mods/minemon`, and VoxeLibre's menu and settingtypes where needed.
- **Tests:**
  - `tests/unit/*_spec.lua`: busted, pure Lua with mocks of `core`;
  - `tests/integration/<name>/`: a test mod run inside the assembled game by `scripts/run_luanti_test.sh`. It writes `test_result.txt` and calls `core.request_shutdown`.
- **Assets:** `tools/*.py` generate our own stand-in creature models (.glb, our art). Pokémon visuals come only from owner-supplied packs (D-014).

## Invariants
1. VoxeLibre and Luanti sources are never modified. We hook only through public APIs (mcl_mobs, core callbacks, overrides in our own mods).
2. Every gameplay rule is per player and multiplayer-safe. Player state lives in player meta (`minemon:*` keys) or mod storage.
3. No globalstep does unbounded work. Use timers of at least 0.5 s for scans, limit radius and object counts, and keep per-entity on_step cheap.
4. No species-specific or move-specific code; behaviour is driven by data.
5. We never create or fetch Pokémon art, models or sounds. Stand-ins are procedural and our own.
6. `bash scripts/check.sh` passes before every commit: luacheck, busted, and headless integration tests.

## Milestones
| M | Playable result | Acceptance |
|---|---|---|
| M0 | Portable Windows build of Minemon (VoxeLibre world) with the lives system; tooling; all 251 species' data | check.sh green; owner runs it and reports fps (≥30, F5 overlay) |
| M1 | Creatures: Kanto + Johto species spawn by biome with stand-in models, temperaments (aggressive hunt the player when no Pokémon is out), level by distance; real-time fights | Integration tests; owner playtest: a Rattata is dangerous |
| M2 | Capture and growth: balls (catch rates), capture only when defeated, party UI, send out and recall, exp, levels, bond, evolutions, saves | Tests; owner catches and levels a starter |
| M3 | Dread: night and cave atmosphere, fog, ambience, rare scares; graphics presets for the Vega 8 | Owner playtest |
| M4 | Towns and missions: Kanto/Johto towns via VoxeLibre villages placed near canon positions, NPC quests, Pokémon Centers as respawn checkpoints | Each mission completable |
| M5 | Eldritch giants (titans) | Owner playtest |
| M6 | Owner Pokémon visual packs; multiplayer with the friend; Android check | — |

## M1 interface contract (D-026). Changing it is a high-risk task plus a D-entry.
All APIs hang off the global `minemon` table created by `minemon_core`.

**minemon_core** (pure modules have no `core` access and are busted-tested):
- `minemon.data`:
  - `get_species(id_or_name)` returns the species.json entry (name matching is case-insensitive) or nil;
  - `get_move(id)` returns the move table or nil;
  - `all_species_ids()` returns 1..251;
  - `type_multiplier(atk_type, def_types)`; `get_item(id)`.
  - Data loads once at mod load with `core.parse_json` from `minemon_core/data/`.
- `minemon.formulas` (`formulas.lua`, pure, a Lua port of the Gen 2 rules in docs/research and the archived Godot core; see the T-20 brief):
  - `calc_stats(base, level, ivs, bond)` returns `{hp,atk,def,spa,spd,spe}`;
  - `damage(atk_view, def_view, move, type_mult_fn, rng)` returns `{amount, crit, effectiveness, missed}`, where a view is `{level, stats, types, status, stages}`;
  - `catch_chance(catch_rate, hp_frac, ball_mult, status)` returns 0..1;
  - `exp_for_level(level, growth)`, `level_for_exp(exp, growth)`, `exp_gain(base_exp, defeated_level, bond)`;
  - `wild_level(distance_from_origin, is_night, rng)` returns 2..70.
- `minemon.rng.new(seed)` returns an object with `:float()` (0..1) and `:int(a, b)`.
- `minemon.instance` (`instance.lua`, pure):
  - `new(species, level, rng)` returns an instance `{uid, species_id, nickname="", level, exp, ivs={hp,atk,def,spa,spd,spe 0..15}, bond=0, hp, status="none", moves={{id,pp}... ≤4: the last 4 learnset moves at or below level}, ball="poke_ball", shiny=false, owner=nil}`;
  - `serialize` / `deserialize` (JSON-safe tables); `stats(instance, species)`.
- `minemon.events`:
  - `register(name, fn)` and `fire(name, ...)`;
  - events: `creature_defeated(victim_luaentity, attacker_obj)`, `creature_captured(player, instance)`, `creature_sent_out(player, obj)`, `creature_recalled(player)`.

**minemon_creatures:**
- One mcl_mobs mob per species, named `minemon_creatures:<lowercase_name_with_underscores>` (e.g. `minemon_creatures:mr_mime`).
- The luaentity holds `self._mm` (the instance). Health is custom (`self.health` = instance hp).
- `minemon.creatures.spawn(pos, species_id, level, owner_name_or_nil)` returns an ObjectRef.
- `minemon.creatures.get_instance(obj)` returns the instance or nil.
- `minemon.creatures.is_exhausted(obj)` reports the defeated, capturable state.

**minemon_party:**
- `minemon.party.get(player)` returns the instance list (max 6), stored in player meta `minemon:party:list` as JSON;
- `set(player, list)`;
- `get_active(player)` returns the ObjectRef or nil;
- `send_out(player, index)`; `recall(player)`.

**minemon_combat:**
- `minemon.combat.use_move(user_obj, target_obj, move_id)` returns true on success; it applies damage and status through the formulas.
- Move archetypes are implemented once each: projectile, beam, melee_arc, area_burst, aura, status_cloud.

### M1 contract addendum (D-027): creature runtime hooks, owned by T-24
In `minemon_creatures`:
- **Brains:** `minemon.creatures.register_brain(name, fn(self, dtime) -> bool handled)`. Brains run in `do_custom`, in registration order, every step. Each brain throttles itself; the first one returning true stops the chain, and mcl_mobs default states still run unless a brain returns the string "skip_states". T-24 dispatches; T-21b registers "wild", T-22 registers "owned".
- **Damage:** `minemon.creatures.damage(obj, amount, attacker_obj, info)` lowers `self.health` and `_mm.hp` together (clamped at 0), shows a damage tint, plays the hurt sound, fires `events.fire("creature_hurt", obj, amount, attacker_obj, info)`. At 0 HP it calls `on_zero_hp(obj, attacker_obj)`:
  - wild creatures enter **exhausted**: `_mm_exhausted = true`, sit animation, no attacking, harmless, a nametag suffix " (exhausted)"; after 20 s they recover 25% HP and flee;
  - owned creatures **faint**: fire `creature_fainted(obj, owner)`, after which T-22 recalls them with hp 0.

  `info` = `{move_id?, effectiveness?, crit?}`.
- Every other damage path (player punches through mcl_mobs `do_punch`/`deal_damage`, falls, fire) also goes through `minemon.creatures.damage`, so health never desyncs. Hook mcl_mobs' `deal_damage` def field (S-12 §1).
- Also: `is_exhausted(obj)`, `heal(obj, amount)`, `is_owned(obj)`, `owner_name(obj)`.
