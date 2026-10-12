class_name Rng
extends RefCounted
## Seeded random source. All gameplay randomness goes through this class.

var seed: int
var _rng: RandomNumberGenerator


func _init(p_seed: int) -> void:
	seed = p_seed
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed


func randf() -> float:
	return _rng.randf()


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func fork(tag: String) -> Rng:
	return Rng.new(hash(str(seed) + tag))
