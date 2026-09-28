class_name Combat
extends Node
## Fighting on foot (docs/01_GDD.md §11, docs/03_BALANCE.md §6; Tale and Saga): LMB strikes — a click is a
## light strike, holding it a heavy one; C blocks (the shield takes more off), Ctrl dodges. Everything costs
## stamina. The strike goes to the host as "attack" on the creature in front; the host decides the damage.
## Hits taken arrive as "hurt" events: a red flash, and a block costs stamina.

const HEAVY_HOLD := 0.45

var world
var db: ContentDB
var state: WorldState
var _charge := -1.0


func setup(p_world) -> void:
	world = p_world
	db = world.db
	state = world.state
	name = "Combat"
	Game.world_event.connect(_on_event)


func can_fight() -> bool:
	return world.on_foot() and not world.ui_open() and not world.cam.in_shot() and not world.player.busy


func _unhandled_input(event: InputEvent) -> void:
	if not can_fight():
		_charge = -1.0
		return
	if event.is_action_pressed("attack"):
		_charge = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released("attack") and _charge >= 0.0:
		strike(_charge >= HEAVY_HOLD)
		_charge = -1.0
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dodge"):
		if world.player.dodge(float(db.balance["combat"]["dodge_stamina"])):
			world.audio.sfx("whoosh")
			world._send_move()


func _process(delta: float) -> void:
	if _charge >= 0.0:
		_charge += delta
	var p: Player = world.player
	var want := can_fight() and Input.is_action_pressed("block") and p.stamina > 1.0
	if want != p.blocking:
		p.blocking = want
		world._send_move()


## The weapon a strike uses now: the best in the bag (WorldCommands.best_weapon), "" = bare hands.
func weapon() -> String:
	return Game.commands.best_weapon(state.inv(Net.local_player_id())) if Game.commands != null else ""


func strike(heavy: bool) -> void:
	var cb: Dictionary = db.balance["combat"]
	var w := weapon()
	var cost := 5.0
	var reach := float(cb["reach_bare"])
	if w != "":
		var wd: Dictionary = db.items[w]["weapon"]
		cost = float(wd["stamina"])
		reach = float(wd.get("reach", 30.0))
	if heavy:
		cost *= float(cb["heavy_stamina_k"])
	var p: Player = world.player
	if p.stamina < cost:
		world.hud.toast(tr("toast.no_stamina"))
		return
	p.stamina -= cost
	p.swing(heavy)
	world.audio.sfx("whoosh")
	var yaw := p.model.rotation.y
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var target: CreatureView = world.creatures.target_for(p.global_position, fwd, reach)
	if target == null:
		return
	Game.submit({"type": "creatures", "pos": {target.uid: WorldState._v3(target.position)}})
	world._send_move()
	var res := Game.submit({"type": "attack", "target": target.uid, "heavy": heavy, "weapon": w})
	if res.get("ok", false):
		world.audio.sfx("hit")


func _on_event(e: Dictionary) -> void:
	var mine := String(e.get("player", "")) == Net.local_player_id()
	match String(e.get("type", "")):
		"hurt":
			if not mine:
				return
			if String(e.get("stance", "")) == "block":
				world.player.stamina = maxf(0.0, world.player.stamina - float(db.balance["combat"]["block_stamina"]))
			if float(e["amount"]) > 0.0:
				world.hud.hurt()
				world.audio.sfx("hurt")
				world.cam.shake(0.25)
