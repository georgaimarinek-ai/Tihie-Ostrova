class_name SettingsWindow
extends Control
## Settings (roadmap phase 8): graphics (light = Compatibility, high = volumetric fog; the renderer changes
## on restart), full screen, sound buses, key bindings (click a key, press the new one), language. Saved to
## user://settings.cfg through Game.settings.

signal closed

var _rows: Dictionary = {}  # action -> Button
var _waiting := ""  # the action waiting for a key
var _restart: Label
var _built := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	if not _built:
		_build()
	visible = true
	_refresh()


func close_window() -> void:
	Game.settings.save_file()
	visible = false
	_waiting = ""
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _waiting != "" and event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.physical_keycode != KEY_ESCAPE:
			Game.settings.keys[_waiting] = int(k.physical_keycode)
			GameSettings.bind(_waiting, k.physical_keycode)
		_waiting = ""
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		close_window()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_built = true
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.05, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.07, 0.1, 0.12, 0.97), 14, 28, Color(1, 1, 1, 0.1)))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UiTheme.label(tr("settings.title"), 36, UiTheme.TEXT, "title"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	v.add_child(cols)
	# left: graphics, sound, language
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(UiTheme.label(tr("settings.graphics").to_upper(), 13, UiTheme.BIRCH, "caps"))
	var q := HBoxContainer.new()
	for pair: Array in [["high", "settings.high"], ["low", "settings.low"]]:
		var b := Button.new()
		b.text = tr(pair[1])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("quality", pair[0])
		var val: String = pair[0]
		b.pressed.connect(func() -> void:
			Game.settings.quality = val
			Game.settings.write_renderer_override()
			_refresh())
		q.add_child(b)
		_rows["quality_" + val] = b
	left.add_child(q)
	left.add_child(UiTheme.label(tr("settings.quality_note"), 13, UiTheme.MUTED))
	_restart = UiTheme.label(tr("settings.restart"), 14, UiTheme.FIRE)
	left.add_child(_restart)
	var fs := MainMenu.check_box(tr("settings.fullscreen"))
	fs.toggled.connect(func(on: bool) -> void:
		Game.settings.fullscreen = on
		Game.settings.apply())
	left.add_child(fs)
	_rows["fullscreen"] = fs
	left.add_child(UiTheme.label(tr("settings.sound").to_upper(), 13, UiTheme.BIRCH, "caps"))
	for bus: String in GameSettings.BUSES:
		var row := HBoxContainer.new()
		var name_l := UiTheme.label(tr("settings.bus." + bus), 15, UiTheme.TEXT2)
		name_l.custom_minimum_size = Vector2(130, 0)
		row.add_child(name_l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := bus
		sl.value_changed.connect(func(x: float) -> void:
			Game.settings.volume[b] = x
			Game.settings.apply())
		row.add_child(sl)
		left.add_child(row)
		_rows["bus_" + bus] = sl
	left.add_child(UiTheme.label(tr("settings.language").to_upper(), 13, UiTheme.BIRCH, "caps"))
	var lang := HBoxContainer.new()
	for code: String in ["ru", "en"]:
		var b := Button.new()
		b.text = tr("settings.lang." + code)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c := code
		b.pressed.connect(func() -> void: _set_language(c))
		lang.add_child(b)
		_rows["lang_" + code] = b
	left.add_child(lang)
	# right: keys
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	right.add_child(UiTheme.label(tr("settings.keys").to_upper(), 13, UiTheme.BIRCH, "caps"))
	for a: String in GameSettings.REBINDABLE:
		var row := HBoxContainer.new()
		var l := UiTheme.label(tr("key." + a), 15, UiTheme.TEXT2)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 32)
		var act := a
		b.pressed.connect(func() -> void:
			_waiting = act
			_refresh())
		row.add_child(b)
		right.add_child(row)
		_rows["key_" + a] = b
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	var done := Button.new()
	done.theme_type_variation = "FireButton"
	done.text = tr("settings.done")
	done.custom_minimum_size = Vector2(160, 46)
	done.pressed.connect(close_window)
	foot.add_child(done)
	v.add_child(foot)


func _refresh() -> void:
	var st := Game.settings
	for val: String in ["high", "low"]:
		(_rows["quality_" + val] as Button).button_pressed = st.quality == val
	_restart.visible = st.needs_restart()
	(_rows["fullscreen"] as CheckBox).set_pressed_no_signal(st.fullscreen)
	for bus: String in GameSettings.BUSES:
		(_rows["bus_" + bus] as HSlider).set_value_no_signal(float(st.volume[bus]))
	var cur := TranslationServer.get_locale().substr(0, 2)
	for code: String in ["ru", "en"]:
		(_rows["lang_" + code] as Button).button_pressed = cur == code
	for a: String in GameSettings.REBINDABLE:
		(_rows["key_" + a] as Button).text = tr("settings.press") if _waiting == a else GameSettings.key_name(a)


## A new language: the texts are built once, so the scene is rebuilt (the world stays in memory).
func _set_language(code: String) -> void:
	Game.settings.language = code
	Game.settings.save_file()
	TranslationServer.set_locale(code)
	get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	if not visible:
		return
	size = get_viewport_rect().size
	var p := get_node("Panel") as Control
	p.size = p.get_combined_minimum_size()
	p.position = (size - p.size) * 0.5
