class_name CreatureInstance
extends RefCounted
## One owned creature. to_dict() and from_dict() round-trip every field (save format, JSON-safe).

var uid: String = ""
var species_id: int = 0
var nickname: String = ""
var level: int = 1
var total_exp: int = 0
var ivs: Dictionary = {}
var bond: int = 0
var current_hp: int = 0
var status: String = ""
var moves: Array = []
var held_item: String = ""
var ball: String = ""
var shiny: bool = false
var caught_at: String = ""


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"species_id": species_id,
		"nickname": nickname,
		"level": level,
		"total_exp": total_exp,
		"ivs": ivs.duplicate(true),
		"bond": bond,
		"current_hp": current_hp,
		"status": status,
		"moves": moves.duplicate(true),
		"held_item": held_item,
		"ball": ball,
		"shiny": shiny,
		"caught_at": caught_at,
	}


static func from_dict(d: Dictionary) -> CreatureInstance:
	var c := CreatureInstance.new()
	c.uid = str(d.get("uid", ""))
	c.species_id = int(d.get("species_id", 0))
	c.nickname = str(d.get("nickname", ""))
	c.level = int(d.get("level", 1))
	c.total_exp = int(d.get("total_exp", 0))
	c.ivs = JsonValues.to_int_dict(d.get("ivs", {}))
	c.bond = int(d.get("bond", 0))
	c.current_hp = int(d.get("current_hp", 0))
	c.status = str(d.get("status", ""))
	c.moves = _moves_from(d.get("moves", []))
	c.held_item = str(d.get("held_item", ""))
	c.ball = str(d.get("ball", ""))
	c.shiny = bool(d.get("shiny", false))
	c.caught_at = str(d.get("caught_at", ""))
	return c


static func _moves_from(raw: Variant) -> Array:
	var out: Array = []
	for entry: Dictionary in JsonValues.to_dict_array(raw):
		out.append({"id": str(entry.get("id", "")), "pp": int(entry.get("pp", 0))})
	return out
