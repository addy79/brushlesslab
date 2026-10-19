class_name MotorSpec
extends RefCounted
## The design data of one brushless motor: what a datasheet (or a careful reverse
## engineer) would write down. Geometry is in millimetres, electrical values are
## line-to-line at 20 °C (what you measure between two of the three leads).
##
## Two real-world style motors are built in, plus a generator for "mystery" outrunners
## with a random slot/pole combination, connection and KV (the reverse-engineering job).

## Deep-groove ball bearings used by the motors. Ball count, ball diameter and pitch
## diameter set the bearing defect frequencies (BPFO, BPFI, BSF, FTF).
## Approximate geometry for these sizes (manufacturers differ slightly).
const BEARINGS := {
	"693ZZ": {"bore": 3.0, "od": 8.0, "width": 4.0, "balls": 7, "ball_d": 1.588, "pitch_d": 5.5},
	"683ZZ": {"bore": 3.0, "od": 7.0, "width": 3.0, "balls": 7, "ball_d": 1.2, "pitch_d": 5.0},
	"694ZZ": {"bore": 4.0, "od": 11.0, "width": 4.0, "balls": 7, "ball_d": 2.0, "pitch_d": 7.5},
	"608ZZ": {"bore": 8.0, "od": 22.0, "width": 7.0, "balls": 7, "ball_d": 3.969, "pitch_d": 15.0},
}

## Slot/pole combinations a mystery outrunner can have (all real, all balanced 3-phase).
const MYSTERY_COMBOS := [[9, 6], [9, 12], [12, 10], [12, 14], [18, 16], [18, 20], [24, 22], [12, 8], [9, 8], [9, 10]]

var id := ""
var name := ""
var kind := "outrunner"          ## "outrunner" (rotor bell outside) or "inrunner"
var is_mystery := false
var slots := 12                  ## stator teeth (N)
var poles := 14                  ## magnets (P)
var connection := "Y"            ## "Y" (star) or "D" (delta)
var kv := 920.0                  ## rpm per volt, no load
var r_ll := 0.105                ## ohm, between two leads, 20 °C
var l_ll := 0.000034             ## henry, between two leads (1 kHz)
var turns := 13                  ## turns per tooth
var wire_d := 0.33               ## mm, enamelled copper
var strands := 2
var stator_od := 22.0
var stator_h := 12.0
var stator_bore := 8.0           ## hole in the lamination stack
var airgap := 0.35
var magnet_t := 1.5              ## magnet thickness (radial)
var magnet_h := 12.0
var back_iron := 1.0
var shaft_d := 3.0
var shaft_len := 40.0
var bearings: Array[String] = ["693ZZ", "693ZZ"]
var has_halls := false
var hall_spacing := 120          ## electrical degrees between hall sensors
var supply_v := 11.1             ## nominal supply (3S LiPo or 24 V bus)
var max_current := 18.0
var max_temp := 110.0            ## winding temperature limit (°C) before damage
var mass_g := 52.0
var rotor_inertia := 2.4e-6      ## kg m²
var friction_t0 := 0.0012        ## N m, bearing + seal drag at rest
var friction_c := 2.4e-6         ## N m per rad/s (windage, eddy, iron losses)
var cogging := 0.004             ## peak cogging torque, N m (relative to rated)
var load := "prop"               ## "prop" (propeller) or "brake" (dynamometer)
var prop_kq := 1.5e-7            ## prop torque  = kq ω²  (10x4.5 prop)
var prop_kt := 1.12e-5           ## prop thrust  = kt ω²  (N)
var thermal_c := 18.0            ## J/K, winding + stator
var thermal_r_still := 9.0       ## K/W at standstill
var thermal_r_fast := 2.2        ## K/W at full speed (airflow)
var lead_colors: Array[Color] = [Color(0.08, 0.08, 0.08), Color(0.08, 0.08, 0.08), Color(0.08, 0.08, 0.08)]
var lead_names: Array[String] = ["A", "B", "C"]
var magnet_grade := "N52SH"
var surface_field := 0.42        ## tesla at the magnet surface, healthy
var size_code := "2212"


func pole_pairs() -> int:
	return poles / 2


## Torque constant (N m per A) of the line current, from KV: Kt = 60 / (2π KV).
func kt() -> float:
	return 60.0 / (TAU * kv)


## Back-EMF constant: peak line-to-line volts per rad/s.
func ke_ll_peak() -> float:
	return 60.0 / (TAU * kv)


## Cogging steps per mechanical revolution = LCM(slots, poles).
func cogging_steps() -> int:
	return lcm(slots, poles)


## Phase resistance (one coil chain), from the line-line value and the connection:
## star: two phases in series; delta: one phase in parallel with the other two.
func r_phase() -> float:
	return r_ll * 0.5 if connection == "Y" else r_ll * 1.5


func r_ll_at(temp_c: float) -> float:
	return r_ll * (1.0 + 0.00393 * (temp_c - 20.0))


static func gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return absi(a)


static func lcm(a: int, b: int) -> int:
	return a / gcd(a, b) * b


## Bearing defect frequencies, as multiples of the shaft frequency.
static func bearing_orders(bearing: String) -> Dictionary:
	var b: Dictionary = BEARINGS.get(bearing, BEARINGS["693ZZ"])
	var n: float = b.balls
	var r: float = b.ball_d / b.pitch_d
	return {
		"BPFO": n * 0.5 * (1.0 - r),            # outer race defect
		"BPFI": n * 0.5 * (1.0 + r),            # inner race defect
		"BSF": 0.5 / r * (1.0 - r * r),         # ball spin
		"FTF": 0.5 * (1.0 - r),                 # cage
	}


# --- catalogue ---------------------------------------------------------------------------

## Outrunner of the 2212 size class used on 1 kg quadcopters: 22 mm stator, 12 mm stack,
## 12 slots 14 magnets (12N14P), dLRK winding, star connected, 920 rpm/V, 3S battery.
static func drone_2212() -> MotorSpec:
	var s := MotorSpec.new()
	s.id = "2212"
	s.name = "Drone outrunner 2212-920KV"
	s.kind = "outrunner"
	s.slots = 12
	s.poles = 14
	s.connection = "Y"
	s.kv = 920.0
	s.r_ll = 0.105
	s.l_ll = 34e-6
	s.turns = 13
	s.size_code = "2212"
	return s


## Industrial inrunner of the 57 mm frame class (57BL type): 12 slots, 8 poles, three Hall
## sensors 120° apart, 24 V, ~4000 rpm rated, 608ZZ bearings, wave-spring preload.
static func industrial_57bl() -> MotorSpec:
	var s := MotorSpec.new()
	s.id = "57BL"
	s.name = "Industrial inrunner 57BL-24V"
	s.kind = "inrunner"
	s.slots = 12
	s.poles = 8
	s.connection = "Y"
	s.kv = 190.0
	s.r_ll = 1.35
	s.l_ll = 2.6e-3
	s.turns = 56
	s.wire_d = 0.45
	s.strands = 1
	s.stator_od = 52.0
	s.stator_h = 40.0
	s.stator_bore = 26.6        # rotor OD 26 + airgap
	s.airgap = 0.3
	s.magnet_t = 2.5
	s.magnet_h = 40.0
	s.back_iron = 0.0
	s.shaft_d = 8.0
	s.shaft_len = 120.0
	s.bearings.assign(["608ZZ", "608ZZ"])
	s.has_halls = true
	s.supply_v = 24.0
	s.max_current = 6.0
	s.max_temp = 130.0
	s.mass_g = 950.0
	s.rotor_inertia = 7.5e-5
	s.friction_t0 = 0.012
	s.friction_c = 1.5e-5
	s.cogging = 0.012
	s.load = "brake"
	s.prop_kq = 0.0
	s.prop_kt = 0.0
	s.thermal_c = 260.0
	s.thermal_r_still = 2.6
	s.thermal_r_fast = 1.2
	s.lead_colors.assign([Color(0.85, 0.75, 0.1), Color(0.15, 0.55, 0.2), Color(0.15, 0.3, 0.75)])
	s.lead_names.assign(["U (yellow)", "V (green)", "W (blue)"])
	s.magnet_grade = "N35"
	s.surface_field = 0.38
	s.size_code = "57"
	return s


## A random outrunner with a hidden design: slot/pole combination, connection, turns
## (and so KV and resistance) all change, but stay physically consistent.
static func mystery(seed_value: int) -> MotorSpec:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var s := drone_2212()
	s.id = "mystery"
	s.is_mystery = true
	var combo: Array = MYSTERY_COMBOS[rng.randi_range(0, MYSTERY_COMBOS.size() - 1)]
	s.slots = combo[0]
	s.poles = combo[1]
	var sizes := [[22.0, 8.0], [22.0, 12.0], [23.0, 10.0], [28.0, 8.0], [28.0, 12.0]]
	if s.slots >= 18:
		sizes = [[28.0, 8.0], [28.0, 12.0], [35.0, 10.0]]
	var size: Array = sizes[rng.randi_range(0, sizes.size() - 1)]
	s.stator_od = size[0]
	s.stator_h = size[1]
	s.magnet_h = s.stator_h
	s.size_code = "%02d%02d" % [int(s.stator_od), int(s.stator_h)]
	s.connection = "Y" if rng.randf() < 0.6 else "D"
	s.turns = rng.randi_range(8, 22)
	# Back-EMF grows with turns × coils per phase × flux area; a star connection adds a
	# factor √3 between the leads. Coil resistance grows with turns² (same copper fill).
	var area: float = s.stator_od * s.stator_h / (22.0 * 12.0)
	var conn_k := sqrt(3.0) if s.connection == "Y" else 1.0
	s.kv = snappedf(920.0 * (13.0 * 12.0) / (s.turns * s.slots) / area * sqrt(3.0) / conn_k * rng.randf_range(0.95, 1.05), 10.0)
	var r_coil: float = 0.105 / 2.0 / 4.0 * pow(s.turns / 13.0, 2.0) * sqrt(area)
	var r_phase: float = r_coil * s.slots / 3.0
	s.r_ll = snappedf(r_phase * (2.0 if s.connection == "Y" else 2.0 / 3.0) * rng.randf_range(0.92, 1.08), 0.001)
	s.l_ll = s.r_ll * rng.randf_range(2.6e-4, 3.6e-4)
	s.bearings.assign(["694ZZ", "694ZZ"] if s.stator_od >= 28.0 else ["693ZZ", "693ZZ"])
	s.shaft_d = 4.0 if s.stator_od >= 28.0 else 3.0
	s.name = "Mystery outrunner #%d" % (seed_value % 1000)
	s.mass_g = snappedf(52.0 * area, 1.0)
	s.rotor_inertia = 2.4e-6 * area * area
	s.thermal_c = 18.0 * area
	s.supply_v = 11.1 if s.kv > 700.0 else 14.8
	return s


static func by_id(motor_id: String, seed_value := 1) -> MotorSpec:
	match motor_id:
		"57BL":
			return industrial_57bl()
		"mystery":
			return mystery(seed_value)
	return drone_2212()
