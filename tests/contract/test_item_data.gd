extends GutTest
## Contract: ItemData.from_dict(d: Dictionary) -> ItemData with catch_mult, heal and price.


func test_from_dict_returns_item_data() -> void:
	var item: ItemData = ItemData.from_dict(
		{"id": "great_ball", "name": "Great Ball", "kind": "ball", "catch_mult": 1.5, "price": 600}
	)
	assert_is(item, ItemData)
	assert_almost_eq(item.catch_mult, 1.5, 0.0001)
	assert_eq(item.price, 600)
	assert_true(item.is_ball())


func test_non_ball_has_zero_catch_mult() -> void:
	var item: ItemData = ItemData.from_dict(
		{"id": "potion", "kind": "medicine", "heal": 20, "price": 300}
	)
	assert_eq(item.catch_mult, 0.0)
	assert_eq(item.heal, 20)
	assert_false(item.is_ball())
