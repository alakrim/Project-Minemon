extends GutTest
## Contract: TypeChart(chart: Dictionary) and multiplier(atk: String, defs: Array[String]) -> float.


func test_constructor_builds_a_type_chart() -> void:
	var chart: TypeChart = TypeChart.new({})
	assert_is(chart, TypeChart)


func test_multiplier_exists_and_returns_float() -> void:
	var chart: TypeChart = TypeChart.new({})
	assert_has_method(chart, "multiplier")
	var defs: Array[String] = ["normal"]
	assert_typeof(chart.multiplier("fire", defs), TYPE_FLOAT)
