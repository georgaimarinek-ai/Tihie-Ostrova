class_name Synth
extends RefCounted
## Offline synthesis of the placeholder sounds (runs once on a worker thread): the sketch's Web Audio
## voices rendered into sample buffers. Karplus–Strong gusli, sawtooth pads through a one-pole low-pass,
## additive bells, a formant "choir", a reed for the zhaleyka, a bowed gudok, filtered noise for wind,
## waves and fire.


static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Brown-ish noise that loops without a click (the tail is cross-faded into the head).
static func noise_loop(rng: RandomNumberGenerator, seconds: float, rate: int, keep: float, add: float) -> PackedFloat32Array:
	var n := int(seconds * rate)
	var fade := mini(int(0.5 * rate), n / 2)  # the cross-fade never reaches past the loop
	var out := PackedFloat32Array()
	out.resize(n + fade)
	var b := 0.0
	for i in n + fade:
		b = keep * b + add * (rng.randf() * 2.0 - 1.0)
		out[i] = b * 0.6
	for i in fade:
		var k := float(i) / fade
		out[i] = out[i] * k + out[n + i] * (1.0 - k)
	out.resize(n)
	return _normalise(out, 0.5)


static func crackle_loop(rng: RandomNumberGenerator, seconds: float, rate: int) -> PackedFloat32Array:
	var out := noise_loop(rng, seconds, rate, 0.6, 0.4)
	var n := out.size()
	for i in n:
		if rng.randf() < 0.0015:
			for k in 60:  # a crackle near the end wraps around, so the loop seam stays clean
				out[(i + k) % n] += (rng.randf() * 2.0 - 1.0) * (1.0 - k / 60.0) * 0.9
	return _normalise(out, 0.6)


## The bourdon: D2 and A2 sawtooth voices, slightly detuned, low-passed. Frequencies are chosen so a
## 20 s loop holds whole cycles (no click at the seam).
static func drone(seconds: float, rate: int) -> PackedFloat32Array:
	var n := int(seconds * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var freqs := [73.15, 73.65, 110.0]
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 380.0 / rate)
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		for f: float in freqs:
			s += fposmod(t * f, 1.0) * 2.0 - 1.0
		lp += a * (s / 3.0 - lp)
		out[i] = lp
	return _normalise(out, 0.7)


## Karplus–Strong plucked string (gusli).
static func pluck(rng: RandomNumberGenerator, midi: int, seconds: float, rate: int) -> PackedFloat32Array:
	var n := int(seconds * rate)
	var period := maxi(2, roundi(rate / hz(midi) - 0.5))
	var ring := PackedFloat32Array()
	ring.resize(period)
	for i in period:
		ring[i] = rng.randf() * 2.0 - 1.0
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var j := i % period
		var v := ring[j]
		out[i] = v
		ring[j] = 0.4985 * (v + ring[(j + 1) % period])
	return _normalise(out, 0.8)


static func bell(midi: int, seconds: float, rate: int) -> PackedFloat32Array:
	var n := int(seconds * rate)
	var f0 := hz(midi)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[1.0, 1.0, 3.2], [2.76, 0.45, 1.6], [5.4, 0.25, 0.8]]
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		for p: Array in partials:
			s += sin(TAU * f0 * float(p[0]) * t) * float(p[1]) * exp(-t * 4.6 / float(p[2]))
		out[i] = s * minf(1.0, t / 0.008)
	return _normalise(out, 0.7)


## A warm pad chord: two detuned saws per note through a low-pass, slow swell and release.
static func pad(midis: Array, seconds: float, rate: int) -> PackedFloat32Array:
	var n := int(seconds * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 900.0 / rate)
	var freqs: Array[float] = []
	for m: int in midis:
		freqs.append(hz(m))
		freqs.append(hz(m) * pow(2.0, 9.0 / 1200.0))
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		for f in freqs:
			s += fposmod(t * f, 1.0) * 2.0 - 1.0
		lp += a * (s / freqs.size() - lp)
		var env := minf(t / (seconds * 0.35), 1.0) * minf(1.0, (seconds - t) / (seconds * 0.4))
		out[i] = lp * env
	return _normalise(out, 0.6)


## The zhaleyka: a reedy tone (odd harmonics) with vibrato, one note after another.
static func reed(melody: Array, note_s: float, rate: int) -> PackedFloat32Array:
	var n := int(melody.size() * note_s * rate + rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var k := mini(int(t / note_s), melody.size() - 1)
		var local := t - k * note_s
		var f := hz(float(melody[k])) * (1.0 + 0.006 * sin(TAU * 5.2 * t))
		phase += f / rate
		var s := sin(TAU * phase) + 0.33 * sin(TAU * phase * 3.0) + 0.2 * sin(TAU * phase * 5.0)
		var env := minf(1.0, local / 0.08) * (0.85 + 0.15 * cos(local / note_s * PI))
		var tail := 1.0 if t < melody.size() * note_s else maxf(0.0, 1.0 - (t - melody.size() * note_s))
		out[i] = s * env * tail
	return _normalise(out, 0.5)


## The gudok: a low bowed string, slow attack, rough.
static func gudok(melody: Array, note_s: float, rate: int) -> PackedFloat32Array:
	var n := int(melody.size() * note_s * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 700.0 / rate)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var k := mini(int(t / note_s), melody.size() - 1)
		var local := t - k * note_s
		phase += hz(float(melody[k])) * (1.0 + 0.004 * sin(TAU * 4.0 * t)) / rate
		var s := fposmod(phase, 1.0) * 2.0 - 1.0
		lp += a * (s - lp)
		out[i] = lp * minf(1.0, local / 0.6) * minf(1.0, (note_s - local) / 0.5)
	return _normalise(out, 0.55)


## A far wordless choir: saw voices with vibrato through two formant band-passes.
static func choir(midis: Array, seconds: float, rate: int) -> PackedFloat32Array:
	var n := int(seconds * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var f1 := _bandpass(700.0, 6.0, rate)
	var f2 := _bandpass(1150.0, 8.0, rate)
	var s1 := [0.0, 0.0, 0.0, 0.0]
	var s2 := [0.0, 0.0, 0.0, 0.0]
	var phases: Array[float] = []
	phases.resize(midis.size())
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		for v in midis.size():
			phases[v] += hz(float(midis[v])) * pow(2.0, 3.0 * sin(TAU * 5.0 * t + v) / 1200.0) / rate
			s += fposmod(phases[v], 1.0) * 2.0 - 1.0
		var y := _biquad(f1, s1, s) + _biquad(f2, s2, s)
		out[i] = y * minf(t / (seconds * 0.4), 1.0) * minf(1.0, (seconds - t) / (seconds * 0.6))
	return _normalise(out, 0.5)


static func effect(kind: String, rng: RandomNumberGenerator, rate: int) -> PackedFloat32Array:
	var dur := {"thud": 0.4, "whoosh": 0.9, "step": 0.1, "chop": 0.25, "gull": 0.6, "creak": 0.7}[kind] as float
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var k := t / dur
		var w := rng.randf() * 2.0 - 1.0
		var v := 0.0
		match kind:
			"thud":
				lp += 0.08 * (w - lp)
				v = lp * exp(-t * 12.0) * 3.0 + sin(TAU * 80.0 * t) * exp(-t * 18.0)
			"whoosh":
				lp += (0.05 + 0.4 * k) * (w - lp)
				v = lp * sin(k * PI)
			"step":
				lp += 0.35 * (w - lp)
				v = lp * exp(-t * 60.0)
			"chop":
				lp += 0.5 * (w - lp)
				v = lp * exp(-t * 35.0) + sin(TAU * 180.0 * t) * exp(-t * 30.0) * 0.6
			"gull":
				var f := 1500.0 * pow(0.6, minf(k / 0.6, 1.0)) if k < 0.6 else 900.0 + (k - 0.6) / 0.4 * 400.0
				phase += f / rate
				v = (absf(fposmod(phase, 1.0) * 2.0 - 1.0) * 2.0 - 1.0) * minf(1.0, t / 0.05) * exp(-t * 5.0)
			"creak":
				var f := 95.0 + 25.0 * sin(TAU * 3.0 * t) + 10.0 * w
				phase += f / rate
				v = (fposmod(phase, 1.0) * 2.0 - 1.0) * (0.5 + 0.5 * sin(TAU * 11.0 * t)) * sin(k * PI)
		out[i] = v
	return _normalise(out, 0.7)


static func _bandpass(freq: float, q: float, rate: int) -> Array:
	var w0 := TAU * freq / rate
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	return [alpha / a0, 0.0, -alpha / a0, -2.0 * cos(w0) / a0, (1.0 - alpha) / a0]


static func _biquad(c: Array, s: Array, x: float) -> float:
	var y: float = c[0] * x + c[1] * s[0] + c[2] * s[1] - c[3] * s[2] - c[4] * s[3]
	s[1] = s[0]
	s[0] = x
	s[3] = s[2]
	s[2] = y
	return y


static func _normalise(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in buf:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in buf.size():
		buf[i] *= k
	return buf
