class_name CompassBar
extends Control
## The compass strip at the top of the screen: ±90° around the camera heading, cardinal letters, ticks every
## 15°, the target as a fire-coloured diamond (clamped to an edge with an arrow when behind).

var heading := 0.0  # radians clockwise from north (map north = -z)
var target := NAN
var ink := Color(0.12, 0.14, 0.16, 0.9)  # letters (dark on white nights, light on polar nights)
var line := Color(1, 1, 1, 0.55)

const SPAN := PI  # the strip shows this much of the horizon


func _draw() -> void:
	var w := size.x
	var y := size.y * 0.72
	draw_line(Vector2(0, y), Vector2(w, y), line, 1.0)
	var letters := {0: "compass.n", 90: "compass.e", 180: "compass.s", 270: "compass.w"}
	var font := UiTheme.font("bold")
	for deg in range(0, 360, 15):
		var off := wrapf(deg_to_rad(deg) - heading, -PI, PI)
		if absf(off) > SPAN * 0.5:
			continue
		var x := w * 0.5 + off / SPAN * w
		if letters.has(deg):
			var s := Loc.t(letters[deg])
			var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			draw_string(font, Vector2(x - sz.x * 0.5, y - 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
			draw_line(Vector2(x, y - 7), Vector2(x, y + 4), line, 1.5)
		else:
			draw_line(Vector2(x, y - 4 if deg % 45 == 0 else y - 2), Vector2(x, y + 3), line, 1.0)
	draw_line(Vector2(w * 0.5, y - 10), Vector2(w * 0.5, y + 8), Color(line, 0.95), 2.0)
	if not is_nan(target):
		var off := wrapf(target - heading, -PI, PI)
		var clamped := clampf(off, -SPAN * 0.46, SPAN * 0.46)
		var x := w * 0.5 + clamped / SPAN * w
		var c := UiTheme.FIRE
		var ty := y - 8
		var pts := PackedVector2Array([Vector2(x, ty - 8), Vector2(x + 7, ty), Vector2(x, ty + 8), Vector2(x - 7, ty)])
		draw_colored_polygon(pts, c)
		if absf(off) > SPAN * 0.46:
			var dir := signf(off)
			draw_colored_polygon(PackedVector2Array([Vector2(x + dir * 12, ty), Vector2(x + dir * 5, ty - 5), Vector2(x + dir * 5, ty + 5)]), c)
