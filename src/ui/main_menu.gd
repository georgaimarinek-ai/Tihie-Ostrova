class_name MainMenu
extends Control
## The main menu (docs/mockups/menu.png) over the living home island: on the left the title, "Continue" (the
## last saved world), "New world", co-op (later), settings, exit; on the right the new world: name, seed,
## danger (Quiet / Tale / Saga, Tale by default) and fine tuning. "Set sail" makes the world and starts it.

signal started

const MODE_TAG := "tale"  # "by default" (modes.json → default)

var _name: LineEdit
var _seed: LineEdit
var _mode := ""
var _cards: Dictionary = {}  # mode -> PanelContainer
var _checks: Dictionary = {}
var _last: Dictionary = {}
var _settings: SettingsWindow
var _slots: VBoxContainer
var _join_row: HBoxContainer
var _join_ip: LineEdit
var _join_status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mode = String(Content.db.raw["modes"]["default"])
	_last = Game.last_world()
	_build()
	add_child(_settings)
	_pick(_mode)


func _build() -> void:
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.04, 0.06, 0.88))
	grad.set_color(1, Color(0.02, 0.04, 0.06, 0.25))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# the left column
	var left := VBoxContainer.new()
	left.name = "Left"
	left.add_theme_constant_override("separation", 14)
	left.custom_minimum_size = Vector2(560, 0)
	add_child(left)
	left.add_child(UiTheme.label(tr("menu.kicker").to_upper(), 14, UiTheme.BIRCH, "caps"))
	var title := UiTheme.label(tr("menu.title"), 84, UiTheme.TEXT, "title")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(560, 0)
	left.add_child(title)
	var about := UiTheme.label(tr("menu.about"), 18, UiTheme.TEXT2)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(430, 0)
	left.add_child(about)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	left.add_child(gap)
	if not _last.is_empty():
		var cont := Button.new()
		cont.theme_type_variation = "FireButton"
		cont.custom_minimum_size = Vector2(380, 64)
		cont.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cont.alignment = HORIZONTAL_ALIGNMENT_LEFT
		cont.text = "%s\n%s" % [tr("menu.continue"), tr("menu.continue_sub") % [_last["name"], int(_last["day"]), Loc.name_of(Content.db.modes[_last["mode"]]["name"])]]
		cont.pressed.connect(_continue)
		left.add_child(cont)
	for pair: Array in [["menu.new", func() -> void: _name.grab_focus(), true], ["menu.coop", func() -> void:
			_join_row.visible = not _join_row.visible
			_join_status.visible = _join_row.visible, true]]:
		var b := Button.new()
		b.text = tr(pair[0])
		b.custom_minimum_size = Vector2(380, 50)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not pair[2]
		if (pair[1] as Callable).is_valid():
			b.pressed.connect(pair[1])
		left.add_child(b)
	# co-op: join a friend's world by address (hosting is from the pause menu of a running world)
	_join_row = HBoxContainer.new()
	_join_row.visible = false
	_join_row.add_theme_constant_override("separation", 8)
	_join_ip = LineEdit.new()
	_join_ip.placeholder_text = tr("coop.address")
	_join_ip.text = "127.0.0.1"
	_join_ip.custom_minimum_size = Vector2(230, 40)
	_join_row.add_child(_join_ip)
	var go_join := Button.new()
	go_join.text = tr("coop.join")
	go_join.custom_minimum_size = Vector2(140, 40)
	go_join.pressed.connect(_join)
	_join_row.add_child(go_join)
	left.add_child(_join_row)
	_join_status = UiTheme.label(tr("coop.hint"), 14, UiTheme.MUTED)
	_join_status.visible = false
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.custom_minimum_size = Vector2(380, 0)
	left.add_child(_join_status)
	Game.joined.connect(func() -> void: get_tree().reload_current_scene())
	Net.connection_failed.connect(func() -> void: _join_status.text = tr("coop.failed"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var settings := Button.new()
	settings.text = tr("menu.settings")
	settings.custom_minimum_size = Vector2(185, 44)
	settings.pressed.connect(func() -> void: _settings.open())
	row.add_child(settings)
	var quit := Button.new()
	quit.text = tr("menu.quit")
	quit.custom_minimum_size = Vector2(185, 44)
	quit.pressed.connect(func() -> void: get_tree().quit())
	row.add_child(quit)
	left.add_child(row)
	# the saved worlds (slots): load or delete
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 4)
	left.add_child(_slots)
	_fill_slots()
	_settings = SettingsWindow.new()
	_settings.name = "Settings"
	# the new world
	var panel := PanelContainer.new()
	panel.name = "NewWorld"
	panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.07, 0.1, 0.12, 0.94), 14, 30, Color(1, 1, 1, 0.1)))
	add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(540, 0)
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var nt := UiTheme.label(tr("menu.new_title"), 30, UiTheme.TEXT, "title")
	nt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nt)
	head.add_child(UiTheme.label(tr("menu.later"), 13, UiTheme.MUTED))
	v.add_child(head)
	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 14)
	var fn := VBoxContainer.new()
	fn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fn.add_child(UiTheme.label(tr("menu.name"), 14, UiTheme.TEXT2))
	_name = LineEdit.new()
	_name.text = tr("menu.default_name")
	fn.add_child(_name)
	fields.add_child(fn)
	var fs := VBoxContainer.new()
	fs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs.add_child(UiTheme.label(tr("menu.seed"), 14, UiTheme.TEXT2))
	_seed = LineEdit.new()
	_seed.text = str(randi() % 9000 + 1000)
	_seed.placeholder_text = tr("menu.random")
	fs.add_child(_seed)
	fields.add_child(fs)
	v.add_child(fields)
	v.add_child(UiTheme.label(tr("menu.danger").to_upper(), 13, UiTheme.BIRCH, "caps"))
	for m: Dictionary in Content.db.raw["modes"]["modes"]:
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 10)
		var dot := RadioDot.new()
		dot.custom_minimum_size = Vector2(18, 22)
		dot.name = "Dot"
		ch.add_child(dot)
		ch.add_child(UiTheme.label(Loc.name_of(m["name"]), 19, UiTheme.TEXT, "bold"))
		if String(m["id"]) == MODE_TAG:
			ch.add_child(UiTheme.label(tr("menu.default").to_upper(), 12, UiTheme.FIRE, "caps"))
		cv.add_child(ch)
		var sum := UiTheme.label(Loc.name_of(m["summary"]), 15, UiTheme.TEXT2)
		sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sum.custom_minimum_size = Vector2(450, 0)
		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", 28)
		indent.add_child(sum)
		cv.add_child(indent)
		card.add_child(cv)
		var mid := String(m["id"])
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				_pick(mid))
		v.add_child(card)
		_cards[mid] = card
	v.add_child(UiTheme.label("▾ " + tr("menu.tuning"), 15, UiTheme.TEXT, "bold"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for rule: String in ["storms", "cold", "durability", "night_raids"]:
		var c := MainMenu.check_box(tr("tuning." + rule))
		grid.add_child(c)
		_checks[rule] = c
	v.add_child(grid)
	var foot := HBoxContainer.new()
	var note := UiTheme.label(tr("menu.note"), 13, UiTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	var go := Button.new()
	go.theme_type_variation = "FireButton"
	go.text = tr("menu.sail")
	go.custom_minimum_size = Vector2(160, 54)
	go.pressed.connect(_start)
	foot.add_child(go)
	v.add_child(foot)


func _fill_slots() -> void:
	for c in _slots.get_children():
		_slots.remove_child(c)
		c.queue_free()
	var all := Game.worlds()
	if all.is_empty():
		return
	_slots.add_child(UiTheme.label(tr("menu.worlds").to_upper(), 13, UiTheme.BIRCH, "caps"))
	for w: Dictionary in all.slice(0, 5):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var load := Button.new()
		load.text = tr("menu.slot") % [w["name"], int(w["day"]), Loc.name_of(Content.db.modes[w["mode"]]["name"]), int(w["lit"])]
		load.alignment = HORIZONTAL_ALIGNMENT_LEFT
		load.custom_minimum_size = Vector2(330, 36)
		var dir: String = w["dir"]
		load.pressed.connect(func() -> void: _load(dir))
		row.add_child(load)
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = tr("menu.delete")
		del.custom_minimum_size = Vector2(44, 36)
		del.pressed.connect(func() -> void:
			if del.get_meta("armed", false):
				SaveCodec.delete_world(dir)
				_fill_slots()
			else:
				del.set_meta("armed", true)
				del.text = tr("menu.delete_sure"))
		row.add_child(del)
		_slots.add_child(row)


func _join() -> void:
	var addr := _join_ip.text.strip_edges()
	var port := Net.PORT
	if addr.contains(":"):
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	Net.leave()
	if Net.join(addr, port) == OK:
		_join_status.text = tr("coop.connecting") % addr
	else:
		_join_status.text = tr("coop.failed")


func _load(dir: String) -> void:
	if Game.load_world(dir):
		Game.show_menu = false
		started.emit()
		get_tree().reload_current_scene()


func _pick(mode: String) -> void:
	_mode = mode
	for m: String in _cards:
		var on := m == mode
		var sb := UiTheme.panel(Color(0.12, 0.14, 0.16, 0.9) if not on else Color(0.2, 0.16, 0.12, 0.95), 10, 16, UiTheme.FIRE if on else Color(1, 1, 1, 0.1))
		sb.set_border_width_all(2 if on else 1)
		(_cards[m] as PanelContainer).add_theme_stylebox_override("panel", sb)
		var dot := (_cards[m] as Node).find_child("Dot", true, false) as RadioDot
		dot.on = on
		dot.queue_redraw()
	var r := Content.db.mode_rules(mode)
	(_checks["storms"] as CheckBox).button_pressed = String(r["storms"]) == "capsize"
	(_checks["cold"] as CheckBox).button_pressed = String(r["cold"]) != "cosmetic"
	(_checks["durability"] as CheckBox).button_pressed = bool(r["durability"])
	(_checks["night_raids"] as CheckBox).button_pressed = bool(r["night_raids"])
	(_checks["night_raids"] as CheckBox).disabled = mode != "saga"


## The fine tuning that differs from the chosen mode's own rules.
func tuning() -> Dictionary:
	var r := Content.db.mode_rules(_mode)
	var want := {
		"storms": "capsize" if (_checks["storms"] as CheckBox).button_pressed else "cosmetic",
		"cold": (String(r["cold"]) if String(r["cold"]) != "cosmetic" else "mild") if (_checks["cold"] as CheckBox).button_pressed else "cosmetic",
		"durability": (_checks["durability"] as CheckBox).button_pressed,
		"night_raids": (_checks["night_raids"] as CheckBox).button_pressed and _mode == "saga",
	}
	var out := {}
	for k: String in want:
		if r.get(k) != want[k]:
			out[k] = want[k]
	return out


func _start() -> void:
	var s := _seed.text.strip_edges()
	var seed_value := int(s) if s.is_valid_int() else absi(s.hash()) % 100000 if s != "" else randi() % 100000
	Game.new_world(seed_value, _mode, _name.text.strip_edges(), tuning())
	Game.show_menu = false
	started.emit()
	get_tree().reload_current_scene()


func _continue() -> void:
	_load(String(_last["dir"]))


## A plain check box: a small square that fills fire-orange, the text beside it (the mockup's fine tuning).
static func check_box(text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	var empty := StyleBoxEmpty.new()
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		c.add_theme_stylebox_override(st, empty)
	c.add_theme_font_size_override("font_size", 15)
	c.add_theme_color_override("font_color", UiTheme.TEXT2)
	c.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	c.add_theme_color_override("font_pressed_color", UiTheme.TEXT2)
	c.add_theme_color_override("font_hover_pressed_color", UiTheme.TEXT)
	c.add_theme_color_override("font_disabled_color", UiTheme.MUTED)
	c.add_theme_icon_override("checked", _box_icon(true))
	c.add_theme_icon_override("unchecked", _box_icon(false))
	c.add_theme_icon_override("checked_disabled", _box_icon(true, true))
	c.add_theme_icon_override("unchecked_disabled", _box_icon(false, true))
	return c


static func _box_icon(on: bool, off: bool = false) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var fill := UiTheme.FIRE if on else Color(0, 0, 0, 0)
	var edge := Color(0.6, 0.62, 0.64) if off else (UiTheme.FIRE if on else UiTheme.TEXT2)
	for y in 16:
		for x in 16:
			var border := x < 2 or y < 2 or x > 13 or y > 13
			img.set_pixel(x, y, edge if border else (fill if not off else Color(0.4, 0.42, 0.44, 0.5 if on else 0.0)))
	if on:
		for i in 5:
			img.set_pixel(4 + i, 7 + i if i < 3 else 11 - (i - 2) * 2 + 1, Color("2a1606"))
	return ImageTexture.create_from_image(img)


## The radio dot of a mode card.
class RadioDot extends Control:
	var on := false

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		draw_arc(c, 7.0, 0, TAU, 20, UiTheme.FIRE if on else UiTheme.TEXT2, 2.0)
		if on:
			draw_circle(c, 3.5, UiTheme.FIRE)


func _process(_delta: float) -> void:
	size = get_viewport_rect().size
	var left := get_node("Left") as Control
	left.position = Vector2(72, maxf(40.0, size.y * 0.5 - left.size.y * 0.5))
	var nw := get_node("NewWorld") as Control
	nw.position = Vector2(size.x - nw.size.x - 56, maxf(30.0, size.y * 0.5 - nw.size.y * 0.5))
