class_name CreatureDirector
extends Node
## The creatures of the world (docs/01_GDD.md §6, §11). Every peer keeps a CreatureView for each creature in
## WorldState.creatures. The host also decides who comes and goes (always through "spawn"/"despawn", which
## check the mode, the region and the fog), runs their behaviour, reports their positions ("creatures") and
## lands their hits ("hurt"). Spirits appear where their tales put them; the player meets them, and E leaves
## a gift. Saga fights: fire-defence waves out of the fog, guardian tricks and summons.

const MAX_AMBIENT := 7
const DESPAWN_M := 190.0
const SPAWN_MIN_M := 22.0
const SPAWN_MAX_M := 46.0
const MEET_M := 22.0
const WAVE_S := 16.0

var world  # the world scene (untyped: player, map, hud, audio, _focus…)
var db: ContentDB
var state: WorldState
var map: WorldMap
var views: Dictionary = {}  # uid -> CreatureView
var night := 0.0
var leshy_goal := Vector3.INF

var _spawn_t := 1.0
var _sync_t := 0.0
var _meet_t := 0.0
var _wave_t := 0.0
var _wave := 0
var _asked: Dictionary = {}  # ids this session already asked about (meet)
var _leshy_island := ""
var _warned: Dictionary = {}  # uid -> true (toast once)


func setup(p_world) -> void:
	world = p_world
	db = world.db
	state = world.state
	map = world.map
	name = "Creatures"
	Game.world_event.connect(_on_event)
	for uid: String in state.creatures:
		var c: Dictionary = state.creatures[uid]
		_add_view(uid, String(c["id"]), c["pos"], String(c["fight"]))


func _add_view(uid: String, id: String, pos: Vector3, fight: String) -> CreatureView:
	if views.has(uid) or not db.creatures.has(id):
		return views.get(uid)
	var v := CreatureView.new()
	world.add_child(v)
	v.setup(self, uid, id, pos, fight)
	if fight != "" and v.behaviour() == "fog" and String(state.fight.get("kind", "")) == "defense":
		var at := db.beacon_pos(fight)
		v.target = Vector3(at.x, map.ground_at(at.x, at.y), at.y)
	views[uid] = v
	return v


func _drop_view(uid: String) -> void:
	var v: CreatureView = views.get(uid)
	if v != null:
		v.queue_free()
		views.erase(uid)


# ---------------------------------------------------------------- what the world tells us

func _on_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"creature_spawned":
			_add_view(String(e["uid"]), String(e["id"]), WorldState._to_v3(e["pos"]), state.busy_beacon if e.get("fight", false) else "")
		"creature_gone":
			_drop_view(String(e["uid"]))
		"creature_died":
			var v: CreatureView = views.get(String(e["uid"]))
			if v != null:
				world.audio.sfx("thud")
			_drop_view(String(e["uid"]))
		"creature_hit":
			var v: CreatureView = views.get(String(e["uid"]))
			if v != null:
				v.flash()
				if v.mood == "sleep":
					v.mood = "chase"  # Likho wakes when struck
		"guardian_phase":
			world.hud.toast(tr("toast.phase") % [Loc.name_of(db.creatures[e["id"]]["name"]), int(e["phase"])], "!")
			world.audio.sfx("swell")
			if String(e["id"]) == "mga" and Net.is_authority():
				var boss: CreatureView = views.get(String(e["uid"]))
				if boss != null:
					summon(boss, "mglyak", 3)  # the fog splits into mistlings
		"offered":
			if String(e["spirit"]) == "leshy":
				leshy_goal = _leshy_target()
		"fight_started":
			_wave_t = 3.0
			_wave = 0
		"fight_ended":
			_wave = 0


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	var f: Vector3 = world._focus()
	var rid := db.region_at(Vector2(f.x, f.z))
	night = Weather.night(db, rid, state.clock_min)
	if not Net.is_authority():
		# a co-op client draws the host's creatures where the host says they are (replayed "creatures")
		var k := 1.0 - exp(-delta * 6.0)
		for uid: String in views:
			if state.creatures.has(uid):
				var v: CreatureView = views[uid]
				var to: Vector3 = state.creatures[uid]["pos"]
				var step := to - v.position
				v.position = Vector3(lerpf(v.position.x, to.x, k), v.position.y, lerpf(v.position.z, to.z, k))
				if Vector2(step.x, step.z).length() > 0.05:
					v.yaw = lerp_angle(v.yaw, atan2(-step.x, -step.z), k)
		return
	for v: CreatureView in views.values():
		v.think(delta)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.5
		_sync()
	_meet_t -= delta
	if _meet_t <= 0.0:
		_meet_t = 1.0
		_meet_around()
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 2.0
		_despawn_far(f)
		_spirits(f, rid)
		_raid(f)
		_ambient(f, rid)
	if not state.fight.is_empty():
		_fight(delta)


func _sync() -> void:
	var moved := {}
	for uid: String in views:
		var v: CreatureView = views[uid]
		if state.creatures.has(uid) and (state.creatures[uid]["pos"] as Vector3).distance_to(v.position) > 0.2:
			moved[uid] = WorldState._v3(v.position)
	if not moved.is_empty():
		Game.submit({"type": "creatures", "pos": moved})


## First sight of a creature: its page in the journal of tales ("meet"). The whale is met by landing on it.
func _meet_around() -> void:
	var p := player_pos()
	for v: CreatureView in views.values():
		if v.id in ["ryba_kit"] or state.journal.has(v.id) or _asked.has(v.id):
			continue
		if v.mood == "sleep" or p.distance_to(v.position) > MEET_M:
			continue
		_asked[v.id] = true
		Game.submit({"type": "meet", "creature": v.id})


# ---------------------------------------------------------------- the host's spawning

func _despawn_far(f: Vector3) -> void:
	for uid: String in views.keys():
		var v: CreatureView = views[uid]
		if v.fight != "":
			continue
		var far := DESPAWN_M * (3.0 if v.id == "ryba_kit" else 1.0)
		var gone := Vector2(v.position.x - f.x, v.position.z - f.z).length() > far
		if v.id == "ryba_kit" and night < 0.3:
			gone = true  # it dives at dawn
		if v.id == "seal" and v.mood == "hide" and map.ground_at(v.position.x, v.position.z) < -0.4:
			gone = true
		if gone:
			Game.submit({"type": "despawn", "uid": uid})


func _count(id: String) -> int:
	var n := 0
	for v: CreatureView in views.values():
		if v.id == id:
			n += 1
	return n


func _ambient_count() -> int:
	var n := 0
	for v: CreatureView in views.values():
		if v.fight == "" and not Creatures.is_spirit(db, v.id):
			n += 1
	return n


## Animals, predators and fog creatures around the player: the region's list (regions.json → creatures),
## what the mode allows, weighted; the host's "spawn" says the final yes or no (fog, night, mode).
func _ambient(f: Vector3, rid: String) -> void:
	if _ambient_count() >= MAX_AMBIENT:
		return
	var aboard: bool = not world.on_foot()
	var r := state.rules()
	var pool: Array = []
	var total := 0.0
	for id: String in db.regions[rid]["creatures"]:
		var g := Creatures.group(db, id)
		if Creatures.is_spirit(db, id) or g == "guardian" or not Creatures.allowed(db, state.mode, r, id):
			continue
		var w := 0.0
		match id:
			"hare", "fox":
				w = 3.0
			"reindeer":
				w = 1.2
			"gull":
				w = 2.0 if _count("gull") < 3 else 0.0
			"seal":
				w = 1.5 if _count("seal") < 2 else 0.0
			"wolf":
				w = 2.5 if night >= 0.5 else 0.4
			"bear", "polar_bear":
				w = 1.0 if _count(id) < 1 else 0.0
			"likho":
				w = 0.0  # it waits in its cave (below)
			"karachun":
				w = 0.5 if _count(id) < 1 else 0.0
			_:
				if g == "fog":
					w = 3.0 if _count(id) < (3 if id == "fog_wolf" else 2) else 0.0
		if aboard and not id in ["seal", "gull", "morok"]:
			w = 0.0
		if w > 0.0:
			pool.append([id, w])
			total += w
	_likho(f)
	if pool.is_empty():
		return
	var pick := randf() * total
	var id := ""
	for e: Array in pool:
		pick -= float(e[1])
		if pick <= 0.0:
			id = e[0]
			break
	if id == "":
		id = pool[-1][0]
	var at := _spot_for(id, f)
	if at == Vector3.INF:
		return
	Game.submit({"type": "spawn", "id": id, "pos": WorldState._v3(at)})


## Where a creature can appear: on the island around the player (not inside the homestead), a shore for
## seals, the air for gulls; for Morok a shore seen from the boat.
func _spot_for(id: String, f: Vector3) -> Vector3:
	var isl := map.island_at(f.x, f.z) if world.on_foot() else map.nearest_island(Vector2(f.x, f.z), 140.0)
	if id == "gull":
		var a := randf() * TAU
		return f + Vector3(cos(a), 0, sin(a)) * 30.0
	if isl == null:
		return Vector3.INF
	for k in 12:
		var a := randf() * TAU
		var p2: Vector2
		if id in ["seal", "morok"]:
			p2 = WorldMap.walk_out(isl, isl.center, Vector2.from_angle(a))["shore"]
		else:
			p2 = Vector2(f.x, f.z) + Vector2.from_angle(a) * randf_range(SPAWN_MIN_M, SPAWN_MAX_M)
		var g := map.ground_at(p2.x, p2.y)
		if id in ["seal", "morok"]:
			if g < -0.2 or g > 1.2 or p2.distance_to(Vector2(f.x, f.z)) < 18.0:
				continue
		elif g < 0.8:
			continue
		if not Crafting.stations_near(state, Vector3(p2.x, g, p2.y), 14.0).is_empty():
			continue  # never inside the homestead
		return Vector3(p2.x, g, p2.y)
	return Vector3.INF


## Likho sleeps in its cave on the Summer Shore until beaten (Saga, optional).
func _likho(f: Vector3) -> void:
	var cave := map.likho_cave()
	if cave == Vector3.INF or _count("likho") > 0 or state.spirits.has("likho"):
		return
	if not Creatures.allowed(db, state.mode, state.rules(), "likho"):
		return
	if Vector2(cave.x - f.x, cave.z - f.z).length() < 120.0:
		Game.submit({"type": "spawn", "id": "likho", "pos": WorldState._v3(cave)})


## Spirits come where their tales put them (docs/01_GDD.md §11).
func _spirits(f: Vector3, rid: String) -> void:
	var on_foot: bool = world.on_foot()
	var list: Array = db.regions[rid]["creatures"]
	# the domovoy by the stove of a home with comfort 5+
	var home := Creatures.domovoy_home(db, state)
	if home != "" and _count("domovoy") == 0:
		var bed: Vector3 = state.pieces[home]["pos"]
		if bed.distance_to(f) < 45.0:
			var at := _near_piece(bed, ["stove", "hearth"], 1.2)
			_spawn("domovoy", at if at != Vector3.INF else bed + Vector3(1, 0, 0))
	# the bannik in a bathhouse, in the late hours
	if _count("bannik") == 0:
		var phase := Weather.day_phase(db, state.clock_min)
		if phase > 0.8 or phase < 0.25:
			var at := _near_piece(f, ["bathhouse_stove"], 1.3, 30.0)
			if at != Vector3.INF:
				_spawn("bannik", at)
	# the leshy on a big forested island in thick fog
	if on_foot and list.has("leshy") and _count("leshy") == 0:
		var isl := map.island_at(f.x, f.z)
		if isl != null and isl.id != _leshy_island and map.forested(isl.id):
			var dark: bool = map.kind_of[isl.id] == "beacon" and not state.lit.has(isl.id)
			if dark or night >= 0.5 or FogField.factor(db, state, Vector2(f.x, f.z)) > 0.8:
				for k in 8:
					var a := randf() * TAU
					var q := Vector2(f.x, f.z) + Vector2.from_angle(a) * 16.0
					if map.ground_at(q.x, q.y) > 1.5:
						_leshy_island = isl.id
						_spawn("leshy", Vector3(q.x, map.ground_at(q.x, q.y), q.y))
						break
	# the vodyanoy at the water's edge of the Summer Shore and the Ter Coast
	if list.has("vodyanoy") and _count("vodyanoy") == 0 and on_foot and map.ground_at(f.x, f.z) < 3.0:
		for k in 12:
			var a := k * TAU / 12.0
			var q := Vector2(f.x, f.z) + Vector2.from_angle(a) * 9.0
			var g := map.ground_at(q.x, q.y)
			if g > -0.4 and g < 0.2:
				_spawn("vodyanoy", Vector3(q.x, g, q.y))
				break
	# Sirin at dawn on a high rock
	if list.has("sirin") and _count("sirin") == 0 and Weather.is_dawn(db, rid, state.clock_min):
		var isl := map.nearest_island(Vector2(f.x, f.z), 220.0)
		if isl != null:
			var c := isl.center
			var h := isl.height_at(c.x, c.y)
			if h >= 9.0:
				_spawn("sirin", Vector3(c.x + 3.0, isl.height_at(c.x + 3.0, c.y), c.y))
	# the miracle whale on calm nights of the Frozen Sea, once a night, near a boat
	if list.has("ryba_kit") and _count("ryba_kit") == 0 and not on_foot and night >= 0.5:
		var whale: Dictionary = state.spirits.get("whale", {})
		if int(whale.get("day", 0)) != state.day and Weather.storm(db, state.world_seed, state.clock_min, rid) == 0:
			var h: Vector2 = world.my_boat.heading()
			var q := Vector2(f.x, f.z) + h * 70.0
			if map.ground_at(q.x, q.y) < -2.0:
				_spawn("ryba_kit", Vector3(q.x, 0.0, q.y))


## Night raids (Saga, modes.json night_raids): on thick-fog nights mistlings probe the edge of a homestead —
## any three or more pieces together near the player. Lamps and fences keep them out; they never touch walls
## or stations (there is no command that could). The host's "spawn" still checks the fog and the night.
func _raid(f: Vector3) -> void:
	if not bool(state.rules()["night_raids"]) or night < 0.5 or not Creatures.allowed(db, state.mode, state.rules(), "mglyak"):
		return
	var centre := homestead(f)
	if centre == Vector3.INF:
		return
	var raiders := 0
	for v: CreatureView in views.values():
		if v.raid != Vector3.INF:
			raiders += 1
	if raiders >= 3:
		return
	var a := randf() * TAU
	var q := centre + Vector3(cos(a), 0, sin(a)) * randf_range(30.0, 40.0)
	q.y = map.ground_at(q.x, q.z)
	if q.y < 0.5:
		return
	var res := Game.submit({"type": "spawn", "id": "mglyak", "pos": WorldState._v3(q)})
	if res.get("ok", false):
		for e: Dictionary in res["events"]:
			var v: CreatureView = views.get(String(e["uid"]))
			if v != null:
				v.raid = centre


## The middle of a homestead near `f`: three or more pieces within 20 m of each other (INF if none).
func homestead(f: Vector3) -> Vector3:
	var near: Array[Vector3] = []
	for uid: String in state.pieces:
		var q: Vector3 = state.pieces[uid]["pos"]
		if q.distance_to(f) < 90.0:
			near.append(q)
	if near.size() < 3:
		return Vector3.INF
	var c := Vector3.ZERO
	for q in near:
		c += q
	return c / near.size()


## How far the nearest lamp or fence keeps raiders off a point: the lamp's fog_radius (a pen: 3 m), 0 if none.
func ward_at(p: Vector3) -> float:
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		var r := float(db.pieces[pc["id"]].get("fog_radius", 0.0))
		if String(pc["id"]) == "sheep_pen":
			r = 3.0
		if r > 0.0 and (pc["pos"] as Vector3).distance_to(p) < r + 2.0:
			return r
	return 0.0


## Any creature that could hurt the player within `r` metres (for the combat hint).
func hostile_near(p: Vector3, r: float) -> bool:
	for v: CreatureView in views.values():
		if not Creatures.is_friendly(db, v.id) and v.position.distance_to(p) < r:
			return true
	return false


func _spawn(id: String, at: Vector3) -> void:
	Game.submit({"type": "spawn", "id": id, "pos": WorldState._v3(at)})


## A spot beside the nearest piece of these kinds within `reach` of `p` (INF if none).
func _near_piece(p: Vector3, ids: Array, off: float, reach: float = 12.0) -> Vector3:
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if String(pc["id"]) in ids and (pc["pos"] as Vector3).distance_to(p) < reach:
			var q: Vector3 = pc["pos"]
			return q + Vector3(off, 0, off * 0.5)
	return Vector3.INF


# ---------------------------------------------------------------- Saga fights

func fight_phase() -> int:
	return int(state.fight.get("phase", 1))


## A fire defence: waves out of the fog every WAVE_S seconds, from the edge of the island towards the fire.
func _fight(delta: float) -> void:
	if String(state.fight["kind"]) != "defense":
		return
	_wave_t -= delta
	if _wave_t > 0.0:
		return
	_wave_t = WAVE_S
	_wave += 1
	var bid := String(state.fight["beacon"])
	var isl: IslandGen = map.by_id[bid]
	var r := state.rules()
	var kinds: Array[String] = []
	for id: String in db.regions[String(db.beacons[bid]["region"])]["creatures"]:
		if Creatures.group(db, id) == "fog" and Creatures.allowed(db, state.mode, r, id):
			kinds.append(id)
	if kinds.is_empty():
		kinds = ["mglyak"]
	for k in 1 + _wave:
		var a := randf() * TAU
		var p2: Vector2 = WorldMap.walk_out(isl, isl.center, Vector2.from_angle(a))["shore"]
		p2 = p2.lerp(isl.center, 0.15)
		var id: String = kinds[k % kinds.size()]
		Game.submit({"type": "spawn", "id": id, "pos": [p2.x, map.ground_at(p2.x, p2.y), p2.y], "fight": true})


# ---------------------------------------------------------------- what creatures do to the player

func player_pos() -> Vector3:
	return (world.player as Node3D).global_position if world.on_foot() else world._focus()


## The fog-clearing radius of the light in hand (0 without one): what fog creatures and wolves keep off.
func player_light_radius() -> float:
	var id: String = world.player.light_id
	if id == "" or not world.on_foot():
		return 0.0
	return float(db.items[id]["light"]["fog_radius"])


## A creature's hit: its position first (the host checks reach), then "hurt".
func bite(v: CreatureView, k: float) -> void:
	Game.submit({"type": "creatures", "pos": {v.uid: WorldState._v3(v.position)}})
	world._send_move()
	Game.submit({"type": "hurt", "player": Net.local_player_id(), "source": v.uid, "k": k})


## A beast rears and growls before it charges.
func roar(v: CreatureView) -> void:
	world.audio.sfx("growl")
	if not _warned.has(v.uid):
		_warned[v.uid] = true
		world.hud.toast(tr("toast.warns") % Loc.name_of(v.info["name"]), "!")


## Siverko's gust: pushes the player away from him (off the ledges) and stings.
func gust(v: CreatureView, strength: float) -> void:
	var p := player_pos()
	var away := Vector3(p.x - v.position.x, 0, p.z - v.position.z).normalized()
	if p.distance_to(v.position) < 18.0 and world.on_foot():
		world.player.push(away * strength)
		bite(v, 0.4)
	world.audio.sfx("whoosh")


## The Bog Maiden drags you into the mire: slow for a moment.
func mire(_v: CreatureView) -> void:
	world.player.slow(0.45, 1.2)


## The Master of the Bay's tidal wave: those near the water are hit and thrown up the shore.
func wave(v: CreatureView) -> void:
	var p := player_pos()
	if p.distance_to(v.position) < 18.0 and p.y < 3.5:
		bite(v, 0.8)
		var inland := Vector3(p.x - v.position.x, 0, p.z - v.position.z).normalized()
		world.player.push(inland * 10.0)
	world.audio.sfx("thud")


## Guardians call their own: fight spawns around the boss.
func summon(v: CreatureView, id: String, n: int) -> void:
	for k in n:
		var a := randf() * TAU
		var q := v.position + Vector3(cos(a), 0, sin(a)) * 5.0
		Game.submit({"type": "spawn", "id": id, "pos": [q.x, map.ground_at(q.x, q.z), q.z], "fight": true})


## A fog creature beats at the fire of a defence.
func douse(v: CreatureView) -> void:
	Game.submit({"type": "creatures", "pos": {v.uid: WorldState._v3(v.position)}})
	Game.submit({"type": "douse", "source": v.uid})


## A drying rack with something on it near a point (INF if none).
func rack_near(p: Vector3) -> Vector3:
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if String(pc["id"]) == "drying_rack" and (pc["pos"] as Vector3).distance_to(p) < 60.0 and not (pc.get("out", {}) as Dictionary).is_empty():
			return pc["pos"]
	return Vector3.INF


func steal(v: CreatureView) -> void:
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if String(pc["id"]) == "drying_rack" and (pc["pos"] as Vector3).distance_to(v.home) < 60.0:
			Game.submit({"type": "steal", "source": v.uid, "uid": uid})
			return


## The leshy's wisp leads to the path of the island's beacon, or else to the nearest shore.
func _leshy_target() -> Vector3:
	var p := player_pos()
	var isl := map.island_at(p.x, p.z)
	if isl == null:
		return Vector3.INF
	if map.paths.has(isl.id):
		return map.path_point(isl.id, 0.1, 0.0)
	var dir := Vector2(p.x - isl.center.x, p.z - isl.center.y).normalized()
	var s: Vector2 = WorldMap.walk_out(isl, Vector2(p.x, p.z), dir)["shore"]
	return Vector3(s.x, map.ground_at(s.x, s.y), s.y)


# ---------------------------------------------------------------- E by a spirit, and targets for a strike

## What E does next to a spirit: leave its gift, or bow (meet). {} if no spirit is near.
func action(p: Vector3, aboard: bool) -> Dictionary:
	for v: CreatureView in views.values():
		if not Creatures.is_spirit(db, v.id):
			continue
		var reach := 26.0 if v.id == "ryba_kit" else 3.5 + v.radius
		if Vector2(p.x - v.position.x, p.z - v.position.z).length() > reach:
			continue
		if v.id == "ryba_kit":
			if aboard:
				return {"label": tr("act.whale"), "run": _meet.bind("ryba_kit")}
			continue
		if aboard:
			continue
		var gift := String(v.info.get("gift", ""))
		var hungry := true
		match v.id:
			"domovoy":
				hungry = not Creatures.domovoy_fed(db, state)
			"vodyanoy":
				hungry = not Creatures.vodyanoy_boon(state)
			"leshy":
				hungry = not Creatures.leshy_guiding(state)
		if gift != "" and hungry and state.inv(Net.local_player_id()).count(gift) > 0:
			return {"label": tr("act.offer") % [Loc.item(db, gift), Loc.name_of(v.info["name"])], "run": _offer.bind(v.id)}
		if gift != "" and hungry:
			return {"label": tr("act.wants") % [Loc.name_of(v.info["name"]), Loc.item(db, gift)], "run": _meet.bind(v.id)}
		return {"label": tr("act.bow") % Loc.name_of(v.info["name"]), "run": _meet.bind(v.id)}
	return {}


func _offer(id: String) -> void:
	world._send_move()
	Game.submit({"type": "offer", "spirit": id})


func _meet(id: String) -> void:
	world._send_move()
	Game.submit({"type": "meet", "creature": id})


## The creature a strike from `p` facing `fwd` would land on: hostile, within reach, in front (±70°).
func target_for(p: Vector3, fwd: Vector3, reach: float) -> CreatureView:
	var best: CreatureView = null
	var best_d := INF
	for v: CreatureView in views.values():
		if Creatures.is_friendly(db, v.id):
			continue
		var to := Vector3(v.position.x - p.x, 0, v.position.z - p.z)
		var d := to.length() - v.radius
		if d > reach or d > best_d:
			continue
		if d > 1.0 and to.normalized().dot(fwd) < 0.34:
			continue
		best = v
		best_d = d
	return best


## The boss of the current fight, if any.
func boss() -> CreatureView:
	return views.get(String(state.fight.get("boss", "")))
