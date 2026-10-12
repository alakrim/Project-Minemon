extends GutTest
## Contract: the Data autoload. load_all(dir) -> Array[String], species(id), move(id),
## item(id) -> ItemData, chart() -> TypeChart, all_species_ids() -> Array[int].


func after_each() -> void:
	Data.load_all()


func test_load_all_returns_an_array_of_errors() -> void:
	var errors: Array[String] = Data.load_all()
	assert_typeof(errors, TYPE_ARRAY)


func test_lookups_return_their_declared_types() -> void:
	Data.load_all()
	assert_is(Data.species(19), SpeciesData)
	assert_is(Data.move("tackle"), MoveData)
	assert_is(Data.item("poke_ball"), ItemData)
	assert_is(Data.chart(), TypeChart)
	assert_typeof(Data.all_species_ids(), TYPE_ARRAY)


func test_all_methods_exist_on_the_autoload() -> void:
	for method: String in ["load_all", "species", "move", "item", "chart", "all_species_ids"]:
		assert_true(Data.has_method(method), method)
