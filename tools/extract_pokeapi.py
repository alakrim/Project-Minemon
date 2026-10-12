#!/usr/bin/env python3
"""Build the Gen 2 (Pokedex 1-251) data files for Minemon.

Writes mods/minemon/minemon_core/data/{species,moves,types,items}.json.
Stdlib only. Raw sources are cached in .tools/cache/pokeapi/ (gitignored): the
first run downloads them, later runs read the cache. Output is deterministic
(sorted keys, fixed indent, no timestamps), so two runs give identical bytes.

Sources
  CSV  https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/
  JSON https://pokeapi.co/api/v2/pokemon/<id> and .../type/<name>, used ONLY
       for past_types and past_damage_relations (the CSVs hold current values).

Gen 2 version rules
  R1  Gen 2 = version groups gold-silver (3) and crystal (4). Learnsets are the
      union of both. Gen 1 version groups (1, 2) are not used for values.
  R2  Move values (power, accuracy, pp, type, priority, target, effect_chance).
      move_changelog.csv row (move, G, fields) stores the value the move had
      BEFORE version group G. A blank field means unchanged. For Gen 2 a field
      takes the stored value of the earliest row with G > 4 that sets it; if no
      such row sets it, the current moves.csv value applies. Gold-silver and
      crystal give the same answer (asserted, because no row has G = 4).
  R3  Move category follows the Gen 2 type rule: physical = normal, fighting,
      flying, poison, ground, rock, bug, ghost, steel; special = fire, water,
      grass, electric, psychic, ice, dragon, dark. Current status moves stay
      status.
  R4  Curse: the changelog stores the Gen 2 type as "???" (id 10001). We store
      ghost, the current type. Gen 2 Curse is typeless for non-Ghost users.
      Known gap, to be handled in M1.
  R5  Species types: pokemon JSON past_types, the entry with the lowest
      generation >= 2. If there is none, the current pokemon_types.csv row
      applies. This covers the Gen 6 Fairy retypes (Clefairy, Mr. Mime, ...).
  R6  Type chart: type JSON past_damage_relations, with the same "lowest
      generation >= 2" rule, else the current relations. Only the 17 Gen 2
      types are used. Offensive lists define chart[attacker][defender]. The
      defensive lists are cross-checked against them (asserted).
  R7  Base stats are PokeAPI current values. spa = special-attack and
      spd = special-defense (Gen 2 split). PokeAPI has no past stat values, so
      any later stat change is not rolled back (known gap).
  R8  Evolutions: pokemon_evolution rows whose evolved species is 1-251, whose
      version group is blank or Gen <= 2, and whose triggers are level-up,
      trade or use-item. The source of an edge is the evolved species'
      evolves_from_species_id. Condition mapping: minimum_level -> min_level,
      minimum_happiness -> min_bond = 220 (Gen 2 threshold, not PokeAPI's 160),
      time_of_day -> time_of_day,
      trigger_item -> item, held_item -> held_item, trade -> trade (true),
      relative_physical_stats 1/-1/0 -> stat_relation attack_gt_defense /
      attack_lt_defense / attack_eq_defense.
  R9  Learnset: pokemon_moves rows for default forms, version group 3 or 4,
      method level-up (id 1). Output is the union, sorted by (level, move).

Design rules (our fields, derived from PokeAPI data)
  D1  temperament, first match wins:
      (a) tools/design_overrides.json (clear named cases);
      (b) legendary, mythical or no-eggs: aggressive if max(atk, spa) >= 110
          (predators such as Mewtwo), otherwise territorial;
      (c) aggressive if atk >= 100, or spa >= 120, or max(atk, spa) >= 85 with
          speed >= 90, or a dark or fighting type with max(atk, spa) >= 70;
      (d) peaceful if egg group plant or fairy, or if max(atk, spa) < 60 and
          (hp >= 60 or def >= 100) (passive or defensive);
      (e) skittish if size is tiny or small with max(atk, spa) < 70, or
          speed >= 80 with max(atk, spa) < 90;
      (f) otherwise territorial.
      Targets (of 251): aggressive 25-35%, territorial 25-35%, skittish 15-25%,
      peaceful 15-25%. Tests check the named cases and the ranges.
  D2  size_class from height in metres: tiny < 0.4, small < 0.9, medium < 1.6,
      large < 3, huge < 6, colossal >= 6.
  D3  body_plan from the PokeAPI shape: ball, arms, upright, legs, humanoid,
      heads, tentacles, armor -> other/biped as listed in SHAPE_PLAN;
      squiggle -> serpent; fish -> fish; blob -> blob; quadruped -> quadruped;
      wings -> avian; bug-wings -> insect.
  D4  habitats: PokeAPI habitat mapped to our tags (grassland -> plains,
      rough-terrain -> mountain, waters-edge -> beach, others unchanged), plus
      type tags (water -> water, ice -> snow, poison -> swamp, ground ->
      desert). If the set is empty, ["plains"].
  D5  eldritch: true only for the names in design_overrides.json.
  D6  move archetype. Status moves: aura if the target is user-side, otherwise
      status_cloud. Damage moves: area_burst if the target is a multi-target
      one; else melee_arc for physical contact moves; beam for other physical;
      projectile for special.
  D7  range_m by archetype: melee_arc 2.0, beam 8.0, projectile 12.0,
      area_burst 6.0, status_cloud 10.0, aura 0.0.
  D8  cast_s = archetype base (melee 0.3, beam 0.4, projectile 0.5, area 0.6,
      status_cloud 0.4, aura 0.3) + 0.1 if power >= 70. cooldown_s = archetype
      base (melee 0.8, beam 1.0, projectile 1.2, area 2.0, status_cloud 1.5,
      aura 3.0) + 1.0 if power >= 80, - 0.2 if priority > 0. These are stand-in
      tuning values for M1.
  D9  effect keys: status (ailment name), status_chance (1-99 only),
      flinch_chance, stat_changes [{stat, stages, target}] with target "user"
      or "target", and stat_chance (1-99 only). Stats: atk def spa spd spe acc
      eva. Other effects (drain, recoil, multi-hit, crit) are not stored.
  D10 items: catch_mult for balls and heal for potions are hand-entered Gen 2
      values (PokeAPI CSVs have neither). Price is the PokeAPI cost (current,
      not Gen 2 verified; placeholder until the shop milestone).
  D11 ids: species name, move key and item key are the PokeAPI identifier with
      "-" replaced by "_" (King's Rock is king_s_rock, per the brief).
"""

import csv
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(ROOT, ".tools", "cache", "pokeapi")
API_CACHE = os.path.join(CACHE, "api")
OUT_DIR = os.path.join(ROOT, "mods", "minemon", "minemon_core", "data")
OVERRIDES_PATH = os.path.join(HERE, "design_overrides.json")
CSV_URL = "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/"
API_URL = "https://pokeapi.co/api/v2/"

MAX_ID = 251
GEN2_VGS = (3, 4)
ENGLISH = "9"
CRYSTAL_VG = 4
TYPELESS_ID = 10001  # PokeAPI "???" type, used by Curse before Gen 6

CSV_FILES = [
    "pokemon_species.csv", "pokemon.csv", "pokemon_stats.csv", "stats.csv",
    "pokemon_types.csv", "types.csv", "pokemon_moves.csv", "moves.csv",
    "move_changelog.csv", "move_damage_classes.csv", "move_targets.csv",
    "move_meta.csv", "move_meta_ailments.csv", "move_meta_stat_changes.csv",
    "move_flag_map.csv", "move_flags.csv", "move_names.csv", "pokemon_evolution.csv",
    "evolution_triggers.csv", "growth_rates.csv", "pokemon_habitats.csv",
    "pokemon_shapes.csv", "pokemon_egg_groups.csv", "egg_groups.csv", "items.csv",
    "item_names.csv", "version_groups.csv", "pokemon_move_methods.csv",
]

# Items PokeAPI does not list: (name, price), as in the Godot-era items.json.
MANUAL_ITEMS = {"link-cable": ("Link Cable", 0)}

# (PokeAPI identifier, our key, kind, catch_mult or None, heal or None)
ITEM_SPECS = [
    ("poke-ball", "poke_ball", "ball", 1.0, None),
    ("great-ball", "great_ball", "ball", 1.5, None),
    ("ultra-ball", "ultra_ball", "ball", 2.0, None),
    ("master-ball", "master_ball", "ball", 255.0, None),
    ("potion", "potion", "medicine", None, 20),
    ("super-potion", "super_potion", "medicine", None, 50),
    ("link-cable", "link_cable", "evo", None, None),  # not in PokeAPI: hand-entered, see MANUAL_ITEMS
    ("fire-stone", "fire_stone", "evo_stone", None, None),
    ("water-stone", "water_stone", "evo_stone", None, None),
    ("thunder-stone", "thunder_stone", "evo_stone", None, None),
    ("leaf-stone", "leaf_stone", "evo_stone", None, None),
    ("moon-stone", "moon_stone", "evo_stone", None, None),
    ("sun-stone", "sun_stone", "evo_stone", None, None),
    ("kings-rock", "king_s_rock", "held_evo", None, None),
    ("metal-coat", "metal_coat", "held_evo", None, None),
    ("dragon-scale", "dragon_scale", "held_evo", None, None),
    ("up-grade", "up_grade", "held_evo", None, None),  # Porygon -> Porygon2 (trade), not in the brief's list
]

PHYSICAL_TYPES = {"normal", "fighting", "flying", "poison", "ground", "rock", "bug", "ghost", "steel"}
SPECIAL_TYPES = {"fire", "water", "grass", "electric", "psychic", "ice", "dragon", "dark"}
STAT_SHORT = {
    "attack": "atk", "defense": "def", "special-attack": "spa", "special-defense": "spd",
    "speed": "spe", "accuracy": "acc", "evasion": "eva",
}
STAT_ID_TO_KEY = {1: "hp", 2: "atk", 3: "def", 4: "spa", 5: "spd", 6: "spe"}
AREA_TARGETS = {"all-other-pokemon", "all-opponents", "all-pokemon", "opponents-field", "entire-field"}
AURA_TARGETS = {"user", "users-field", "user-and-allies"}
SHAPE_PLAN = {
    "ball": "other", "squiggle": "serpent", "fish": "fish", "arms": "biped", "blob": "blob",
    "upright": "biped", "legs": "biped", "quadruped": "quadruped", "wings": "avian",
    "tentacles": "other", "heads": "other", "humanoid": "biped", "bug-wings": "insect",
    "armor": "other",
}
HABITAT_MAP = {
    "cave": "cave", "forest": "forest", "grassland": "plains", "mountain": "mountain",
    "rare": "rare", "rough-terrain": "mountain", "sea": "sea", "urban": "urban",
    "waters-edge": "beach",
}
TYPE_HABITAT = {"water": "water", "ice": "snow", "poison": "swamp", "ground": "desert"}
ARCHETYPE_RANGE = {"melee_arc": 2.0, "beam": 8.0, "projectile": 12.0, "area_burst": 6.0,
                   "status_cloud": 10.0, "aura": 0.0}
ARCHETYPE_CAST = {"melee_arc": 0.3, "beam": 0.4, "projectile": 0.5, "area_burst": 0.6,
                  "status_cloud": 0.4, "aura": 0.3}
ARCHETYPE_COOLDOWN = {"melee_arc": 0.8, "beam": 1.0, "projectile": 1.2, "area_burst": 2.0,
                      "status_cloud": 1.5, "aura": 3.0}
REL_NAME = {1: "attack_gt_defense", -1: "attack_lt_defense", 0: "attack_eq_defense"}
# Conditions present in PokeAPI rows that Gen 2 does not use. Counted, not stored.
# A value of "0" counts as unset (boolean flags).
UNHANDLED_COLS = [
    "location_id", "known_move_id", "known_move_type_id", "minimum_beauty",
    "minimum_affection", "party_species_id", "party_type_id", "trade_species_id",
    "needs_overworld_rain", "turn_upside_down", "needs_multiplayer", "near_special_rock",
    "gender_id", "region_id", "used_move_id", "minimum_move_count", "minimum_steps",
    "minimum_damage_taken", "nature_bitmask", "condition_expression", "percentage_chance",
]
# R8: every happiness evolution used this threshold in Gen 2 (Bulbapedia, Friendship
# evolution: 220 from Gen II to VII, 160 from Gen VIII). PokeAPI's current value
# (160) is the Gen 8+ threshold. Not in the CSVs; hand-applied.
GEN2_HAPPINESS = 220
TEMPERAMENTS = {"aggressive", "territorial", "skittish", "peaceful"}
SIZES = ["tiny", "small", "medium", "large", "huge", "colossal"]


def size_class_for(height_m):
    """D2 thresholds, in metres."""
    if height_m < 0.4:
        return "tiny"
    if height_m < 0.9:
        return "small"
    if height_m < 1.6:
        return "medium"
    if height_m < 3:
        return "large"
    if height_m < 6:
        return "huge"
    return "colossal"


def fetch(url, path):
    """Download url to path once. Writes via a .part file so an interrupted run leaves no partial cache."""
    if os.path.exists(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    last = None
    for _ in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (minemon-extract)"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
            with open(path + ".part", "wb") as fh:
                fh.write(data)
            os.replace(path + ".part", path)
            return
        except OSError as exc:  # URLError and HTTPError are OSError subclasses
            last = exc
            time.sleep(2)
    raise SystemExit("download failed: %s (%s)" % (url, last))


def read_csv(name):
    fetch(CSV_URL + name, os.path.join(CACHE, name))
    with open(os.path.join(CACHE, name), encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def read_json_api(rel, cache_name):
    path = os.path.join(API_CACHE, cache_name)
    fetch(API_URL + rel, path)
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def to_int(text):
    return None if text is None or text == "" else int(text)


def key_of(identifier):
    return identifier.replace("-", "_")


def gen_number(entry):
    return int(entry["generation"]["url"].rstrip("/").split("/")[-1])


def gen2_past(entries):
    """Entry with the lowest generation >= 2, or None (rule R5/R6)."""
    cands = [e for e in entries if gen_number(e) >= 2]
    return min(cands, key=gen_number) if cands else None


def fail(msg):
    raise SystemExit("ERROR: " + msg)


def load_overrides():
    with open(OVERRIDES_PATH, encoding="utf-8") as fh:
        raw = json.load(fh)
    return {k: v for k, v in raw.items() if not k.startswith("_")}


def build_types():
    """Gen 2 types and the 17x17 chart (R6). Returns (type_names, chart, defence_check_count)."""
    type_rows = read_csv("types.csv")
    names = {int(r["id"]): r["identifier"] for r in type_rows if int(r["id"]) <= 18}
    gen2_ids = [i for i in sorted(names) if i <= 17]
    gen2_names = [names[i] for i in gen2_ids]
    gen2_set = set(gen2_names)

    offence = {}
    defence = {}
    for name in names.values():
        data = read_json_api("type/%s/" % name, "type_%s.json" % name)
        past = gen2_past(data.get("past_damage_relations", []))
        # One dict holds both the offensive and the defensive lists of an entry.
        rel = past["damage_relations"] if past else data["damage_relations"]
        offence[name] = rel
        defence[name] = rel

    chart = {}
    for atk in gen2_names:
        rel = offence[atk]
        row = {}
        for target, mult in (("double_damage_to", 2.0), ("half_damage_to", 0.5), ("no_damage_to", 0.0)):
            for entry in rel[target]:
                if entry["name"] in gen2_set:
                    row[entry["name"]] = mult
        if row:
            chart[atk] = dict(sorted(row.items()))

    # Cross-check: each defender's defensive list must agree with the offensive lists.
    checked = 0
    for dfn in gen2_names:
        rel = defence[dfn]
        expect = {}
        for entry in rel["double_damage_from"]:
            expect[entry["name"]] = 2.0
        for entry in rel["half_damage_from"]:
            expect[entry["name"]] = 0.5
        for entry in rel["no_damage_from"]:
            expect[entry["name"]] = 0.0
        for atk in gen2_names:
            got = chart.get(atk, {}).get(dfn, 1.0)
            want = expect.get(atk, 1.0)
            if atk in expect or got != 1.0:
                checked += 1
                if got != want:
                    fail("type chart mismatch %s->%s: offence %s, defence %s" % (atk, dfn, got, want))
    return gen2_names, chart, checked


def main():
    ov = load_overrides()

    species_rows = {int(r["id"]): r for r in read_csv("pokemon_species.csv") if int(r["id"]) <= MAX_ID}
    if sorted(species_rows) != list(range(1, MAX_ID + 1)):
        fail("pokemon_species.csv does not give ids 1-251")
    default_pokemon = {}
    for r in read_csv("pokemon.csv"):
        if r["is_default"] == "1" and int(r["species_id"]) <= MAX_ID:
            default_pokemon[int(r["species_id"])] = r
    for sid in range(1, MAX_ID + 1):
        if int(default_pokemon[sid]["id"]) != sid:
            fail("default pokemon id differs from species id for %d" % sid)

    stat_names = {int(r["id"]): r["identifier"] for r in read_csv("stats.csv")}
    base_stats = {}
    for r in read_csv("pokemon_stats.csv"):
        base_stats[(int(r["pokemon_id"]), int(r["stat_id"]))] = int(r["base_stat"])
    type_names = {int(r["id"]): r["identifier"] for r in read_csv("types.csv")}
    cur_types = {}
    for r in read_csv("pokemon_types.csv"):
        cur_types.setdefault(int(r["pokemon_id"]), []).append((int(r["slot"]), type_names[int(r["type_id"])]))
    default_pokemon_id = {sid: int(default_pokemon[sid]["id"]) for sid in range(1, MAX_ID + 1)}

    gen2_type_names, chart, chart_checks = build_types()

    growth = {int(r["id"]): key_of(r["identifier"]) for r in read_csv("growth_rates.csv")}
    habitat_name = {int(r["id"]): r["identifier"] for r in read_csv("pokemon_habitats.csv")}
    shape_name = {int(r["id"]): r["identifier"] for r in read_csv("pokemon_shapes.csv")}
    egg_name = {int(r["id"]): r["identifier"] for r in read_csv("egg_groups.csv")}
    egg_groups = {}
    for r in read_csv("pokemon_egg_groups.csv"):
        egg_groups.setdefault(int(r["species_id"]), set()).add(egg_name[int(r["egg_group_id"])])

    # R5: species types, with a check against the current CSV types.
    species_types = {}
    past_used = 0
    json_mismatch = 0
    for sid in range(1, MAX_ID + 1):
        data = read_json_api("pokemon/%d/" % sid, "pokemon_%d.json" % sid)
        if data["id"] != sid:
            fail("pokemon JSON id mismatch for %d" % sid)
        current = [t["type"]["name"] for t in sorted(data["types"], key=lambda t: t["slot"])]
        csv_current = [t for _, t in sorted(cur_types[default_pokemon_id[sid]])]
        if current != csv_current:
            json_mismatch += 1
        past = gen2_past(data.get("past_types", []))
        if past is not None:
            past_used += 1
            species_types[sid] = [t["type"]["name"] for t in sorted(past["types"], key=lambda t: t["slot"])]
        else:
            species_types[sid] = csv_current
        for t in species_types[sid]:
            if t not in gen2_type_names:
                fail("species %d has non-Gen 2 type %s after rollback" % (sid, t))
    if json_mismatch:
        fail("%d species: JSON current types differ from pokemon_types.csv" % json_mismatch)

    # R2: changelog and moves. Version groups: 3 = gold-silver, 4 = crystal.
    changes = {}
    for r in read_csv("move_changelog.csv"):
        changes.setdefault(int(r["move_id"]), []).append(
            (int(r["changed_in_version_group_id"]), r))
    for mid in changes:
        changes[mid].sort(key=lambda item: item[0])
    moves_rows = {int(r["id"]): r for r in read_csv("moves.csv")}
    if any(vg == CRYSTAL_VG for rows in changes.values() for vg, _ in rows):
        fail("changelog has a row for version group 4; gold-silver and crystal would differ")

    def gen2_value(mid, field, from_vg):
        for vg, row in changes.get(mid, []):
            if vg > from_vg and row[field] != "":
                return row[field], True
        return moves_rows[mid][field], False

    # R9: learnsets (union of gold-silver and crystal).
    pid_to_species = {v: k for k, v in default_pokemon_id.items()}
    per_vg = {vg: {} for vg in GEN2_VGS}
    for r in read_csv("pokemon_moves.csv"):
        if int(r["version_group_id"]) not in GEN2_VGS or int(r["pokemon_move_method_id"]) != 1:
            continue
        pid = int(r["pokemon_id"])
        if pid not in pid_to_species:
            continue
        per_vg[int(r["version_group_id"])].setdefault(pid_to_species[pid], set()).add(
            (int(r["level"]), int(r["move_id"])))
    learn_sets = {}
    gold_crystal_differ = 0
    for sid in range(1, MAX_ID + 1):
        g = per_vg[3].get(sid, set())
        c = per_vg[4].get(sid, set())
        if g != c:
            gold_crystal_differ += 1
        learn_sets[sid] = g | c
    used_moves = sorted({mid for s in learn_sets.values() for _, mid in s})

    # Moves.
    move_names = {int(r["move_id"]): r["name"] for r in read_csv("move_names.csv")
                  if r["local_language_id"] == ENGLISH}
    target_name = {int(r["id"]): r["identifier"] for r in read_csv("move_targets.csv")}
    ailment_name = {int(r["id"]): r["identifier"] for r in read_csv("move_meta_ailments.csv")}
    damage_name = {int(r["id"]): r["identifier"] for r in read_csv("move_damage_classes.csv")}
    meta = {int(r["move_id"]): r for r in read_csv("move_meta.csv")}
    stat_changes = {}
    for r in read_csv("move_meta_stat_changes.csv"):
        stat_changes.setdefault(int(r["move_id"]), []).append(
            (stat_names[int(r["stat_id"])], int(r["change"])))
    contact_id = None
    for r in read_csv("move_flags.csv"):
        if r["identifier"] == "contact":
            contact_id = int(r["id"])
    if contact_id is None:
        fail("move_flags.csv has no contact flag")
    contact_moves = {int(r["move_id"]) for r in read_csv("move_flag_map.csv")
                     if int(r["move_flag_id"]) == contact_id}

    rollback_fields = {"power": 0, "accuracy": 0, "pp": 0, "priority": 0, "type_id": 0,
                       "target_id": 0, "effect_chance": 0}
    moves = {}
    for mid in used_moves:
        row = moves_rows[mid]
        for field in rollback_fields:
            if gen2_value(mid, field, GEN2_VGS[0])[0] != gen2_value(mid, field, GEN2_VGS[1])[0]:
                fail("gen2 value differs between gold-silver and crystal for %s" % row["identifier"])

        def g2(field):
            value, changed = gen2_value(mid, field, CRYSTAL_VG)
            if changed:
                rollback_fields[field] += 1
            return value

        damage_class = damage_name[int(row["damage_class_id"])]
        type_raw = int(g2("type_id"))
        type_key = "ghost" if type_raw == TYPELESS_ID else type_names[type_raw]
        power = to_int(g2("power"))
        accuracy = to_int(g2("accuracy"))
        pp = to_int(g2("pp"))
        priority = to_int(g2("priority"))
        target = target_name[to_int(g2("target_id"))]
        eff_chance = to_int(g2("effect_chance"))
        if type_key not in gen2_type_names:
            fail("move %s has non-Gen 2 type %s" % (row["identifier"], type_key))

        if damage_class == "status":
            category = "status"
        else:
            category = "physical" if type_key in PHYSICAL_TYPES else "special"
            if type_key not in PHYSICAL_TYPES and type_key not in SPECIAL_TYPES:
                fail("unclassified type %s" % type_key)

        if category == "status":
            archetype = "aura" if target in AURA_TARGETS else "status_cloud"
        elif target in AREA_TARGETS:
            archetype = "area_burst"
        elif category == "physical" and mid in contact_moves:
            archetype = "melee_arc"
        elif category == "physical":
            archetype = "beam"
        else:
            archetype = "projectile"

        cast = ARCHETYPE_CAST[archetype] + (0.1 if power is not None and power >= 70 else 0.0)
        cooldown = ARCHETYPE_COOLDOWN[archetype]
        if power is not None and power >= 80:
            cooldown += 1.0
        if priority is not None and priority > 0:
            cooldown -= 0.2

        effect = {}
        m = meta[mid]
        ail = ailment_name.get(int(m["meta_ailment_id"]), "none")
        if ail not in ("none", "unknown"):
            effect["status"] = ail
            if eff_chance is not None and 0 < eff_chance < 100:
                effect["status_chance"] = eff_chance
        if to_int(m["flinch_chance"]):
            effect["flinch_chance"] = int(m["flinch_chance"])
        changes_list = []
        for stat, change in sorted(stat_changes.get(mid, [])):
            if stat == "special":
                fail("move %s changes the unified Gen 1 special stat" % row["identifier"])
            changes_list.append({
                "stat": STAT_SHORT[stat],
                "stages": change,
                "target": "user" if target == "user" else "target",
            })
        if changes_list:
            effect["stat_changes"] = changes_list
            stat_chance = to_int(m["stat_chance"])
            if stat_chance is not None and 0 < stat_chance < 100:
                effect["stat_chance"] = stat_chance

        moves[key_of(row["identifier"])] = {
            "name": move_names[mid],
            "type": type_key,
            "category": category,
            "power": power,
            "accuracy": accuracy,
            "pp": pp,
            "priority": priority,
            "archetype": archetype,
            "range_m": ARCHETYPE_RANGE[archetype],
            "cast_s": round(cast, 1),
            "cooldown_s": round(cooldown, 1),
            "effect": effect,
        }
    if not moves:
        fail("no moves produced")
    gen_of_move = {int(r["id"]): int(r["generation_id"]) for r in moves_rows.values()}
    late_moves = [moves_rows[mid]["identifier"] for mid in used_moves if gen_of_move[mid] > 2]

    # Evolutions (R8).
    trigger_name = {int(r["id"]): r["identifier"] for r in read_csv("evolution_triggers.csv")}
    vg_gen = {int(r["id"]): int(r["generation_id"]) for r in read_csv("version_groups.csv")}
    item_ident = {int(r["id"]): r["identifier"] for r in read_csv("items.csv")}
    item_cost = {int(r["id"]): int(r["cost"]) for r in read_csv("items.csv")}
    item_names = {int(r["item_id"]): r["name"] for r in read_csv("item_names.csv")
                  if r["local_language_id"] == ENGLISH}
    item_key = {ident: key for ident, key, _, _, _ in ITEM_SPECS}

    def key_for_item(item_id):
        ident = item_ident[item_id]
        if ident not in item_key:
            fail("evolution uses item %s, not in ITEM_SPECS" % ident)
        return item_key[ident]

    evolutions = {sid: [] for sid in range(1, MAX_ID + 1)}
    skipped_triggers = {}
    unhandled = {}
    happiness_rows = 0
    for r in read_csv("pokemon_evolution.csv"):
        to = int(r["evolved_species_id"])
        if to > MAX_ID:
            continue
        if r["version_group_id"] and vg_gen[int(r["version_group_id"])] > 2:
            continue
        from_raw = species_rows[to]["evolves_from_species_id"]
        if not from_raw:
            fail("evolved species %d has no pre-evolution" % to)
        frm = int(from_raw)
        if frm > MAX_ID:
            fail("pre-evolution %d above 251" % frm)
        trig = trigger_name[int(r["evolution_trigger_id"])]
        if trig not in ("level-up", "trade", "use-item"):
            skipped_triggers[trig] = skipped_triggers.get(trig, 0) + 1
            continue
        for col in UNHANDLED_COLS:
            if r[col] not in ("", "0"):
                unhandled[col] = unhandled.get(col, 0) + 1
        cond = {}
        if r["minimum_level"]:
            cond["min_level"] = int(r["minimum_level"])
        if r["minimum_happiness"]:
            cond["min_bond"] = GEN2_HAPPINESS
            happiness_rows += 1
        if r["time_of_day"]:
            cond["time_of_day"] = r["time_of_day"]
        if r["trigger_item_id"]:
            cond["item"] = key_for_item(int(r["trigger_item_id"]))
        if r["held_item_id"]:
            cond["held_item"] = key_for_item(int(r["held_item_id"]))
        if r["relative_physical_stats"] != "":
            cond["stat_relation"] = REL_NAME[int(r["relative_physical_stats"])]
        if trig == "trade":
            cond["trade"] = True
        evolutions[frm].append({"to": to, "conditions": cond})
    for sid in evolutions:
        evolutions[sid].sort(key=lambda e: (e["to"], json.dumps(e["conditions"], sort_keys=True)))

    # Species.
    species_out = []
    temper_counts = {"aggressive": 0, "territorial": 0, "skittish": 0, "peaceful": 0}
    eldritch_count = 0
    temper_over = ov.get("temperament", {})
    eldritch_list = set(ov.get("eldritch", []))
    names = {sid: key_of(species_rows[sid]["identifier"]) for sid in range(1, MAX_ID + 1)}
    for name in list(temper_over) + list(eldritch_list) + list(ov.get("habitats", {})):
        if name not in names.values():
            fail("override names unknown species %s" % name)
    for name, value in temper_over.items():
        if value not in TEMPERAMENTS:
            fail("bad temperament %s for %s" % (value, name))
    for sid in range(1, MAX_ID + 1):
        sp = species_rows[sid]
        pid = default_pokemon_id[sid]
        name = names[sid]
        stats = {STAT_ID_TO_KEY[i]: base_stats[(pid, i)] for i in range(1, 7)}
        types = species_types[sid]
        egg = egg_groups.get(sid, set())
        atk_max = max(stats["atk"], stats["spa"])
        height_m = round(int(default_pokemon[sid]["height"]) / 10.0, 1)
        weight_kg = round(int(default_pokemon[sid]["weight"]) / 10.0, 1)

        size = size_class_for(height_m)
        is_legend = sp["is_legendary"] == "1" or sp["is_mythical"] == "1" or "no-eggs" in egg
        if name in temper_over:
            temper = temper_over[name]
        elif is_legend:
            temper = "aggressive" if atk_max >= 110 else "territorial"
        elif (stats["atk"] >= 100 or stats["spa"] >= 120 or (atk_max >= 85 and stats["spe"] >= 90)
              or ({"dark", "fighting"} & set(types) and atk_max >= 70)):
            temper = "aggressive"
        elif (egg & {"plant", "fairy"}) or (atk_max < 60 and (stats["hp"] >= 60 or stats["def"] >= 100)):
            temper = "peaceful"
        elif (size in ("tiny", "small") and atk_max < 70) or (stats["spe"] >= 80 and atk_max < 90):
            temper = "skittish"
        else:
            temper = "territorial"
        temper_counts[temper] += 1

        if name in ov.get("size_class", {}):
            size = ov["size_class"][name]
        body = SHAPE_PLAN[shape_name[int(sp["shape_id"])]] if sp["shape_id"] else "other"
        if name in ov.get("body_plan", {}):
            body = ov["body_plan"][name]

        habitats = set()
        if sp["habitat_id"]:
            habitats.add(HABITAT_MAP[habitat_name[int(sp["habitat_id"])]])
        for t in types:
            if t in TYPE_HABITAT:
                habitats.add(TYPE_HABITAT[t])
        if name in ov.get("habitats", {}):
            habitats = set(ov["habitats"][name])
        if not habitats:
            habitats = {"plains"}

        eldritch = name in eldritch_list
        eldritch_count += int(eldritch)

        learn = [{"level": lvl, "move": key_of(moves_rows[mid]["identifier"])}
                 for lvl, mid in sorted(learn_sets[sid], key=lambda x: (x[0], moves_rows[x[1]]["identifier"]))]
        species_out.append({
            "id": sid,
            "name": name,
            "types": types,
            "base_stats": stats,
            "catch_rate": int(sp["capture_rate"]),
            "growth_rate": growth[int(sp["growth_rate_id"])],
            "base_exp": int(default_pokemon[sid]["base_experience"]),
            "gender_ratio": int(sp["gender_rate"]),
            "evolutions": evolutions[sid],
            "learnset": learn,
            "temperament": temper,
            "size_class": size,
            "body_plan": body,
            "habitats": sorted(habitats),
            "eldritch": eldritch,
            "height_m": height_m,
            "weight_kg": weight_kg,
        })

    # Items.
    items_out = {}
    for ident, key, kind, catch_mult, heal in ITEM_SPECS:
        if ident in MANUAL_ITEMS:
            entry = {"name": MANUAL_ITEMS[ident][0], "kind": kind, "price": MANUAL_ITEMS[ident][1]}
        else:
            item_id = [i for i, v in item_ident.items() if v == ident]
            if len(item_id) != 1:
                fail("item %s not found once" % ident)
            entry = {"name": item_names[item_id[0]], "kind": kind, "price": item_cost[item_id[0]]}
        if catch_mult is not None:
            entry["catch_mult"] = catch_mult
        if heal is not None:
            entry["heal"] = heal
        items_out[key] = entry

    # Types output.
    types_out = {"types": gen2_type_names, "chart": chart}

    # Learnset check: Gen 2 learnsets should only use Gen 1-2 moves.
    if late_moves:
        fail("Gen 2 learnsets use moves from later generations: %s" % late_moves)

    # Pre-evolution check: every evolution target must exist.
    for sid, evos in evolutions.items():
        for e in evos:
            if not (1 <= e["to"] <= MAX_ID):
                fail("evolution target out of range")

    os.makedirs(OUT_DIR, exist_ok=True)
    outputs = {
        "species.json": species_out,
        "moves.json": dict(sorted(moves.items())),
        "types.json": types_out,
        "items.json": dict(sorted(items_out.items())),
    }
    for fname, obj in outputs.items():
        text = json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        with open(os.path.join(OUT_DIR, fname), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    total_learn = sum(len(s["learnset"]) for s in species_out)
    print("species %d, moves %d, learnset entries %d" % (len(species_out), len(moves), total_learn))
    print("types %d, chart entries %d, chart checks %d" % (
        len(gen2_type_names), sum(len(v) for v in chart.values()), chart_checks))
    print("temperament %s" % json.dumps(temper_counts, sort_keys=True))
    print("eldritch %d" % eldritch_count)
    print("species with Gen 2 past types %d, learnset gold-silver != crystal %d" % (
        past_used, gold_crystal_differ))
    print("move fields rolled back to Gen 2: %s" % json.dumps(rollback_fields, sort_keys=True))
    print("skipped evolution triggers (not Gen 2) %s" % json.dumps(skipped_triggers, sort_keys=True))
    print("ignored evolution columns %s" % json.dumps(unhandled, sort_keys=True))
    print("happiness evolution rows set to min_bond %d: %d" % (GEN2_HAPPINESS, happiness_rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
