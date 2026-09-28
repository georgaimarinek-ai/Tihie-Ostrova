class_name CarryTrial
extends Trial
## "Carry the fire to the top" (b01): make a torch, carry the flame up the path to the tower. The host sees
## the fire in hand and the player at the tower, so arriving there with a light completes the trial.


func goal() -> String:
	return tr("goal.climb") if has_light() else tr("goal.need_fire")


func tick(_delta: float) -> void:
	if finished or not has_light():
		return
	var p := player_pos()
	var t := tower_base()
	if Vector2(p.x - t.x, p.z - t.z).length() < 7.0:
		complete()
