extends "res://tests/lib/case.gd"


func test_height_is_bounded() -> void:
	var m := Waves.max_height()
	for i in 200:
		var h := Waves.height(i * 3.7, -i * 2.1, i * 0.37)
		check(absf(h) <= m + 1e-5, "height %f > max %f" % [h, m])
	check(Waves.max_height(3.0) > m, "storm raises waves")


func test_normal_points_up() -> void:
	for i in 50:
		var n := Waves.normal(i * 5.0, i * 1.3, i * 0.2)
		near(n.length(), 1.0, 1e-4)
		check(n.y > 0.8, "normal too steep: %s" % n)


## The water shader must use exactly the same wave numbers, or boats float above/below the water.
func test_shader_matches_gdscript() -> void:
	var src := FileAccess.get_file_as_string("res://src/shaders/water.gdshader")
	var a := src.find("WAVES-BEGIN")
	var b := src.find("WAVES-END")
	check(a >= 0 and b > a, "WAVES block markers")
	var block := src.substr(a, b - a)
	block = block.substr(block.find("{"))  # skip the comment line and the signature
	var re := RegEx.new()
	re.compile("-?\\d+\\.\\d+")
	var nums := PackedFloat32Array()
	for m in re.search_all(block):
		nums.append(float(m.get_string()))
	var expected := Waves.flat_params()
	eq(nums.size(), expected.size(), "number count in the shader block")
	for i in mini(nums.size(), expected.size()):
		near(nums[i], expected[i], 1e-6, "param %d" % i)
