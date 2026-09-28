class_name MapWindow
extends Control
## The chart, «Лоция» (M), docs/mockups/map.png: a paper map of what the fog has shown so far. Around home,
## around every lit beacon (its clear_radius) and along the way the player has come the paper is drawn;
## the rest is Mga. Islands by their coastlines, lit beacons with their fire, the next beacon as a light in
## the fog, home, the player's pomor crosses, the dotted path and where the player is now; region borders,
## a scale bar and a compass rose. On the right: the region, the legend and "Next". A mark set on the chart
## is followed by the compass. Only reads the world.

signal closed
signal mark_set(at: Vector2)

const PANEL_W := 358.0
const FOG := Color("c5c8c2")
const FOG_TEXT := Color("8e9590")
const PAPER := Color("e0d5bb")
const SIDE := Color("ece3cf")
const INK := Color("3a2c22")
const LAND := Color("b9ab88")
const TRAIL := Color("7a2e22")
const FIRE := Color("f0a060")
const HOME_SEEN_M := 380.0  # the paper around home
const TRAIL_SEEN_M := 110.0  # what the player saw along the way

var db: ContentDB
var state: WorldState
var map: WorldMap
var me := Vector2.ZERO
var yaw := 0.0
var trail := PackedVector2Array()
var mark := Vector2.INF
var center := Vector2.ZERO  # the world point in the middle of the map area
var zoom := 0.9  # pixels per metre
var picking := false  # "Set a mark": the next click on the map puts it there

var _built := false
var _drag := false
var _side_box: VBoxContainer
var _title: Label
var _count: Label
var _next_name: Label
var _next_info: Label
var _next_panel: PanelContainer
var _mark_button: Button
var _seen: Array[Vector3] = []  # x, z, radius


func _ready() -> void:
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(p_db: ContentDB, p_state: WorldState, p_map: WorldMap, p_me: Vector2, p_yaw: float, p_trail: PackedVector2Array, p_mark: Vector2) -> void:
	db = p_db
	state = p_state
	map = p_map
	me = p_me
	yaw = p_yaw
	trail = p_trail
	mark = p_mark
	picking = false
	if not _built:
		_build()
	_seen = seen_circles()
	_frame_view()
	visible = true
	_refresh_side()
	queue_redraw()


func close_window() -> void:
	visible = false
	picking = false
	closed.emit()


## Where the paper is drawn: home, the lit beacons' clearings and the way the player has come.
func seen_circles() -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3(0, 0, HOME_SEEN_M)]
	for bid: String in state.lit:
		var p := db.beacon_pos(bid)
		out.append(Vector3(p.x, p.y, float(db.beacons[bid]["clear_radius"])))
	for i in trail.size():
		out.append(Vector3(trail[i].x, trail[i].y, TRAIL_SEEN_M))
	out.append(Vector3(me.x, me.y, TRAIL_SEEN_M))
	return out


func is_seen(p: Vector2, margin: float = 0.0) -> bool:
	for c in _seen:
		if p.distance_to(Vector2(c.x, c.y)) <= c.z + margin:
			return true
	return false


## Start with the player and the next beacon both on the map.
func _frame_view() -> void:
	var area := _map_rect()
	var next := Progress.next_beacon(db, state)
	center = me
	zoom = 0.9
	if next != "":
		var b := db.beacon_pos(next)
		if b.distance_to(me) < 2200.0:
			center = (me + b) * 0.5
			var need := (b - me).abs() + Vector2(360, 360)
			zoom = clampf(minf(area.size.x / need.x, area.size.y / need.y), 0.2, 1.2)


func _map_rect() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(Vector2.ZERO, Vector2(s.x - PANEL_W, s.y))


func to_screen(p: Vector2) -> Vector2:
	return _map_rect().get_center() + (p - center) * zoom  # north (-z) is up


func to_world(s: Vector2) -> Vector2:
	return center + (s - _map_rect().get_center()) / zoom


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("map") or event.is_action_pressed("pause")):
		close_window()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and _map_rect().has_point(mb.position):
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var at := to_world(mb.position)
			zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.08, 3.0)
			center += at - to_world(mb.position)  # zoom around the cursor
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and picking:
				picking = false
				mark = to_world(mb.position)
				mark_set.emit(mark)
				_refresh_side()
				queue_redraw()
			else:
				_drag = mb.pressed
		accept_event()
	var mm := event as InputEventMouseMotion
	if mm != null and _drag:
		center -= mm.relative / zoom
		queue_redraw()
		accept_event()


func _on_mark_pressed() -> void:
	if mark != Vector2.INF:
		mark = Vector2.INF
		mark_set.emit(mark)
		picking = false
	else:
		picking = not picking
	_refresh_side()
	queue_redraw()


# ---------------------------------------------------------------- the side panel

func _build() -> void:
	_built = true
	var side := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SIDE
	sb.border_color = INK
	sb.border_width_left = 2
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 34
	sb.content_margin_bottom = 26
	side.add_theme_stylebox_override("panel", sb)
	side.name = "Side"
	add_child(side)
	_side_box = VBoxContainer.new()
	_side_box.add_theme_constant_override("separation", 10)
	side.add_child(_side_box)
	_side_box.add_child(UiTheme.label(tr("map.title").to_upper(), 13, TRAIL, "caps"))
	_title = UiTheme.label("", 38, INK, "title")
	_side_box.add_child(_title)
	_count = UiTheme.label("", 15, Color(INK, 0.75))
	_side_box.add_child(_count)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_side_box.add_child(gap)
	for row: Array in [["lit", "map.legend.lit"], ["next", "map.legend.next"], ["fog", "map.legend.fog"],
			["cross", "map.legend.cross"], ["trail", "map.legend.trail"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var icon := Legend.new()
		icon.kind = row[0]
		icon.custom_minimum_size = Vector2(24, 24)
		h.add_child(icon)
		h.add_child(UiTheme.label(tr(row[1]), 15, INK))
		_side_box.add_child(h)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 12)
	_side_box.add_child(gap2)
	_next_panel = PanelContainer.new()
	var nb := StyleBoxFlat.new()
	nb.bg_color = Color(1, 1, 1, 0.0)
	nb.border_color = Color(INK, 0.8)
	nb.set_border_width_all(1)
	nb.set_corner_radius_all(4)
	nb.set_content_margin_all(16)
	_next_panel.add_theme_stylebox_override("panel", nb)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 6)
	_next_panel.add_child(nv)
	nv.add_child(UiTheme.label(tr("map.next").to_upper(), 13, TRAIL, "caps"))
	_next_name = UiTheme.label("", 17, INK, "bold")
	_next_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_name.custom_minimum_size = Vector2(PANEL_W - 96, 0)
	nv.add_child(_next_name)
	_next_info = UiTheme.label("", 15, Color(INK, 0.8))
	_next_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_info.custom_minimum_size = Vector2(PANEL_W - 96, 0)
	nv.add_child(_next_info)
	_side_box.add_child(_next_panel)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_box.add_child(fill)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_mark_button = _button("", true)
	_mark_button.pressed.connect(_on_mark_pressed)
	buttons.add_child(_mark_button)
	var close := _button(tr("map.close"), false)
	close.pressed.connect(close_window)
	buttons.add_child(close)
	_side_box.add_child(buttons)


func _button(text: String, filled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if filled else Control.SIZE_SHRINK_END
	b.add_theme_font_override("font", UiTheme.font("bold"))
	b.add_theme_font_size_override("font_size", 16)
	for st: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = INK if filled else Color(1, 1, 1, 0.0)
		if st == "hover":
			sb.bg_color = INK.lightened(0.15) if filled else Color(INK, 0.08)
		sb.border_color = INK
		sb.set_border_width_all(0 if filled else 1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		b.add_theme_stylebox_override(st, sb)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, SIDE if filled else INK)
	return b


func _refresh_side() -> void:
	var rid := db.region_at(me)
	_title.text = Loc.region(db, rid)
	_count.text = tr("map.lit") % [state.lit.size(), db.beacon_order.size()]
	var next := Progress.next_beacon(db, state)
	if next == "":
		_next_name.text = tr("goal.free")
		_next_info.text = ""
	else:
		var v := db.beacon_pos(next) - me
		_next_name.text = "%s · %s %s" % [Loc.beacon(db, next), Loc.meters(v.length()), Loc.direction(v)]
		_next_info.text = next_info(next)
	if mark != Vector2.INF:
		_mark_button.text = tr("map.unmark")
	else:
		_mark_button.text = tr("map.pick") if picking else tr("map.mark")


## "Trial: the bells. Fuel: smolye ×6. Opens the Summer Coast."
func next_info(bid: String) -> String:
	var b: Dictionary = db.beacons[bid]
	var fuel: PackedStringArray = []
	var bag := ContentDB.bag(b["fuel"])
	for k: String in bag:
		fuel.append("%s ×%d" % [Loc.item(db, k).to_lower(), int(bag[k])])
	var text := tr("map.info") % [tr("trial." + String(b["trial"])), ", ".join(fuel)]
	if b.get("opens") != null:
		text += " " + tr("map.opens") % Loc.region(db, String(b["opens"]))
	return text


func _process(_delta: float) -> void:
	if not visible:
		return
	size = get_viewport_rect().size
	var side := get_node("Side") as Control
	side.position = Vector2(size.x - PANEL_W, 0)
	side.size = Vector2(PANEL_W, size.y)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if db == null:
		return
	var area := _map_rect()
	draw_rect(area, FOG)
	var title := UiTheme.font("title")
	draw_string(title, area.position + Vector2(118, 124), tr("map.fog").to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 86, FOG_TEXT)
	for c in _seen:
		draw_circle(to_screen(Vector2(c.x, c.y)), c.z * zoom, PAPER)
	_draw_borders(area)
	var next := Progress.next_beacon(db, state)
	for isl: IslandGen in map.islands:
		var kind := String(map.kind_of[isl.id])
		if is_seen(isl.center, isl.radius * 0.5):
			_draw_island(isl, kind)
		elif isl.id == next:
			_draw_hidden_beacon(isl)
	_draw_trail()
	for bid: String in state.lit:
		_draw_lit(bid)
	_draw_home()
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if String(pc["id"]) == "pomor_cross":
			var q: Vector3 = pc["pos"]
			_draw_cross(Vector2(q.x, q.z))
	if mark != Vector2.INF:
		var m := to_screen(mark)
		draw_arc(m, 11, 0, TAU, 20, TRAIL, 2.0)
		draw_line(m + Vector2(-6, -6), m + Vector2(6, 6), TRAIL, 2.0)
		draw_line(m + Vector2(-6, 6), m + Vector2(6, -6), TRAIL, 2.0)
	_draw_player()
	_draw_rose(Vector2(area.end.x - 100, 110))
	_draw_scale(Vector2(area.position.x + 60, area.end.y - 40))
	if picking:
		var f := UiTheme.font("bold")
		var t := tr("map.pick_hint")
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(f, Vector2(area.get_center().x - w * 0.5, area.end.y - 70), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TRAIL)


## Region borders: thin circles, dashed where the region beyond is still closed, with a label.
func _draw_borders(area: Rect2) -> void:
	var italic := UiTheme.font("italic")
	var order := ContentDB.REGION_ORDER
	for i in order.size() - 1:
		var rid: String = order[i]
		var r := float(db.regions[rid]["ring_m"][1])
		var c := to_screen(Vector2.ZERO)
		var beyond_open := db.region_open(order[i + 1], state.lit)
		var col := Color(INK, 0.35)
		var n := 256
		for k in n:
			if not beyond_open and k % 2 == 1:
				continue
			var a0 := k * TAU / n
			var a1 := (k + 1) * TAU / n
			draw_line(c + Vector2.from_angle(a0) * r * zoom, c + Vector2.from_angle(a1) * r * zoom, col, 1.2)
		# the label where the border crosses the lower part of the map
		var dir := (center - Vector2.ZERO)
		var a := dir.angle() if dir.length() > 1.0 else PI * 0.5
		for probe in [a, a + 0.25, a - 0.25, a + 0.5, a - 0.5]:
			var at := c + Vector2.from_angle(probe) * r * zoom
			if area.grow(-60).has_point(at):
				var text := tr("map.border") % [Loc.region(db, rid), int(r)]
				draw_string(italic, at + Vector2(-80, -14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK, 0.7))
				break


func _draw_island(isl: IslandGen, kind: String) -> void:
	var pts := PackedVector2Array()
	for q in map.outline(isl.id):
		pts.append(to_screen(q))
	if pts.size() < 3:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	if Geometry2D.triangulate_polygon(pts).is_empty():
		draw_circle(to_screen(isl.center), isl.radius * 0.8 * zoom, LAND)
	else:
		draw_colored_polygon(pts, LAND)
	draw_polyline(closed, INK, 2.0, true)
	if kind != "islet":
		# a few hatching strokes on the bigger islands, like the mockup
		var c := to_screen(isl.center)
		var r := isl.radius * zoom
		for k in 4:
			var o := c + Vector2(-0.35 + k * 0.22, -0.25 + k * 0.08) * r
			draw_line(o, o + Vector2(0.22, -0.22) * r, Color(INK, 0.35), 1.0)
	if kind == "beacon" and not state.lit.has(isl.id):
		_draw_tower(to_screen(isl.center), Color(INK, 0.8), false)
		_label(to_screen(isl.center) + Vector2(-40, 34), Loc.beacon(db, isl.id))


## The next beacon still in the fog: a lighter patch, a dashed tower in a white circle and "Name?".
func _draw_hidden_beacon(isl: IslandGen) -> void:
	var c := to_screen(isl.center)
	draw_circle(c, maxf(40.0, isl.radius * 1.3 * zoom), Color(1, 1, 1, 0.12))
	draw_arc(c, maxf(40.0, isl.radius * 1.3 * zoom), 0, TAU, 48, Color(INK, 0.18), 1.5)
	draw_circle(c, 22, Color(1, 1, 1, 0.85))
	_draw_tower(c, Color(INK, 0.7), true)
	_label(c + Vector2(-58, 60), Loc.beacon(db, isl.id) + "?")


func _draw_lit(bid: String) -> void:
	var p := to_screen(db.beacon_pos(bid))
	for k in 6:
		draw_circle(p, 34.0 - k * 5.0, Color(FIRE, 0.10 + k * 0.05))
	_draw_tower(p, INK, false)
	var flame := PackedVector2Array([p + Vector2(0, -26), p + Vector2(4, -18), p + Vector2(0, -14), p + Vector2(-4, -18)])
	draw_colored_polygon(flame, Color("e0701e"))
	_label(p + Vector2(-70, 36), Loc.beacon(db, bid))


func _draw_tower(p: Vector2, col: Color, dashed: bool) -> void:
	var segs := [[Vector2(-7, 12), Vector2(-3, -12)], [Vector2(7, 12), Vector2(3, -12)], [Vector2(-5, 0), Vector2(5, 0)],
		[Vector2(-7, 12), Vector2(7, 12)], [Vector2(-3, -12), Vector2(3, -12)]]
	for s: Array in segs:
		if dashed:
			draw_dashed_line(p + s[0], p + s[1], col, 1.6, 3.0)
		else:
			draw_line(p + s[0], p + s[1], col, 1.8)


func _draw_home() -> void:
	var izba: Vector3 = map.home["izba"]
	var p := to_screen(Vector2(izba.x, izba.z))
	var house := PackedVector2Array([p + Vector2(-12, 10), p + Vector2(-12, -2), p + Vector2(0, -12), p + Vector2(12, -2), p + Vector2(12, 10)])
	draw_colored_polygon(house, INK)
	_label(p + Vector2(20, 6), tr("map.home"))


func _draw_cross(p: Vector2) -> void:
	var s := to_screen(p)
	draw_line(s + Vector2(0, -10), s + Vector2(0, 10), INK, 1.8)
	draw_line(s + Vector2(-6, -3), s + Vector2(6, -3), INK, 1.8)
	draw_line(s + Vector2(-4, -7), s + Vector2(4, -7), INK, 1.4)
	draw_line(s + Vector2(-4, 6), s + Vector2(4, 3), INK, 1.4)


## The way the player has come: a dotted line of the trail colour.
func _draw_trail() -> void:
	var pts := trail.duplicate()
	pts.append(me)
	var carry := 0.0
	for i in range(1, pts.size()):
		var a := to_screen(pts[i - 1])
		var b := to_screen(pts[i])
		var len := a.distance_to(b)
		var t := carry
		while t < len:
			draw_circle(a.lerp(b, t / len), 1.6, TRAIL)
			t += 8.0
		carry = t - len


func _draw_player() -> void:
	var p := to_screen(me)
	var f := Vector2(-sin(yaw), -cos(yaw))
	var r := Vector2(-f.y, f.x)
	var tri := PackedVector2Array([p + f * 12.0, p - f * 6.0 + r * 7.0, p - f * 2.0, p - f * 6.0 - r * 7.0])
	draw_colored_polygon(tri, TRAIL)


func _draw_rose(c: Vector2) -> void:
	draw_arc(c, 34, 0, TAU, 40, INK, 1.5)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -42), c + Vector2(6, 0), c + Vector2(-6, 0)]), INK)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 42), c + Vector2(6, 0), c + Vector2(-6, 0)]), Color(INK, 0.55))
	draw_colored_polygon(PackedVector2Array([c + Vector2(42, 0), c + Vector2(0, 4), c + Vector2(0, -4)]), Color(INK, 0.55))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-42, 0), c + Vector2(0, 4), c + Vector2(0, -4)]), Color(INK, 0.55))
	var f := UiTheme.font("bold")
	var n := tr("map.north")
	draw_string(f, c + Vector2(-f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x * 0.5, -52), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)


## A scale bar of a round length that fits in about 180 px.
func _draw_scale(at: Vector2) -> void:
	var metres := 50.0
	for m: float in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0]:
		if m * zoom <= 200.0:
			metres = m
	var w := metres * zoom
	draw_line(at, at + Vector2(w, 0), INK, 1.6)
	for k in 3:
		var x := at.x + w * k * 0.5
		draw_line(Vector2(x, at.y - 5), Vector2(x, at.y + 5), INK, 1.4)
	var f := UiTheme.font("ui")
	draw_string(f, at + Vector2(-3, -12), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	var t := Loc.meters(metres)
	draw_string(f, at + Vector2(w - f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, -12), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)


func _label(at: Vector2, text: String) -> void:
	draw_string(UiTheme.font("italic"), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)


## The small signs of the legend.
class Legend extends Control:
	var kind := ""

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"lit":
				draw_circle(c, 10, Color("f0a060"))
			"next":
				draw_circle(c, 10, Color.WHITE)
				draw_arc(c, 10, 0, TAU, 24, Color("3a2c22"), 2.0)
				for k in 8:
					draw_arc(c, 10, k * TAU / 8.0, k * TAU / 8.0 + 0.3, 3, Color.WHITE, 3.0)
			"fog":
				draw_rect(Rect2(c - Vector2(10, 10), Vector2(20, 20)), Color("c5c8c2"))
			"cross":
				var ink := Color("3a2c22")
				draw_line(c + Vector2(0, -10), c + Vector2(0, 10), ink, 1.8)
				draw_line(c + Vector2(-6, -3), c + Vector2(6, -3), ink, 1.8)
				draw_line(c + Vector2(-4, -7), c + Vector2(4, -7), ink, 1.4)
				draw_line(c + Vector2(-4, 6), c + Vector2(4, 3), ink, 1.4)
			"trail":
				for k in 4:
					draw_circle(c + Vector2(-9 + k * 6, 0), 1.6, Color("7a2e22"))
