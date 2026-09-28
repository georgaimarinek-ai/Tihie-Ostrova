class_name AudioDirector
extends Node
## Procedural stand-in for the recorded stems (docs/04_TECH_SPEC.md §9, docs/05_ART_AUDIO.md §7), ported
## from the sketch's AU object: wind, waves, boat creak, fire, and music in layers that grow with every
## lit beacon (D dorian, 72 bpm): drone and sparse gusli always; warm chords Dm–F–C–G after the first beacon;
## gusli more often after the third; a zhaleyka melody from the fourth; low gudok and bells from the
## seventh and eighth; frost bells and a far choir at the end. Dense fog hushes the music, leaving wind and
## far bells; it comes back by the fire. Samples are synthesised once on a worker thread, then scheduled.
## Replace with AudioStreamSynchronized stems when the music is recorded.

const RATE := 22050
const LOW_RATE := 11025
const SCALE: Array[int] = [62, 64, 65, 67, 69, 72, 74, 76]  # D dorian from D4
const CHORDS: Array = [[50, 57, 62, 65], [53, 57, 60, 65], [48, 55, 60, 64], [55, 59, 62, 67]]  # Dm F C G
## The music layers above the base plucks (docs/01_GDD.md §12, Progress.music_layers): stems of one length
## played together in an AudioStreamSynchronized, each faded in by the lit beacons (roadmap phase 10).
const STEMS: Array[String] = ["chords", "gusli", "zhaleyka", "gudok", "bells", "frost", "choir"]
const STEM_S := 32.0  # four chords of 8 s

## Inputs set by World every frame.
var lit := 0
var fog := 1.0  # FogField.factor at the listener (1 = full fog, 0.22 = clearing)
var on_foot := false
var boat_speed := 0.0
var boat_roll := 0.0
var fire_near := 0.0
var night := 0.0
var enabled := true
var volume := 0.85

var _samples: Dictionary = {}
var _mutex := Mutex.new()
var _task := -1
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}
var _queue: Array = []
var _t := 0.0
var _next: Dictionary = {}
var _chord_i := 0
var _wind_fx: AudioEffectBandPassFilter
var _waves_fx: AudioEffectLowPassFilter
var _headless := false
var _music: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _stem_db: Array[float] = []


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless" or AudioServer.get_output_device_list().is_empty()
	_setup_buses()
	for i in 28:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_pool.append(p)
	for n: String in ["wind", "waves", "fire", "drone"]:
		var p := AudioStreamPlayer.new()
		p.bus = {"wind": "Wind", "waves": "Waves", "fire": "Ambience", "drone": "Music"}[n]
		p.volume_db = -80.0
		add_child(p)
		_loops[n] = p
	_next = {"phrase": 2.0, "chord": 4.0, "bell": 3.0, "choir": 5.0, "gull": 6.0, "reed": 8.0, "gudok": 6.0, "frost": 4.0, "creak": 1.0}
	if not _headless:
		_task = WorkerThreadPool.add_task(_synthesise)


## The stems, all STEM_S long and looping (mono, LOW_RATE): chords Dm–F–C–G, gusli phrases, the zhaleyka's
## tunes, the gudok, bells from the capes, frost bells, a far choir. Seeded: the same music every time.
static func build_stems(seconds: float = STEM_S, rate: int = LOW_RATE) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	var n := int(seconds * rate)
	var out := {}
	var bar := seconds / 4.0
	for layer: String in STEMS:
		var buf := PackedFloat32Array()
		buf.resize(n)
		match layer:
			"chords":
				for i in 4:
					_mix(buf, Synth.pad(CHORDS[i], bar + 1.0, rate), i * bar, 0.8, rate)
			"gusli":
				var cache := {}
				var t := 0.5
				while t < seconds - 0.5:
					var idx := rng.randi() % SCALE.size()
					for k in 4:
						idx = clampi(idx + rng.randi() % 3 - 1, 0, SCALE.size() - 1)
						var m: int = SCALE[idx]
						if not cache.has(m):
							cache[m] = Synth.pluck(rng, m, 2.0, rate)
						_mix(buf, cache[m], t + k * 0.42, 0.5, rate)
					t += 4.0
			"zhaleyka":
				_mix(buf, Synth.reed([62, 64, 65, 69, 67, 65, 64, 62], 0.9, rate), bar * 0.25, 0.7, rate)
				_mix(buf, Synth.reed([69, 67, 65, 64, 65, 62], 0.9, rate), bar * 2.25, 0.7, rate)
			"gudok":
				_mix(buf, Synth.gudok([38, 45, 43, 38], bar / 4.0 * 2.0, rate), 0.0, 0.8, rate)
				_mix(buf, Synth.gudok([41, 45, 43, 43], bar / 4.0 * 2.0, rate), bar * 2.0, 0.8, rate)
			"bells", "frost":
				var arp: Array = [74, 77, 81, 84, 86] if layer == "bells" else [93, 96, 98]
				var cache := {}
				var t := 1.0
				while t < seconds - 1.0:
					for k in (4 if layer == "bells" else 3):
						var m: int = arp[rng.randi() % arp.size()]
						if not cache.has(m):
							cache[m] = Synth.bell(m, 3.0, rate)
						_mix(buf, cache[m], t + k * (0.42 if layer == "bells" else 0.21), 0.35, rate)
					t += 6.0 if layer == "bells" else 9.0
			"choir":
				_mix(buf, Synth.choir([50, 57, 62], bar * 2.0, rate), 0.0, 0.8, rate)
				_mix(buf, Synth.choir([48, 55, 60], bar * 2.0, rate), bar * 2.0, 0.8, rate)
		out[layer] = to_wav(Synth._normalise(buf, 0.6), rate, true)
	return out


## Adds `src` into the loop `buf` at `at` seconds, wrapping round the end so the loop is seamless.
static func _mix(buf: PackedFloat32Array, src: PackedFloat32Array, at: float, gain: float, rate: int = LOW_RATE) -> void:
	var n := buf.size()
	var start := int(at * rate)
	for i in src.size():
		var j := (start + i) % n
		buf[j] += src[i] * gain


## Which stems play now: the layers the lit beacons have opened; bells ring from the capes in thick fog early.
static func stem_on(layer: String, lit_count: int, fog_factor: float) -> bool:
	if Progress.music_layers(lit_count).has(layer):
		return true
	return layer == "bells" and lit_count >= 2 and fog_factor > 0.8


func _start_stems() -> void:
	if _sync != null or not _has("stem_chords"):
		return
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = STEMS.size()
	for i in STEMS.size():
		_sync.set_sync_stream(i, _sample("stem_" + STEMS[i]))
		_sync.set_sync_stream_volume(i, -60.0)
		_stem_db.append(-60.0)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.stream = _sync
	_music.volume_db = -10.0
	add_child(_music)
	_music.play()


func _mix_stems(delta: float) -> void:
	if _sync == null:
		return
	for i in STEMS.size():
		var want := -4.0 if stem_on(STEMS[i], lit, fog) else -60.0
		_stem_db[i] = move_toward(_stem_db[i], want, delta * 12.0)  # a layer comes in over ~5 s
		_sync.set_sync_stream_volume(i, _stem_db[i])


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _setup_buses() -> void:
	for spec: Array in [["Music", "Master"], ["Ambience", "Master"], ["Wind", "Ambience"], ["Waves", "Ambience"], ["Sfx", "Master"]]:
		if AudioServer.get_bus_index(spec[0]) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, spec[0])
		AudioServer.set_bus_send(idx, spec[1])
		if spec[0] == "Music" or spec[0] == "Sfx":
			var rv := AudioEffectReverb.new()
			rv.room_size = 0.85 if spec[0] == "Music" else 0.5
			rv.damping = 0.4
			rv.wet = 0.38 if spec[0] == "Music" else 0.18
			rv.dry = 0.85
			AudioServer.add_bus_effect(idx, rv)
		elif spec[0] == "Wind":
			_wind_fx = AudioEffectBandPassFilter.new()
			_wind_fx.cutoff_hz = 600.0
			_wind_fx.resonance = 0.6
			AudioServer.add_bus_effect(idx, _wind_fx)
		elif spec[0] == "Waves":
			_waves_fx = AudioEffectLowPassFilter.new()
			_waves_fx.cutoff_hz = 420.0
			AudioServer.add_bus_effect(idx, _waves_fx)
	if _wind_fx == null:
		_wind_fx = AudioServer.get_bus_effect(AudioServer.get_bus_index("Wind"), 0)
	if _waves_fx == null:
		_waves_fx = AudioServer.get_bus_effect(AudioServer.get_bus_index("Waves"), 0)


# ---------------------------------------------------------------- mixing

func _process(delta: float) -> void:
	if _headless:
		return
	_t += delta
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume if enabled else 0.0, 0.0001)))
	_start_loops()
	var t := _t
	var sp := clampf(absf(boat_speed) / 9.0, 0.0, 1.0) if not on_foot else 0.0
	if _wind_fx != null:
		_wind_fx.cutoff_hz = 420.0 + 380.0 * (0.5 + 0.5 * sin(t * 0.13)) + sp * 300.0
	var dense := smoothstep(0.55, 1.0, fog)
	_loop_gain("wind", (0.12 + 0.12 * (0.5 + 0.5 * sin(t * 0.07))) * (0.7 if on_foot else 1.0) * (0.7 + 0.5 * dense) * (1.0 - 0.4 * night) * 2.4)
	_loop_gain("waves", (0.22 + 0.18 * (0.5 + 0.5 * sin(t * 0.6)) + sp * 0.15) * (0.55 if on_foot else 1.0) * 2.2)
	_loop_gain("fire", fire_near * (0.05 + 0.06 * randf()) * 6.0)
	_loop_gain("drone", 0.05 * 5.0 * (0.8 if lit >= 10 else 1.0))
	# music hushes in thick fog and returns in clearings and by the fire
	var music := lerpf(1.0, 0.3, dense * (1.0 - fire_near))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music, 0.0001)))
	_start_stems()
	_mix_stems(delta)
	_schedule(t)
	_flush(t)


func _loop_gain(n: String, g: float) -> void:
	var p: AudioStreamPlayer = _loops[n]
	if p.playing:
		p.volume_db = lerpf(p.volume_db, linear_to_db(maxf(g, 0.0001)), 0.08)


func _start_loops() -> void:
	for n: String in _loops:
		var p: AudioStreamPlayer = _loops[n]
		if not p.playing and _has(n):
			p.stream = _sample(n)
			p.volume_db = -60.0
			p.play()


## The sketch's tick(): phrases, chords, bells and choir by layer.
func _schedule(t: float) -> void:
	if t > _next["phrase"] and _has("pluck62"):
		var n := 3 + randi() % 4
		var i := randi() % 4
		for k in n:
			i = clampi(i + randi() % 3 - 1, 0, SCALE.size() - 1)
			play("pluck%d" % (SCALE[i] - (12 if lit == 0 else 0)), t + k * (0.35 + randf() * 0.2), -16.0)
		var gap: float = [7.0, 5.0, 4.0][0 if lit == 0 else (1 if lit < 3 else 2)]
		_next["phrase"] = t + gap + randf() * (8.0 if lit == 0 else 4.0)
	# chords, gusli, zhaleyka, gudok, bells, frost and choir are stems (_mix_stems)
	if t > _next["gull"] and _has("gull") and night < 0.5:
		play("gull", t, -22.0, "Ambience")
		if randf() < 0.5:
			play("gull", t + 0.7, -24.0, "Ambience", 1.1)
		_next["gull"] = t + 9.0 + randf() * 14.0
	if not on_foot and t > _next["creak"] and _has("creak") and absf(boat_roll) > 0.05:
		play("creak", t, -24.0 + absf(boat_roll) * 30.0, "Ambience", 0.8 + randf() * 0.4)
		_next["creak"] = t + 2.5 + randf() * 4.0


## Queue a sample at time `at` (seconds on this node's clock).
func play(sample: String, at: float = -1.0, db: float = -12.0, bus: String = "Music", pitch: float = 1.0) -> void:
	if _headless or not _has(sample):
		return
	_queue.append({"t": at if at >= 0.0 else _t, "s": sample, "db": db, "bus": bus, "pitch": pitch})


func _flush(t: float) -> void:
	var keep: Array = []
	for e: Dictionary in _queue:
		if float(e["t"]) > t:
			keep.append(e)
			continue
		for p in _pool:
			if not p.playing:
				p.stream = _sample(e["s"])
				p.volume_db = float(e["db"])
				p.bus = e["bus"]
				p.pitch_scale = float(e["pitch"])
				p.play()
				break
	_queue = keep


## One-shot sounds of actions, in tune with the mode (docs/05_ART_AUDIO.md §7.2).
func sfx(kind: String, arg: int = 0) -> void:
	var t := _t + 0.02
	match kind:
		"pickup":
			var notes := [74, 77, 81]
			play("pluck%d" % notes[arg % 3], t, -14.0, "Sfx")
			play("pluck%d" % (int(notes[arg % 3]) + 7), t + 0.09, -18.0, "Sfx")
		"land", "board":
			play("thud", t, -12.0, "Sfx")
			play("pluck55", t + 0.05, -18.0, "Sfx")
		"torch":
			play("whoosh", t, -10.0, "Sfx")
			play("pluck50", t + 0.1, -14.0, "Sfx")
			play("pluck62", t + 0.25, -17.0, "Sfx")
		"lantern":
			play("bell%d" % [69, 72, 74][clampi(arg, 0, 2)], t, -14.0, "Sfx")
			play("pluck%d" % [57, 60, 62][clampi(arg, 0, 2)], t, -14.0, "Sfx")
		"step":
			play("step", t, -26.0 + randf() * 3.0, "Sfx", 0.85 + randf() * 0.3)
		"chop":
			play("chop", t, -12.0, "Sfx", 0.9 + randf() * 0.2)
		"craft":
			play("pluck69", t, -15.0, "Sfx")
			play("pluck74", t + 0.12, -17.0, "Sfx")
		"bell":
			play("bell%d" % arg, t, -10.0, "Sfx")
		"swell":
			# the beacon moment: two warm chords and rising plucks D–F–A–C–D–F
			play("pad0", t, -12.0)
			play("pad1", t + 3.2, -12.0)
			var up := [62, 65, 69, 72, 74, 77]
			for i in up.size():
				play("pluck%d" % up[i], t + 0.3 + i * 0.28, -12.0)
		"deny":
			play("pluck50", t, -18.0, "Sfx", 0.9)
		"thud":
			play("thud", t, -10.0, "Sfx", 0.8 + randf() * 0.2)
		"growl":
			# a beast's warning: two low thuds and a low dissonant pluck
			play("thud", t, -8.0, "Sfx", 0.55)
			play("thud", t + 0.25, -10.0, "Sfx", 0.5)
			play("pluck38", t + 0.1, -14.0, "Sfx", 0.9)
		"hit":
			play("chop", t, -9.0, "Sfx", 1.2 + randf() * 0.2)
		"hurt":
			play("thud", t, -8.0, "Sfx", 1.1)
			play("pluck41", t + 0.05, -16.0, "Sfx")
		"whoosh":
			play("whoosh", t, -9.0, "Sfx", 0.8 + randf() * 0.3)
		"sirin":
			# Sirin's motif: a high falling phrase A–G–F–D
			for i in 4:
				play("bell%d" % [81, 79, 77, 74][i], t + i * 0.55, -16.0)


func _has(n: String) -> bool:
	_mutex.lock()
	var ok := _samples.has(n)
	_mutex.unlock()
	return ok


func _sample(n: String) -> AudioStreamWAV:
	_mutex.lock()
	var s: AudioStreamWAV = _samples.get(n)
	_mutex.unlock()
	return s


func _store(n: String, s: AudioStreamWAV) -> void:
	_mutex.lock()
	_samples[n] = s
	_mutex.unlock()


# ---------------------------------------------------------------- synthesis (worker thread)

func _synthesise() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	_store("wind", to_wav(Synth.noise_loop(rng, 4.0, RATE, 0.985, 0.15), RATE, true))
	_store("waves", to_wav(Synth.noise_loop(rng, 5.0, RATE, 0.992, 0.08), RATE, true))
	_store("fire", to_wav(Synth.crackle_loop(rng, 3.0, RATE), RATE, true))
	_store("drone", to_wav(Synth.drone(20.0, LOW_RATE), LOW_RATE, true))
	for n: String in ["thud", "whoosh", "step", "chop", "gull", "creak"]:
		_store(n, to_wav(Synth.effect(n, rng, RATE), RATE, false))
	var plucks := {}
	for m in SCALE:
		plucks[m] = true
		plucks[m - 12] = true
	for m in [38, 41, 50, 55, 57, 60, 62, 77, 79, 81, 84, 86, 88]:
		plucks[m] = true
	for m: int in plucks:
		_store("pluck%d" % m, to_wav(Synth.pluck(rng, m, 2.4, RATE), RATE, false))
	for m in [69, 72, 74, 76, 77, 79, 81, 84, 86, 93, 96, 98]:
		_store("bell%d" % m, to_wav(Synth.bell(m, 3.4, RATE), RATE, false))
	for i in CHORDS.size():
		_store("pad%d" % i, to_wav(Synth.pad(CHORDS[i], 9.0, LOW_RATE), LOW_RATE, false))
	var melodies := [[62, 64, 65, 69, 67, 65, 64, 62], [69, 67, 65, 64, 65, 62], [65, 67, 69, 72, 69, 67, 65]]
	for i in melodies.size():
		_store("reed%d" % i, to_wav(Synth.reed(melodies[i], 0.9, LOW_RATE), LOW_RATE, false))
	_store("gudok", to_wav(Synth.gudok([38, 45, 43, 38], 3.0, LOW_RATE), LOW_RATE, false))
	_store("choir", to_wav(Synth.choir([50, 57, 62], 11.0, LOW_RATE), LOW_RATE, false))
	var stems := build_stems()
	for layer: String in stems:
		_store("stem_" + layer, stems[layer])


static func to_wav(data: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w
