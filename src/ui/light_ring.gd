class_name LightRing
extends Control
## The light in hand on the HUD (mockup island.png): its icon inside a fire-coloured ring that burns down,
## and the time left.

var item := "torch"
var left := 0.0  # minutes, -1 = never goes out
var total := 5.0


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c, r, Color(0.06, 0.09, 0.11, 0.85))
	draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.12), 6.0, true)
	var k := 1.0 if left < 0.0 else clampf(left / maxf(total, 0.01), 0.0, 1.0)
	draw_arc(c, r, -PI / 2, -PI / 2 + TAU * k, 48, UiTheme.FIRE, 6.0, true)
	var f := UiTheme.font("bold")
	var t := "∞" if left < 0.0 else ItemInfo.clock(left).trim_prefix("0")
	var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(f, Vector2(c.x - ts.x * 0.5, c.y + r * 0.62), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.TEXT)


func _ready() -> void:
	var icon := ItemIcon.new(item)
	icon.position = Vector2(size.x * 0.5 - 16, size.y * 0.5 - 26)
	icon.size = Vector2(32, 32)
	icon.name = "Icon"
	add_child(icon)


func _process(_d: float) -> void:
	var icon := get_node_or_null("Icon") as ItemIcon
	if icon != null and icon.item != item:
		icon.set_item(item)
