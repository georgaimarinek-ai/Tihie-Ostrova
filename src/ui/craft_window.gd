class_name CraftWindow
extends Control
## The bag and the crafting table (mockup docs/mockups/craft.png, roadmap phase 3). Left: the bag (24
## places) and the three food places; middle: recipes of the chosen station with what they need, in words
## (Crafting.check reasons → craft.* texts); right: the card of the chosen recipe or item. Long recipes are
## loaded into the station and cook without the player; the station's queue and output are shown here.
## Everything goes through Game.submit(): craft, load_station, cancel_station, collect, eat, light.

signal closed
## Put a station down in front of the player (World picks the spot and sends "place").
signal place_requested(piece: String)

const SLOT := Vector2(66, 62)

var db: ContentDB
var state: WorldState
var pid := ""
## Stations within reach: [{"uid", "id"}] (World passes them when opening).
var stations: Array = []
var tab := "hand"  # "hand" or a station piece id
var tab_uid := ""
var selected := ""  # recipe id
var selected_item := ""  # item id when a bag slot is chosen
var qty := 1

var _title: Label
var _subtitle: Label
var _tabs: HBoxContainer
var _bag_grid: GridContainer
var _bag_count: Label
var _food_row: HBoxContainer
var _list: VBoxContainer
var _list_title: Label
var _card: VBoxContainer
var _crafting := {}  # {"recipe", "times", "t", "total"} while a short recipe is being made
var _built := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _build() -> void:
	_built = true
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 44
	root.offset_right = -44
	root.offset_top = 30
	root.offset_bottom = -30
	root.add_theme_constant_override("separation", 22)
	add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_title = UiTheme.label("", 44, UiTheme.TEXT, "title")
	_subtitle = UiTheme.label("", 16, UiTheme.TEXT2)
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_title)
	head.add_child(_subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	head.add_child(_tabs)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(48, 44)
	close.pressed.connect(close_window)
	head.add_child(close)
	root.add_child(head)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# the bag
	var bag := _panel(Vector2(480, 0))
	var bv := bag.get_child(0) as VBoxContainer
	var bh := HBoxContainer.new()
	var bt := UiTheme.label(tr("ui.bag").to_upper(), 14, UiTheme.BIRCH, "caps")
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_count = UiTheme.label("", 14, UiTheme.BIRCH, "caps")
	bh.add_child(bt)
	bh.add_child(_bag_count)
	bv.add_child(bh)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 6
	_bag_grid.add_theme_constant_override("h_separation", 8)
	_bag_grid.add_theme_constant_override("v_separation", 8)
	bv.add_child(_bag_grid)
	var ft := UiTheme.label(tr("ui.food_slots").to_upper(), 14, UiTheme.BIRCH, "caps")
	bv.add_child(ft)
	_food_row = HBoxContainer.new()
	_food_row.add_theme_constant_override("separation", 8)
	bv.add_child(_food_row)
	body.add_child(bag)
	# recipes
	var mid := _panel(Vector2(460, 0))
	var mv := mid.get_child(0) as VBoxContainer
	_list_title = UiTheme.label("", 14, UiTheme.BIRCH, "caps")
	mv.add_child(_list_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	mv.add_child(scroll)
	body.add_child(mid)
	# the card
	var right := _panel(Vector2(430, 0))
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_card = right.get_child(0) as VBoxContainer
	body.add_child(right)


func _panel(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.04, 0.07, 0.09, 0.9), 14, 22, Color(1, 1, 1, 0.08)))
	p.custom_minimum_size = min_size
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	return p


## Open at the stations within reach (World lists them, nearest first).
func open(p_db: ContentDB, p_state: WorldState, p_pid: String, near: Array) -> void:
	db = p_db
	state = p_state
	pid = p_pid
	stations = near
	if not _built:
		_build()
	var keep := false
	for s: Dictionary in stations:
		if s["id"] == tab and s["uid"] == tab_uid:
			keep = true
	if not keep:
		tab = "hand"
		tab_uid = ""
		for s: Dictionary in stations:
			if _is_station(String(s["id"])):
				tab = s["id"]
				tab_uid = s["uid"]
				break
	selected = ""
	selected_item = ""
	qty = 1
	visible = true
	refresh()


func close_window() -> void:
	visible = false
	_crafting = {}
	closed.emit()


func is_busy() -> bool:
	return not _crafting.is_empty()


func _is_station(piece: String) -> bool:
	return bool(db.pieces.get(piece, {}).get("station", false))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
		close_window()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or _crafting.is_empty():
		return
	_crafting["t"] = float(_crafting["t"]) + delta
	if float(_crafting["t"]) >= float(_crafting["total"]):
		var c := _crafting
		_crafting = {}
		Game.submit({"type": "craft", "recipe": c["recipe"], "times": c["times"]})
	refresh_card()


# ---------------------------------------------------------------- content

func refresh() -> void:
	if not visible or not _built:
		return
	_refresh_head()
	_refresh_bag()
	_refresh_list()
	refresh_card()


func _refresh_head() -> void:
	_title.text = (tr("ui.by_hand") if tab == "hand" else Loc.name_of(db.pieces[tab]["name"])).to_upper()
	var names: PackedStringArray = []
	for s: Dictionary in stations:
		var n := Loc.name_of(db.pieces[s["id"]]["name"]).to_lower()
		if not n in names:
			names.append(n)
	_subtitle.text = (tr("ui.nearby") % ", ".join(names)) if not names.is_empty() else ""
	for c in _tabs.get_children():
		c.queue_free()
	var seen := {}
	_tab_button(tr("ui.by_hand"), "hand", "")
	for s: Dictionary in stations:
		if _is_station(String(s["id"])) and not seen.has(s["id"]):
			seen[s["id"]] = true
			_tab_button(Loc.name_of(db.pieces[s["id"]]["name"]), s["id"], s["uid"])


func _tab_button(text: String, id: String, uid: String) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	if id == tab:
		b.add_theme_stylebox_override("normal", UiTheme.panel(UiTheme.TEXT, 10, 16))
		b.add_theme_color_override("font_color", Color(0.08, 0.1, 0.12))
	b.pressed.connect(func() -> void:
		tab = id
		tab_uid = uid
		selected = ""
		qty = 1
		refresh())
	_tabs.add_child(b)


func _refresh_bag() -> void:
	for c in _bag_grid.get_children():
		c.queue_free()
	var inv := state.inv(pid)
	var used := 0
	for i in inv.size:
		var s: Dictionary = inv.slots[i]
		if not s.is_empty():
			used += 1
		_bag_grid.add_child(_slot(s, i))
	_bag_count.text = "%d / %d" % [used, inv.size]
	for c in _food_row.get_children():
		c.queue_free()
	var food: Array = state.players[pid]["food"]
	for i in int(db.balance["player"]["food_slots"]):
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(142, 40)
		if i < food.size():
			var f: Dictionary = food[i]
			p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.2, 0.17, 0.13, 0.9), 8, 10))
			var l := RichTextLabel.new()
			l.bbcode_enabled = true
			l.fit_content = true
			l.scroll_active = false
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.add_theme_font_size_override("normal_font_size", 15)
			l.add_theme_font_size_override("bold_font_size", 15)
			l.add_theme_font_override("bold_font", UiTheme.font("bold"))
			l.text = "%s · [b]%s[/b]" % [Loc.item(db, f["id"]), ItemInfo.clock(float(f["until"]) - state.clock_min)]
			p.add_child(l)
		else:
			p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0, 0, 0, 0.2), 8, 10, Color(1, 1, 1, 0.15)))
			p.add_child(UiTheme.label(tr("ui.empty"), 15, UiTheme.MUTED))
		_food_row.add_child(p)


func _slot(s: Dictionary, index: int) -> Control:
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	var chosen: bool = not s.is_empty() and s["id"] == selected_item
	b.add_theme_stylebox_override("normal", UiTheme.panel(Color(0.3, 0.2, 0.12, 0.9) if chosen else Color(0.12, 0.15, 0.18, 0.9), 10, 4, UiTheme.FIRE if chosen else Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("hover", UiTheme.panel(Color(0.18, 0.21, 0.24, 0.95), 10, 4, Color(1, 1, 1, 0.25)))
	if s.is_empty():
		b.disabled = true
		b.add_theme_stylebox_override("disabled", UiTheme.panel(Color(0.08, 0.1, 0.12, 0.6), 10, 4, Color(1, 1, 1, 0.04)))
		return b
	var icon := ItemIcon.new(String(s["id"]), int(s["n"]))
	icon.color = UiTheme.FIRE if chosen else UiTheme.TEXT
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -4
	b.add_child(icon)
	b.tooltip_text = Loc.item(db, s["id"])
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_RIGHT or mb.double_click:
				use_item(String(s["id"]))
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				selected_item = String(s["id"])
				selected = ""
				refresh())
	return b


## Use an item from the bag: eat food, light a light.
func use_item(id: String) -> void:
	var it: Dictionary = db.items[id]
	if it.has("food"):
		Game.submit({"type": "eat", "item": id})
	elif it.has("light"):
		Game.submit({"type": "light", "item": id})


func _recipes() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in db.recipes.values():
		if r["station"] == tab:
			out.append(r["id"])
	var inv := state.inv(pid)
	out.sort_custom(func(a: String, b: String) -> bool:
		var ra := _rank(a, inv)
		var rb := _rank(b, inv)
		return ra < rb if ra != rb else a < b)
	return out


func _rank(rid: String, inv: Inventory) -> int:
	if not db.is_unlocked(db.recipes[rid]["unlock"], state.lit):
		return 2
	return 0 if Crafting.affordable(db, inv, rid) > 0 else 1


func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_list_title.text = (tr("ui.recipes_hand") if tab == "hand" else tr("ui.recipes_of") % Loc.name_of(db.pieces[tab]["name"]).to_lower()).to_upper()
	if tab_uid != "":
		_station_status()
	var inv := state.inv(pid)
	for rid in _recipes():
		_list.add_child(_recipe_row(rid, inv))
	if tab == "hand":
		_station_section(inv)


## By hand: the stations the player can set up (full building comes with the build mode, B).
func _station_section(inv: Inventory) -> void:
	var t := UiTheme.label(tr("ui.stations").to_upper(), 14, UiTheme.BIRCH, "caps")
	_list.add_child(t)
	for p: Dictionary in db.pieces.values():
		if String(p["category"]) != "station" or not bool(p.get("station", false)) or not db.is_unlocked(p["unlock"], state.lit):
			continue
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.1, 0.13, 0.16, 0.9), 10, 14, Color(1, 1, 1, 0.1)))
		var h := HBoxContainer.new()
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		v.add_child(UiTheme.label(Loc.name_of(p["name"]), 18, UiTheme.TEXT, "bold"))
		v.add_child(UiTheme.label(ItemInfo.bag_text(db, p["cost"]), 15, UiTheme.TEXT2))
		h.add_child(v)
		var b := Button.new()
		b.text = tr("ui.place")
		b.custom_minimum_size = Vector2(0, 44)
		b.disabled = not inv.has_bag(ContentDB.bag(p["cost"]))
		var piece_id := String(p["id"])
		b.pressed.connect(func() -> void: place_requested.emit(piece_id))
		h.add_child(b)
		row.add_child(h)
		_list.add_child(row)


## What the station is cooking and what waits in it.
func _station_status() -> void:
	var pc: Dictionary = state.pieces.get(tab_uid, {})
	var queue: Array = pc.get("queue", [])
	var out: Dictionary = pc.get("out", {})
	if queue.is_empty() and out.is_empty():
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.16, 0.12, 0.08, 0.9), 10, 14, Color(1, 0.6, 0.25, 0.4)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UiTheme.label(tr("ui.cooking").to_upper(), 13, UiTheme.FIRE, "caps"))
	for i in queue.size():
		var q: Dictionary = queue[i]
		var r: Dictionary = db.recipes[q["recipe"]]
		var h := HBoxContainer.new()
		var name := Loc.item(db, (r["output"] as Dictionary).keys()[0])
		var l := UiTheme.label("%s ×%d · %s" % [name, int(q["times"]), ItemInfo.clock(float(q["left_s"]) / 60.0) if i == 0 else tr("ui.waiting")], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var x := Button.new()
		x.text = "✕"
		x.tooltip_text = tr("ui.cancel_load")
		x.custom_minimum_size = Vector2(36, 32)
		x.pressed.connect(func() -> void: Game.submit({"type": "cancel_station", "uid": tab_uid, "index": i}))
		h.add_child(x)
		v.add_child(h)
	if not out.is_empty():
		var h := HBoxContainer.new()
		var l := UiTheme.label(tr("ui.ready") % ItemInfo.bag_text(db, out), 16, UiTheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(l)
		var take := Button.new()
		take.theme_type_variation = "FireButton"
		take.text = tr("ui.collect")
		take.pressed.connect(func() -> void: Game.submit({"type": "collect", "uid": tab_uid}))
		h.add_child(take)
		v.add_child(h)
	_list.add_child(p)


func _recipe_row(rid: String, inv: Inventory) -> Control:
	var r: Dictionary = db.recipes[rid]
	var unlocked := db.is_unlocked(r["unlock"], state.lit)
	var can := Crafting.affordable(db, inv, rid) if unlocked else 0
	var chosen: bool = rid == selected
	var p := PanelContainer.new()
	var border := UiTheme.FIRE if chosen else Color(1, 1, 1, 0.1 if unlocked else 0.05)
	p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.1, 0.13, 0.16, 0.9 if unlocked else 0.4), 10, 14, border))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	var out_id: String = (r["output"] as Dictionary).keys()[0]
	var n := int(r["output"][out_id])
	v.add_child(UiTheme.label(Loc.item(db, out_id) + (" ×%d" % n if n > 1 else ""), 18, UiTheme.TEXT if unlocked else UiTheme.MUTED, "bold"))
	v.add_child(UiTheme.label(ItemInfo.bag_text(db, r["inputs"]), 15, UiTheme.TEXT2 if unlocked else UiTheme.MUTED))
	h.add_child(v)
	var status := ""
	var col := UiTheme.FIRE
	if not unlocked:
		status = tr("ui.opens_at") % Loc.beacon(db, r["unlock"])
		col = UiTheme.TEXT2
	elif can > 0:
		status = tr("ui.can") % can
	else:
		var miss := inv.missing(r["inputs"])
		var k: String = miss.keys()[0]
		status = tr("ui.lacks") % ["%s ×%d" % [Loc.item(db, k), int(miss[k])]]
		col = UiTheme.TEXT
	if unlocked and Crafting.is_background(db, rid):
		status += "\n" + tr("ui.background_short")
	var sl := UiTheme.label(status, 14, col, "bold")
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sl)
	p.add_child(h)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			selected = rid
			selected_item = ""
			qty = 1
			refresh())
	return p


func refresh_card() -> void:
	if not _built:
		return
	for c in _card.get_children():
		c.queue_free()
	if selected != "":
		_recipe_card(selected)
	elif selected_item != "" and state.inv(pid).count(selected_item) > 0:
		_item_card(selected_item)
	else:
		var hint := UiTheme.label(tr("ui.pick_recipe"), 16, UiTheme.TEXT2)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(380, 0)
		_card.add_child(hint)


func _card_head(item: String, subtitle: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.3, 0.2, 0.12, 0.9), 10, 6))
	box.custom_minimum_size = Vector2(76, 76)
	var icon := ItemIcon.new(item)
	icon.color = UiTheme.FIRE
	icon.custom_minimum_size = Vector2(60, 60)
	box.add_child(icon)
	h.add_child(box)
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(UiTheme.label(Loc.item(db, item), 30, UiTheme.TEXT, "title"))
	v.add_child(UiTheme.label(subtitle, 15, UiTheme.TEXT2))
	h.add_child(v)
	_card.add_child(h)
	var d := UiTheme.label(ItemInfo.describe(db, item), 16, UiTheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(380, 0)
	_card.add_child(d)


func _recipe_card(rid: String) -> void:
	var r: Dictionary = db.recipes[rid]
	var out_id: String = (r["output"] as Dictionary).keys()[0]
	var bg := Crafting.is_background(db, rid)
	_card_head(out_id, "%s · %d %s" % [ItemInfo.kind(db, out_id), int(r["time_s"]), tr("unit.s")])
	var inv := state.inv(pid)
	for k: String in r["inputs"]:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.12, 0.15, 0.18, 0.9), 8, 12))
		var h := HBoxContainer.new()
		var name := UiTheme.label(Loc.item(db, k), 17)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name)
		var need := int(r["inputs"][k]) * qty
		var have := inv.count(k)
		h.add_child(UiTheme.label("%d / %d" % [have, need], 17, UiTheme.TEXT if have >= need else UiTheme.HEALTH_BONUS, "bold"))
		row.add_child(h)
		_card.add_child(row)
	var unlocked := db.is_unlocked(r["unlock"], state.lit)
	var reason := ""
	if not unlocked:
		reason = tr("ui.opens_at") % Loc.beacon(db, r["unlock"])
	elif bg:
		reason = "" if tab_uid != "" else tr("craft.no_station")
	else:
		var why := Crafting.check(db, state, pid, rid, qty)
		reason = "" if why == "" else tr("craft." + why)
	var can := Crafting.affordable(db, inv, rid) if unlocked else 0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var step := HBoxContainer.new()
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(44, 48)
	minus.pressed.connect(func() -> void:
		qty = maxi(1, qty - 1)
		refresh_card())
	var q := UiTheme.label(str(qty), 20, UiTheme.TEXT, "bold")
	q.custom_minimum_size = Vector2(40, 0)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(44, 48)
	plus.pressed.connect(func() -> void:
		qty = mini(maxi(1, can), qty + 1)
		refresh_card())
	step.add_child(minus)
	step.add_child(q)
	step.add_child(plus)
	row.add_child(step)
	var go := Button.new()
	go.theme_type_variation = "FireButton"
	go.custom_minimum_size = Vector2(0, 50)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.add_theme_font_size_override("font_size", 20)
	if not _crafting.is_empty() and _crafting["recipe"] == rid:
		go.text = tr("ui.making") % roundi(100.0 * float(_crafting["t"]) / float(_crafting["total"]))
		go.disabled = true
	else:
		go.text = tr("ui.load") if bg else tr("ui.make")
		go.disabled = reason != "" or not _crafting.is_empty()
		go.pressed.connect(_make.bind(rid, qty))
	row.add_child(go)
	_card.add_child(row)
	if can > 1 and reason == "" and not bg:
		var all := Button.new()
		all.text = tr("ui.make_all") % can
		all.custom_minimum_size = Vector2(0, 46)
		all.disabled = not _crafting.is_empty()
		all.pressed.connect(_make.bind(rid, can))
		_card.add_child(all)
	var note := UiTheme.label(reason if reason != "" else (tr("ui.background_note") if bg else tr("ui.background_hint")), 14, UiTheme.MUTED if reason == "" else UiTheme.HEALTH_BONUS)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(380, 0)
	_card.add_child(note)


func _item_card(id: String) -> void:
	_card_head(id, ItemInfo.kind(db, id))
	var it: Dictionary = db.items[id]
	if it.has("food") or it.has("light"):
		var use := Button.new()
		use.theme_type_variation = "FireButton"
		use.custom_minimum_size = Vector2(0, 50)
		use.text = tr("ui.eat") if it.has("food") else tr("act.light_torch") if id == "torch" else tr("ui.light")
		use.pressed.connect(use_item.bind(id))
		_card.add_child(use)


func _make(rid: String, times: int) -> void:
	if Crafting.is_background(db, rid):
		Game.submit({"type": "load_station", "uid": tab_uid, "recipe": rid, "times": times})
		return
	_crafting = {"recipe": rid, "times": times, "t": 0.0, "total": float(db.recipes[rid]["time_s"]) * times}
	refresh_card()
