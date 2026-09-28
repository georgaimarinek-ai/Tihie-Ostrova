class_name GameSettings
extends RefCounted
## Player settings (roadmap phase 8), user://settings.cfg: graphics (light = the Compatibility renderer, high =
## Forward+ with volumetric fog), window, sound buses, key bindings, language. apply() puts them into effect;
## the renderer only changes on the next start (override.cfg), so the UI asks for a restart.

const PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "Ambience", "Sfx"]
## Actions a player can rebind (Game.INPUT_ACTIONS keys; the mouse strike stays on LMB).
const REBINDABLE := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "interact", "cycle",
	"inventory", "build_menu", "rotate", "map", "journal", "block", "dodge"]

var quality := "high"  # "high" | "low"
var fullscreen := false
var volume := {"Master": 1.0, "Music": 0.8, "Ambience": 0.9, "Sfx": 1.0}
var keys: Dictionary = {}  # action -> physical keycode (only the rebound ones)
var language := ""  # "" = the system's (ru or en)
var path := PATH


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	quality = String(cf.get_value("graphics", "quality", quality))
	fullscreen = bool(cf.get_value("graphics", "fullscreen", fullscreen))
	for b: String in BUSES:
		volume[b] = clampf(float(cf.get_value("audio", b, volume[b])), 0.0, 1.0)
	keys = {}
	for a: String in REBINDABLE:
		if cf.has_section_key("keys", a):
			keys[a] = int(cf.get_value("keys", a))
	language = String(cf.get_value("general", "language", language))


func save_file() -> Error:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "quality", quality)
	cf.set_value("graphics", "fullscreen", fullscreen)
	for b: String in BUSES:
		cf.set_value("audio", b, volume[b])
	for a: String in keys:
		cf.set_value("keys", a, keys[a])
	cf.set_value("general", "language", language)
	return cf.save(path)


## The renderer this quality wants.
func rendering_method() -> String:
	return "forward_plus" if quality == "high" else "gl_compatibility"


## True when the running renderer isn't the chosen one (a restart applies it).
func needs_restart() -> bool:
	return RenderingServer.get_current_rendering_method() != rendering_method() and DisplayServer.get_name() != "headless"


## Settings that apply at once: sound, keys, language, window. The renderer goes to override.cfg for next time.
func apply() -> void:
	for b: String in BUSES:
		var idx := AudioServer.get_bus_index(b)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(volume[b]), 0.0001)))
			AudioServer.set_bus_mute(idx, float(volume[b]) <= 0.001)
	for a: String in keys:
		bind(a, int(keys[a]))
	if language != "":
		TranslationServer.set_locale(language)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


## Puts the chosen renderer into override.cfg (next to the executable when exported, the project when run from
## the editor): Godot reads it at start-up.
func write_renderer_override() -> Error:
	var dir := OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("res://")
	var cf := ConfigFile.new()
	var file := dir.path_join("override.cfg")
	cf.load(file)
	cf.set_value("rendering", "renderer/rendering_method", rendering_method())
	return cf.save(file)


## One key for an action (replacing its keys; mouse and gamepad events stay).
static func bind(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var k := InputEventKey.new()
	k.physical_keycode = keycode as Key
	InputMap.action_add_event(action, k)


## The key shown for an action ("W", "Space"…).
static func key_name(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	return "—"
