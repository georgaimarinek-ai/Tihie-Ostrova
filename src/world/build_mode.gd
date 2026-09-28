class_name BuildMode
extends Node3D
## The build mode (B; roadmap phase 4, mockup docs/mockups/build.png). Pick a piece on the bar below; a
## ghost follows the mouse on the 2 m grid (Building.snap) and is green when "place" would pass
## (Game.check: the same command with dry = true) or red with the reason. R turns it, the left button
## builds, the right button takes the piece under the cursor down — everything spent comes back.
## Top right: comfort at the nearest bed. Only a view: building goes through Game.submit().

const GHOST_SHADER := preload("res://src/shaders/ghost.gdshader")
const REACH := 9.0
## Bar categories → piece ids (every piece in buildables.json is in exactly one; tests check it).
const CATEGORIES: Array = [
	["build.cat.walls", ["log_foundation", "log_wall", "log_wall_half", "plank_floor", "pier"]],
	["build.cat.roof", ["gable_roof", "roof_ridge", "carved_horse"]],
	["build.cat.doors", ["door", "window_hatch", "mica_window"]],
	["build.cat.furniture", ["bench", "table", "bed", "chest", "drying_rack", "oil_lamp"]],
	["build.cat.stations", ["workbench", "hearth", "tar_pit", "bathhouse_stove", "kiln", "bloomery", "forge", "stove", "quern", "loom", "boatyard", "trypot", "salt_pan"]],
	["build.cat.farm", ["garden_bed", "sheep_pen"]],
	["build.cat.marks", ["pomor_cross"]],
]

signal exited

var db: ContentDB
var state: WorldState
var map: WorldMap
var player: Player
var cam: CameraRig
var pid := ""
var active := false
var category := 0
var piece := "log_wall"
var turns := 0
var ok := false
var reason := ""
var hover_uid := ""
var snap_result: Dictionary = {}
## Screenshots and tests: aim here instead of under the mouse.
var debug_aim: Variant = null

var _ghost: Node3D
var _ghost_mat: ShaderMaterial
var _ghost_piece := ""
var _ui: Control
var _tabs: HBoxContainer
var _cards: HBoxContainer
var _carry: Label
var _comfort_title: Label
var _comfort_bar: ProgressBar
var _comfort_list: GridContainer
var _comfort_rest: Label
var _comfort_hint: Label
var _tip: PanelContainer
var _tip_label: RichTextLabel
var _ui_dirty := true


func setup(p_db: ContentDB, p_state: WorldState, p_map: WorldMap, p_player: Player, p_cam: CameraRig, p_pid: String, ui_parent: Node) -> void:
	db = p_db
	state = p_state
	map = p_map
	player = p_player
	cam = p_cam
	pid = p_pid
	name = "BuildMode"
	_ghost_mat = ShaderMaterial.new()
	_ghost_mat.shader = GHOST_SHADER
	_build_ui()
	ui_parent.add_child(_ui)
	_ui.visible = false


func enter() -> void:
	active = true
	cam.build_mode = true
	_ui.visible = true
	_ui_dirty = true
	_refresh_ui()


func exit() -> void:
	active = false
	cam.build_mode = false
	_ui.visible = false
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_ghost_piece = ""
	exited.emit()


func refresh() -> void:
	_ui_dirty = true


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("rotate"):
		turns = (turns + 1) % 8
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_menu") or event.is_action_pressed("pause"):
		exit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			place()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			remove_hovered()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var list: Array = CATEGORIES[category][1]
			var i := list.find(piece)
			piece = list[posmod(i + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), list.size())]
			_ui_dirty = true
			get_viewport().set_input_as_handled()


func place() -> void:
	if snap_result.is_empty() or not ok:
		return
	var p: Vector3 = snap_result["pos"]
	Game.submit({"type": "move", "pos": _v(player.global_position)})
	Game.submit({"type": "place", "piece": piece, "pos": [p.x, p.y, p.z], "rot": snap_result["rot"]})
	_ui_dirty = true


func remove_hovered() -> void:
	if hover_uid == "":
		return
	Game.submit({"type": "move", "pos": _v(player.global_position)})
	Game.submit({"type": "remove", "uid": hover_uid})
	_ui_dirty = true


static func _v(p: Vector3) -> Array:
	return [p.x, p.y, p.z]


func _process(_delta: float) -> void:
	if not active:
		return
	if not db.is_unlocked(db.pieces[piece]["unlock"], state.lit):
		piece = _first_unlocked(category)
	var hit := _ray() if debug_aim == null else {}
	var aim: Vector3 = hit.get("position", player.global_position - player.model.global_transform.basis.z * 3.0)
	if debug_aim != null:
		aim = debug_aim
	var flat := Vector2(aim.x - player.global_position.x, aim.z - player.global_position.z)
	if flat.length() > REACH:
		flat = flat.normalized() * REACH
		aim = Vector3(player.global_position.x + flat.x, 0.0, player.global_position.z + flat.y)
		aim.y = map.ground_at(aim.x, aim.z)
	hover_uid = _uid_of(hit.get("collider"))
	snap_result = Building.snap(db, state, map, piece, aim, turns)
	var p: Vector3 = snap_result["pos"]
	var res := Game.check({"type": "place", "piece": piece, "pos": [p.x, p.y, p.z], "rot": snap_result["rot"]})
	ok = res["ok"]
	reason = String(res["error"])
	_update_ghost()
	_update_tip()
	if _ui_dirty:
		_refresh_ui()


func _ray() -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)


## The placed piece a collider belongs to (PiecesView marks piece roots with meta "uid").
func _uid_of(collider: Variant) -> String:
	var n := collider as Node
	while n != null:
		if n.has_meta("uid"):
			return String(n.get_meta("uid"))
		n = n.get_parent()
	return ""


func _update_ghost() -> void:
	if _ghost_piece != piece:
		if _ghost != null:
			_ghost.queue_free()
		_ghost = ModelLibrary.instance("pieces", piece)
		for mi: MeshInstance3D in ModelLibrary._meshes(_ghost):
			mi.material_override = _ghost_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for si in mi.get_surface_override_material_count():
				mi.set_surface_override_material(si, null)
		for c in _ghost.find_children("*", "Light3D", true, false):
			c.queue_free()
		add_child(_ghost)
		_ghost_piece = piece
	_ghost.global_position = snap_result["pos"]
	_ghost.rotation = Vector3(0, float(snap_result["rot"]), 0)
	_ghost.visible = hover_uid == "" or ok
	_ghost_mat.set_shader_parameter("color", UiTheme.OK if ok else UiTheme.RED)


func _update_tip() -> void:
	var text := ""
	if hover_uid != "" and not ok and state.pieces.has(hover_uid):
		var pc: Dictionary = state.pieces[hover_uid]
		text = "[color=#e3806b][b]%s[/b][/color] · %s" % [tr("build.remove") % Loc.name_of(db.pieces[pc["id"]]["name"]), tr("build.refund") % ItemInfo.bag_text(db, db.pieces[pc["id"]]["cost"])]
	else:
		var p: Dictionary = db.pieces[piece]
		var cost := ContentDB.bag(p["cost"])
		var parts: PackedStringArray = []
		var inv := state.inv(pid)
		for k: String in cost:
			parts.append("%s %d → %d" % [Loc.item(db, k), inv.count(k), maxi(0, inv.count(k) - int(cost[k]))])
		var how := tr("build.joins") if String(snap_result.get("hint", "")) == "joins" else tr("build.on_ground")
		if ok:
			text = "[color=#8fe3a0][b]%s[/b][/color] · %s · %s" % [Loc.name_of(p["name"]), how, " · ".join(parts)]
		else:
			text = "[color=#e3806b][b]%s[/b][/color] · %s" % [Loc.name_of(p["name"]), tr("cmd." + reason)]
	_tip_label.text = text
	var anchor: Vector3 = (snap_result["pos"] as Vector3) + Vector3(0, 3.0, 0)
	if hover_uid != "" and not ok and state.pieces.has(hover_uid):
		anchor = (state.pieces[hover_uid]["pos"] as Vector3) + Vector3(0, 3.0, 0)
	if cam.is_position_behind(anchor):
		_tip.visible = false
		return
	_tip.visible = true
	_tip.size = Vector2.ZERO
	_tip.position = cam.unproject_position(anchor) - Vector2(_tip.size.x * 0.5, _tip.size.y)


func _first_unlocked(cat: int) -> String:
	for id: String in CATEGORIES[cat][1]:
		if db.is_unlocked(db.pieces[id]["unlock"], state.lit):
			return id
	return String(CATEGORIES[cat][1][0])


# ---------------------------------------------------------------- the panels

func _build_ui() -> void:
	_ui = Control.new()
	_ui.name = "BuildUi"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UiTheme.theme()
	# help, top left
	var help := PanelContainer.new()
	help.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.2, 0.22, 0.24, 0.82), 12, 16))
	help.position = Vector2(30, 24)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hv.add_child(UiTheme.label(tr("build.title").to_upper(), 14, UiTheme.BIRCH, "caps"))
	for key: String in ["build.help_turn", "build.help_remove", "build.help_exit"]:
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.scroll_active = false
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.add_theme_font_size_override("normal_font_size", 16)
		l.text = tr(key)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hv.add_child(l)
	help.add_child(hv)
	_ui.add_child(help)
	# comfort, top right
	var cp := PanelContainer.new()
	cp.name = "Comfort"
	cp.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.2, 0.22, 0.24, 0.85), 12, 18))
	cp.custom_minimum_size = Vector2(300, 0)
	cp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	_comfort_title = UiTheme.label("", 15, UiTheme.BIRCH, "caps")
	cv.add_child(_comfort_title)
	_comfort_bar = ProgressBar.new()
	_comfort_bar.show_percentage = false
	_comfort_bar.custom_minimum_size = Vector2(0, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.FIRE
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(4)
	_comfort_bar.add_theme_stylebox_override("fill", fill)
	_comfort_bar.add_theme_stylebox_override("background", bg)
	cv.add_child(_comfort_bar)
	_comfort_list = GridContainer.new()
	_comfort_list.columns = 2
	_comfort_list.add_theme_constant_override("h_separation", 26)
	cv.add_child(_comfort_list)
	cv.add_child(HSeparator.new())
	_comfort_rest = UiTheme.label("", 16, UiTheme.TEXT)
	cv.add_child(_comfort_rest)
	_comfort_hint = UiTheme.label("", 14, UiTheme.MUTED)
	_comfort_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_comfort_hint.custom_minimum_size = Vector2(264, 0)
	cv.add_child(_comfort_hint)
	cp.add_child(cv)
	_ui.add_child(cp)
	# the bar at the bottom
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.03, 0.05, 0.06, 0.5)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_ui.add_child(_tabs)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 12)
	_ui.add_child(_cards)
	_carry = UiTheme.label("", 15, UiTheme.TEXT2)
	_carry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_carry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(_carry)
	# the tip over the ghost
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.06, 0.09, 0.11, 0.85), 8, 12))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true
	_tip_label.fit_content = true
	_tip_label.scroll_active = false
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip_label.add_theme_font_size_override("normal_font_size", 16)
	_tip_label.add_theme_font_size_override("bold_font_size", 16)
	_tip_label.add_theme_font_override("bold_font", UiTheme.font("bold"))
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_label)
	_ui.add_child(_tip)
	_ui.resized.connect(_layout)


func _layout() -> void:
	var s := _ui.get_viewport_rect().size
	(_ui.get_node("Comfort") as Control).position = Vector2(s.x - 30 - 300, 24)
	var shade := _ui.get_node("Shade") as ColorRect
	shade.position = Vector2(0, s.y - 196)
	shade.size = Vector2(s.x, 196)
	_tabs.position = Vector2(30, s.y - 184)
	_cards.position = Vector2(30, s.y - 134)
	_carry.position = Vector2(s.x - 440, s.y - 118)
	_carry.size = Vector2(410, 90)


func _refresh_ui() -> void:
	_ui_dirty = false
	_layout()
	for c in _tabs.get_children():
		c.queue_free()
	for i in CATEGORIES.size():
		var b := Button.new()
		b.text = tr(CATEGORIES[i][0])
		b.custom_minimum_size = Vector2(0, 40)
		b.focus_mode = Control.FOCUS_NONE
		if i == category:
			b.add_theme_stylebox_override("normal", UiTheme.panel(UiTheme.TEXT, 10, 14))
			b.add_theme_color_override("font_color", Color(0.08, 0.1, 0.12))
		var idx := i
		b.pressed.connect(func() -> void:
			category = idx
			piece = _first_unlocked(idx)
			_ui_dirty = true)
		_tabs.add_child(b)
	for c in _cards.get_children():
		c.queue_free()
	var inv := state.inv(pid)
	var mats := {}
	for id: String in CATEGORIES[category][1]:
		var p: Dictionary = db.pieces[id]
		var unlocked := db.is_unlocked(p["unlock"], state.lit)
		for k: String in p["cost"]:
			mats[k] = true
		var card := PanelContainer.new()
		var chosen := id == piece
		var afford := inv.has_bag(ContentDB.bag(p["cost"]))
		card.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.08, 0.11, 0.13, 0.92 if unlocked else 0.5), 12, 14, UiTheme.OK if chosen else Color(1, 1, 1, 0.1)))
		card.custom_minimum_size = Vector2(186, 104)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var icon := ItemIcon.new(id)
		icon.custom_minimum_size = Vector2(30, 30)
		icon.color = UiTheme.OK if chosen else (UiTheme.TEXT if unlocked else UiTheme.MUTED)
		v.add_child(icon)
		v.add_child(UiTheme.label(Loc.name_of(p["name"]), 17, UiTheme.TEXT if unlocked and afford else UiTheme.MUTED, "bold"))
		var sub := ItemInfo.bag_text(db, p["cost"]) if unlocked else tr("ui.opens_at") % Loc.beacon(db, p["unlock"])
		v.add_child(UiTheme.label(sub, 14, UiTheme.TEXT2 if unlocked else UiTheme.MUTED))
		card.add_child(v)
		if unlocked:
			card.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					piece = id
					_ui_dirty = true
					_ui.get_viewport().set_input_as_handled())
		_cards.add_child(card)
	var have: PackedStringArray = []
	for k: String in mats:
		have.append("%s %d" % [Loc.item(db, k), inv.count(k)])
	_carry.text = tr("build.carry") % " · ".join(have) + "\n" + tr("build.no_collapse")
	_refresh_comfort()


func _refresh_comfort() -> void:
	for c in _comfort_list.get_children():
		c.queue_free()
	var bed := Comfort.nearest_bed(db, state, player.global_position, 40.0)
	var at: Vector3 = state.pieces[bed]["pos"] if bed != "" else player.global_position
	var cf := Comfort.at(db, state, at)
	_comfort_title.text = "%s   %d / %d" % [tr("build.comfort").to_upper(), int(cf["total"]), int(cf["max"])]
	_comfort_bar.max_value = float(cf["max"])
	_comfort_bar.value = float(cf["total"])
	for part: Dictionary in cf["parts"]:
		_comfort_list.add_child(UiTheme.label("%s +%d" % [Loc.name_of(db.pieces[part["id"]]["name"]), int(part["comfort"])], 15, UiTheme.TEXT2))
	if bed == "":
		_comfort_rest.text = tr("build.no_bed")
	else:
		_comfort_rest.text = tr("build.rest_after") % roundi(Comfort.rested_minutes(db, int(cf["total"])))
	# the biggest comfort still missing
	var have := {}
	for part: Dictionary in cf["parts"]:
		have[part["id"]] = true
	var best := ""
	for id: String in db.pieces:
		var p: Dictionary = db.pieces[id]
		if p.has("comfort") and not have.has(id) and (best == "" or int(p["comfort"]) > int(db.pieces[best]["comfort"])):
			best = id
	_comfort_hint.text = ""
	if best != "":
		var p: Dictionary = db.pieces[best]
		var hint := tr("build.next_comfort") % [Loc.name_of(p["name"]), int(p["comfort"])]
		if not db.is_unlocked(p["unlock"], state.lit):
			hint += " " + tr("build.opens_later") % Loc.beacon(db, p["unlock"])
		_comfort_hint.text = hint
