class_name ItemIcon
extends Control
## A line icon for an item (docs/05_ART_AUDIO.md §6: linear, 1.7 px stroke on a 24 grid, no emoji), drawn
## from a small set of glyphs so every item in content has one without any image files.

const GLYPH := {
	"wood": "log", "larch": "log", "larch_plank": "plank", "branch": "sticks", "stone": "stone", "flint": "shard",
	"fiber": "tuft", "flax": "tuft", "moss": "moss", "birch_bark": "scroll", "resin": "drop", "tar": "drop",
	"fish_oil": "drop", "raw_fish": "fish", "cooked_fish": "fish", "salted_cod": "fish", "cloudberry": "berries",
	"lingonberry": "berries", "mushroom": "mushroom", "bog_ore": "ore", "clay": "clay", "barley": "grain",
	"flour": "sack", "wool": "wool", "pearl": "pearl", "mica": "gem", "spolokh": "spark", "stone_axe": "axe",
	"iron_axe": "axe", "knife": "knife", "wooden_shovel": "shovel", "fishing_rod": "rod", "iron_pick": "pick",
	"torch": "torch", "iron_lantern": "lantern", "spolokh_lantern": "lantern", "rope": "rope", "charcoal": "coal",
	"iron": "ingot", "brick": "brick", "linen": "cloth", "salt": "pile", "smolye": "bundle", "tar_faggot": "bundle",
	"oil_cask": "cask", "ukha": "bowl", "rybnik": "pie", "kalitki": "pie", "spear": "spear", "iron_spear": "spear",
	"spolokh_spear": "spear", "harpoon": "spear", "bow": "bow", "arrows": "arrow", "shield": "shield",
	"wool_coat": "coat", "pearl_necklace": "necklace",
	# building pieces (buildables.json) for the build bar
	"log_foundation": "foundation", "log_wall": "wall", "log_wall_half": "wall", "plank_floor": "floor",
	"gable_roof": "roof", "roof_ridge": "log", "carved_horse": "horse", "door": "door", "window_hatch": "window",
	"mica_window": "window", "pier": "pier", "bench": "bench", "table": "table", "bed": "bed", "chest": "cask",
	"drying_rack": "rack", "workbench": "table", "hearth": "fire", "tar_pit": "fire", "kiln": "fire",
	"bloomery": "fire", "forge": "anvil", "stove": "stove", "loom": "rack", "quern": "stone",
	"garden_bed": "grain", "boatyard": "pier", "trypot": "bowl", "salt_pan": "pile", "oil_lamp": "lantern",
	"sheep_pen": "pen", "pomor_cross": "cross", "bathhouse_stove": "stone",
	# boats, and the few signs banners and the map need
	"karbas": "boat", "shnyaka": "boat", "koch": "boat", "music": "note", "beacon": "tower",
}

var item := ""
var color := UiTheme.TEXT
var count := 0
var stroke := 1.7


func _init(p_item: String = "", p_count: int = 0) -> void:
	item = p_item
	count = p_count
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_item(p_item: String, p_count: int = 0) -> void:
	item = p_item
	count = p_count
	queue_redraw()


func _draw() -> void:
	if item == "":
		return
	var s := minf(size.x, size.y) / 24.0
	var o := (size - Vector2(24, 24) * s) * 0.5
	var w := stroke * s
	var c := color
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match String(GLYPH.get(item, "stone")):
		"log":
			draw_polyline(PackedVector2Array([P.call(6, 8), P.call(18, 8)]), c, w)
			draw_polyline(PackedVector2Array([P.call(6, 16), P.call(18, 16)]), c, w)
			draw_arc(P.call(18, 12), 4 * s, -PI / 2, PI / 2, 12, c, w)
			draw_arc(P.call(6, 12), 4 * s, 0, TAU, 16, c, w)
			draw_arc(P.call(6, 12), 1.5 * s, 0, TAU, 10, c, w)
		"plank":
			draw_rect(Rect2(P.call(4, 9), Vector2(16, 6) * s), c, false, w)
			draw_line(P.call(8, 12), P.call(16, 12), c, w * 0.6)
		"sticks":
			draw_line(P.call(5, 19), P.call(19, 5), c, w)
			draw_line(P.call(10, 14), P.call(9, 7), c, w)
			draw_line(P.call(14, 10), P.call(19, 12), c, w)
			draw_line(P.call(7, 17), P.call(4, 13), c, w)
		"stone":
			draw_polyline(PackedVector2Array([P.call(6, 17), P.call(4, 11), P.call(9, 6), P.call(16, 6), P.call(20, 12), P.call(17, 18), P.call(6, 17)]), c, w)
		"shard":
			draw_polyline(PackedVector2Array([P.call(12, 4), P.call(19, 18), P.call(5, 18), P.call(12, 4)]), c, w)
			draw_line(P.call(12, 4), P.call(11, 18), c, w * 0.6)
		"tuft":
			for x: float in [8.0, 12.0, 16.0]:
				draw_polyline(_curve(P.call(12, 20), P.call(x, 11), P.call(x + (x - 12) * 0.6, 4)), c, w)
		"moss":
			draw_arc(P.call(9, 14), 4 * s, PI, TAU, 10, c, w)
			draw_arc(P.call(15, 13), 5 * s, PI, TAU, 10, c, w)
			draw_line(P.call(4, 14), P.call(20, 14), c, w)
			draw_line(P.call(5, 18), P.call(19, 18), c, w * 0.6)
		"scroll":
			draw_rect(Rect2(P.call(6, 6), Vector2(12, 12) * s), c, false, w)
			draw_arc(P.call(6, 12), 3 * s, PI / 2, PI * 1.5, 8, c, w)
			draw_line(P.call(9, 10), P.call(15, 10), c, w * 0.6)
			draw_line(P.call(9, 14), P.call(15, 14), c, w * 0.6)
		"drop":
			draw_polyline(PackedVector2Array([P.call(12, 3), P.call(7, 12)]), c, w)
			draw_polyline(PackedVector2Array([P.call(12, 3), P.call(17, 12)]), c, w)
			draw_arc(P.call(12, 14), 5.5 * s, -0.4, PI + 0.4, 14, c, w)
		"fish":
			draw_arc(P.call(11, 12), 7 * s, -2.3, -0.8, 10, c, w)
			draw_arc(P.call(11, 12), 7 * s, 0.8, 2.3, 10, c, w)
			draw_polyline(PackedVector2Array([P.call(16, 7.5), P.call(21, 12), P.call(16, 16.5)]), c, w)
			draw_polyline(PackedVector2Array([P.call(6, 7), P.call(3, 12), P.call(6, 17)]), c, w)
			draw_circle(P.call(7, 11), 0.9 * s, c)
		"berries":
			for q: Vector2 in [Vector2(12, 8), Vector2(8, 13), Vector2(16, 13), Vector2(12, 17)]:
				draw_arc(P.call(q.x, q.y), 3.2 * s, 0, TAU, 12, c, w)
		"mushroom":
			draw_arc(P.call(12, 12), 7 * s, PI, TAU, 14, c, w)
			draw_line(P.call(5, 12), P.call(19, 12), c, w)
			draw_rect(Rect2(P.call(10, 12), Vector2(4, 7) * s), c, false, w)
		"ore":
			draw_polyline(PackedVector2Array([P.call(5, 16), P.call(7, 8), P.call(14, 5), P.call(19, 10), P.call(18, 18), P.call(5, 16)]), c, w)
			for q: Vector2 in [Vector2(10, 11), Vector2(14, 14), Vector2(13, 9)]:
				draw_circle(P.call(q.x, q.y), 1.0 * s, c)
		"clay":
			draw_arc(P.call(12, 14), 7 * s, PI, TAU, 14, c, w)
			draw_line(P.call(5, 14), P.call(19, 14), c, w)
			draw_line(P.call(9, 10), P.call(15, 10), c, w * 0.6)
		"grain":
			draw_line(P.call(12, 21), P.call(12, 5), c, w)
			for y: float in [8.0, 12.0, 16.0]:
				draw_line(P.call(12, y + 2), P.call(8, y - 1), c, w)
				draw_line(P.call(12, y + 2), P.call(16, y - 1), c, w)
		"sack":
			draw_polyline(PackedVector2Array([P.call(8, 6), P.call(6, 19), P.call(18, 19), P.call(16, 6), P.call(8, 6)]), c, w)
			draw_line(P.call(9, 9), P.call(15, 9), c, w)
		"wool":
			draw_arc(P.call(12, 12), 7 * s, 0, TAU, 18, c, w)
			draw_arc(P.call(12, 12), 4 * s, 0.5, TAU - 0.3, 12, c, w)
			draw_arc(P.call(12, 12), 1.5 * s, 0, TAU, 8, c, w)
		"pearl":
			draw_arc(P.call(12, 12), 6 * s, 0, TAU, 18, c, w)
			draw_arc(P.call(10, 10), 2 * s, PI, PI * 1.6, 6, c, w)
		"gem":
			draw_polyline(PackedVector2Array([P.call(12, 4), P.call(19, 11), P.call(12, 20), P.call(5, 11), P.call(12, 4)]), c, w)
			draw_line(P.call(5, 11), P.call(19, 11), c, w * 0.6)
		"spark":
			for a in 4:
				var v := Vector2.from_angle(a * PI / 4.0)
				draw_line(P.call(12, 12) + v * 8 * s, P.call(12, 12) - v * 8 * s, c, w if a % 2 == 0 else w * 0.6)
		"axe":
			draw_line(P.call(8, 20), P.call(15, 5), c, w)
			draw_polyline(PackedVector2Array([P.call(13, 8), P.call(19, 6), P.call(20, 11), P.call(15, 11)]), c, w)
		"knife":
			draw_line(P.call(5, 19), P.call(9, 15), c, w * 1.4)
			draw_polyline(PackedVector2Array([P.call(9, 15), P.call(19, 4), P.call(12, 16), P.call(9, 15)]), c, w)
		"shovel":
			draw_line(P.call(12, 3), P.call(12, 14), c, w)
			draw_polyline(PackedVector2Array([P.call(8, 14), P.call(16, 14), P.call(15, 20), P.call(12, 22), P.call(9, 20), P.call(8, 14)]), c, w)
		"rod":
			draw_line(P.call(4, 20), P.call(18, 4), c, w)
			draw_polyline(PackedVector2Array([P.call(18, 4), P.call(19, 14), P.call(17, 16)]), c, w * 0.6)
		"pick":
			draw_line(P.call(12, 7), P.call(12, 21), c, w)
			draw_arc(P.call(12, 13), 8 * s, -PI * 0.85, -PI * 0.15, 12, c, w)
		"torch":
			draw_line(P.call(10, 21), P.call(13, 11), c, w * 1.3)
			draw_polyline(PackedVector2Array([P.call(13, 3), P.call(16, 8), P.call(14, 11), P.call(11, 10), P.call(11, 7), P.call(13, 3)]), c, w)
		"lantern":
			draw_rect(Rect2(P.call(8, 8), Vector2(8, 11) * s), c, false, w)
			draw_arc(P.call(12, 7), 3 * s, PI, TAU, 8, c, w)
			draw_line(P.call(12, 11), P.call(12, 16), c, w * 0.7)
		"rope":
			draw_arc(P.call(12, 12), 7 * s, 0, TAU, 18, c, w)
			draw_arc(P.call(12, 12), 4 * s, 0, TAU, 14, c, w)
			draw_line(P.call(19, 12), P.call(21, 19), c, w)
		"coal":
			draw_polyline(PackedVector2Array([P.call(5, 15), P.call(8, 8), P.call(16, 7), P.call(19, 14), P.call(14, 18), P.call(5, 15)]), c, w)
			draw_line(P.call(10, 10), P.call(13, 15), c, w * 0.6)
		"ingot":
			draw_polyline(PackedVector2Array([P.call(4, 17), P.call(7, 9), P.call(17, 9), P.call(20, 17), P.call(4, 17)]), c, w)
		"brick":
			draw_rect(Rect2(P.call(4, 8), Vector2(16, 8) * s), c, false, w)
			draw_line(P.call(12, 8), P.call(12, 16), c, w * 0.6)
		"cloth":
			draw_polyline(PackedVector2Array([P.call(4, 8), P.call(20, 8), P.call(20, 16), P.call(4, 16), P.call(4, 8)]), c, w)
			draw_line(P.call(4, 12), P.call(20, 12), c, w * 0.6)
		"pile":
			draw_polyline(PackedVector2Array([P.call(4, 18), P.call(12, 7), P.call(20, 18), P.call(4, 18)]), c, w)
			draw_circle(P.call(11, 14), 0.9 * s, c)
			draw_circle(P.call(14, 15), 0.9 * s, c)
		"bundle":
			for i in 3:
				draw_line(P.call(5 + i * 3, 18), P.call(13 + i * 3, 5), c, w)
			draw_line(P.call(7, 11), P.call(17, 13), c, w * 0.7)
		"cask":
			draw_arc(P.call(12, 12), 7 * s, -0.9, 0.9, 10, c, w)
			draw_arc(P.call(12, 12), 7 * s, PI - 0.9, PI + 0.9, 10, c, w)
			draw_line(P.call(8, 6), P.call(16, 6), c, w)
			draw_line(P.call(8, 18), P.call(16, 18), c, w)
			draw_line(P.call(6, 12), P.call(18, 12), c, w * 0.6)
		"bowl":
			draw_arc(P.call(12, 11), 8 * s, 0, PI, 14, c, w)
			draw_line(P.call(4, 11), P.call(20, 11), c, w)
			draw_polyline(_curve(P.call(10, 8), P.call(9, 5), P.call(11, 3)), c, w * 0.6)
			draw_polyline(_curve(P.call(14, 8), P.call(13, 5), P.call(15, 3)), c, w * 0.6)
		"pie":
			draw_arc(P.call(12, 15), 8 * s, PI, TAU, 14, c, w)
			draw_line(P.call(4, 15), P.call(20, 15), c, w)
			draw_line(P.call(9, 12), P.call(11, 10), c, w * 0.6)
			draw_line(P.call(13, 12), P.call(15, 10), c, w * 0.6)
		"spear":
			draw_line(P.call(4, 20), P.call(17, 7), c, w)
			draw_polyline(PackedVector2Array([P.call(15, 6), P.call(20, 4), P.call(18, 9)]), c, w)
		"bow":
			draw_arc(P.call(8, 12), 9 * s, -PI / 2.4, PI / 2.4, 14, c, w)
			draw_line(P.call(10.5, 3.5), P.call(10.5, 20.5), c, w * 0.6)
		"arrow":
			draw_line(P.call(4, 20), P.call(19, 5), c, w)
			draw_polyline(PackedVector2Array([P.call(14, 5), P.call(19, 5), P.call(19, 10)]), c, w)
		"shield":
			draw_arc(P.call(12, 12), 8 * s, 0, TAU, 20, c, w)
			draw_circle(P.call(12, 12), 1.6 * s, c)
		"coat":
			draw_polyline(PackedVector2Array([P.call(9, 4), P.call(4, 8), P.call(6, 20), P.call(18, 20), P.call(20, 8), P.call(15, 4), P.call(12, 8), P.call(9, 4)]), c, w)
		"foundation":
			draw_rect(Rect2(P.call(4, 13), Vector2(16, 4) * s), c, false, w)
			draw_line(P.call(6, 13), P.call(8, 9), c, w * 0.7)
			draw_line(P.call(18, 13), P.call(16, 9), c, w * 0.7)
			draw_line(P.call(8, 9), P.call(16, 9), c, w * 0.7)
		"wall":
			for y: float in [6.0, 10.0, 14.0, 18.0]:
				draw_line(P.call(4, y), P.call(20, y), c, w)
			draw_line(P.call(6, 6), P.call(6, 18), c, w * 0.6)
			draw_line(P.call(18, 6), P.call(18, 18), c, w * 0.6)
		"floor":
			draw_polyline(PackedVector2Array([P.call(3, 15), P.call(9, 9), P.call(21, 9), P.call(15, 15), P.call(3, 15)]), c, w)
			draw_line(P.call(7, 12), P.call(19, 12), c, w * 0.6)
		"roof":
			draw_polyline(PackedVector2Array([P.call(3, 17), P.call(12, 6), P.call(21, 17)]), c, w)
			draw_line(P.call(6, 17), P.call(18, 17), c, w * 0.6)
		"horse":
			draw_polyline(PackedVector2Array([P.call(6, 20), P.call(9, 10), P.call(13, 5), P.call(18, 7), P.call(15, 10), P.call(12, 11), P.call(11, 20)]), c, w)
		"door":
			draw_rect(Rect2(P.call(7, 4), Vector2(10, 16) * s), c, false, w)
			draw_circle(P.call(14, 12), 1.0 * s, c)
		"window":
			draw_rect(Rect2(P.call(5, 7), Vector2(14, 10) * s), c, false, w)
			draw_line(P.call(12, 7), P.call(12, 17), c, w * 0.6)
			draw_line(P.call(5, 12), P.call(19, 12), c, w * 0.6)
		"pier":
			draw_line(P.call(3, 10), P.call(21, 10), c, w)
			for x: float in [6.0, 12.0, 18.0]:
				draw_line(P.call(x, 10), P.call(x, 19), c, w)
			draw_polyline(_curve(P.call(3, 17), P.call(12, 21), P.call(21, 17)), c, w * 0.6)
		"bench":
			draw_line(P.call(4, 11), P.call(20, 11), c, w * 1.2)
			draw_line(P.call(7, 11), P.call(7, 18), c, w)
			draw_line(P.call(17, 11), P.call(17, 18), c, w)
		"table":
			draw_line(P.call(3, 9), P.call(21, 9), c, w * 1.2)
			draw_line(P.call(6, 9), P.call(6, 19), c, w)
			draw_line(P.call(18, 9), P.call(18, 19), c, w)
		"bed":
			draw_rect(Rect2(P.call(4, 9), Vector2(16, 5) * s), c, false, w)
			draw_line(P.call(5, 14), P.call(5, 20), c, w)
			draw_line(P.call(19, 14), P.call(19, 20), c, w)
			draw_arc(P.call(8, 7.5), 2 * s, PI, TAU, 8, c, w)
		"rack":
			draw_line(P.call(5, 4), P.call(5, 20), c, w)
			draw_line(P.call(19, 4), P.call(19, 20), c, w)
			draw_line(P.call(5, 6), P.call(19, 6), c, w)
			for x: float in [9.0, 12.0, 15.0]:
				draw_line(P.call(x, 6), P.call(x, 13), c, w * 0.8)
		"fire":
			draw_polyline(PackedVector2Array([P.call(12, 4), P.call(16, 11), P.call(14, 16), P.call(10, 16), P.call(8, 11), P.call(12, 4)]), c, w)
			draw_line(P.call(4, 19), P.call(20, 19), c, w)
			draw_line(P.call(6, 16), P.call(18, 20), c, w * 0.6)
		"anvil":
			draw_polyline(PackedVector2Array([P.call(4, 8), P.call(20, 8), P.call(17, 12), P.call(14, 12), P.call(15, 17), P.call(9, 17), P.call(10, 12), P.call(7, 12), P.call(4, 8)]), c, w)
			draw_line(P.call(7, 20), P.call(17, 20), c, w)
		"stove":
			draw_rect(Rect2(P.call(4, 9), Vector2(16, 11) * s), c, false, w)
			draw_rect(Rect2(P.call(14, 3), Vector2(4, 6) * s), c, false, w)
			draw_arc(P.call(12, 17), 3.5 * s, PI, TAU, 8, c, w)
		"pen":
			for y: float in [9.0, 15.0]:
				draw_line(P.call(3, y), P.call(21, y), c, w)
			for x: float in [5.0, 12.0, 19.0]:
				draw_line(P.call(x, 6), P.call(x, 19), c, w)
		"cross":
			draw_line(P.call(12, 3), P.call(12, 21), c, w)
			draw_line(P.call(6, 9), P.call(18, 9), c, w)
			draw_line(P.call(9, 5), P.call(15, 5), c, w * 0.8)
			draw_line(P.call(8, 17), P.call(16, 14), c, w * 0.8)
		"boat":
			draw_polyline(PackedVector2Array([P.call(3, 13), P.call(21, 13), P.call(18, 18), P.call(6, 18), P.call(3, 13)]), c, w)
			draw_line(P.call(12, 13), P.call(12, 3), c, w)
			draw_polyline(PackedVector2Array([P.call(12, 4), P.call(18, 11), P.call(12, 11)]), c, w)
		"note":
			draw_arc(P.call(8, 17), 2.5 * s, 0, TAU, 12, c, w)
			draw_arc(P.call(17, 15), 2.5 * s, 0, TAU, 12, c, w)
			draw_line(P.call(10.5, 17), P.call(10.5, 6), c, w)
			draw_line(P.call(19.5, 15), P.call(19.5, 4), c, w)
			draw_line(P.call(10.5, 6), P.call(19.5, 4), c, w * 1.6)
		"tower":
			draw_line(P.call(8, 21), P.call(10, 8), c, w)
			draw_line(P.call(16, 21), P.call(14, 8), c, w)
			draw_line(P.call(7, 8), P.call(17, 8), c, w)
			draw_line(P.call(9, 15), P.call(15, 15), c, w * 0.8)
			draw_polyline(PackedVector2Array([P.call(9, 8), P.call(10, 5), P.call(14, 5), P.call(15, 8)]), c, w)
		"necklace":
			for i in 7:
				var a := PI * 0.15 + i * PI * 0.7 / 6.0
				draw_arc(P.call(12, 6) + Vector2(cos(a), sin(a)) * 9 * s, 1.4 * s, 0, TAU, 8, c, w * 0.8)
	if count > 1:
		var f := UiTheme.font("bold")
		var t := str(count)
		var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(f, Vector2(size.x - ts.x - 3, size.y - 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)


func _curve(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out
