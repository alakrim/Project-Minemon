extends GutTest
## Contract: SpeciesData.from_dict(d: Dictionary) -> SpeciesData with the PLAN.md fields and types.


func test_from_dict_returns_species_data_with_typed_fields() -> void:
	var raw: Dictionary = {
		"id": 19,
		"name": "rattata",
		"types": ["normal"],
		"base_stats": {"hp": 30, "atk": 56, "def": 35, "spa": 25, "spd": 35, "spe": 72},
		"catch_rate": 255.0,
		"growth_rate": "medium_fast",
		"base_exp": 51,
		"gender_ratio": 4,
		"evolutions": [],
		"learnset": [],
		"temperament": "aggressive",
		"size_class": "tiny",
		"body_plan": "quadruped",
		"habitats": ["town"],
		"eldritch": false,
	}
	var sp: SpeciesData = SpeciesData.from_dict(raw)
	assert_is(sp, SpeciesData)
	assert_typeof(sp.id, TYPE_INT)
	assert_eq(sp.catch_rate, 255)
	assert_eq(sp.types, ["normal"])
	assert_eq(sp.base_stats["atk"], 56)


func test_from_dict_has_defaults_for_missing_keys() -> void:
	var sp: SpeciesData = SpeciesData.from_dict({})
	assert_eq(sp.id, 0)
	assert_eq(sp.gender_ratio, -1)
	assert_eq(sp.eldritch, false)
