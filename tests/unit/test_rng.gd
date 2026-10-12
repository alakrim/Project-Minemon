extends GutTest
## Unit tests for Rng: determinism, seed sensitivity, fork and bounds.


func _sequence(rng: Rng, count: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in count:
		out.append(rng.randi_range(0, 1000000))
	return out


func test_same_seed_gives_same_sequence() -> void:
	var a := Rng.new(42)
	var b := Rng.new(42)
	assert_eq(_sequence(a, 50), _sequence(b, 50))


func test_different_seed_gives_different_sequence() -> void:
	var a := Rng.new(42)
	var b := Rng.new(43)
	assert_ne(_sequence(a, 50), _sequence(b, 50))


func test_fork_is_deterministic() -> void:
	var first := Rng.new(7).fork("terrain")
	var second := Rng.new(7).fork("terrain")
	assert_eq(first.seed, second.seed)
	assert_eq(_sequence(first, 50), _sequence(second, 50))


func test_fork_tag_changes_seed() -> void:
	var parent := Rng.new(7)
	assert_ne(parent.fork("terrain").seed, parent.fork("combat").seed)


func test_randi_range_stays_in_bounds() -> void:
	var rng := Rng.new(1234)
	var in_bounds := true
	for i: int in 2000:
		var value: int = rng.randi_range(-3, 5)
		if value < -3 or value > 5:
			in_bounds = false
	assert_true(in_bounds, "randi_range returned a value outside -3..5")
