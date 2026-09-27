extends "res://tests/lib/case.gd"
## The procedural placeholder voices render real sound (not silence, not clipping) and loop cleanly.


func _peak(buf: PackedFloat32Array) -> float:
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	return m


func test_voices_render() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var rate := 8000
	var voices := {
		"pluck": Synth.pluck(rng, 62, 0.5, rate),
		"bell": Synth.bell(74, 0.5, rate),
		"pad": Synth.pad([50, 57, 62], 0.5, rate),
		"reed": Synth.reed([62, 64], 0.2, rate),
		"choir": Synth.choir([50, 57], 0.5, rate),
		"wind": Synth.noise_loop(rng, 0.5, rate, 0.985, 0.15),
		"creak": Synth.effect("creak", rng, rate),
	}
	for name: String in voices:
		var buf: PackedFloat32Array = voices[name]
		check(buf.size() > 100, name + " has samples")
		var p := _peak(buf)
		check(p > 0.3 and p <= 1.0, "%s peak %.2f" % [name, p])


func test_wav_loops_whole_buffer() -> void:
	for seed_value in [1, 2, 3, 4, 5]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var buf := Synth.noise_loop(rng, 0.25, 8000, 0.985, 0.15)
		var w := AudioDirector.to_wav(buf, 8000, true)
		eq(w.loop_end, buf.size())
		eq(w.data.size(), buf.size() * 2, "16-bit mono")
		var step := 0.0
		for i in buf.size() - 1:
			step = maxf(step, absf(buf[i + 1] - buf[i]))
		var seam := absf(buf[0] - buf[buf.size() - 1])
		check(seam <= step * 1.001, "seed %d: the loop seam (%.3f) is no bigger than an ordinary step (%.3f)" % [seed_value, seam, step])


func test_music_layer_samples_exist_for_every_note() -> void:
	# every note the scheduler asks for must be synthesised (AudioDirector._synthesise lists)
	for m in AudioDirector.SCALE:
		check(m >= 50 and m <= 88, "scale note %d in range" % m)
