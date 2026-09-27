class_name Hud
extends Control
## The minimal HUD (docs/01_GDD.md §14, mockups sea.png and island.png):
## top-left the chapter and region and the goal line; top-centre the compass strip with the target and
## its distance; the fire-coloured action button with its key; bottom-left the boat panel (wind, speed,
## hold) or the light in hand; bottom-right health and stamina; toasts on the right; a quiet controls hint.
## Only shows what World tells it; never touches the world.

signal action_pressed

var region_label: Label
var goal_label: Label
var goal_panel: PanelContainer
var compass: CompassBar
var target_label: Label
var target_panel: PanelContainer
var action_button: Button
var boat_panel: PanelContainer
var boat_name: Label
var boat_wind: Label
var boat_speed: Label
var boat_hold: Label
var wind_dial: WindDial
var bars: StatBars
var hint_label: Label
var toasts: VBoxContainer
var banner: PanelContainer
var banner_box: VBoxContainer
var buffs: HBoxContainer
var hotbar: HBoxContainer
var light_ring: LightRing

var _banner_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.theme()
	# top-left: chapter · region, and the goal
	region_label = Label.new()
	region_label.theme_type_variation = "Caps"
	region_label.position = Vector2(32, 22)
	add_child(region_label)
	goal_panel = PanelContainer.new()
	goal_panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.3, 0.33, 0.35, 0.82), 10, 16))
	goal_panel.position = Vector2(30, 50)
	goal_panel.custom_minimum_size = Vector2(470, 0)
	goal_label = UiTheme.label("", 19)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_label.custom_minimum_size = Vector2(440, 0)
	goal_panel.add_child(goal_label)
	add_child(goal_panel)
	# top-centre: compass and distance
	compass = CompassBar.new()
	compass.custom_minimum_size = Vector2(470, 40)
	compass.size = Vector2(470, 40)
	add_child(compass)
	target_panel = PanelContainer.new()
	target_panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.25, 0.28, 0.3, 0.85), 6, 10))
	target_label = UiTheme.label("", 16)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_panel.add_child(target_label)
	add_child(target_panel)
	# top-right: food and rest buffs (phase 3)
	buffs = HBoxContainer.new()
	buffs.add_theme_constant_override("separation", 10)
	buffs.alignment = BoxContainer.ALIGNMENT_END
	add_child(buffs)
	# hotbar: the first eight places of the bag, keys 1–8
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 8)
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 8:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(62, 58)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := ItemIcon.new()
		icon.custom_minimum_size = Vector2(50, 46)
		cell.add_child(icon)
		var num := UiTheme.label(str(i + 1), 12, UiTheme.MUTED)
		num.position = Vector2(5, 1)
		cell.add_child(num)
		hotbar.add_child(cell)
	add_child(hotbar)
	# the light in hand: a ring that burns down
	light_ring = LightRing.new()
	light_ring.custom_minimum_size = Vector2(84, 84)
	light_ring.size = Vector2(84, 84)
	light_ring.visible = false
	add_child(light_ring)
	# the action button
	action_button = Button.new()
	action_button.theme_type_variation = "FireButton"
	action_button.add_theme_font_size_override("font_size", 21)
	action_button.custom_minimum_size = Vector2(0, 52)
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.visible = false
	action_button.pressed.connect(func() -> void: action_pressed.emit())
	add_child(action_button)
	# bottom-left: the boat
	boat_panel = PanelContainer.new()
	boat_panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.06, 0.09, 0.11, 0.86), 12, 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	wind_dial = WindDial.new()
	wind_dial.custom_minimum_size = Vector2(88, 88)
	row.add_child(wind_dial)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	boat_name = UiTheme.label("", 24, UiTheme.TEXT, "title")
	boat_wind = UiTheme.label("", 16, UiTheme.TEXT2)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 60)
	boat_speed = UiTheme.label("", 16, UiTheme.TEXT)
	boat_hold = UiTheme.label("", 16, UiTheme.TEXT)
	line.add_child(boat_speed)
	line.add_child(boat_hold)
	col.add_child(boat_name)
	col.add_child(boat_wind)
	col.add_child(line)
	row.add_child(col)
	boat_panel.add_child(row)
	add_child(boat_panel)
	# bottom-right: health and stamina
	bars = StatBars.new()
	bars.custom_minimum_size = Vector2(330, 96)
	bars.size = Vector2(330, 96)
	add_child(bars)
	# controls hint
	hint_label = UiTheme.label("", 15, UiTheme.MUTED)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.custom_minimum_size = Vector2(800, 0)
	add_child(hint_label)
	# toasts
	toasts = VBoxContainer.new()
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 8)
	add_child(toasts)
	# the banner ("Beacon lit", "Unlocked:")
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.18, 0.2, 0.22, 0.88), 14, 28, Color(1, 0.6, 0.25, 0.35)))
	banner.visible = false
	banner_box = VBoxContainer.new()
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.add_theme_constant_override("separation", 10)
	banner.add_child(banner_box)
	add_child(banner)


func _process(delta: float) -> void:
	_layout()
	for t: Control in toasts.get_children():
		var age: float = t.get_meta("age", 0.0) + delta
		t.set_meta("age", age)
		t.modulate.a = clampf(4.0 - age, 0.0, 1.0)
		if age > 4.0:
			t.queue_free()
	if banner.visible:
		_banner_t -= delta
		banner.modulate.a = clampf(_banner_t, 0.0, 1.0) if _banner_t < 1.0 else minf(1.0, banner.modulate.a + delta * 2.0)
		if _banner_t <= 0.0:
			banner.visible = false


func _layout() -> void:
	size = get_viewport_rect().size
	var w := size.x
	var h := size.y
	region_label.position = Vector2(32, 22)
	goal_panel.position = Vector2(30, 50)
	compass.position = Vector2(w * 0.5 - compass.size.x * 0.5, 12)
	target_panel.position = Vector2(w * 0.5 - target_panel.size.x * 0.5, 56)
	buffs.position = Vector2(w - 40 - buffs.size.x, 24)
	action_button.position = Vector2(w * 0.62, h * 0.58) - action_button.size * 0.5
	boat_panel.position = Vector2(30, h - 30 - boat_panel.size.y)
	hotbar.position = Vector2(w * 0.5 - hotbar.size.x * 0.5, h - 92)
	light_ring.position = Vector2(30, h - 30 - light_ring.size.y)
	bars.position = Vector2(w - 30 - bars.size.x, h - 24 - bars.size.y)
	hint_label.position = Vector2(w * 0.5 - hint_label.size.x * 0.5, h - 30)
	toasts.position = Vector2(w - 40 - toasts.size.x, 150)
	banner.position = Vector2(w * 0.5 - banner.size.x * 0.5, 100)


## Light fog behind the HUD (white nights) wants dark captions; dark skies want light ones.
func set_backdrop(light: bool) -> void:
	var c := Color(0.2, 0.24, 0.27, 0.9) if light else UiTheme.BIRCH
	if region_label.get_theme_color("font_color", "Caps") != c:
		region_label.add_theme_color_override("font_color", c)
		compass.ink = Color(0.12, 0.14, 0.16, 0.9) if light else Color(0.9, 0.93, 0.93, 0.9)
		compass.line = Color(0.15, 0.18, 0.2, 0.55) if light else Color(1, 1, 1, 0.55)
		hint_label.add_theme_color_override("font_color", Color(0.2, 0.24, 0.27, 0.55) if light else UiTheme.MUTED)


func set_region(text: String) -> void:
	region_label.text = text.to_upper()


func set_goal(text: String) -> void:
	goal_label.text = text
	goal_panel.visible = text != ""


## Compass: camera bearing and the target's bearing in radians (clockwise from north), NAN = no target.
func set_compass(cam_bearing: float, target_bearing: float, text: String) -> void:
	compass.heading = cam_bearing
	compass.target = target_bearing
	compass.queue_redraw()
	target_label.text = text
	target_panel.visible = text != ""


## The action for the E key ("" hides the button).
func set_action(text: String, key: String = "E") -> void:
	action_button.visible = text != ""
	if text != "":
		var t := "%s   [%s]" % [text, key]
		if action_button.text != t:
			action_button.text = t
			action_button.size = Vector2.ZERO


## Boat panel: {} hides it. Keys: name, wind_text, speed, hold, wind_angle (radians, relative to the bow).
func set_boat(info: Dictionary) -> void:
	boat_panel.visible = not info.is_empty()
	if info.is_empty():
		return
	boat_name.text = String(info["name"])
	boat_wind.text = String(info["wind_text"])
	boat_speed.text = String(info["speed"])
	boat_hold.text = String(info["hold"])
	wind_dial.heading = float(info["heading"])
	wind_dial.wind = float(info["wind_angle"])
	wind_dial.queue_redraw()


func set_bars(hp: float, hp_max: float, hp_bonus: float, st: float, st_max: float) -> void:
	bars.hp = hp
	bars.hp_max = hp_max
	bars.hp_bonus = hp_bonus
	bars.st = st
	bars.st_max = st_max
	bars.queue_redraw()


## Hotbar: the first eight bag slots ({} = empty) and the chosen one.
func set_hotbar(slots: Array, chosen: int, show: bool) -> void:
	hotbar.visible = show
	if not show:
		return
	for i in 8:
		var cell := hotbar.get_child(i) as PanelContainer
		var s: Dictionary = slots[i] if i < slots.size() else {}
		var active := i == chosen and not s.is_empty()
		cell.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.06, 0.09, 0.11, 0.85) if not s.is_empty() else Color(0.06, 0.09, 0.11, 0.35), 10, 6, UiTheme.FIRE if active else Color(1, 1, 1, 0.08)))
		var icon := cell.get_child(0) as ItemIcon
		var id := String(s.get("id", ""))
		var n := int(s.get("n", 0))
		if icon.item != id or icon.count != n or icon.color != (UiTheme.FIRE if active else UiTheme.TEXT):
			icon.color = UiTheme.FIRE if active else UiTheme.TEXT
			icon.set_item(id, n)


## Food and rest in the top-right corner: [{"id", "left_min"}], rested minutes (0 = not rested).
func set_buffs(food: Array, rested_min: float) -> void:
	var want := food.size() + (1 if rested_min > 0.0 else 0)
	if buffs.get_child_count() != want or buffs.get_meta("sig", "") != str(food.map(func(f: Dictionary) -> String: return f["id"])) + str(rested_min > 0.0):
		for c in buffs.get_children():
			c.queue_free()
		buffs.set_meta("sig", str(food.map(func(f: Dictionary) -> String: return f["id"])) + str(rested_min > 0.0))
		for f: Dictionary in food:
			var v := VBoxContainer.new()
			v.alignment = BoxContainer.ALIGNMENT_CENTER
			var ring := PanelContainer.new()
			var sb := UiTheme.panel(Color(0.2, 0.22, 0.24, 0.9), 28, 6, UiTheme.FIRE)
			sb.set_border_width_all(3)
			ring.add_theme_stylebox_override("panel", sb)
			ring.custom_minimum_size = Vector2(52, 52)
			var icon := ItemIcon.new(String(f["id"]))
			icon.custom_minimum_size = Vector2(36, 36)
			ring.add_child(icon)
			v.add_child(ring)
			var t := PanelContainer.new()
			t.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.08, 0.1, 0.12, 0.85), 4, 5))
			t.add_child(UiTheme.label("", 12, UiTheme.TEXT, "bold"))
			v.add_child(t)
			buffs.add_child(v)
		if rested_min > 0.0:
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.2, 0.22, 0.24, 0.9), 10, 12))
			var v := VBoxContainer.new()
			var a := UiTheme.label(tr("ui.rested").to_upper(), 12, UiTheme.BIRCH, "caps")
			a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(a)
			var b := UiTheme.label("", 15, UiTheme.TEXT, "bold")
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(b)
			p.add_child(v)
			buffs.add_child(p)
	for i in food.size():
		var lbl := (buffs.get_child(i).get_child(1) as PanelContainer).get_child(0) as Label
		lbl.text = ItemInfo.clock(float(food[i]["left_min"]))
	if rested_min > 0.0 and buffs.get_child_count() > food.size():
		var box := buffs.get_child(food.size()).get_child(0) as VBoxContainer
		(box.get_child(1) as Label).text = "%d %s" % [ceili(rested_min), tr("unit.min").to_upper()]


## The light in hand: item and minutes left (-1 = forever), or "" to hide.
func set_light(item: String, left_min: float, total_min: float) -> void:
	light_ring.visible = item != ""
	if item == "":
		return
	light_ring.item = item
	light_ring.left = left_min
	light_ring.total = total_min
	light_ring.queue_redraw()


func set_hint(text: String) -> void:
	hint_label.text = text


func toast(text: String, accent: String = "") -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.2, 0.23, 0.26, 0.85), 8, 12))
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.scroll_active = false
	l.add_theme_font_override("normal_font", UiTheme.font("ui"))
	l.add_theme_font_override("bold_font", UiTheme.font("bold"))
	l.add_theme_font_size_override("normal_font_size", 17)
	l.add_theme_font_size_override("bold_font_size", 17)
	l.text = ("[color=#ff9a40][b]%s[/b][/color] " % accent if accent != "" else "") + text
	p.add_child(l)
	p.set_meta("age", 0.0)
	toasts.add_child(p)
	if toasts.get_child_count() > 6:
		toasts.get_child(0).queue_free()


## A banner at the top: caps kicker, a title in Ruslan Display, lines, chips. Stays `seconds`.
func show_banner(kicker: String, title: String, lines: Array, chips: Array, footer: String = "", seconds: float = 7.0) -> void:
	for c in banner_box.get_children():
		c.queue_free()
	var k := UiTheme.label(kicker.to_upper(), 14, UiTheme.FIRE, "caps")
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(k)
	var t := UiTheme.label(title, 44, UiTheme.TEXT, "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(t)
	for line: String in lines:
		var l := UiTheme.label(line, 18, UiTheme.TEXT2)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner_box.add_child(l)
	if not chips.is_empty():
		var sep := HSeparator.new()
		banner_box.add_child(sep)
		var h := UiTheme.label(Loc.t("hud.unlocked").to_upper(), 13, UiTheme.BIRCH, "caps")
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner_box.add_child(h)
		var flow := HFlowContainer.new()
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.custom_minimum_size = Vector2(520, 0)
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for chip: String in chips:
			var cp := PanelContainer.new()
			cp.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.28, 0.31, 0.33, 0.9), 8, 12, Color(1, 1, 1, 0.12)))
			cp.add_child(UiTheme.label(chip, 16))
			flow.add_child(cp)
		banner_box.add_child(flow)
	if footer != "":
		var f := UiTheme.label(footer, 16, UiTheme.BIRCH)
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner_box.add_child(f)
	banner.visible = true
	banner.modulate.a = 0.0
	banner.size = Vector2.ZERO
	_banner_t = seconds
