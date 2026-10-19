class_name Magnetics
extends RefCounted
## Air-gap flux model of a surface-magnet brushless motor.
##
## The rotor's field around the gap, B(φ), is the sum of the magnets: each one a soft-edged
## arc of ±B (alternating N/S, its own strength, possibly shifted or flipped). The flux
## through tooth i at rotor angle θ is the integral of B over the tooth face. A phase's
## flux linkage λ(θ) is Σ turns·sign·flux over its coils, and its back-EMF is
## e = dλ/dt = (dλ/dθ)·ω. Everything is tabulated over one mechanical revolution.
##
## The absolute scale is calibrated once on the healthy design so that the peak
## line-to-line EMF matches the motor's KV; damage (weak, flipped or loose magnets, shorted
## turns, a wrong rewind) then changes the waveforms the way it would on a real motor.

const N := 2048            ## table samples per mechanical revolution
const FIELD_N := 4096      ## samples of B(φ) around the gap
const TOOTH_SPAN := 0.82   ## tooth face width / slot pitch
const MAGNET_ARC := 0.86   ## magnet arc / pole pitch
const FRINGE := 0.07       ## edge softness, fraction of the pole pitch

var slots := 12
var poles := 14
var connection := "Y"
## Volt-seconds per table unit (set by calibrate()).
var scale := 1.0
## dλ/dθ per phase (A, B, C), unscaled, N samples each.
var k_phase: Array[PackedFloat32Array] = []
## Y-equivalent phase constants (V·s/rad, scaled): e_y = k_y · ω; torque = Σ i_y · k_y.
var k_y: Array[PackedFloat32Array] = []
## Rotor field around the gap at θ = 0 (for halls and the viewing film), FIELD_N samples.
var field := PackedFloat32Array()


## coils: Winding coils (per tooth); magnets: Array of {strength, polarity, shift (rad)};
## shorted: fraction of turns shorted per phase (they don't reach the terminals).
func build(p_slots: int, p_poles: int, p_connection: String, coils: Array, magnets: Array, shorted := [0.0, 0.0, 0.0]) -> void:
	slots = p_slots
	poles = p_poles
	connection = p_connection
	_build_field(magnets)
	# cumulative integral of B (mean removed: the net flux returns through the yoke)
	var mean := 0.0
	for v in field:
		mean += v
	mean /= FIELD_N
	var dphi := TAU / FIELD_N
	var cum := PackedFloat64Array()
	cum.resize(FIELD_N + 1)
	cum[0] = 0.0
	for j in FIELD_N:
		cum[j + 1] = cum[j] + (field[j] - mean) * dphi
	var half := TOOTH_SPAN * PI / slots
	var lam: Array[PackedFloat64Array] = []
	for p in 3:
		var a := PackedFloat64Array()
		a.resize(N)
		a.fill(0.0)
		lam.append(a)
	for i in mini(coils.size(), slots):
		var c: Dictionary = coils[i]
		if c.turns == 0:
			continue
		var p: int = c.phase
		var w: float = float(c.turns) * c.sign * (1.0 - float(shorted[p]))
		var center := TAU * i / slots
		for s in N:
			var th := TAU * s / N
			lam[p][s] += w * (_cum_at(cum, center + half - th) - _cum_at(cum, center - half - th))
	k_phase.clear()
	for p in 3:
		var k := PackedFloat32Array()
		k.resize(N)
		var dth := TAU / N
		for s in N:
			k[s] = (lam[p][(s + 1) % N] - lam[p][(s - 1 + N) % N]) / (2.0 * dth)
		k_phase.append(k)
	_rebuild_y()


## Scales the tables so the peak line-to-line EMF is `ke_ll_peak` V per rad/s.
## Returns the scale (keep it: a damaged motor reuses the healthy motor's scale).
func calibrate(ke_ll_peak: float) -> float:
	scale = 1.0
	_rebuild_y()
	var peak := 0.0
	for s in N:
		peak = maxf(peak, absf(line_k(0, s)))
	scale = ke_ll_peak / peak if peak > 1e-12 else 1.0
	_rebuild_y()
	return scale


func set_scale(value: float) -> void:
	scale = value
	_rebuild_y()


func _rebuild_y() -> void:
	k_y.clear()
	for p in 3:
		var k := PackedFloat32Array()
		k.resize(N)
		k_y.append(k)
	for s in N:
		var a: float = k_phase[0][s]
		var b: float = k_phase[1][s]
		var c: float = k_phase[2][s]
		if connection == "Y":
			var m := (a + b + c) / 3.0
			k_y[0][s] = (a - m) * scale
			k_y[1][s] = (b - m) * scale
			k_y[2][s] = (c - m) * scale
		else:
			# delta: phase A between leads a-b, B b-c, C c-a. Line voltages minus the
			# circulating (zero-sequence) part; Y-equivalent = (v_ab - v_ca) / 3.
			var m := (a + b + c) / 3.0
			var vab := a - m
			var vbc := b - m
			var vca := c - m
			k_y[0][s] = (vab - vca) / 3.0 * scale
			k_y[1][s] = (vbc - vab) / 3.0 * scale
			k_y[2][s] = (vca - vbc) / 3.0 * scale


static func _cum_at(cum: PackedFloat64Array, phi: float) -> float:
	# periodic cumulative integral (the mean was removed, so one turn adds nothing)
	var x := fposmod(phi, TAU) / TAU * FIELD_N
	var j := int(x)
	var f := x - j
	return lerpf(cum[j], cum[mini(j + 1, FIELD_N)], f)


func _build_field(magnets: Array) -> void:
	field.resize(FIELD_N)
	field.fill(0.0)
	var pitch := TAU / poles
	var half_arc := MAGNET_ARC * pitch * 0.5
	var w := FRINGE * pitch
	for k in poles:
		var m: Dictionary = magnets[k] if k < magnets.size() else {}
		var strength: float = m.get("strength", 1.0)
		if strength == 0.0:
			continue
		var pol: int = (1 if k % 2 == 0 else -1) * int(m.get("polarity", 1))
		var center := pitch * k + float(m.get("shift", 0.0))
		for j in FIELD_N:
			var phi := TAU * j / FIELD_N
			var d := absf(wrapf(phi - center, -PI, PI))
			if d > half_arc + 4.0 * w:
				continue
			field[j] += pol * strength * 0.5 * (1.0 - tanh((d - half_arc) / w))


## Rotor field (normalised, ±1 ≈ healthy magnet) at stator angle φ with rotor angle θ.
func field_at(phi: float, theta: float) -> float:
	var x := fposmod(phi - theta, TAU) / TAU * FIELD_N
	return field[int(x) % FIELD_N]


func _idx(theta: float) -> int:
	return int(fposmod(theta, TAU) / TAU * N) % N


## Unscaled line constant between two leads (0 = a-b, 1 = b-c, 2 = c-a) at table index s.
func line_k(pair: int, s: int) -> float:
	var a: float = k_y[pair][s]
	var b: float = k_y[(pair + 1) % 3][s]
	return a - b


## Line-to-line back-EMF (V) between leads pair (0 ab, 1 bc, 2 ca) at rotor angle θ, speed ω.
func line_emf(pair: int, theta: float, omega: float) -> float:
	return line_k(pair, _idx(theta)) * omega


## Y-equivalent phase EMF constant at θ (V per rad/s).
func phase_k(phase: int, theta: float) -> float:
	return k_y[phase][_idx(theta)]


## Peak line-to-line EMF constant (V per rad/s) over a revolution, for each pair.
func peak_line_k() -> Array[float]:
	var out: Array[float] = [0.0, 0.0, 0.0]
	for s in N:
		for p in 3:
			out[p] = maxf(out[p], absf(line_k(p, s)))
	return out


## Hall sensor angles (mechanical rad): spaced `spacing_deg` electrical apart, centred in a
## slot opening next to phase A's first tooth.
## `base` is the first sensor's angle (MotorState lines it up with the commutation points,
## as a manufacturer does when it fixes the Hall board).
var hall_base := -1.0


func hall_angles(spacing_deg: int) -> Array[float]:
	var pp := poles / 2
	var base := hall_base if hall_base >= 0.0 else PI / slots
	var out: Array[float] = []
	for k in 3:
		out.append(base + deg_to_rad(spacing_deg) * k / pp)
	return out


## Peak |line EMF constant| of lead pair `pair` in each electrical cycle (P/2 values). On a
## healthy rotor they are all equal; a weak, flipped or missing magnet makes some lower,
## which is what the scope shows as uneven peaks.
func cycle_peaks(pair: int) -> Array[float]:
	var pp := poles / 2
	var out: Array[float] = []
	for c in pp:
		var m := 0.0
		for s in range(c * N / pp, (c + 1) * N / pp):
			m = maxf(m, absf(line_k(pair, s)))
		out.append(m)
	return out
