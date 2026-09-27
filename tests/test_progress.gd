extends "res://tests/lib/case.gd"


func test_next_beacon_follows_the_order() -> void:
	var st := WorldState.new(db)
	eq(Progress.next_beacon(db, st), "b01")
	st.lit["b01"] = 1
	eq(Progress.next_beacon(db, st), "b02")
	st.lit["b02"] = 1
	st.lit["b03"] = 1
	eq(Progress.next_beacon(db, st), "b04", "r2 opens after b03")
	for bid in db.beacon_order:
		st.lit[bid] = 1
	eq(Progress.next_beacon(db, st), "")


func test_next_skips_closed_regions() -> void:
	var st := WorldState.new(db)
	st.lit["b01"] = 1
	st.lit["b02"] = 1
	st.lit["b04"] = 1  # can't happen in play, but the compass must not point into a closed region
	eq(Progress.next_beacon(db, st), "b03")


func test_music_layers_grow() -> void:
	eq(Progress.music_layers(0), ["base"])
	check("chords" in Progress.music_layers(1), "chords after the first beacon")
	check("choir" in Progress.music_layers(12), "choir at the end")
	check(not "choir" in Progress.music_layers(10), "no choir yet at 10")


func test_wind_turns_slowly() -> void:
	var a := Weather.wind(db, 7, 10.0)
	var b := Weather.wind(db, 7, 10.1)
	near(a.length(), 1.0, 1e-5)
	check(a.angle_to(b) < 0.05, "no jumps in a few seconds")
	eq(Weather.wind(db, 7, 33.0), Weather.wind(db, 7, 33.0), "deterministic")
