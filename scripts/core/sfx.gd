class_name Sfx
extends Node
## Workshop sounds synthesised at start-up (no audio files): a tool click, a screw
## ratchet, the clack of a magnet snapping on, an error buzz, a success chime and
## the press creak.

const RATE := 22050

var enabled := true
## Everything played (the autotest checks feedback happened).
var history: Array[String] = []
var _players := {}


func _ready() -> void:
	_add("click", _tone(0.03, 2400.0, 90.0, 0.3))
	_add("ratchet", _ratchet())
	_add("clack", _clack())
	_add("error", _error())
	_add("success", _chime())
	_add("press", _press())
	_add("pop", _tone(0.08, 520.0, 40.0, 0.35))


func play(sound: String) -> void:
	if not _players.has(sound):
		return
	history.append(sound)
	if history.size() > 80:
		history.pop_front()
	if enabled:
		(_players[sound] as AudioStreamPlayer).play()


func _add(sound: String, stream: AudioStreamWAV) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -6.0
	add_child(p)
	_players[sound] = p


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _tone(seconds: float, freq: float, decay: float, amp: float) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	for i in int(seconds * RATE):
		var t := float(i) / RATE
		s.append(amp * sin(TAU * freq * t) * exp(-decay * t))
	return _wav(s)


static func _ratchet() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in int(0.45 * RATE):
		var t := float(i) / RATE
		var tick := fmod(t, 0.075)
		s.append(0.5 * rng.randf_range(-1.0, 1.0) * exp(-180.0 * tick) + 0.2 * sin(TAU * 3100.0 * t) * exp(-260.0 * tick))
	return _wav(s)


static func _clack() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in int(0.25 * RATE):
		var t := float(i) / RATE
		s.append(0.8 * sin(TAU * 1450.0 * t) * exp(-45.0 * t) + 0.6 * rng.randf_range(-1.0, 1.0) * exp(-120.0 * t))
	return _wav(s)


static func _error() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	for i in int(0.3 * RATE):
		var t := float(i) / RATE
		var on := fmod(t, 0.15) < 0.11
		s.append(0.22 * signf(sin(TAU * 196.0 * t)) * (1.0 if on else 0.0))
	return _wav(s)


static func _chime() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	for i in int(0.6 * RATE):
		var t := float(i) / RATE
		var b := sin(TAU * 660.0 * t) * exp(-6.0 * t)
		if t > 0.09:
			b += sin(TAU * 880.0 * (t - 0.09)) * exp(-6.0 * (t - 0.09))
		if t > 0.18:
			b += sin(TAU * 1320.0 * (t - 0.18)) * exp(-7.0 * (t - 0.18))
		s.append(0.14 * b)
	return _wav(s)


static func _press() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var lp := 0.0
	for i in int(0.7 * RATE):
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.05)
		s.append(0.6 * lp * (0.5 + 0.5 * sin(TAU * 7.0 * t)) * minf(t * 10.0, 1.0) * exp(-2.0 * t) + 0.5 * sin(TAU * 90.0 * t) * exp(-30.0 * maxf(t - 0.6, 0.0)) * (1.0 if t > 0.6 else 0.0))
	return _wav(s)
