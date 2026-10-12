class_name SpeciesData
extends RefCounted
## One species, built from one entry of data/species.json.
## gender_ratio is the female share in eighths (-1 = genderless).

var id: int = 0
var name: String = ""
var types: Array[String] = []
var base_stats: Dictionary = {}
var catch_rate: int = 0
var growth_rate: String = ""
var base_exp: int = 0
var gender_ratio: int = -1
var evolutions: Array = []
var learnset: Array = []
var temperament: String = ""
var size_class: String = ""
var body_plan: String = ""
var habitats: Array[String] = []
var eldritch: bool = false


static func from_dict(d: Dictionary) -> SpeciesData:
	var s := SpeciesData.new()
	s.id = int(d.get("id", 0))
	s.name = str(d.get("name", ""))
	s.types = JsonValues.to_string_array(d.get("types", []))
	s.base_stats = JsonValues.to_int_dict(d.get("base_stats", {}))
	s.catch_rate = int(d.get("catch_rate", 0))
	s.growth_rate = str(d.get("growth_rate", ""))
	s.base_exp = int(d.get("base_exp", 0))
	s.gender_ratio = int(d.get("gender_ratio", -1))
	s.evolutions = JsonValues.to_dict_array(d.get("evolutions", []))
	s.learnset = JsonValues.to_dict_array(d.get("learnset", []))
	s.temperament = str(d.get("temperament", ""))
	s.size_class = str(d.get("size_class", ""))
	s.body_plan = str(d.get("body_plan", ""))
	s.habitats = JsonValues.to_string_array(d.get("habitats", []))
	s.eldritch = bool(d.get("eldritch", false))
	return s
