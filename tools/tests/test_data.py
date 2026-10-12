"""Checks for the generated Gen 2 data (mods/minemon/minemon_core/data/*.json).

Run: python3 -m unittest discover -s tools/tests -v
Stdlib only. Reads the JSON files; does not call PokeAPI.
"""

import json
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "mods", "minemon", "minemon_core", "data")

TEMPERAMENTS = {"aggressive", "territorial", "skittish", "peaceful"}
SIZES = {"tiny", "small", "medium", "large", "huge", "colossal"}
BODY_PLANS = {"biped", "quadruped", "serpent", "avian", "blob", "insect", "fish", "other"}
HABITATS = {"plains", "forest", "mountain", "cave", "water", "sea", "beach", "desert", "snow",
            "swamp", "urban", "rare"}
ARCHETYPES = {"projectile", "beam", "melee_arc", "area_burst", "aura", "status_cloud"}
ARCHETYPE_RANGE = {"melee_arc": 2.0, "beam": 8.0, "projectile": 12.0, "area_burst": 6.0,
                   "status_cloud": 10.0, "aura": 0.0}
PHYSICAL = {"normal", "fighting", "flying", "poison", "ground", "rock", "bug", "ghost", "steel"}
SPECIAL = {"fire", "water", "grass", "electric", "psychic", "ice", "dragon", "dark"}


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as fh:
        return json.load(fh)


class DataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.species = load("species.json")
        cls.by_name = {s["name"]: s for s in cls.species}
        cls.moves = load("moves.json")
        cls.types = load("types.json")
        cls.items = load("items.json")
        cls.type_names = set(cls.types["types"])

    def test_exactly_251_species_ids_1_to_251(self):
        self.assertEqual(len(self.species), 251)
        self.assertEqual([s["id"] for s in self.species], list(range(1, 252)))

    def test_every_species_type_is_valid_and_1_or_2_long(self):
        for s in self.species:
            self.assertIn(len(s["types"]), (1, 2), s["name"])
            for t in s["types"]:
                self.assertIn(t, self.type_names, s["name"])

    def test_every_move_type_is_valid_and_category_matches_gen2_rule(self):
        for key, m in self.moves.items():
            self.assertIn(m["type"], self.type_names, key)
            if m["category"] == "status":
                self.assertIsNone(m["power"], key)
            elif m["type"] in PHYSICAL:
                self.assertEqual(m["category"], "physical", key)
            else:
                self.assertIn(m["type"], SPECIAL, key)
                self.assertEqual(m["category"], "special", key)

    def test_every_learnset_move_exists_in_moves(self):
        for s in self.species:
            for entry in s["learnset"]:
                self.assertIn(entry["move"], self.moves, "%s %s" % (s["name"], entry["move"]))

    def test_every_evolution_target_is_in_1_to_251(self):
        for s in self.species:
            for evo in s["evolutions"]:
                self.assertTrue(1 <= evo["to"] <= 251, s["name"])

    def test_catch_rate_in_range_3_to_255(self):
        for s in self.species:
            self.assertTrue(3 <= s["catch_rate"] <= 255, s["name"])

    def test_design_fields_use_allowed_values(self):
        for s in self.species:
            self.assertIn(s["temperament"], TEMPERAMENTS, s["name"])
            self.assertIn(s["size_class"], SIZES, s["name"])
            self.assertIn(s["body_plan"], BODY_PLANS, s["name"])
            self.assertTrue(s["habitats"], s["name"])
            self.assertTrue(set(s["habitats"]) <= HABITATS, s["name"])
            self.assertIsInstance(s["eldritch"], bool, s["name"])

    def test_move_archetype_range_matches_archetype(self):
        for key, m in self.moves.items():
            self.assertIn(m["archetype"], ARCHETYPES, key)
            self.assertEqual(m["range_m"], ARCHETYPE_RANGE[m["archetype"]], key)

    def test_type_chart_has_17_gen2_types_and_no_fairy(self):
        self.assertEqual(len(self.types["types"]), 17)
        self.assertNotIn("fairy", self.types["types"])
        self.assertTrue(set(self.types["chart"]) <= self.type_names)
        for atk, row in self.types["chart"].items():
            self.assertTrue(set(row) <= self.type_names, atk)
            for mult in row.values():
                self.assertIn(mult, (0.0, 0.5, 2.0), atk)

    def test_items_include_balls_with_catch_mult(self):
        self.assertEqual(self.items["poke_ball"]["catch_mult"], 1.0)
        self.assertEqual(self.items["great_ball"]["catch_mult"], 1.5)
        self.assertEqual(self.items["ultra_ball"]["catch_mult"], 2.0)
        self.assertEqual(self.items["master_ball"]["catch_mult"], 255.0)
        for key in ("fire_stone", "water_stone", "thunder_stone", "leaf_stone", "moon_stone",
                    "sun_stone", "king_s_rock", "metal_coat", "dragon_scale", "link_cable"):
            self.assertIn(key, self.items)

    def test_every_evolution_item_is_in_items_json(self):
        for s in self.species:
            for evo in s["evolutions"]:
                for field in ("item", "held_item"):
                    if field in evo["conditions"]:
                        self.assertIn(evo["conditions"][field], self.items, s["name"])

    def test_json_files_are_in_canonical_format(self):
        for name in ("species.json", "moves.json", "types.json", "items.json"):
            with open(os.path.join(DATA, name), encoding="utf-8") as fh:
                text = fh.read()
            obj = json.loads(text)
            canon = json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
            self.assertEqual(text, canon, name)

    def test_named_species_have_the_brief_temperament(self):
        expected = {
            "aggressive": ["beedrill", "fearow", "dodrio", "scyther", "tauros", "mewtwo", "arbok",
                           "primeape", "gyarados", "houndoom", "ursaring", "granbull", "sneasel",
                           "tyranitar", "haunter", "gengar", "rattata", "raticate"],
            "peaceful": ["shuckle", "wobbuffet", "chansey", "blissey", "miltank", "togepi",
                         "slowpoke", "lapras", "snorlax"],
            "skittish": ["caterpie", "weedle", "ditto", "pidgey", "sentret", "hoppip", "natu",
                         "abra", "smoochum", "magikarp"],
        }
        for temper, names in expected.items():
            for name in names:
                self.assertEqual(self.by_name[name]["temperament"], temper, name)

    def test_temperament_distribution_within_target_ranges(self):
        counts = {t: 0 for t in TEMPERAMENTS}
        for s in self.species:
            counts[s["temperament"]] += 1
        total = len(self.species)
        ranges = {"aggressive": (0.25, 0.35), "territorial": (0.25, 0.35),
                  "skittish": (0.15, 0.25), "peaceful": (0.15, 0.25)}
        for temper, (low, high) in ranges.items():
            share = counts[temper] / total
            self.assertTrue(low <= share <= high,
                            "%s is %d of %d (%.1f%%)" % (temper, counts[temper], total, share * 100))

    def test_legendary_predators_are_not_territorial_by_default(self):
        self.assertEqual(self.by_name["mewtwo"]["temperament"], "aggressive")
        self.assertEqual(self.by_name["zapdos"]["temperament"], "aggressive")

    def test_raticate_base_stats(self):
        self.assertEqual(self.by_name["raticate"]["base_stats"],
                         {"hp": 55, "atk": 81, "def": 60, "spa": 50, "spd": 70, "spe": 97})

    def test_gengar_catch_rate_is_45(self):
        self.assertEqual(self.by_name["gengar"]["catch_rate"], 45)

    def test_scary_face_gen2_accuracy_is_90(self):
        self.assertEqual(self.moves["scary_face"]["accuracy"], 90)

    def test_cyndaquil_learns_ember_at_level_12(self):
        self.assertIn({"level": 12, "move": "ember"}, self.by_name["cyndaquil"]["learnset"])

    def test_eevee_has_five_gen2_evolutions_with_bond_and_time_for_espeon_umbreon(self):
        evos = self.by_name["eevee"]["evolutions"]
        self.assertEqual(len(evos), 5)
        by_to = {e["to"]: e["conditions"] for e in evos}
        self.assertEqual(by_to[196]["min_bond"], 220)
        self.assertEqual(by_to[196]["time_of_day"], "day")
        self.assertEqual(by_to[197]["min_bond"], 220)
        self.assertEqual(by_to[197]["time_of_day"], "night")

    def test_tyrogue_has_three_evolutions_with_stat_relation(self):
        evos = self.by_name["tyrogue"]["evolutions"]
        self.assertEqual(len(evos), 3)
        for evo in evos:
            self.assertIn("stat_relation", evo["conditions"])

    def test_steelix_comes_from_onix_by_trade_holding_metal_coat(self):
        onix = self.by_name["onix"]["evolutions"]
        self.assertEqual(onix, [{"to": 208, "conditions": {"held_item": "metal_coat", "trade": True}}])

    def test_tackle_gen2_values(self):
        tackle = self.moves["tackle"]
        self.assertEqual((tackle["power"], tackle["accuracy"], tackle["pp"]), (35, 95, 35))
        self.assertEqual(tackle["type"], "normal")
        self.assertEqual(tackle["category"], "physical")

    def test_fire_blast_gen2_values(self):
        fire_blast = self.moves["fire_blast"]
        self.assertEqual((fire_blast["power"], fire_blast["accuracy"], fire_blast["pp"]), (120, 85, 5))
        self.assertEqual(fire_blast["category"], "special")


if __name__ == "__main__":
    unittest.main()
