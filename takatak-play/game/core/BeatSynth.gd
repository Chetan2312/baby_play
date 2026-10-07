extends RefCounted
## Original, synthesized music sounds (no files, no licences): kick, hi-hat, clap and
## plucked bass notes, for rhythm games. Use with: const BeatSynth = preload("res://core/BeatSynth.gd")

const RATE := 22050


static func _wav(samples: PackedFloat32Array, vol: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * vol, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## Kick: a sine sweeping 130 → 45 Hz with a fast decay.
static func kick(vol := 0.9) -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 45.0 + 85.0 * exp(-t * 28.0)
		phase += TAU * f / RATE
		out[i] = sin(phase) * exp(-t * 14.0)
	return _wav(out, vol)


## Hi-hat: a short burst of bright noise.
static func hat(vol := 0.25) -> AudioStreamWAV:
	var n := int(RATE * 0.05)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		out[i] = (x - prev) * exp(-t * 70.0)   # first difference ≈ high-pass
		prev = x
	return _wav(out, vol)


## Clap: noise with a few quick re-hits.
static func clap(vol := 0.45) -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var t := float(i) / RATE
		var env := exp(-fmod(t, 0.012) * 300.0) if t < 0.036 else exp(-(t - 0.036) * 22.0)
		out[i] = rng.randf_range(-1.0, 1.0) * env
	return _wav(out, vol)


## Plucked bass note (Hz): a triangle-ish tone with a soft decay.
static func pluck(freq: float, vol := 0.5, dur := 0.3) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var x := fmod(t * freq, 1.0)
		var tri := 4.0 * absf(x - 0.5) - 1.0
		out[i] = (tri * 0.7 + 0.3 * sin(TAU * freq * 2.0 * t)) * minf(1.0, t / 0.005) * exp(-t * 6.0)
	return _wav(out, vol)
