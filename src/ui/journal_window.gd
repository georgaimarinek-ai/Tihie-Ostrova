class_name JournalWindow
extends Control
## The journal of tales (J), docs/01_GDD.md §11: every creature met and every Chud ruin explored opens a page
## (WorldState.journal, page id -> day). Paper like the chart: sections on the left, the page on the right.
## The tales themselves live in i18n (tale.<id>); the author's final texts replace the TODO drafts.

signal closed

const PAPER := Color("ece3cf")
const INK := Color("3a2c22")
const RED := Color("7a2e22")
const SECTIONS := [
	["journal.spirits", ["spirit", "wonder", "legend"]],
	["journal.beasts", ["animal", "predator"]],
	["journal.fog", ["fog", "elite"]],
	["journal.guardians", ["guardian"]],
]

var db: ContentDB
var state: WorldState
var selected := ""
var _list: VBoxContainer
var _title: Label
var _meta: Label
var _text: Label
var _count: Label
var _built := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(p_db: ContentDB, p_state: WorldState) -> void:
	db = p_db
	state = p_state
	if not _built:
		_build()
	if selected == "" or not state.journal.has(selected):
		selected = _latest()
	visible = true
	refresh()


func close_window() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("journal") or event.is_action_pressed("pause")):
		close_window()
		get_viewport().set_input_as_handled()


func _latest() -> String:
	var best := ""
	var best_day := -1
	for k: String in state.journal:
		if int(state.journal[k]) >= best_day:
			best_day = int(state.journal[k])
			best = k
	return best


func _build() -> void:
	_built = true
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.05, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var book := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(28)
	book.add_theme_stylebox_override("panel", sb)
	book.name = "Book"
	add_child(book)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	book.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	left.add_child(UiTheme.label(tr("journal.kicker").to_upper(), 13, RED, "caps"))
	left.add_child(UiTheme.label(tr("journal.title"), 36, INK, "title"))
	_count = UiTheme.label("", 15, Color(INK, 0.75))
	left.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var sep := VSeparator.new()
	row.add_child(sep)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(600, 560)
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	_meta = UiTheme.label("", 14, RED, "caps")
	right.add_child(_meta)
	_title = UiTheme.label("", 34, INK, "title")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(600, 0)
	right.add_child(_title)
	_text = UiTheme.label("", 19, INK, "italic")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(600, 0)
	right.add_child(_text)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	var close := Button.new()
	close.text = tr("journal.close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(close_window)
	right.add_child(close)


## Title and text of a page: a creature (its name, tale.<id>) or a Chud ruin (tale.chud.N).
func page(id: String) -> Dictionary:
	if db.creatures.has(id):
		return {"title": Loc.name_of(db.creatures[id]["name"]), "text": tr("tale." + id), "group": Creatures.group(db, id)}
	if id.begins_with("chud_"):
		var n := 1 + posmod(id.hash(), 6)
		var kind := "mine" if WorldMap.shared(db).chud_sites().any(func(s: Dictionary) -> bool: return s["id"] == id and s["kind"] == "mine") else "circle"
		return {"title": tr("journal.chud_" + kind), "text": tr("tale.chud.%d" % n), "group": "legend"}
	return {"title": id, "text": "", "group": ""}


func refresh() -> void:
	if not visible or db == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var found := 0
	var total := 0
	for sec: Array in SECTIONS:
		_list.add_child(UiTheme.label(tr(sec[0]).to_upper(), 13, RED, "caps"))
		var ids: Array = []
		for id: String in db.creatures:
			if (sec[1] as Array).has(Creatures.group(db, id)) and id != "chud":
				ids.append(id)
		if sec[0] == "journal.spirits":
			ids.append("chud")
			for s: Dictionary in WorldMap.shared(db).chud_sites():
				if state.journal.has(s["id"]):
					ids.append(s["id"])
		for id: String in ids:
			if not String(id).begins_with("chud_"):
				total += 1
			var has := state.journal.has(id) or (id == "chud" and _any_ruin())
			if has and not String(id).begins_with("chud_"):
				found += 1
			var b := Button.new()
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 30)
			var tight := StyleBoxEmpty.new()
			tight.content_margin_top = 2
			tight.content_margin_bottom = 2
			for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
				b.add_theme_stylebox_override(st, tight)
			b.add_theme_font_override("font", UiTheme.font("italic"))
			b.add_theme_font_size_override("font_size", 17)
			var col := INK if has else Color(INK, 0.45)
			for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
				b.add_theme_color_override(k, RED if id == selected else col)
			b.text = ("   " if String(id).begins_with("chud_") else "") + (String(page(id)["title"]) if has else "· · ·")
			b.disabled = not has
			b.pressed.connect(func() -> void:
				selected = id
				refresh())
			_list.add_child(b)
	_count.text = tr("journal.count") % [found, total]
	if selected == "chud" and not state.journal.has("chud"):
		selected = _latest_ruin()
	if selected == "" or not (state.journal.has(selected) or selected == "chud"):
		_title.text = tr("journal.empty")
		_meta.text = ""
		_text.text = tr("journal.empty_text")
		return
	var pg := page(selected)
	_title.text = pg["title"]
	_meta.text = tr("journal.day") % int(state.journal.get(selected, state.day))
	_text.text = pg["text"]


func _any_ruin() -> bool:
	return _latest_ruin() != ""


func _latest_ruin() -> String:
	for k: String in state.journal:
		if k.begins_with("chud_"):
			return k
	return ""


func _process(_delta: float) -> void:
	if not visible:
		return
	size = get_viewport_rect().size
	var book := get_node("Book") as Control
	book.size = book.get_combined_minimum_size()
	book.position = (size - book.size) * 0.5
