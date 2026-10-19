class_name Faults
extends RefCounted
## Service jobs: a customer complaint, a hidden root cause that is applied to the motor,
## and what counts as the right diagnosis and repair. The symptoms are not scripted: they
## come out of the physics (flux model, drive simulation, bearing and vibration models).

const CAUSES := {
	"bearing_worn": "Worn bearing",
	"bent_shaft": "Bent shaft",
	"shorted_turns": "Shorted turns in the winding",
	"open_phase": "Open phase (broken lead joint)",
	"ground_fault": "Winding insulation fault to the frame",
	"loose_magnet": "Loose magnet",
	"demagnetized": "Demagnetised magnets (overheated)",
	"debris": "Metal debris on the magnets",
	"hall_dead": "Dead Hall sensor",
	"none": "No fault found",
}

## motors: which motors the job can come on.
const JOBS := [
	{"id": "bearing_worn", "motors": ["2212", "57BL"], "title": "Grinding noise",
		"complaint": "\"It started making a grinding, gravelly noise and the drone's camera footage has jello. It still flies.\"",
		"hint": "Listen and look at the vibration spectrum: peaks that are not whole multiples of the shaft speed come from a bearing."},
	{"id": "bent_shaft", "motors": ["2212"], "title": "Wobble after a crash",
		"complaint": "\"Crashed into a tree last week. Since then the prop wobbles and the arm vibrates a lot.\"",
		"hint": "Vibration exactly at 1× shaft speed: something is off-centre. Check the shaft with the dial indicator."},
	{"id": "shorted_turns", "motors": ["2212", "57BL"], "title": "Runs hot, weak",
		"complaint": "\"It gets far too hot to touch after a minute and it has less power than the other three motors.\"",
		"hint": "Compare the three lead pairs: the two pairs that share a damaged phase read lower. Inductance drops even more."},
	{"id": "open_phase", "motors": ["2212", "57BL"], "title": "Stutters, won't start",
		"complaint": "\"It just twitches and beeps when I arm it. Sometimes it starts if I flick the prop.\"",
		"hint": "Measure all three lead pairs: two of them read open (OL)."},
	{"id": "ground_fault", "motors": ["2212", "57BL"], "title": "Trips the controller",
		"complaint": "\"The controller shuts down with an over-current / ground fault error a few seconds after start-up.\"",
		"hint": "An insulation tester (megger) between a lead and the frame tells you."},
	{"id": "loose_magnet", "motors": ["2212"], "title": "Rattle",
		"complaint": "\"There's a ticking rattle when I spin it by hand, and it sounds rough under power.\"",
		"hint": "Look inside the bell and use the Gauss meter or viewing film on each magnet."},
	{"id": "demagnetized", "motors": ["2212", "57BL"], "title": "Spins fast but no torque",
		"complaint": "\"After a hot summer flight it spins faster with no load but the drone can barely lift off.\"",
		"hint": "Measure KV with the drill and the scope and compare with the label. Then check the magnets."},
	{"id": "debris", "motors": ["2212"], "title": "Scraping",
		"complaint": "\"Landed in gravel. Now it scrapes and feels gritty when I turn it by hand.\"",
		"hint": "Magnets collect steel grit. Take the bell off and look."},
	{"id": "hall_dead", "motors": ["57BL"], "title": "Jerky start",
		"complaint": "\"The conveyor motor jerks back and forth at start-up, and runs rough at low speed.\"",
		"hint": "Power the Hall sensors with the tester and turn the shaft by hand: every sensor must toggle."},
	{"id": "none", "motors": ["2212", "57BL"], "title": "Customer says it's weak",
		"complaint": "\"I think this motor is weaker than the others. Can you check it?\"",
		"hint": "Measure everything. If it all matches the datasheet, it is fine: say so."},
]


static func job(id: String) -> Dictionary:
	for j: Dictionary in JOBS:
		if j.id == id:
			return j
	return JOBS[0]


static func jobs_for(motor_id: String) -> Array:
	var out: Array = []
	for j: Dictionary in JOBS:
		if (j.motors as Array).has(motor_id):
			out.append(j)
	return out


## Applies a fault to a healthy motor. rng picks the details (which phase, which magnet).
static func apply(state: MotorState, fault: String, rng: RandomNumberGenerator) -> void:
	var outrunner := state.spec.kind == "outrunner"
	var bnames := state.bearing_names()
	match fault:
		"bearing_worn":
			var b: String = bnames[1] if outrunner else bnames[rng.randi_range(0, 1)]
			state.bearings[b].wear = rng.randf_range(0.7, 0.9)
		"bent_shaft":
			state.runout_mm = rng.randf_range(0.09, 0.16)
		"shorted_turns":
			var p := rng.randi_range(0, 2)
			state.shorted[p] = rng.randf_range(0.18, 0.26)
			var teeth: Array[int] = []
			for i in state.coils.size():
				if state.coils[i].phase == p:
					teeth.append(i)
			state.burnt_teeth = [teeth[rng.randi_range(0, teeth.size() - 1)]]
		"open_phase":
			state.open_phase = rng.randi_range(0, 2)
		"ground_fault":
			state.insulation_mohm = rng.randf_range(0.08, 0.6)
			state.burnt_teeth = [rng.randi_range(0, state.spec.slots - 1)]
		"loose_magnet":
			var k := rng.randi_range(0, state.spec.poles - 1)
			state.magnets[k].loose = true
			state.magnets[k].shift = deg_to_rad(rng.randf_range(2.0, 3.5)) * (1 if rng.randf() < 0.5 else -1)
			state.magnets[k].strength = 0.9
		"demagnetized":
			for m: Dictionary in state.magnets:
				m.strength = rng.randf_range(0.76, 0.82)
		"debris":
			state.debris = rng.randi_range(6, 11)
		"hall_dead":
			state.hall_dead = rng.randi_range(0, 2)
	state.rebuild()
