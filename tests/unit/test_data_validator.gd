extends GutTest
## Unit tests for DataValidator on small in-memory documents: valid gives none, each fault gives one.

const TYPE_NAMES: Array[String] = [
	"normal",
	"fighting",
	"flying",
	"poison",
	"ground",
	"rock",
	"bug",
	"ghost",
	"steel",
	"fire",
	"water",
	"grass",
	"electric",
	"psychic",
	"ice",
	"dragon",
	"dark",
]


func _types_doc() -> Dictionary:
	return {"types": TYPE_NAMES, "chart": {"ice": {"dragon": 2.0}}}


func _items_doc() -> Dictionary:
	return {"poke_ball": {"name": "Poke Ball", "kind": "ball", "catch_mult": 1.0, "price": 200}}


func _move() -> Dictionary:
	return {
		"name": "Tackle",
		"type": "normal",
		"category": "physical",
		"power": 35,
		"accuracy": 95,
		"pp": 35,
		"priority": 0,
		"archetype": "melee_arc",
		"range_m": 2.0,
		"cast_s": 0.3,
		"cooldown_s": 0.8,
		"effect": {},
	}


func _moves_doc() -> Dictionary:
	return {"tackle": _move()}


func _species(id: int) -> Dictionary:
	return {
		"id": id,
		"name": "Rattata",
		"types": ["normal"],
		"base_stats": {"hp": 30, "atk": 56, "def": 35, "spa": 25, "spd": 35, "spe": 72},
		"catch_rate": 255,
		"growth_rate": "medium_fast",
		"base_exp": 51,
		"gender_ratio": 4,
		"evolutions": [],
		"learnset": [{"level": 1, "move": "tackle"}],
		"temperament": "aggressive",
		"size_class": "tiny",
		"body_plan": "quadruped",
		"habitats": ["town"],
		"eldritch": false,
	}


func _validate(species: Array, moves: Dictionary = _moves_doc()) -> Array[String]:
	return DataValidator.validate(_types_doc(), _items_doc(), moves, species)


func test_valid_minimal_set_has_no_errors() -> void:
	assert_eq(_validate([_species(19)]), [])


func test_unknown_type_is_reported() -> void:
	var sp: Dictionary = _species(19)
	sp["types"] = ["plasma"]
	var errors: Array[String] = _validate([sp])
	assert_eq(errors.size(), 1)
	assert_true(errors[0].begins_with("species.json[19].types:"), errors[0])


func test_catch_rate_out_of_range_is_reported() -> void:
	var sp: Dictionary = _species(19)
	sp["catch_rate"] = 0
	var errors: Array[String] = _validate([sp])
	assert_eq(errors, ["species.json[19].catch_rate: 0 not in 3..255"])


func test_duplicate_species_id_is_reported() -> void:
	var errors: Array[String] = _validate([_species(19), _species(19)])
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "duplicate")


func test_missing_field_is_named() -> void:
	var sp: Dictionary = _species(19)
	sp.erase("temperament")
	var errors: Array[String] = _validate([sp])
	assert_eq(errors, ["species.json[19].temperament: missing"])


func test_evolution_target_must_exist() -> void:
	var sp: Dictionary = _species(19)
	sp["evolutions"] = [{"to": 999, "conditions": {"min_level": 20}}]
	var errors: Array[String] = _validate([sp])
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "species.json[19].evolutions[0].to")


func test_learnset_move_must_exist() -> void:
	var sp: Dictionary = _species(19)
	sp["learnset"] = [{"level": 1, "move": "no_such_move"}]
	var errors: Array[String] = _validate([sp])
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "species.json[19].learnset[0].move")


func test_bad_move_category_and_unknown_effect_key_are_reported() -> void:
	var move: Dictionary = _move()
	move["category"] = "magic"
	move["effect"] = {"zap_chance": 10}
	var errors: Array[String] = _validate([_species(19)], {"tackle": move})
	assert_eq(errors.size(), 2)
	assert_string_contains(errors[0], "moves.json[tackle].category")
	assert_string_contains(errors[1], "unknown effect key")
