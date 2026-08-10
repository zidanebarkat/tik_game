extends RefCounted
## ProceduralHorn: generates a small horn + drum cue as an AudioStreamWAV at
## runtime. No audio asset files exist in the project, and a real soundtrack
## can replace this later without touching the call sites.

class_name ProceduralHorn

const SAMPLE_RATE := 22050

static func make_horn_wav() -> AudioStreamWAV:
	const DURATION := 2.4
	var frames := int(SAMPLE_RATE * DURATION)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var attack := 0.06
	var freq := 108.0
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	var ph := 0.0
	var pd := 0.0

	for i in frames:
		var t := float(i) / SAMPLE_RATE
		var envelope := minf(t / attack, 1.0) * exp(-1.8 * maxf(t - 0.08, 0.0))
		var vibrato := 1.0 + 0.012 * sin(TAU * 5.0 * t)
		p1 += TAU * freq * vibrato / SAMPLE_RATE
		p2 += TAU * freq * 2.0 / SAMPLE_RATE
		p3 += TAU * freq * 3.0 / SAMPLE_RATE
		ph += TAU * freq * 0.5 / SAMPLE_RATE
		var horn := (sin(p1) * 0.55 + sin(p2) * 0.24 + sin(p3) * 0.10 + sin(ph) * 0.28) * envelope

		var drum := 0.0
		if t < 0.55:
			pd += TAU * 62.0 / SAMPLE_RATE
			drum = sin(pd) * 0.7 * exp(-7.0 * t)

		var s := clampf(horn * 0.8 + drum, -1.0, 1.0)
		data.encode_s16(i * 2, int(clampf(s * 12000.0, -32768.0, 32767.0)))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
