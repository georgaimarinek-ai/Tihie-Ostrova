class_name CreatureView
extends Node3D
## One creature (creatures.json): its body (art/models/creatures/<id>.glb or a CreatureShapes placeholder)
## and, on the host, its behaviour (docs/01_GDD.md §11). Animals flee or watch; the wolf hunts at night and
## keeps away from fire; bears warn before they charge; the Mga's creatures come out of thick fog and back
## off from light; guardians have their own tricks. Harm is never done here: the director sends "hurt" and
## the host's WorldCommands decides. Friendly creatures have no attack at all.

var uid := ""
var id := ""
var info: Dictionary = {}
var director  # CreatureDirector (untyped: the world is read through it)
var model: Node3D
var height := 1.0
var radius := 0.5
var home := Vector3.ZERO
var fight := ""  # the beacon whose fight it belongs to ("" = ambient)
var mood := "idle"  # idle | wander | flee | warn | chase | keep_off | sleep | hide | circle
var yaw := 0.0
var hover := 0.0  # height over the ground (gulls fly, mistlings float)
var target := Vector3.INF  # what it goes for instead of the player (the beacon's fire in a defence)
var raid := Vector3.INF  # a night raid: the homestead it probes
var phase_t := 0.0  # a sea creature: seconds in its current phase (circle → grip → roll)
var hit_t := 999.0  # seconds since a player last struck it
var hits := 0  # strikes taken while gripping (three drive it off)
var false_light: Node3D  # the Morok's lure over the shallows

var _goal := Vector3.ZERO
var _t := 0.0
var _cool := 0.0
var _special := 3.0
var _mood_t := 0.0
var _flash := 0.0
var _bob := 0.0


func setup(p_director, p_uid: String, p_id: String, pos: Vector3, p_fight: String) -> void:
	director = p_director
	uid = p_uid
	id = p_id
	fight = p_fight
	info = director.db.creatures[id]
	name = "Creature_%s_%s" % [id, uid]
	model = ModelLibrary.instance("creatures", id)
	add_child(model)
	var size := ModelLibrary.fit(model)  # the placeholder says its size; the artist's model is measured
	height = float(size["height"])
	radius = float(size["radius"])
	match id:
		"gull":
			hover = 9.0
		"mglyak", "ice_mglyak", "morok":
			hover = 0.4
		"siverko":
			hover = 1.2
		"ryba_kit":
			hover = -1.4
		"puchinnik":
			hover = -0.7  # awash: only the hump and the crest show
	home = pos
	_goal = pos
	position = pos
	yaw = randf() * TAU
	if id == "likho":
		mood = "sleep"
	_bob = randf() * 10.0
	if id == "morok":
		_hang_false_light()


## The Morok's trick (creatures.json special): a warm light like a beacon's hint, hung over the shallows
## 60–200 m out from its shore. A boat that steers for it runs onto the bottom. Not on the compass; with fire
## in hand it flickers green.
func _hang_false_light() -> void:
	var map: WorldMap = director.map
	var best := Vector3.INF
	for k in 24:
		var a := k * TAU / 24.0
		for r in range(60, 200, 20):
			var p2 := Vector2(position.x, position.z) + Vector2.from_angle(a) * float(r)
			var g := map.ground_at(p2.x, p2.y)
			if g < -0.4 and g > -1.6:
				best = Vector3(p2.x, 6.0, p2.y)
				break
		if best != Vector3.INF:
			break
	if best == Vector3.INF:
		return
	false_light = Node3D.new()
	false_light.name = "FalseLight"
	false_light.top_level = true
	false_light.position = best
	false_light.add_child(Placeholders.glow(Color("ffb060"), 4.0, 1.2))
	var l := OmniLight3D.new()
	l.light_color = Color("ffb060")
	l.light_energy = 2.0
	l.omni_range = 14.0
	l.shadow_enabled = false
	l.add_to_group("budget_light")
	false_light.add_child(l)
	add_child(false_light)


func behaviour() -> String:
	return String(info["behaviour"])


func speed() -> float:
	return float(info.get("speed", 3.0))


## Hit feedback: a quick swell of the body.
func flash() -> void:
	_flash = 0.25


func _process(delta: float) -> void:
	_bob += delta
	_flash = maxf(0.0, _flash - delta)
	hit_t += delta
	var s := 1.0 + _flash * 0.6
	model.scale = Vector3.ONE * s
	model.rotation.y = yaw
	var ground: float = director.map.ground_at(position.x, position.z)
	var y := maxf(ground, 0.0) + hover
	if hover > 0.2:
		y += sin(_bob * 1.7) * 0.25
	if id == "ryba_kit":
		y = hover + sin(_bob * 0.3) * 0.3
	elif behaviour() == "sea":
		y = Sea.height(position.x, position.z, director.world.sea.storm) + hover + sin(_bob * 0.8) * 0.2
		model.rotation.x = sin(_bob * 0.8) * 0.08
	if false_light != null:
		var torch_near: bool = director.player_light_radius() > 0.0 and _flat_from(director.player_pos(), false_light.position) < 60.0
		var glow := false_light.get_node("Glow") as MeshInstance3D
		var col := Color("70e090") if torch_near else Color("ffb060")
		(glow.material_override as ShaderMaterial).set_shader_parameter("color", col)
		(glow.material_override as ShaderMaterial).set_shader_parameter("strength", 1.2 + sin(_bob * (9.0 if torch_near else 2.0)) * 0.5)
		(false_light.get_child(1) as OmniLight3D).light_color = col
	elif id in ["seal", "vodyanoy"] and ground < 0.3:
		y = -0.6 + sin(_bob) * 0.1  # in the water to the shoulders
	position.y = lerpf(position.y, y, 1.0 - exp(-delta * 6.0))
	if mood == "warn":
		model.rotation.x = lerpf(model.rotation.x, 0.5, 1.0 - exp(-delta * 6.0))  # rears up
	else:
		model.rotation.x = lerpf(model.rotation.x, 0.0, 1.0 - exp(-delta * 6.0))


# ---------------------------------------------------------------- behaviour (host)

## One step of behaviour: called by the director on the host only.
func think(delta: float) -> void:
	_t += delta
	_cool -= delta
	_special -= delta
	_mood_t -= delta
	var pp: Vector3 = director.player_pos()
	var d := _flat(pp)
	var on_foot: bool = director.world.on_foot()
	match behaviour():
		"flee":
			if d < 12.0 and on_foot:
				_run_from(pp, speed(), delta)
			else:
				_wander(4.0, speed() * 0.25, delta)
		"sea":
			_sea(pp, d, on_foot, delta)
		"watch":
			if d < 7.0 and on_foot and id == "seal":
				mood = "hide"
				_go(_shore_out(), speed(), delta)
			elif id == "seal" and not on_foot and d < 35.0 and absf(float(director.world.my_boat.speed)) > 1.0:
				# seals keep the boat company: alongside, a little astern (docs/08_NEXT.md 13.1)
				mood = "escort"
				var h: Vector2 = director.world.my_boat.heading()
				var side := 1.0 if uid.hash() % 2 == 0 else -1.0
				_go(pp + Vector3(-h.y, 0, h.x) * 6.0 * side - Vector3(h.x, 0, h.y) * 3.0, speed() * 2.0, delta)
			elif id == "sirin":
				_face(pp, delta)
			else:
				_face(pp, delta * 0.3)
		"thief":
			var rack: Vector3 = director.rack_near(home)
			var centre := rack if rack != Vector3.INF else home
			var a := _t * 0.35 + float(uid.hash() % 7)
			_go(centre + Vector3(cos(a), 0, sin(a)) * 11.0, speed() * 0.7, delta)
			if rack != Vector3.INF and _special <= 0.0:
				_special = 40.0
				director.steal(self)
		"territorial":
			_territorial(pp, d, on_foot, delta)
		"night_hunter":
			if director.night >= 0.5 and on_foot and d < float(info["aggro_m"]) * 2.0:
				_hunt(pp, d, 10.0, delta)
			elif d < 15.0 and on_foot:
				_run_from(pp, speed() * 0.6, delta)
			else:
				_wander(10.0, speed() * 0.3, delta)
		"fog":
			_fog(pp, d, on_foot, delta)
		"guardian":
			_guardian(pp, d, delta)
		"friend", "island":
			_friend(pp, d, delta)


func _territorial(pp: Vector3, d: float, on_foot: bool, delta: float) -> void:
	var aggro := float(info["aggro_m"])
	var from_home := _flat_from(home, pp)
	if mood == "sleep":
		# Likho sleeps until you are close — and doesn't see you on its blind (right) side
		if d < 8.0 and on_foot and not _blind_side(pp):
			mood = "chase"
			director.roar(self)
		return
	if not on_foot or from_home > aggro * 2.6:
		mood = "idle"
		_go(home, speed() * 0.5, delta)
		return
	match mood:
		"idle", "wander":
			if d < aggro * 1.5:
				mood = "warn"
				_mood_t = 2.5
				director.roar(self)
			else:
				_wander(6.0, speed() * 0.2, delta)
		"warn":
			_face(pp, delta)
			if _mood_t <= 0.0:
				mood = "chase" if d < aggro else "idle"
		"chase":
			_hunt(pp, d, 0.0, delta)
			if d > aggro * 2.2:
				mood = "idle"


## Go for the player (or the target) and bite; keep off beyond `fear_m` of fire in hand if fear_m > 0.
func _hunt(pp: Vector3, d: float, fear_m: float, delta: float) -> void:
	var light_r: float = director.player_light_radius()
	if fear_m > 0.0 and light_r > 0.0 and d < maxf(fear_m, light_r):
		mood = "keep_off"
		_circle(pp, maxf(fear_m, light_r) + 1.5, delta)
		return
	mood = "chase"
	var reach := radius + 1.3
	if d > reach:
		_go(pp, speed(), delta)
	else:
		_face(pp, delta)
		if _cool <= 0.0:
			_cool = 1.6
			director.bite(self, 1.0)


func _fog(pp: Vector3, d: float, on_foot: bool, delta: float) -> void:
	# a defence: go for the fire; a light in hand keeps them off either way
	if target != Vector3.INF:
		var dt := _flat(target)
		var light_r: float = director.player_light_radius()
		if light_r > 0.0 and d < light_r and on_foot:
			mood = "keep_off"
			_circle(pp, light_r + 1.0, delta)
			return
		if d < 6.0 and on_foot:
			_hunt(pp, d, 0.0, delta)
			return
		if dt > 3.0:
			_go(target, speed(), delta)
		elif _cool <= 0.0:
			_cool = 2.0
			director.douse(self)
		return
	if on_foot and d < float(info["aggro_m"]):
		_hunt(pp, d, 1.0, delta)  # they fear light: fear_m only matters when a light burns
	elif raid != Vector3.INF:
		# probing the homestead: up to the lamps and fences, never past them
		var ward: float = director.ward_at(position)
		if ward > 0.0:
			mood = "keep_off"
			_circle(raid, _flat(raid) + 0.5, delta)
		else:
			mood = "wander"
			_go(raid, speed() * 0.5, delta)
	else:
		_wander(8.0, speed() * 0.3, delta)


## A creature of the deep (the Puchinnik, docs/08_NEXT.md 13.3). Fire in hand or a lantern at the bow keeps it
## off at keep_off_m and makes it let go. Else: it circles the boat and rocks it for circle_s, then grips the
## hull (director.grapple) and strikes everyone aboard every 5 s; three strikes on it, or half its health,
## drive it off to circle again; left unanswered for grapple_s it rolls the boat (director.sink) and leaves.
func _sea(pp: Vector3, d: float, on_foot: bool, delta: float) -> void:
	phase_t += delta
	var boat: Boat = director.boat_of(self)
	if on_foot or boat == null:
		mood = "wander"
		_go(home + Vector3(sin(_t * 0.3), 0, cos(_t * 0.3)) * 25.0, speed() * 0.5, delta)
		return
	var keep_off: float = float(director.db.raw["boats"]["parts"]["lantern"]["keep_off_m"])
	var lit: bool = director.player_light_radius() > 0.0 or boat.has_part("lantern")
	var holding: bool = boat.held and String(director.state.boats[boat.uid]["held"]) == uid
	if lit:
		if holding:
			director.release(self, boat)
			hits = 0
		if mood != "keep_off":
			phase_t = 0.0
		mood = "keep_off"
		_circle(pp, maxf(keep_off, radius + 6.0), delta)
		if phase_t > 60.0:
			director.leave(self)  # it tires of the light
		return
	if holding:
		mood = "chase"
		_face(pp, delta)
		position.x = lerpf(position.x, pp.x + (position.x - pp.x) * 0.9, 1.0 - exp(-delta * 2.0))
		position.z = lerpf(position.z, pp.z + (position.z - pp.z) * 0.9, 1.0 - exp(-delta * 2.0))
		if hit_t < 0.5:
			hit_t = 1.0
			hits += 1
			phase_t = 0.0
		if hits >= 3 or float(director.state.creatures.get(uid, {}).get("hp", 0.0)) < float(info["hp"]) * 0.5:
			director.release(self, boat)
			hits = 0
			mood = "circle"
			phase_t = -20.0  # it keeps its distance a while before it comes again
			return
		if _cool <= 0.0:
			_cool = 5.0
			director.bite_all(self, boat, 0.6)
		if phase_t > float(info.get("grapple_s", 30.0)):
			director.sink(self, boat)
			director.leave(self)
		return
	if mood != "circle" and mood != "chase":
		mood = "circle"
		phase_t = 0.0
	if mood == "circle":
		_circle(pp, 22.0, delta)
		if _special <= 0.0:
			_special = 8.0
			director.rock(self, boat)
		if phase_t > float(info.get("circle_s", 40.0)):
			mood = "chase"
			phase_t = 0.0
		return
	_go(pp, speed(), delta)  # the grip: up to the hull
	if d < radius + 2.5 and phase_t > 1.0:
		director.grapple(self, boat)
		phase_t = 0.0
		hits = 0


func _friend(pp: Vector3, d: float, delta: float) -> void:
	match id:
		"leshy":
			_face(pp, delta * 0.5)
			var wisp := model.get_node_or_null("Wisp") as Node3D
			if wisp != null:
				var guide: Vector3 = director.leshy_goal
				if guide != Vector3.INF and Creatures.leshy_guiding(director.state):
					var local := to_local(guide)
					var dir := local.normalized() if local.length() > 0.1 else Vector3.FORWARD
					var ahead := dir * minf(local.length(), 6.0 + fmod(_t * 3.0, 10.0))
					wisp.position = wisp.position.lerp(ahead + Vector3(0, 1.4, 0), 1.0 - exp(-delta * 1.5))
				else:
					wisp.position = wisp.position.lerp(Vector3(0.8 + sin(_t) * 0.4, 1.6 + sin(_t * 1.7) * 0.3, -1.2), 1.0 - exp(-delta * 2.0))
		"domovoy", "bannik", "vodyanoy":
			_face(pp, delta * 0.6)
		"ryba_kit":
			yaw += delta * 0.01


func _guardian(pp: Vector3, d: float, delta: float) -> void:
	var phase: int = director.fight_phase()
	match id:
		"siverko":
			# circles the tower; gusts push you off; ice needles from afar; phase 2 calls a squall
			var a := _t * (0.25 + 0.1 * phase)
			_go(home + Vector3(cos(a), 0, sin(a)) * 9.0, speed() * 1.5 if speed() > 0.0 else 5.0, delta)
			_face(pp, delta)
			if _special <= 0.0:
				_special = 6.0 / phase
				director.gust(self, 9.0 + 3.0 * phase)
			elif _cool <= 0.0 and d < 14.0:
				_cool = 3.0 / phase
				director.bite(self, 0.6)
		"bolotnitsa":
			_hunt(pp, d, 0.0, delta)
			if d < 5.0:
				director.mire(self)
			if _special <= 0.0:
				_special = 20.0
				director.summon(self, "kikimora", 1 + phase)
		"hozyain_guby":
			_go(home, 2.0, delta)
			_face(pp, delta)
			if _special <= 0.0:
				_special = 8.0 - phase
				director.wave(self)
			elif d < radius + 4.0 and _cool <= 0.0:
				_cool = 2.2
				director.bite(self, 1.0)
		"mga":
			_hunt(pp, d, 0.0, delta)
			if _special <= 0.0:
				_special = 10.0
				if director.player_light_radius() > 0.0 and d < 16.0:
					director.bite(self, 0.3)  # the fog swallows the light
		_:
			_hunt(pp, d, 0.0, delta)


# ---------------------------------------------------------------- movement

func _flat(p: Vector3) -> float:
	return Vector2(p.x - position.x, p.z - position.z).length()


func _flat_from(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Walk (or fly) towards a point; land creatures don't walk into the sea.
func _go(p: Vector3, spd: float, delta: float) -> void:
	var to := Vector2(p.x - position.x, p.z - position.z)
	var d := to.length()
	if d < 0.05:
		return
	var n := to / d
	var step := minf(d, spd * delta)
	var next := position + Vector3(n.x, 0, n.y) * step
	if hover < 0.3 and not id in ["seal", "vodyanoy", "hozyain_guby", "ryba_kit"] and behaviour() != "sea" and director.map.ground_at(next.x, next.z) < 0.25:
		_goal = home
		return
	if behaviour() == "sea" and director.map.ground_at(next.x, next.z) > -3.0:
		return  # the deep never comes into the shallows
	position.x = next.x
	position.z = next.z
	yaw = lerp_angle(yaw, atan2(-n.x, -n.y), 1.0 - exp(-delta * 8.0))


func _face(p: Vector3, delta: float) -> void:
	var n := Vector2(p.x - position.x, p.z - position.z)
	if n.length() > 0.01:
		yaw = lerp_angle(yaw, atan2(-n.x, -n.y), 1.0 - exp(-delta * 5.0))


func _run_from(p: Vector3, spd: float, delta: float) -> void:
	mood = "flee"
	var away := Vector3(position.x - p.x, 0, position.z - p.z).normalized()
	_go(position + away * 5.0, spd, delta)


func _wander(r: float, spd: float, delta: float) -> void:
	mood = "wander"
	if _flat(_goal) < 0.6:
		if _mood_t > 0.0:
			return  # arrived: stand a while (no shivering between goals)
		var a := randf() * TAU
		_goal = home + Vector3(cos(a), 0, sin(a)) * randf() * r
		_mood_t = 2.0 + randf() * 4.0
	elif _mood_t <= 0.0:
		_goal = position  # took too long: give up on this goal and rest
		_mood_t = 2.0 + randf() * 3.0
		return
	_go(_goal, spd, delta)


func _circle(p: Vector3, r: float, delta: float) -> void:
	var a := atan2(position.z - p.z, position.x - p.x) + delta * 0.6
	_go(p + Vector3(cos(a), 0, sin(a)) * r, speed(), delta)
	_face(p, delta)


## Likho's missing eye is on its right: a player to its right isn't seen.
func _blind_side(p: Vector3) -> bool:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var to := Vector2(p.x - position.x, p.z - position.z).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	return to.dot(right) > 0.3


## Where a seal slides off to: the nearest water a few metres away.
func _shore_out() -> Vector3:
	for k in 12:
		var a := k * TAU / 12.0
		var q := position + Vector3(cos(a), 0, sin(a)) * 6.0
		if director.map.ground_at(q.x, q.z) < -0.5:
			return q
	return position
