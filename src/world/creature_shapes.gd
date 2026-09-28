class_name CreatureShapes
extends RefCounted
## Placeholder bodies for every creature in creatures.json until the artist's models arrive
## (art/models/creatures/<id>.glb through ModelLibrary). Low-poly primitives in one vertex-coloured mesh,
## glowing eyes and wisps as separate unfogged glows. Every body faces -Z, stands on y = 0 and carries
## meta "height" (for the health bar) and "radius" (for hit reach).

const EYE := Color("fff2c0")


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var parts: Array = []
	var height := 1.0
	var radius := 0.5
	match id:
		"hare":
			_beast(parts, 0.5, 0.32, Color("8c7a66"), Color("a8957e"))
			_b(parts, Vector3(0.05, 0.22, 0.04), Vector3(-0.05, 0.42, -0.26), Color("a8957e"))
			_b(parts, Vector3(0.05, 0.22, 0.04), Vector3(0.05, 0.42, -0.26), Color("a8957e"))
			height = 0.55
			radius = 0.3
		"fox":
			_beast(parts, 0.85, 0.42, Color("c0622a"), Color("d27a3e"))
			_b(parts, Vector3(0.14, 0.14, 0.5), Vector3(0, 0.36, 0.62), Color("c0622a"), Vector3(0.4, 0, 0))
			_b(parts, Vector3(0.12, 0.12, 0.14), Vector3(0, 0.28, 0.86), Color("f2ede2"))
			_ears(parts, 0.85, 0.42, Color("3a2a22"))
			height = 0.6
		"reindeer":
			_beast(parts, 1.8, 1.25, Color("7a6d62"), Color("9a8d80"))
			for s in [-1.0, 1.0]:
				_b(parts, Vector3(0.05, 0.6, 0.05), Vector3(0.14 * s, 1.75, -0.95), Color("d9cbb0"), Vector3(0, 0, 0.35 * s))
				_b(parts, Vector3(0.05, 0.3, 0.05), Vector3(0.3 * s, 1.95, -0.85), Color("d9cbb0"), Vector3(0.5, 0, 0.8 * s))
			height = 2.2
			radius = 0.8
		"wolf":
			_beast(parts, 1.3, 0.8, Color("6e6c68"), Color("8a8782"))
			_ears(parts, 1.3, 0.8, Color("4a4845"))
			_b(parts, Vector3(0.14, 0.14, 0.55), Vector3(0, 0.62, 0.85), Color("6e6c68"), Vector3(0.5, 0, 0))
			height = 1.1
			radius = 0.6
		"fog_wolf":
			_beast(parts, 1.45, 0.9, Color("2c3440"), Color("3a4452"))
			_ears(parts, 1.45, 0.9, Color("1e242c"))
			_eyes(root, Vector3(0, 0.95, -1.0), 0.13, Color("9fd8ff"))
			height = 1.2
			radius = 0.7
		"bear", "polar_bear":
			var col := Color("5a4030") if id == "bear" else Color("e8e6dc")
			var k := 1.0 if id == "bear" else 1.2
			_beast(parts, 2.0 * k, 1.2 * k, col, col.darkened(0.1), 1.8)
			_b(parts, Vector3(0.14, 0.14, 0.1) * k, Vector3(-0.2, 1.3, -1.05) * k, col)
			_b(parts, Vector3(0.14, 0.14, 0.1) * k, Vector3(0.2, 1.3, -1.05) * k, col)
			height = 1.7 * k
			radius = 1.0 * k
		"seal":
			_sph(parts, 0.45, Vector3(0, 0.3, 0), Color("7d8288"), Vector3(1.0, 0.8, 1.7))
			_sph(parts, 0.25, Vector3(0, 0.42, -0.72), Color("6c7278"))
			_b(parts, Vector3(0.5, 0.06, 0.25), Vector3(0, 0.14, 0.78), Color("5c6268"))
			height = 0.7
			radius = 0.7
		"gull":
			_sph(parts, 0.16, Vector3(0, 0, 0), Color("f2f0ea"), Vector3(1.0, 0.9, 1.9))
			_sph(parts, 0.09, Vector3(0, 0.08, -0.3), Color("f2f0ea"))
			_b(parts, Vector3(0.03, 0.03, 0.1), Vector3(0, 0.06, -0.42), Color("e0a93a"))
			for s in [-1.0, 1.0]:
				_b(parts, Vector3(0.55, 0.03, 0.2), Vector3(0.36 * s, 0.04, 0.02), Color("9aa0a6"), Vector3(0, 0, 0.18 * s))
			height = 0.4
			radius = 0.4
		"mglyak", "ice_mglyak":
			var col := Color("2a3038") if id == "mglyak" else Color("9fb8cc")
			_sph(parts, 0.55, Vector3(0, 1.0, 0), col, Vector3(1.0, 1.3, 1.0))
			_sph(parts, 0.38, Vector3(0.3, 0.55, 0.1), col.darkened(0.1))
			_sph(parts, 0.32, Vector3(-0.28, 0.5, 0.05), col.darkened(0.15))
			_c(parts, 0.35, 0.05, 0.7, Vector3(0, 0.25, 0), col.darkened(0.2))
			_eyes(root, Vector3(0, 1.15, -0.45), 0.1, Color("d8f0ff"))
			height = 1.7
			radius = 0.6
		"kikimora":
			_c(parts, 0.45, 0.25, 1.2, Vector3(0, 0.6, 0), Color("4a5a36"), Vector3(-0.3, 0, 0))
			_sph(parts, 0.28, Vector3(0, 1.3, -0.35), Color("6a6a4a"))
			for s in [-1.0, 1.0]:
				_b(parts, Vector3(0.1, 0.9, 0.1), Vector3(0.42 * s, 0.75, -0.3), Color("3e4a2c"), Vector3(0.5, 0, 0.2 * s))
			_sph(parts, 0.3, Vector3(0, 1.45, -0.25), Color("2e4a24"), Vector3(1.4, 0.6, 1.2))
			_eyes(root, Vector3(0, 1.32, -0.6), 0.07, Color("c8ff70"))
			height = 1.6
		"morok":
			_c(parts, 0.55, 0.18, 1.8, Vector3(0, 0.9, 0), Color("b8bec4"))
			_sph(parts, 0.26, Vector3(0, 1.9, 0), Color("c8ced4"))
			var lure := Placeholders.glow(Color("ffb060"), 2.6, 0.9)
			lure.name = "Lure"
			lure.position = Vector3(0.9, 1.6, -0.6)
			root.add_child(lure)
			height = 2.1
		"domovoy":
			_c(parts, 0.26, 0.2, 0.5, Vector3(0, 0.25, 0), Color("a3372c"))
			_sph(parts, 0.17, Vector3(0, 0.62, 0), Color("e0b89a"))
			_sph(parts, 0.2, Vector3(0, 0.5, -0.08), Color("d9d3c6"), Vector3(1.0, 1.2, 0.8))
			_c(parts, 0.19, 0.08, 0.2, Vector3(0, 0.8, 0), Color("5a4a3a"))
			_eyes(root, Vector3(0, 0.66, -0.16), 0.04, EYE)
			height = 0.9
			radius = 0.3
		"bannik":
			_c(parts, 0.4, 0.25, 1.1, Vector3(0, 0.55, 0), Color("d8d8d0"))
			_sph(parts, 0.22, Vector3(0, 1.25, 0), Color("e4e2da"))
			_sph(parts, 0.26, Vector3(0, 1.08, -0.1), Color("c8c6be"), Vector3(1.0, 1.3, 0.8))
			var steam := Placeholders.glow(Color("f4f0e8"), 3.0, 0.35)
			steam.name = "Steam"
			steam.position = Vector3(0, 1.0, 0)
			root.add_child(steam)
			height = 1.5
		"leshy":
			_c(parts, 0.45, 0.35, 2.4, Vector3(0, 1.2, 0), Color("5a4632"))
			_sph(parts, 0.42, Vector3(0, 2.7, 0), Color("4c3c2a"), Vector3(1.0, 1.2, 1.0))
			_sph(parts, 0.45, Vector3(0, 2.3, -0.2), Color("4a6a36"), Vector3(1.1, 1.4, 0.8))
			for s in [-1.0, 1.0]:
				_b(parts, Vector3(0.14, 1.4, 0.14), Vector3(0.62 * s, 1.9, 0), Color("5a4632"), Vector3(0, 0, 0.5 * s))
				_b(parts, Vector3(0.08, 0.7, 0.08), Vector3(0.45 * s, 3.3, 0), Color("6a5440"), Vector3(0, 0, -0.4 * s))
			_eyes(root, Vector3(0, 2.8, -0.38), 0.08, Color("9dff7a"))
			var wisp := Placeholders.glow(Color("7dff6a"), 1.4, 0.9)
			wisp.name = "Wisp"
			wisp.position = Vector3(0.8, 1.6, -1.2)
			root.add_child(wisp)
			height = 3.6
			radius = 0.6
		"vodyanoy":
			_c(parts, 0.42, 0.3, 1.1, Vector3(0, 0.55, 0), Color("4a6a5a"))
			_sph(parts, 0.3, Vector3(0, 1.3, 0), Color("6a8a70"))
			_sph(parts, 0.32, Vector3(0, 1.0, -0.2), Color("2e4a3a"), Vector3(1.0, 1.6, 0.7))
			_eyes(root, Vector3(0, 1.38, -0.27), 0.06, Color("c8ffe0"))
			height = 1.7
		"sirin":
			_sph(parts, 0.45, Vector3(0, 0.7, 0), Color("3a3048"), Vector3(1.0, 0.9, 1.5))
			for s in [-1.0, 1.0]:
				_b(parts, Vector3(1.2, 0.06, 0.5), Vector3(0.8 * s, 0.95, 0.1), Color("c8a04a"), Vector3(0, 0, 0.35 * s))
			_sph(parts, 0.2, Vector3(0, 1.25, -0.45), Color("e8c8a8"))
			_c(parts, 0.16, 0.2, 0.12, Vector3(0, 1.46, -0.45), Color("e0b040"))
			_b(parts, Vector3(0.5, 0.05, 0.6), Vector3(0, 0.55, 0.75), Color("c8a04a"), Vector3(0.3, 0, 0))
			var song := Placeholders.glow(Color("ffe6a8"), 2.2, 0.5)
			song.name = "Song"
			song.position = Vector3(0, 1.3, -0.5)
			root.add_child(song)
			height = 1.6
			radius = 0.8
		"ryba_kit":
			_sph(parts, 6.0, Vector3(0, 0.0, 0), Color("4a5a6a"), Vector3(1.4, 0.55, 3.2))
			_b(parts, Vector3(9.0, 0.6, 3.0), Vector3(0, 0.4, 17.0), Color("3e4c5a"))
			_b(parts, Vector3(2.4, 2.0, 2.8), Vector3(0, 4.0, 0), Color("8a6a4c"))
			_c(parts, 1.9, 0.0, 1.4, Vector3(0, 5.7, 0), Color("4a3a2c"), Vector3.ZERO, 4)
			_sph(parts, 0.5, Vector3(0, 6.7, 0), Color("c8a04a"), Vector3(1.0, 1.3, 1.0))
			_b(parts, Vector3(0.08, 1.0, 0.08), Vector3(0, 7.6, 0), Color("c8a04a"))
			_b(parts, Vector3(0.5, 0.08, 0.08), Vector3(0, 7.8, 0), Color("c8a04a"))
			var lamp := Placeholders.glow(Color("ffc070"), 2.0, 0.8)
			lamp.name = "Lamp"
			lamp.position = Vector3(0, 4.2, -1.5)
			root.add_child(lamp)
			height = 8.0
			radius = 9.0
		"likho":
			_c(parts, 0.9, 0.7, 2.4, Vector3(0, 1.2, 0), Color("5a5046"))
			_sph(parts, 0.75, Vector3(0, 2.9, 0), Color("6a5e52"))
			for s in [-1.0, 1.0]:
				_b(parts, Vector3(0.35, 2.0, 0.35), Vector3(1.05 * s, 1.8, 0), Color("5a5046"), Vector3(0, 0, 0.25 * s))
				_b(parts, Vector3(0.4, 1.2, 0.4), Vector3(0.45 * s, 0.6, 0), Color("4a4036"))
			_eyes(root, Vector3(-0.28, 3.05, -0.7), 0.2, Color("ff6a3a"), true)  # one eye: the right side is blind
			height = 3.8
			radius = 1.2
		"karachun":
			_c(parts, 0.7, 0.3, 2.8, Vector3(0, 1.4, 0), Color("a8c8e0"))
			_sph(parts, 0.38, Vector3(0, 3.0, 0), Color("c8e0f0"))
			for i in 5:
				var a := -0.8 + i * 0.4
				_b(parts, Vector3(0.08, 0.6, 0.08), Vector3(sin(a) * 0.3, 3.4, cos(a) * 0.1), Color("e8f6ff"), Vector3(0, 0, a))
			_eyes(root, Vector3(0, 3.05, -0.34), 0.07, Color("bfe8ff"))
			var frost := Placeholders.glow(Color("bfe6ff"), 5.0, 0.4)
			frost.name = "Frost"
			frost.position = Vector3(0, 2.0, 0)
			root.add_child(frost)
			height = 3.6
			radius = 0.9
		"siverko":
			for i in 7:
				var y := 0.8 + i * 0.8
				_b(parts, Vector3(3.2 - i * 0.25, 0.12, 0.5), Vector3(0, y, 0), Color("dfe8ee").darkened(0.05 * (i % 2)), Vector3(0, i * 0.9, 0.25))
			_c(parts, 0.6, 1.1, 5.6, Vector3(0, 3.0, 0), Color("b8c8d4"))
			_eyes(root, Vector3(0, 5.2, -0.9), 0.16, Color("e8f6ff"))
			var gust := Placeholders.glow(Color("e8f4ff"), 9.0, 0.35)
			gust.name = "Gust"
			gust.position = Vector3(0, 3.5, 0)
			root.add_child(gust)
			height = 6.4
			radius = 1.6
		"bolotnitsa":
			_c(parts, 1.1, 0.5, 3.0, Vector3(0, 1.5, 0), Color("4a4a30"))
			_sph(parts, 0.5, Vector3(0, 3.4, 0), Color("7a7458"))
			for i in 9:
				var a := i * TAU / 9.0
				_c(parts, 0.06, 0.02, 2.4, Vector3(cos(a) * 0.5, 2.6, sin(a) * 0.5), Color("5a6a34"), Vector3(sin(a) * 0.2, 0, cos(a) * 0.2))
			for s in [-1.0, 1.0]:
				_b(parts, Vector3(0.22, 2.0, 0.22), Vector3(1.0 * s, 2.2, -0.2), Color("3e3e28"), Vector3(0.4, 0, 0.4 * s))
			_eyes(root, Vector3(0, 3.5, -0.46), 0.1, Color("c8ff70"))
			height = 4.2
			radius = 1.3
		"hozyain_guby":
			_sph(parts, 2.8, Vector3(0, 4.0, 0), Color("3e4a4a"), Vector3(1.2, 1.0, 1.0))
			_sph(parts, 1.6, Vector3(0, 2.6, -2.2), Color("2c3434"), Vector3(1.4, 0.5, 1.0))
			for i in 6:
				var a := PI * 0.1 + i * PI * 0.16
				_c(parts, 0.5, 0.15, 6.0, Vector3(cos(a) * 3.2, 2.0, -sin(a) * 1.5), Color("4a5a3a"), Vector3(0.6, 0, cos(a) * 0.8))
			_eyes(root, Vector3(0, 5.0, -2.5), 0.3, Color("7affe0"))
			height = 8.0
			radius = 3.4
		"mga":
			for i in 11:
				var a := i * 2.4
				_sph(parts, 1.4 + 0.5 * (i % 3), Vector3(cos(a) * 2.0, 2.0 + i * 0.55, sin(a) * 2.0), Color("1c222c").lightened(0.04 * (i % 4)))
			var core := Placeholders.glow(Color("cfe0ff"), 6.0, 0.8)
			core.name = "Core"
			core.position = Vector3(0, 4.5, 0)
			root.add_child(core)
			height = 9.0
			radius = 3.5
		_:
			_b(parts, Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), Color.MAGENTA)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = Placeholders.merge_colored(parts)
	mi.material_override = Placeholders.mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	root.add_child(mi)
	root.set_meta("height", height)
	root.set_meta("radius", radius)
	return root


## A four-legged body: `length` long, `h` tall at the shoulder, head forward (-Z).
static func _beast(parts: Array, length: float, h: float, col: Color, head: Color, bulk: float = 1.0) -> void:
	var w := length * 0.3 * bulk
	_b(parts, Vector3(w, h * 0.45, length * 0.72), Vector3(0, h * 0.72, 0), col)
	var leg := h * 0.55
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_b(parts, Vector3(w * 0.28, leg, w * 0.28), Vector3(c.x * w * 0.32, leg * 0.5, c.y * length * 0.28), col.darkened(0.15))
	_b(parts, Vector3(w * 0.7, h * 0.34, length * 0.28), Vector3(0, h * 0.9, -length * 0.44), head)
	_b(parts, Vector3(w * 0.4, h * 0.18, length * 0.16), Vector3(0, h * 0.84, -length * 0.62), head.darkened(0.1))


static func _ears(parts: Array, length: float, h: float, col: Color) -> void:
	for s in [-1.0, 1.0]:
		_c(parts, 0.07 * length, 0.0, 0.16 * length, Vector3(0.1 * length * s, h * 1.12, -length * 0.42), col, Vector3.ZERO, 4)


static func _eyes(root: Node3D, at: Vector3, size: float, col: Color, one: bool = false) -> void:
	var eyes := Node3D.new()
	eyes.name = "Eyes"
	root.add_child(eyes)
	var sides: Array = [0.0] if one else [-1.0, 1.0]
	for s: float in sides:
		var g := Placeholders.glow(col, size * 4.0, 1.0)
		g.position = at + Vector3(s * size * 1.6, 0, 0)
		eyes.add_child(g)


static func _b(parts: Array, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	parts.append([bm, Transform3D(Basis.from_euler(rot), pos), col])


static func _sph(parts: Array, r: float, pos: Vector3, col: Color, scale: Vector3 = Vector3.ONE) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 7
	sm.rings = 4
	parts.append([sm, Transform3D(Basis.from_scale(scale), pos), col])


static func _c(parts: Array, bottom: float, top: float, h: float, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, seg: int = 6) -> void:
	parts.append([Placeholders._cyl(bottom, top, h, seg), Transform3D(Basis.from_euler(rot), pos), col])
