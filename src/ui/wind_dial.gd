class_name WindDial
extends Control
## The small dial on the boat panel: north mark, the boat's bow, and the wind as a dashed fire-coloured
## arrow (mockup sea.png).

var heading := 0.0  # the boat's bearing, radians clockwise from north
var wind := 0.0  # where the wind blows to, bearing in radians


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.35), 1.2, true)
	var font := UiTheme.font("bold")
	var n_dir := Vector2(sin(-heading), -cos(-heading))
	draw_string(font, c + n_dir * (r - 9) + Vector2(-4, 5), Loc.t("compass.n"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	# the bow always points up; the wind turns around it
	draw_line(c + Vector2(0, r * 0.55), c + Vector2(0, -r * 0.6), Color(1, 1, 1, 0.9), 2.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.7), c + Vector2(5, -r * 0.5), c + Vector2(-5, -r * 0.5)]), Color(1, 1, 1, 0.9))
	var a := wind - heading
	var d := Vector2(sin(a), -cos(a))
	var from := c - d * r * 0.75
	var to := c + d * r * 0.7
	var steps := 7
	for i in steps:
		if i % 2 == 0:
			draw_line(from.lerp(to, float(i) / steps), from.lerp(to, float(i + 1) / steps), UiTheme.FIRE, 2.0)
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([to + d * 6, to - d * 3 + side * 5, to - d * 3 - side * 5]), UiTheme.FIRE)
