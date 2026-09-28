class_name PauseMenu
extends Control
## Pause (Esc): the world stops in a solo game (Game.paused), the mode can change at any time except during a
## guardian fight or a fire defence ("set_mode"), fine tuning too ("set_tuning"); the journal, saving,
## back to the menu, quitting. Only sends commands.

signal closed
signal journal_requested

var world
var _info: Label
var _modes: Array[Button] = []
var _checks: Dictionary = {}  # rule -> CheckBox
var _built := false
var _quiet := false  # while refreshing: don't send commands


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(p_world) -> void:
	world = p_world
	if not _built:
		_build()
	visible = true
	Game.paused = true
	refresh()


func close_window() -> void:
	visible = false
	Game.paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close_window()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_built = true
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.05, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.07, 0.1, 0.12, 0.96), 14, 30, Color(1, 1, 1, 0.1)))
	add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UiTheme.label(tr("pause.title"), 40, UiTheme.TEXT, "title"))
	_info = UiTheme.label("", 16, UiTheme.TEXT2)
	v.add_child(_info)
	v.add_child(UiTheme.label(tr("menu.danger").to_upper(), 13, UiTheme.BIRCH, "caps"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	for m: Dictionary in Content.db.raw["modes"]["modes"]:
		var b := Button.new()
		b.text = Loc.name_of(m["name"])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mid := String(m["id"])
		b.pressed.connect(func() -> void: _set_mode(mid))
		b.set_meta("mode", mid)
		modes.add_child(b)
		_modes.append(b)
	v.add_child(modes)
	v.add_child(UiTheme.label(tr("pause.mode_note"), 14, UiTheme.MUTED))
	v.add_child(UiTheme.label(tr("menu.tuning").to_upper(), 13, UiTheme.BIRCH, "caps"))
	var grid := GridContainer.new()
	grid.columns = 2
	for rule: String in ["storms", "cold", "durability", "night_raids"]:
		var c := MainMenu.check_box(tr("tuning." + rule))
		var r := rule
		c.toggled.connect(func(on: bool) -> void: _set_rule(r, on))
		grid.add_child(c)
		_checks[rule] = c
	v.add_child(grid)
	var sep := HSeparator.new()
	v.add_child(sep)
	for pair: Array in [["pause.resume", close_window], ["pause.journal", func() -> void:
			close_window()
			journal_requested.emit()], ["pause.save", _save], ["pause.save_menu", _save_menu], ["pause.quit", _quit]]:
		var b := Button.new()
		b.text = tr(pair[0])
		b.custom_minimum_size = Vector2(0, 42)
		b.pressed.connect(pair[1])
		v.add_child(b)


func refresh() -> void:
	var st: WorldState = Game.state
	_quiet = true
	var mode_name := Loc.name_of(Content.db.modes[st.mode]["name"])
	_info.text = tr("pause.info") % [st.name if st.name != "" else tr("menu.unnamed"), st.day, mode_name]
	for b in _modes:
		b.button_pressed = String(b.get_meta("mode")) == st.mode
	var r := st.rules()
	(_checks["storms"] as CheckBox).button_pressed = String(r["storms"]) == "capsize"
	(_checks["cold"] as CheckBox).button_pressed = String(r["cold"]) != "cosmetic"
	(_checks["durability"] as CheckBox).button_pressed = bool(r["durability"])
	(_checks["night_raids"] as CheckBox).button_pressed = bool(r["night_raids"])
	(_checks["night_raids"] as CheckBox).disabled = st.mode != "saga"
	_quiet = false


func _set_mode(m: String) -> void:
	if _quiet:
		return
	Game.submit({"type": "set_mode", "mode": m})
	refresh()


## A tuning box: on = the rule as the mode has it (or its milder "on"), off = only the look of it.
func _set_rule(rule: String, on: bool) -> void:
	if _quiet:
		return
	var own: Variant = Content.db.mode_rules(Game.state.mode)[rule]
	var value: Variant
	match rule:
		"storms":
			value = "capsize" if on else "cosmetic"
		"cold":
			value = (own if String(own) != "cosmetic" else "mild") if on else "cosmetic"
		_:
			value = on
	Game.submit({"type": "set_tuning", "rule": rule, "value": value})
	refresh()


func _save() -> void:
	var err: Error = Game.save()
	world.hud.toast(tr("toast.saved") if err == OK else tr("toast.save_failed"))


func _save_menu() -> void:
	Game.save()
	Game.paused = false
	Game.show_menu = true
	get_tree().reload_current_scene()


func _quit() -> void:
	Game.save()
	get_tree().quit()


func _process(_delta: float) -> void:
	if not visible:
		return
	size = get_viewport_rect().size
	var p := get_node("Panel") as Control
	p.position = (size - p.size) * 0.5
