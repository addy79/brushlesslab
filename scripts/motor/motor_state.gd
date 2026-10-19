class_name MotorState
extends RefCounted
## The physical condition of one particular motor on the bench: its design (MotorSpec)
## plus everything that can be worn, damaged, repaired or rebuilt. Every instrument reads
## from here, and every repair writes here; `changed` tells the views to refresh.

signal changed

const ROOM_TEMP := 22.0

var spec: MotorSpec
## Current winding (the design one, or the learner's rewind).
var coils: Array = []
var connection := "Y"
var rewound := false
## One entry per magnet: strength (1 = new), polarity (+1 right way, -1 glued in flipped),
## shift (rad, a loose magnet slides), loose, cracked, present.
var magnets: Array = []
## Fraction of each phase's turns shorted together (burnt insulation between turns).
var shorted: Array[float] = [0.0, 0.0, 0.0]
## Teeth whose varnish is visibly darkened.
var burnt_teeth: Array[int] = []
## -1, or the phase whose lead is broken at the solder joint.
var open_phase := -1
## Insulation resistance phase → frame (MΩ at 500 V). Healthy: > 2000.
var insulation_mohm := 2500.0
## Bearings by position ("top"/"bottom" on an outrunner, "front"/"rear" on an inrunner):
## {type, wear 0..1, brinelled (dented by a bad press), new}.
var bearings := {}
## Total indicated runout of the shaft (mm).
var runout_mm := 0.004
## Metal particles stuck to the magnets.
var debris := 0
## -1, or the Hall sensor (0..2) that is dead (output stuck high).
var hall_dead := -1
## Threadlocker on the shaft grub screw (outrunner).
var grub_locked := true
var shim_present := true
var winding_temp := ROOM_TEMP
var magnet_temp := ROOM_TEMP
## Permanent damage from overheating on the test stand (adds to the job report).
var overheated := false

var mag := Magnetics.new()
var _flux_scale := 1.0
var _hall_angles: Array[float] = []


func _init(p_spec: MotorSpec) -> void:
	spec = p_spec
	connection = spec.connection
	coils = Winding.design(spec.slots, spec.poles, spec.turns)
	magnets.clear()
	for k in spec.poles:
		magnets.append({"strength": 1.0, "polarity": 1, "shift": 0.0, "loose": false, "cracked": false, "present": true})
	var names := ["top", "bottom"] if spec.kind == "outrunner" else ["front", "rear"]
	for i in 2:
		bearings[names[i]] = {"type": spec.bearings[i], "wear": 0.03, "brinelled": false, "new": false}
	# calibrate on the healthy design, then keep that scale for everything that follows
	mag.build(spec.slots, spec.poles, connection, coils, _magnet_list())
	_flux_scale = mag.calibrate(spec.ke_ll_peak())
	if spec.has_halls:
		_align_halls()
	_hall_angles = mag.hall_angles(spec.hall_spacing)


## Finds where the Hall board must sit so the sensor edges fall on the six commutation
## points (as the factory does), by trying positions over one pole pitch.
func _align_halls() -> void:
	var pp := spec.pole_pairs()
	var samples := 360
	var best := 0.0
	var best_score := -1
	for c in 120:
		mag.hall_base = TAU / pp * c / 120.0
		var angles := mag.hall_angles(spec.hall_spacing)
		var votes := {}
		var truth: Array[String] = []
		var codes: Array[int] = []
		for i in samples:
			var th := TAU / pp * i / samples
			var hi := 0
			var lo := 0
			for p in 3:
				if mag.phase_k(p, th) > mag.phase_k(hi, th):
					hi = p
				if mag.phase_k(p, th) < mag.phase_k(lo, th):
					lo = p
			var key := "%d%d" % [hi, lo]
			var code := 0
			for k in 3:
				code = (code << 1) | int(mag.field_at(angles[k], th) > 0.0)
			truth.append(key)
			codes.append(code)
			if not votes.has(code):
				votes[code] = {}
			votes[code][key] = votes[code].get(key, 0) + 1
		var score := 0
		for code: int in votes:
			var top := 0
			for key: String in votes[code]:
				top = maxi(top, votes[code][key])
			score += top
		if score > best_score:
			best_score = score
			best = mag.hall_base
	mag.hall_base = best


## Rebuilds the flux tables after a change to the winding, magnets or shorts.
func rebuild() -> void:
	mag.build(spec.slots, spec.poles, connection, coils, _magnet_list(), shorted)
	mag.set_scale(_flux_scale)
	changed.emit()


func _magnet_list() -> Array:
	var out: Array = []
	for m: Dictionary in magnets:
		var s: float = m.strength if m.present else 0.0
		out.append({"strength": s, "polarity": m.polarity, "shift": m.shift})
	return out


func bearing_names() -> Array:
	return bearings.keys()


## Worst bearing condition, 0 (new) .. 1 (destroyed); a brinelled bearing counts as 0.6.
func bearing_damage(name: String) -> float:
	var b: Dictionary = bearings[name]
	return maxf(b.wear, 0.6 if b.brinelled else 0.0)


func worst_bearing() -> float:
	var w := 0.0
	for n: String in bearings:
		w = maxf(w, bearing_damage(n))
	return w


## Line-to-line resistance between two leads (ohm) at the winding temperature; INF if open.
func resistance_ll(a: int, b: int) -> float:
	if a == b:
		return 0.0
	var rp := _phase_r()
	var r := INF
	if connection == "Y":
		r = rp[a] + rp[b]
	else:
		# delta: phase k sits between leads k and k+1. Between a and b: the direct phase in
		# parallel with the other two in series.
		var direct := -1
		for k in 3:
			if (k == a and (k + 1) % 3 == b) or (k == b and (k + 1) % 3 == a):
				direct = k
		var r1: float = rp[direct]
		var r2 := 0.0
		for k in 3:
			if k != direct:
				r2 += rp[k]
		if is_inf(r1) and is_inf(r2):
			r = INF
		elif is_inf(r1):
			r = r2
		elif is_inf(r2):
			r = r1
		else:
			r = r1 * r2 / (r1 + r2)
	return r


func _phase_r() -> Array[float]:
	var nominal := spec.r_phase() * (1.0 + 0.00393 * (winding_temp - 20.0))
	var design_turns: float = spec.turns * spec.slots / 3.0
	var out: Array[float] = []
	for p in 3:
		var t := 0.0
		for c: Dictionary in coils:
			if c.phase == p:
				t += c.turns
		var r: float = nominal * (t / design_turns) * (1.0 - shorted[p])
		out.append(INF if p == open_phase or t == 0.0 else r)
	return out


## Line-to-line inductance at 1 kHz (H). Shorted turns act like a shorted transformer
## secondary and pull the inductance down much more than the resistance.
func inductance_ll(a: int, b: int, rotor_angle := 0.0) -> float:
	if a == b:
		return 0.0
	var lp := _phase_l(rotor_angle)
	if connection == "Y":
		return lp[a] + lp[b]
	var direct := -1
	for k in 3:
		if (k == a and (k + 1) % 3 == b) or (k == b and (k + 1) % 3 == a):
			direct = k
	var l1: float = lp[direct]
	var l2 := 0.0
	for k in 3:
		if k != direct:
			l2 += lp[k]
	if is_inf(l1):
		return l2
	if is_inf(l2):
		return l1
	return l1 * l2 / (l1 + l2)


func _phase_l(rotor_angle: float) -> Array[float]:
	var nominal := spec.l_ll * (0.5 if connection == "Y" else 1.5)
	var design_turns: float = spec.turns * spec.slots / 3.0
	var out: Array[float] = []
	for p in 3:
		var t := 0.0
		for c: Dictionary in coils:
			if c.phase == p:
				t += c.turns
		var l: float = nominal * pow(t / design_turns, 2.0) * pow(1.0 - shorted[p], 2.0) * maxf(1.0 - 3.5 * shorted[p], 0.1)
		# small saliency: ±2 % at twice the electrical angle
		l *= 1.0 + 0.02 * cos(2.0 * (spec.poles / 2) * rotor_angle - p * TAU / 3.0)
		out.append(INF if p == open_phase or t == 0.0 else maxf(l, nominal * 0.05))
	return out


## Insulation resistance from a lead to the frame (MΩ) at 500 V. Any phase: the coils are
## all connected, so a fault anywhere shows on every lead.
func insulation(_lead: int) -> float:
	return insulation_mohm


## Surface field over magnet k (tesla), as a Gauss meter would read it.
func magnet_field(k: int) -> float:
	var m: Dictionary = magnets[k]
	if not m.present:
		return 0.0
	return spec.surface_field * m.strength * (0.82 if m.cracked else 1.0) * m.polarity * (1 if k % 2 == 0 else -1)


## Dial-indicator reading (mm) on the shaft at rotation angle θ (zeroed at the low point).
func runout_reading(theta: float) -> float:
	var play := 0.0
	for n: String in bearings:
		play = maxf(play, bearing_damage(n))
	return runout_mm * 0.5 * (1.0 - cos(theta)) + play * 0.012 * (0.5 + 0.5 * sin(3.0 * theta + 1.0))


## Radial play of a bearing (mm) when you rock the shaft: ~5 µm new, 50+ µm worn out.
func bearing_play(name: String) -> float:
	return 0.005 + 0.06 * bearing_damage(name)


## Hand-spin test of a bearing: seconds it keeps spinning and how rough it feels (0..1).
func bearing_spin(name: String) -> Dictionary:
	var d := bearing_damage(name)
	return {"seconds": lerpf(6.0, 0.8, d), "rough": clampf(d * 1.3, 0.0, 1.0)}


## Hall sensor k's output (true = high) at rotor angle θ; a dead sensor sticks high.
func hall(k: int, theta: float) -> bool:
	if k == hall_dead:
		return true
	return mag.field_at(_hall_angles[k], theta) > 0.0


func hall_code(theta: float) -> int:
	return (int(hall(0, theta)) << 2) | (int(hall(1, theta)) << 1) | int(hall(2, theta))


## Peak line-to-line EMF (V) at `rpm` for each lead pair: what the scope's Vpk shows.
func emf_peaks(rpm: float) -> Array[float]:
	var w := rpm * TAU / 60.0
	var k := mag.peak_line_k()
	return [k[0] * w, k[1] * w, k[2] * w]


## Measured KV from the A-B pair (what a careful learner gets from the scope).
func measured_kv() -> float:
	var k: float = mag.peak_line_k()[0]
	return 60.0 / (TAU * k) if k > 1e-9 else INF


func is_healthy() -> bool:
	return problems().is_empty()


## Everything still wrong with the motor (empty = fit to go back into service).
func problems() -> Array[String]:
	var out: Array[String] = []
	for n: String in bearings:
		var b: Dictionary = bearings[n]
		if b.brinelled:
			out.append("%s bearing was dented (brinelled) when it was pressed in" % n)
		elif b.wear > 0.3:
			out.append("%s bearing is worn" % n)
	if runout_mm > 0.03:
		out.append("shaft is bent (%.2f mm runout)" % runout_mm)
	if shorted.max() > 0.0:
		out.append("winding has shorted turns")
	if open_phase >= 0:
		out.append("a phase lead is open")
	if insulation_mohm < 100.0:
		out.append("winding insulation to the frame is damaged")
	for k in magnets.size():
		var m: Dictionary = magnets[k]
		if not m.present:
			out.append("magnet %d is missing" % (k + 1))
		elif m.polarity < 0:
			out.append("magnet %d is glued in the wrong way round" % (k + 1))
		elif m.loose:
			out.append("magnet %d is loose" % (k + 1))
		elif m.cracked:
			out.append("magnet %d is cracked" % (k + 1))
		elif m.strength < 0.9:
			out.append("magnets are weakened (demagnetised)")
			break
	if debris > 0:
		out.append("metal debris on the magnets")
	if hall_dead >= 0:
		out.append("Hall sensor %s is dead" % ["A", "B", "C"][hall_dead])
	if not shim_present:
		out.append("shim washer missing (axial play)")
	if rewound:
		var issues := Winding.check(coils, spec.slots, spec.poles)
		for i in issues:
			out.append("rewind: " + i)
	return out
