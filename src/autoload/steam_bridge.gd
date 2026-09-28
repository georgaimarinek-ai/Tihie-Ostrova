class_name SteamBridge
extends RefCounted
## Steam through GodotSteam (roadmap phase 10) when the GodotSteam GDExtension is installed and Steam runs;
## otherwise every call does nothing and the game is the same (achievements are still kept locally).
## Lobbies: the host's lobby carries its address for friends to join (Net stays ENet); cloud saves are
## Steam Auto-Cloud over user://worlds (docs/04_TECH_SPEC.md §13) and need no code.

const APP_ID_SETTING := "steam/app_id"

var steam: Object = null
var ok := false
var lobby_id := 0


func start() -> void:
	if not Engine.has_singleton("Steam"):
		return
	steam = Engine.get_singleton("Steam")
	var app_id := int(ProjectSettings.get_setting(APP_ID_SETTING, 480))
	var res: Variant = steam.call("steamInitEx", false, app_id)
	ok = res is Dictionary and int((res as Dictionary).get("status", 1)) == 0
	if ok and steam.has_signal("lobby_created"):
		steam.connect("lobby_created", _on_lobby_created)


func poll() -> void:
	if ok:
		steam.call("run_callbacks")


func unlock(id: String) -> void:
	if ok:
		steam.call("setAchievement", id)
		steam.call("storeStats")


## A friends-only lobby for the world this host has opened (Net.host): friends see "Join game" in Steam.
func open_lobby() -> void:
	if ok:
		steam.call("createLobby", 1, 4)  # LOBBY_TYPE_FRIENDS_ONLY, Net.MAX_PLAYERS


func close_lobby() -> void:
	if ok and lobby_id != 0:
		steam.call("leaveLobby", lobby_id)
		lobby_id = 0


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		return
	lobby_id = id
	var ips := Net.addresses()
	steam.call("setLobbyData", id, "address", ips[0] if not ips.is_empty() else "")
	steam.call("setLobbyData", id, "port", str(Net.PORT))
	steam.call("setRichPresence", "connect", "+connect %s:%d" % [ips[0] if not ips.is_empty() else "", Net.PORT])
