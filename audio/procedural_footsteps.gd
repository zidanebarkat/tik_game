extends RefCounted
## ProceduralFootsteps: generates short, distinct footstep sounds as
## AudioStreamWAVs at runtime. No audio asset files exist in the project; a
## real sound bank can replace this later without touching the call sites.
## stone = crisp thump, dirt = soft mid thump, grass = low muffled rustle.

class_name ProceduralFootsteps

const SAMPLE_RATE := 22050
const DURATION := 0.11

static func make_wav(kind: String) -> AudioStreamWAV:
	var p := _params(kind)
	var frames := int(SAMPLE_RATE * DURATION)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var phase := 0.0
	var nphase := 0.0
	var nphase2 := 0.0
	for i in frames:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-p.decay * t)
		var freq: float = p.f_low + (p.f_high - p.f_low) * exp(-t * 30.0)
		phase += TAU * freq / SAMPLE_RATE
		nphase += TAU * 950.0 / SAMPLE_RATE
		nphase2 += TAU * 1570.0 / SAMPLE_RATE
		var tone := sin(phase) * 0.8 + sin(phase * 0.5 + 0.7) * 0.2
		var noise := (sin(nphase) * 0.4 + sin(nphase2 + 1.3) * 0.3) * exp(-t * 55.0)
		var s: float = (tone * (1.0 - p.noise) + noise * p.noise) * env * p.gain
		if t < 0.006:
			s += 0.35 * p.noise * (1.0 - t / 0.006)
		s = clampf(s, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 9000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav

static func _params(kind: String) -> Dictionary:
	match kind:
		"dirt":
			return {"f_high": 96.0, "f_low": 45.0, "decay": 22.0, "noise": 0.45, "gain": 0.8}
		"grass":
			return {"f_high": 70.0, "f_low": 38.0, "decay": 17.0, "noise": 0.62, "gain": 0.55}
		_:
			return {"f_high": 150.0, "f_low": 60.0, "decay": 28.0, "noise": 0.22, "gain": 0.95}
