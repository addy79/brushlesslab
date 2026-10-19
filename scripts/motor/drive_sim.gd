class_name DriveSim
extends RefCounted
## Time-domain simulation of the motor on the test stand, driven by a six-step ("trapezoidal")
## electronic speed controller, the way hobby ESCs and simple industrial drives work.
##
## Electrical: in each 60° step two leads are driven (one high, one low) and the third
##   floats. The current in the driven pair obeys V·d = R·i + L·di/dt + e, with e the
##   line back-EMF from the flux model at the rotor's exact angle. Solved exactly over each
##   20 µs step; free-wheel diodes stop the current going negative.
## Commutation: sensorless motors use back-EMF zero crossings on the floating lead (commutate
##   30° after each crossing), after an open-loop start ramp; sensored motors read the three
##   Hall sensors. Both tables are learned from the healthy design, like an ESC's setup.
## Mechanical: J·dω/dt = T_e − friction − cogging − load − shorted-turn drag.
## Thermal: one lumped winding temperature with speed-dependent cooling.
##
## Fast mode (standalone headsets): 100 µs steps, one per recorded sample, and in closed-loop
##   running the ESC is taken as perfectly in sync (it commutates where the zero-crossing
##   detector would), instead of modelling the detector. About 4× cheaper. An open lead,
##   which blinds the detector, is reproduced as missed crossings on the sectors where that
##   lead floats. tests/model_test.gd checks that both modes agree.

const DT := 2.0e-5
const SAMPLE_EVERY := 5          ## record at 10 kHz
const SAMPLE_RATE := 1.0 / (DT * SAMPLE_EVERY)
const BUF := 8192

signal tripped(reason: String)

var state: MotorState
var spec: MotorSpec
var supply_v := 11.1
var throttle := 0.0                ## 0..1, what the user sets
var battery_r := 0.05              ## ohm: pack + wires + ESC switches
var brake_torque := 0.0            ## N m (dynamometer), inrunner
var prop_on := true
var armed := false
var fast := false                  ## see "Fast mode" above

var theta := 0.0                   ## mechanical angle (rad)
var omega := 0.0                   ## rad/s
var current := 0.0                 ## A in the driven pair
var duty := 0.0
var mode := "stopped"              ## stopped | ramp | run | fault
var fault_reason := ""
var time := 0.0
var step_index := 0
var commutations := 0
var desyncs := 0

## Commutation sequence: 6 entries [pos, neg] learned from the healthy motor.
var sequence: Array = []
## For each step: sign the floating lead's EMF has once it has crossed zero.
var zc_sign: Array[float] = []
## Sensored: hall code (0..7) -> sequence index, or -1 for invalid codes.
var hall_table: Array[int] = []
## Fast mode: sequence index an in-sync ESC uses at each table angle.
var _ideal_idx := PackedInt32Array()

# averaged readouts (exponential, ~0.2 s)
var avg := {"rpm": 0.0, "bus_i": 0.0, "phase_i_rms": 0.0, "torque": 0.0, "p_in": 0.0, "p_out": 0.0, "thrust": 0.0}

# ring buffers at 10 kHz
var buf_accel := PackedFloat32Array()
var buf_current := PackedFloat32Array()   ## lead A current
var buf_va := PackedFloat32Array()        ## lead A voltage to battery minus
var buf_pos := 0

var _ramp_period := 0.0
var _ramp_timer := 0.0
var _ramp_steps := 0
var _last_comm_t := 0.0
var _sector_t := 0.004
var _zc_seen := false
var _zc_t := 0.0
var _float_sign := 0.0
var _pending_comm_t := -1.0
var _restart_wait := 0.0
var _fail_count := 0
var _ground_t := 0.0
var _sample_n := 0
var _rng := RandomNumberGenerator.new()
var _bpfo_phase := {}
var _ring := 0.0
var _ring_phase := 0.0
var _rattle := 0.0
var _last_theta_rev := 0.0
var _i_sq_acc := 0.0
# per-call constants for _record (fixed while advance() runs)
var _rec_unb := 0.0
var _rec_loose := 0
var _rec_bearings: Array = []      ## [name, damage, BPFO order] of damaged bearings


func _init(p_state: MotorState) -> void:
	state = p_state
	spec = state.spec
	supply_v = spec.supply_v
	prop_on = spec.load == "prop"
	_rng.seed = 7
	_learn_tables()
	buf_accel.resize(BUF)
	buf_current.resize(BUF)
	buf_va.resize(BUF)
	buf_accel.fill(0.0)
	buf_current.fill(0.0)
	buf_va.fill(0.0)
	for n: String in state.bearings:
		_bpfo_phase[n] = 0.0


## Learns the six-step sequence and the Hall table on a healthy copy of the design.
func _learn_tables() -> void:
	var ref := MotorState.new(spec)
	var pp := spec.pole_pairs()
	var samples := 720
	var order: Array = []
	var hall_votes := {}
	for s in samples:
		var th := TAU / pp * s / samples
		var k := [ref.mag.phase_k(0, th), ref.mag.phase_k(1, th), ref.mag.phase_k(2, th)]
		var hi := 0
		var lo := 0
		for p in 3:
			if k[p] > k[hi]:
				hi = p
			if k[p] < k[lo]:
				lo = p
		var pair := [hi, lo]
		if order.is_empty() or order[-1] != pair:
			if not order.has(pair):
				order.append(pair)
		var code := ref.hall_code(th)
		if not hall_votes.has(code):
			hall_votes[code] = {}
		var key := "%d%d" % pair
		hall_votes[code][key] = hall_votes[code].get(key, 0) + 1
	sequence = order
	# in-sync commutation table for fast mode, over one mechanical turn
	_ideal_idx.resize(Magnetics.N)
	for i in Magnetics.N:
		var hi := 0
		var lo := 0
		for p in 3:
			if ref.mag.k_y[p][i] > ref.mag.k_y[hi][i]:
				hi = p
			if ref.mag.k_y[p][i] < ref.mag.k_y[lo][i]:
				lo = p
		_ideal_idx[i] = maxi(order.find([hi, lo]), 0)
	# sign of the floating lead's EMF after its zero crossing, for each step (forward run)
	zc_sign.clear()
	zc_sign.resize(order.size())
	var prev_pair: Array = []
	for s in samples + 1:
		var th := TAU / pp * (s % samples) / samples
		var k := [ref.mag.phase_k(0, th), ref.mag.phase_k(1, th), ref.mag.phase_k(2, th)]
		var hi := 0
		var lo := 0
		for p in 3:
			if k[p] > k[hi]:
				hi = p
			if k[p] < k[lo]:
				lo = p
		var pair := [hi, lo]
		if not prev_pair.is_empty() and pair != prev_pair:
			var th0 := TAU / pp * (s - 1) / samples
			var f := 3 - int(prev_pair[0]) - int(prev_pair[1])
			zc_sign[order.find(prev_pair)] = signf(ref.mag.phase_k(f, th0))
		prev_pair = pair
	hall_table.clear()
	for c in 8:
		hall_table.append(-1)
	for code: int in hall_votes:
		var best := ""
		var best_n := 0
		for key: String in hall_votes[code]:
			if hall_votes[code][key] > best_n:
				best_n = hall_votes[code][key]
				best = key
		for i in sequence.size():
			if "%d%d" % sequence[i] == best:
				hall_table[code] = i


func rpm() -> float:
	return omega * 60.0 / TAU


func start() -> void:
	armed = true
	if mode == "stopped" or mode == "fault":
		_begin_ramp()


func stop() -> void:
	armed = false
	mode = "stopped"
	duty = 0.0


func _begin_ramp() -> void:
	fault_reason = ""
	if spec.has_halls:
		mode = "run"
		return
	mode = "ramp"
	_ramp_period = 0.012
	_ramp_timer = 0.0
	_ramp_steps = 0
	_zc_seen = false
	_pending_comm_t = -1.0


func _trip(reason: String) -> void:
	mode = "fault"
	armed = false
	fault_reason = reason
	duty = 0.0
	tripped.emit(reason)


## Advances the simulation by `seconds` (call every frame with the frame time).
func advance(seconds: float) -> void:
	var h := DT * SAMPLE_EVERY if fast else DT
	var rec_every := 1 if fast else SAMPLE_EVERY
	var steps := int(round(seconds / h))
	var r_phase: Array[float] = state._phase_r()
	var l_phase: Array[float] = state._phase_l(0.0)
	var mag := state.mag
	var pp := spec.pole_pairs()
	var t0 := spec.friction_t0 * (1.0 + 4.0 * state.worst_bearing()) + (0.002 if state.debris > 0 else 0.0) * spec.friction_t0 / 0.0012
	var cog_n := spec.cogging_steps()
	var cog_extra := 0.0
	for m: Dictionary in state.magnets:
		cog_extra = maxf(cog_extra, absf(1.0 - float(m.strength)) + (0.5 if m.loose else 0.0))
	_prepare_record()
	var start_duty := clampf(0.25 * spec.max_current * spec.r_ll / supply_v, 0.02, 0.3)
	for _s in steps:
		time += h
		var on := armed and mode != "stopped" and mode != "fault"
		# --- commutation -----------------------------------------------------------------
		if on:
			if spec.has_halls:
				var code := state.hall_code(theta)
				var idx: int = hall_table[code]
				if idx >= 0:
					if idx != step_index:
						commutations += 1
					step_index = idx
				duty = move_toward(duty, throttle, h * 1.5)
			elif mode == "ramp":
				# open-loop: raise the voltage with the forced speed so it stays ahead of
				# the back-EMF (V ≈ e + I·R), like an ESC's start-up ramp
				var w_forced := (PI / 3.0) / _ramp_period / pp
				duty = clampf(start_duty + spec.ke_ll_peak() * w_forced * 0.85 / supply_v, start_duty, 0.6)
				_ramp_timer += h
				if _ramp_timer >= _ramp_period:
					_ramp_timer = 0.0
					_commutate()
					_ramp_steps += 1
					_ramp_period = maxf(_ramp_period * 0.93, 0.0012)
					if _ramp_steps > 90:
						mode = "run"
						_sector_t = _ramp_period
						_last_comm_t = time
						_zc_seen = false
			else:
				duty = move_toward(duty, maxf(throttle, 0.04), h * 1.5)
				if fast:
					_in_sync()
				else:
					_sensorless(mag)
		else:
			duty = 0.0
		# --- electrical ------------------------------------------------------------------
		var pair: Array = sequence[step_index % sequence.size()]
		var p: int = pair[0]
		var n: int = pair[1]
		var ti := int(fposmod(theta, TAU) / TAU * Magnetics.N) % Magnetics.N
		var kp: float = mag.k_y[p][ti]
		var kn: float = mag.k_y[n][ti]
		var e := (kp - kn) * omega
		var r := r_phase[p] + r_phase[n]
		var l := l_phase[p] + l_phase[n]
		# battery, wiring and MOSFET resistance make the supply sag under load
		var v := (supply_v - current * duty * battery_r) * duty if on else 0.0
		if is_inf(r) or not on:
			current = 0.0
		else:
			var i_inf := (v - e) / r
			current = i_inf + (current - i_inf) * exp(-r * h / l)
			if current < 0.0:
				current = 0.0
			if current > spec.max_current * 1.6:
				current = spec.max_current * 1.6     # cycle-by-cycle current limit
		var t_e := (kp - kn) * current
		# --- mechanical ------------------------------------------------------------------
		var t_short := _short_drag(omega, pp)
		var t_load := 0.0
		if spec.load == "prop" and prop_on:
			t_load = spec.prop_kq * omega * absf(omega)
		elif spec.load == "brake":
			t_load = brake_torque * clampf(omega / 5.0, -1.0, 1.0)
		var t_cog := spec.cogging * (sin(cog_n * theta) + cog_extra * 0.6 * sin(spec.slots * theta))
		var t_fric_dyn := spec.friction_c * omega
		var drive := t_e - t_cog - t_load - t_short - t_fric_dyn
		if absf(omega) < 0.5 and absf(drive) <= t0:
			omega = 0.0
		else:
			omega += (drive - t0 * signf(omega if absf(omega) > 1e-6 else drive)) / spec.rotor_inertia * h
		theta += omega * h
		# --- bookkeeping -----------------------------------------------------------------
		_i_sq_acc += current * current * r * h if not is_inf(r) else 0.0
		_sample_n += 1
		if _sample_n >= rec_every:
			_sample_n = 0
			_record(p, n, kp, kn, t_e, mag.k_y[0][ti])
	# thermal and averages, once per call
	var dt := steps * h
	if dt > 0.0:
		var p_cu := _i_sq_acc / dt
		_i_sq_acc = 0.0
		var p_iron := spec.friction_c * omega * omega * 0.6 + _short_drag(omega, pp) * absf(omega)
		var cool := lerpf(spec.thermal_r_still, spec.thermal_r_fast, clampf(absf(rpm()) / (spec.kv * spec.supply_v), 0.0, 1.0))
		var temp := state.winding_temp
		temp += (p_cu + p_iron - (temp - MotorState.ROOM_TEMP) / cool) / spec.thermal_c * dt
		state.winding_temp = temp
		if temp > spec.max_temp and mode != "fault":
			_trip("Over-temperature: winding at %.0f °C" % temp)
		var a := clampf(dt / 0.2, 0.0, 1.0)
		var bus := current * duty
		avg.rpm = lerpf(avg.rpm, rpm(), a)
		avg.bus_i = lerpf(avg.bus_i, bus, a)
		avg.phase_i_rms = lerpf(avg.phase_i_rms, current * sqrt(2.0 / 3.0), a)
		var torque_load := 0.0
		if spec.load == "prop" and prop_on:
			torque_load = spec.prop_kq * omega * omega
		else:
			torque_load = brake_torque if absf(omega) > 5.0 else 0.0
		avg.torque = lerpf(avg.torque, torque_load, a)
		avg.p_in = lerpf(avg.p_in, bus * supply_v, a)
		avg.p_out = lerpf(avg.p_out, torque_load * absf(omega), a)
		avg.thrust = lerpf(avg.thrust, spec.prop_kt * omega * omega if prop_on and spec.load == "prop" else 0.0, a)
		# insulation fault: leakage to the frame trips the controller's protection
		if state.insulation_mohm < 1.0 and mode == "run" and duty > 0.08:
			_ground_t += dt
			if _ground_t > 1.2:
				_trip("Ground fault / over-current trip")
		else:
			_ground_t = 0.0
		if mode == "fault" and fault_reason.begins_with("Desync") == false:
			pass


func _commutate() -> void:
	step_index = (step_index + 1) % sequence.size()
	commutations += 1
	var pair: Array = sequence[step_index]
	var f := 3 - int(pair[0]) - int(pair[1])
	_float_sign = signf(state.mag.k_y[f][int(fposmod(theta, TAU) / TAU * Magnetics.N) % Magnetics.N] * omega)
	_zc_seen = false


## Fast mode: the ESC commutates exactly where its zero-crossing detector would. With an
## open lead (Y) the detector sees noise on the sectors where that lead floats, so about
## half of those crossings are missed, as in the detailed model.
func _in_sync() -> void:
	var idx: int = _ideal_idx[int(fposmod(theta, TAU) / TAU * Magnetics.N) % Magnetics.N]
	if idx == step_index:
		return
	var pair: Array = sequence[idx]
	var f := 3 - int(pair[0]) - int(pair[1])
	if f == state.open_phase and spec.connection == "Y" and _rng.randf() < 0.5:
		desyncs += 1
		_fail_count += 3
		if _fail_count > 30:
			_trip("Desync: the controller could not find the rotor (no clean back-EMF)")
		else:
			_begin_ramp()
		return
	step_index = idx
	commutations += 1
	_fail_count = maxi(_fail_count - 1, 0)


## Closed-loop sensorless commutation from back-EMF zero crossings: after a blanking time,
## the comparator watches the floating lead; once its EMF has the sign it should have after
## the crossing, the next commutation is scheduled the same time later (30° electrical).
func _sensorless(mag: Magnetics) -> void:
	var pair: Array = sequence[step_index]
	var f := 3 - int(pair[0]) - int(pair[1])
	var ef: float = mag.k_y[f][int(fposmod(theta, TAU) / TAU * Magnetics.N) % Magnetics.N] * omega
	ef += _rng.randf_range(-1.0, 1.0) * supply_v * 0.002    # comparator noise
	if f == state.open_phase and spec.connection == "Y":
		ef = _rng.randf_range(-1.0, 1.0) * supply_v * 0.05   # broken lead: the comparator sees noise
	var since := time - _last_comm_t
	if not _zc_seen and since > _sector_t * 0.2 and signf(ef) == zc_sign[step_index]:
		_zc_seen = true
		_zc_t = time
		_pending_comm_t = time + clampf(since, 2.0e-5, 0.05)
	if _zc_seen and time >= _pending_comm_t:
		_sector_t = lerpf(_sector_t, time - _last_comm_t, 0.5)
		_last_comm_t = time
		_commutate()
		_fail_count = maxi(_fail_count - 1, 0)
	elif not _zc_seen and since > maxf(_sector_t * 3.0, 0.004):
		# no zero crossing where one was expected: lost sync
		desyncs += 1
		_fail_count += 3
		if _fail_count > 30:
			_trip("Desync: the controller could not find the rotor (no clean back-EMF)")
		else:
			_begin_ramp()


func _short_drag(w: float, pp: int) -> float:
	var t := 0.0
	for p in 3:
		var s: float = state.shorted[p]
		if s <= 0.0:
			continue
		var k_rms := spec.ke_ll_peak() / sqrt(6.0)
		var e := s * k_rms * absf(w)
		var r_s := maxf(spec.r_phase() * s * 0.15, 1e-4)
		var l_s := spec.l_ll * 0.5 * s * s * 0.5
		var z2 := r_s * r_s + pow(w * pp * l_s, 2.0)
		var power := e * e * r_s / z2
		t += 0.35 * power / maxf(absf(w), 1.0) * signf(w)
	return t


func _record(p: int, n: int, kp: float, kn: float, t_e: float, ka: float) -> void:
	var f_r := omega / TAU
	var dt := 1.0 / SAMPLE_RATE
	# vibration (m/s²): unbalance + bent shaft (1×, 2×), bearings, torque ripple, magnets
	var a := 0.0
	a += _rec_unb * omega * omega * 1e-3 * cos(theta)
	a += state.runout_mm * 0.03 * omega * omega * 1e-3 * cos(2.0 * theta + 0.6)
	if absf(f_r) >= 0.5:
		for b: Array in _rec_bearings:
			var name: String = b[0]
			var dmg: float = b[1]
			_bpfo_phase[name] += absf(f_r) * float(b[2]) * dt
			if _bpfo_phase[name] >= 1.0:
				_bpfo_phase[name] -= 1.0
				_ring += dmg * (2.0 + absf(omega) * 0.004)
			a += dmg * 1.4 * sin(TAU * _bpfo_phase[name]) * minf(absf(f_r) / 50.0, 1.0)
	_ring *= exp(-dt * 900.0)
	_ring_phase += dt * 2900.0
	a += _ring * sin(TAU * _ring_phase)
	# torque ripple shakes the housing (6 × electrical frequency, cogging)
	a += (t_e - avg.torque) * 40.0 / maxf(spec.mass_g / 50.0, 1.0)
	# once-per-revolution events: loose magnet knock, grit scraping
	var rev := floorf(theta / TAU)
	if rev != _last_theta_rev:
		_last_theta_rev = rev
		_rattle += 3.0 * _rec_loose
	if state.debris > 0 and absf(omega) > 1.0:
		a += _rng.randf_range(-1.0, 1.0) * 0.25 * state.debris * minf(absf(omega) / 200.0, 1.0)
	_rattle *= exp(-dt * 400.0)
	a += _rattle * sin(TAU * 1700.0 * time)
	a += _rng.randf_range(-1.0, 1.0) * 0.04
	buf_accel[buf_pos] = a
	# lead A current and voltage (for the scope)
	var ia := 0.0
	if p == 0:
		ia = current
	elif n == 0:
		ia = -current
	buf_current[buf_pos] = ia
	var vp := supply_v * duty
	var va := 0.0
	if p == 0:
		va = vp
	elif n == 0:
		va = 0.0
	else:
		va = vp * 0.5 + (ka - (kp + kn) * 0.5) * omega
	buf_va[buf_pos] = va if (armed and mode != "fault") else ka * omega
	buf_pos = (buf_pos + 1) % BUF


func _prepare_record() -> void:
	# residual unbalance of a balanced rotor ≈ 0.6 mm/s at full speed (ISO zone A)
	_rec_unb = 0.0009 + state.runout_mm * 0.08
	_rec_loose = 0
	for m: Dictionary in state.magnets:
		if m.loose:
			_rec_unb += 0.004
			_rec_loose += 1
	_rec_bearings.clear()
	for name: String in state.bearings:
		var dmg := state.bearing_damage(name)
		if dmg >= 0.08:
			_rec_bearings.append([name, dmg, MotorSpec.bearing_orders(state.bearings[name].type).BPFO])


## The last `count` samples of a ring buffer, oldest first.
func recent(buf: PackedFloat32Array, count: int) -> PackedFloat32Array:
	count = mini(count, BUF)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = buf[(buf_pos - count + i + BUF) % BUF]
	return out


## Frequencies (Hz) a technician looks for, at the current speed.
func marker_frequencies() -> Dictionary:
	var f_r := absf(avg.rpm) / 60.0
	var out := {"1×": f_r, "2×": 2.0 * f_r, "electrical": f_r * spec.pole_pairs(), "cogging": f_r * spec.cogging_steps()}
	var names := state.bearing_names()
	var orders := MotorSpec.bearing_orders(state.bearings[names[0]].type)
	out["BPFO"] = f_r * orders.BPFO
	out["BPFI"] = f_r * orders.BPFI
	return out
