class_name ItemData
extends RefCounted
## One item, built from one entry of data/items.json. catch_mult is 0 for items that are not balls.

var id: String = ""
var name: String = ""
var kind: String = ""
var catch_mult: float = 0.0
var heal: int = 0
var price: int = 0


static func from_dict(d: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.id = str(d.get("id", ""))
	item.name = str(d.get("name", ""))
	item.kind = str(d.get("kind", ""))
	item.catch_mult = float(d.get("catch_mult", 0.0))
	item.heal = int(d.get("heal", 0))
	item.price = int(d.get("price", 0))
	return item


func is_ball() -> bool:
	return kind == "ball"
