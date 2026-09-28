class_name EveningWindow
extends Control
## "An evening by the stove" (docs/mockups/evening.png, docs/01_GDD.md §15): on the way out, what this evening
## brought — the beacon lit, what was built and gathered, the journal's new pages, what opened — and what to do
## next time (the next beacon, where, what fuel). The world is saved first. "A little more" goes back to the
## game, "Until tomorrow" quits.

signal closed

var db: ContentDB
var state: WorldState
var _built := false
var _box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(p_db: ContentDB, p_state: WorldState, where: Vector3) -> void:
	db = p_db
	state = p_state
	Game.save()
	Game.paused = true
	if not _built:
		_built = true
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.03, 0.04, 0.55)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(shade)
		var panel := PanelContainer.new()
		panel.name = "Panel"
		panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.08, 0.08, 0.08, 0.9), 14, 36, Color(1, 0.6, 0.25, 0.3)))
		add_child(panel)
		_box = VBoxContainer.new()
		_box.custom_minimum_size = Vector2(600, 0)
		_box.add_theme_constant_override("separation", 12)
		panel.add_child(_box)
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_fill(where)
	visible = true


func close_window() -> void:
	visible = false
	Game.paused = false
	closed.emit()


## "1 h 12 min" of this evening.
static func session_time(ms: int) -> String:
	var m := int(ms / 60000.0)
	if m < 60:
		return Loc.t("evening.min") % m
	return Loc.t("evening.hmin") % [m / 60, m % 60]


## The rows: [label, value] for what this evening brought (empty values are left out).
func rows() -> Array:
	var s: Dictionary = Game.session
	var out: Array = []
	var lit: Array = s.get("lit", [])
	if not lit.is_empty():
		out.append([tr("evening.lit"), ", ".join(lit.map(func(b: String) -> String: return Loc.beacon(db, b)))])
	var built: Dictionary = s.get("built", {})
	if not built.is_empty():
		var parts: PackedStringArray = []
		for id: String in built:
			var n := int(built[id])
			parts.append(Loc.name_of(db.pieces[id]["name"]).to_lower() + (" ×%d" % n if n > 1 else ""))
		out.append([tr("evening.built"), ", ".join(parts)])
	var got: Dictionary = s.get("gathered", {})
	if not got.is_empty():
		var ids := got.keys()
		ids.sort_custom(func(a: String, b: String) -> bool: return int(got[a]) > int(got[b]))
		var parts: PackedStringArray = []
		for id: String in ids.slice(0, 3):
			parts.append("%s %d" % [Loc.item(db, id).to_lower(), int(got[id])])
		out.append([tr("evening.gathered"), " · ".join(parts)])
	var pages: Array = s.get("pages", [])
	if not pages.is_empty():
		var names: PackedStringArray = []
		for p: String in pages.slice(0, 3):
			names.append(Loc.name_of(db.creatures[p]["name"]) if db.creatures.has(p) else tr("journal.chud_circle"))
		out.append([tr("evening.journal"), ", ".join(names)])
	if out.is_empty():
		out.append([tr("evening.quiet"), tr("evening.quiet_value")])
	return out


## "Next time": the next beacon, how far and where, its fuel and whether the bag has it.
func next_time(where: Vector3) -> String:
	var next := Progress.next_beacon(db, state)
	if next == "":
		return tr("goal.free")
	var v := db.beacon_pos(next) - Vector2(where.x, where.z)
	var fuel := ContentDB.bag(db.beacons[next]["fuel"])
	var text := tr("evening.next") % [Loc.beacon(db, next), Loc.meters(v.length()), Loc.direction(v), ItemInfo.bag_text(db, fuel)]
	var pid := Net.local_player_id()
	if state.players.has(pid) and state.inv(pid).has_bag(fuel):
		text += " " + tr("evening.fuel_ready")
	return text


func _fill(where: Vector3) -> void:
	var rid := db.region_at(Vector2(where.x, where.z))
	var ms := Time.get_ticks_msec() - int(Game.session.get("started", Time.get_ticks_msec()))
	_box.add_child(UiTheme.label((tr("evening.kicker") % [state.day, Loc.region(db, rid), session_time(ms)]).to_upper(), 13, UiTheme.FIRE, "caps"))
	_box.add_child(UiTheme.label(tr("evening.title"), 44, UiTheme.TEXT, "title"))
	for r: Array in rows():
		var sep := HSeparator.new()
		_box.add_child(sep)
		var row := HBoxContainer.new()
		var l := UiTheme.label(String(r[0]), 17, UiTheme.TEXT2)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var val := UiTheme.label(String(r[1]), 17, UiTheme.TEXT, "bold")
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val.custom_minimum_size = Vector2(360, 0)
		row.add_child(val)
		_box.add_child(row)
	var chips: Array = []
	for u: Array in (Game.session.get("unlocks", []) as Array).slice(0, 6):
		var kind: String = u[0]
		var id: String = u[1]
		match kind:
			"pieces":
				chips.append(Loc.name_of(db.pieces[id]["name"]))
			"boats":
				chips.append(Loc.name_of(db.boats[id]["name"]))
			"recipes":
				for item: String in db.recipes[id]["output"]:
					chips.append(Loc.item(db, item))
	if not chips.is_empty():
		_box.add_child(UiTheme.label(tr("evening.opened").to_upper(), 13, UiTheme.BIRCH, "caps"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		for c: String in chips:
			var cp := PanelContainer.new()
			cp.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.2, 0.2, 0.2, 0.9), 8, 10, Color(1, 1, 1, 0.12)))
			cp.add_child(UiTheme.label(c, 15))
			flow.add_child(cp)
		_box.add_child(flow)
	var nx := PanelContainer.new()
	nx.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.18, 0.18, 0.18, 0.9), 8, 16))
	var nv := VBoxContainer.new()
	nv.add_child(UiTheme.label(tr("evening.next_title").to_upper(), 13, UiTheme.BIRCH, "caps"))
	var nt := UiTheme.label(next_time(where), 17, UiTheme.TEXT)
	nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nt.custom_minimum_size = Vector2(560, 0)
	nv.add_child(nt)
	nx.add_child(nv)
	_box.add_child(nx)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	var saved := UiTheme.label(tr("evening.saved") % SaveCodec.backups(Game.world_dir()), 14, UiTheme.MUTED)
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(saved)
	var more := Button.new()
	more.text = tr("evening.more")
	more.custom_minimum_size = Vector2(160, 48)
	more.pressed.connect(close_window)
	foot.add_child(more)
	var bye := Button.new()
	bye.theme_type_variation = "FireButton"
	bye.text = tr("evening.bye")
	bye.custom_minimum_size = Vector2(190, 48)
	bye.pressed.connect(func() -> void: Game.quit_now())
	foot.add_child(bye)
	_box.add_child(foot)


func _process(_delta: float) -> void:
	if not visible:
		return
	size = get_viewport_rect().size
	var p := get_node("Panel") as Control
	p.size = p.get_combined_minimum_size()
	p.position = (size - p.size) * 0.5
