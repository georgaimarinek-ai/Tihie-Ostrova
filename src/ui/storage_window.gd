class_name StorageWindow
extends Control
## A chest or a boat's hold beside the bag (docs/01_GDD.md §8: the hold is the boat's own chest). Click a
## place to move the stack across ("store" / "take"); in the hold, "All into the storehouse" empties it into
## a chest by the pier ("unload"). Only sends commands.

signal closed

const SLOT := Vector2(62, 58)

var db: ContentDB
var state: WorldState
var pid := ""
var uid := ""  # chest piece uid or boat uid
var unload_to := ""  # chest near the boat for "unload" ("" = none)

var _title: Label
var _bag: GridContainer
var _box: GridContainer
var _box_title: Label
var _unload: Button
var _built := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(p_db: ContentDB, p_state: WorldState, p_pid: String, p_uid: String, p_unload_to: String = "") -> void:
	db = p_db
	state = p_state
	pid = p_pid
	uid = p_uid
	unload_to = p_unload_to
	if not _built:
		_build()
	visible = true
	refresh()


func close_window() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("inventory") or event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close_window()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_built = true
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.add_theme_constant_override("separation", 20)
	add_child(root)
	var head := HBoxContainer.new()
	_title = UiTheme.label("", 40, UiTheme.TEXT, "title")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(48, 44)
	close.pressed.connect(close_window)
	head.add_child(close)
	root.add_child(head)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)
	body.add_child(_side(tr("ui.bag"), true))
	body.add_child(_side("", false))
	_unload = Button.new()
	_unload.theme_type_variation = "FireButton"
	_unload.custom_minimum_size = Vector2(0, 50)
	_unload.text = tr("ui.unload")
	_unload.pressed.connect(func() -> void: Game.submit({"type": "unload", "boat": uid, "chest": unload_to}))
	root.add_child(_unload)
	root.resized.connect(func() -> void: root.position = (get_viewport_rect().size - root.size) * 0.5)


func _side(title: String, bag: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.04, 0.07, 0.09, 0.92), 14, 22, Color(1, 1, 1, 0.08)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var t := UiTheme.label(title.to_upper(), 14, UiTheme.BIRCH, "caps")
	v.add_child(t)
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	p.add_child(v)
	if bag:
		_bag = g
	else:
		_box = g
		_box_title = t
	return p


func _container() -> Inventory:
	if state.pieces.has(uid):
		return state.pieces[uid].get("inv")
	if state.boats.has(uid):
		return state.boats[uid]["cargo"]
	return null


func refresh() -> void:
	if not visible or not _built:
		return
	var box := _container()
	if box == null:
		close_window()
		return
	if state.pieces.has(uid):
		_title.text = Loc.name_of(db.pieces[state.pieces[uid]["id"]]["name"]).to_upper()
		_box_title.text = Loc.name_of(db.pieces[state.pieces[uid]["id"]]["name"]).to_upper()
	else:
		_title.text = Loc.name_of(db.boats[state.boats[uid]["type"]]["name"]).to_upper()
		_box_title.text = tr("hud.hold").to_upper()
	_fill(_bag, state.inv(pid), "store")
	_fill(_box, box, "take")
	_unload.visible = unload_to != "" and state.boats.has(uid) and not box.is_empty()


func _fill(grid: GridContainer, inv: Inventory, command: String) -> void:
	for c in grid.get_children():
		c.queue_free()
	for i in inv.size:
		var s: Dictionary = inv.slots[i]
		var b := Button.new()
		b.custom_minimum_size = SLOT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiTheme.panel(Color(0.12, 0.15, 0.18, 0.9), 10, 4, Color(1, 1, 1, 0.06)))
		b.add_theme_stylebox_override("hover", UiTheme.panel(Color(0.18, 0.21, 0.24, 0.95), 10, 4, UiTheme.FIRE))
		if s.is_empty():
			b.disabled = true
			b.add_theme_stylebox_override("disabled", UiTheme.panel(Color(0.08, 0.1, 0.12, 0.6), 10, 4, Color(1, 1, 1, 0.04)))
		else:
			var icon := ItemIcon.new(String(s["id"]), int(s["n"]))
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 6
			icon.offset_top = 4
			icon.offset_right = -4
			icon.offset_bottom = -4
			b.add_child(icon)
			b.tooltip_text = Loc.item(db, s["id"])
			var slot := i
			b.pressed.connect(func() -> void: Game.submit({"type": command, "uid": uid, "slot": slot}))
		grid.add_child(b)
