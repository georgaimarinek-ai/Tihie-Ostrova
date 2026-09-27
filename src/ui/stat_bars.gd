class_name StatBars
extends Control
## Health and stamina bars (mockups): the base part in the main colour, food bonus in a lighter one.

var hp := 100.0
var hp_max := 100.0
var hp_bonus := 0.0
var st := 100.0
var st_max := 100.0


func _draw() -> void:
	var w := size.x
	var font := UiTheme.font("caps")
	var num := UiTheme.font("bold")
	_row(0.0, Loc.t("hud.health"), "%d" % roundi(hp_max) if hp_bonus <= 0.0 else "%d + %d" % [roundi(hp_max - hp_bonus), roundi(hp_bonus)], hp / maxf(1.0, hp_max), (hp_max - hp_bonus) / maxf(1.0, hp_max), UiTheme.HEALTH, UiTheme.HEALTH_BONUS, font, num, w)
	_row(46.0, Loc.t("hud.stamina"), "%d/%d" % [roundi(st), roundi(st_max)], st / maxf(1.0, st_max), 1.0, UiTheme.STAMINA, UiTheme.STAMINA, font, num, w)


func _row(y: float, title: String, value: String, fill: float, base: float, c1: Color, c2: Color, font: Font, num: Font, w: float) -> void:
	draw_string(font, Vector2(0, y + 14), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
	var vs := num.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(num, Vector2(w - vs.x, y + 14), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.TEXT)
	var bar := Rect2(0, y + 24, w, 10)
	draw_rect(bar, Color(0.05, 0.08, 0.1, 0.8))
	var f := clampf(fill, 0.0, 1.0)
	var b := clampf(base, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(w * minf(f, b), bar.size.y)), c1)
	if f > b:
		draw_rect(Rect2(bar.position + Vector2(w * b, 0), Vector2(w * (f - b), bar.size.y)), c2)
