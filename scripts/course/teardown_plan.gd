class_name TeardownPlan
extends RefCounted
## How each motor comes apart and goes back together: which tool each part needs, what
## must come off first, where it lands on the parts tray, and the shop-floor reason for
## each step. Used by the teardown bench (rules, hints) and the autotest (the right order).

const TOOLS := {
	"hand": {"name": "Hands", "icon": "✋"},
	"wrench": {"name": "7 mm wrench", "icon": "🔧"},
	"circlip_pliers": {"name": "Circlip pick", "icon": "🪝"},
	"tweezers": {"name": "Tweezers", "icon": "🥢"},
	"hex_1_5": {"name": "1.5 mm hex key", "icon": "⬡"},
	"hex_3": {"name": "3 mm hex key", "icon": "⬢"},
	"phillips": {"name": "Phillips PH1", "icon": "✚"},
	"mallet": {"name": "Soft mallet", "icon": "🔨"},
	"heat_gun": {"name": "Heat gun", "icon": "🔥"},
	"punch": {"name": "Drift punch", "icon": "📍"},
	"bearing_puller": {"name": "Bearing puller", "icon": "🗜"},
	"arbor_press": {"name": "Arbor press", "icon": "⬇"},
	"soldering_iron": {"name": "Soldering iron", "icon": "🖊"},
}

## Outrunner: part -> {tool, needs (must be off first), verb, why, tray (mm offset),
## put (tool to put back), sits_on (must be in place before it goes back)}.
const OUTRUNNER := {
	"prop_adapter": {"tool": "wrench", "needs": [], "tray": Vector3(70, -8, 30),
		"verb": "Undo the prop nut and slide the collet off the shaft.",
		"why": "The collet clamps the prop; it hides nothing but must come off before the shaft can move.",
		"put": "wrench", "sits_on": ["bell"]},
	"circlip": {"tool": "circlip_pliers", "needs": [], "tray": Vector3(70, 6, 52),
		"verb": "Flip the motor and pick the E-clip off the shaft under the base.",
		"why": "The clip is the only thing stopping the magnets pulling the bell off the shaft... and holding it on.",
		"put": "circlip_pliers", "sits_on": ["bell"]},
	"shim": {"tool": "tweezers", "needs": ["circlip"], "tray": Vector3(86, 6, 52),
		"verb": "Lift the thin shim washer off the shaft. Keep it: it sets the end play.",
		"why": "Shims take up the axial play between the bell and the bottom bearing. Lose it and the bell clicks up and down.",
		"put": "tweezers", "sits_on": ["bell"]},
	"bell": {"tool": "hand", "needs": ["circlip", "shim"], "tray": Vector3(100, -6, -10),
		"verb": "Pull the bell straight up. The magnets pull back hard (about 2 kg): don't let it snap back.",
		"why": "The rotor bell carries the magnets and the shaft; once it's off you can see the windings.",
		"put": "hand", "sits_on": ["stator", "bearing_top", "bearing_bottom"]},
	"grub_screw": {"tool": "hex_1_5", "needs": ["bell"], "tray": Vector3(118, 6, 40),
		"verb": "Warm the hub, then back the grub screw out (it is threadlocked).",
		"why": "Only needed to change the shaft: the grub screw locks the shaft in the bell's hub.",
		"put": "hex_1_5", "sits_on": []},
	"stator": {"tool": "heat_gun", "needs": ["bell"], "tray": Vector3(55, -6, -60),
		"verb": "Heat the stator to about 120 °C to soften the retaining compound, then push it off the bearing tube.",
		"why": "Hobby stators are glued onto the base. Prying cold cracks the laminations' varnish.",
		"put": "hand", "sits_on": []},
	"bearing_top": {"tool": "punch", "needs": ["bell"], "tray": Vector3(130, 6, 0),
		"verb": "Drive the top bearing out from below with the drift punch, tapping around its outer ring.",
		"why": "Bearings sit in the base tube with a light press fit.",
		"put": "arbor_press", "sits_on": []},
	"bearing_bottom": {"tool": "punch", "needs": ["bell"], "tray": Vector3(130, 6, 20),
		"verb": "Drive the bottom bearing out from above.",
		"why": "Same fit as the top one; change bearings in pairs.",
		"put": "arbor_press", "sits_on": []},
}

const INRUNNER := {
	"bolts": {"tool": "hex_3", "needs": [], "tray": Vector3(110, -20, 50),
		"verb": "Undo the four long through-bolts (3 mm hex).",
		"why": "The bolts clamp both end caps to the housing; they are the only fasteners.",
		"put": "hex_3", "sits_on": ["front_cap", "rear_cap"]},
	"rear_cap": {"tool": "mallet", "needs": ["bolts"], "tray": Vector3(110, -20, -30),
		"verb": "Tap the rear cap off with the soft mallet, evenly around the edge.",
		"why": "The cap is a press fit on the rear bearing; a steel hammer would dent it.",
		"put": "mallet", "sits_on": ["rotor", "hall_board"]},
	"wave_washer": {"tool": "tweezers", "needs": ["rear_cap"], "tray": Vector3(150, -20, 10),
		"verb": "Lift out the wave spring washer.",
		"why": "It preloads the bearings so the balls don't skid. Forget it and the motor hums and wears fast.",
		"put": "tweezers", "sits_on": ["rotor"]},
	"hall_board": {"tool": "phillips", "needs": ["rear_cap"], "tray": Vector3(150, -20, -40),
		"verb": "Unscrew the Hall board and fold it aside with its cable.",
		"why": "The three Hall sensors tell the drive where the rotor is. Mark the board's angle before removing it.",
		"put": "phillips", "sits_on": ["rotor"]},
	"front_cap": {"tool": "mallet", "needs": ["bolts"], "tray": Vector3(-90, -20, 40),
		"verb": "Tap the front flange off.",
		"why": "The front bearing stays on the shaft.",
		"put": "mallet", "sits_on": ["rotor"]},
	"rotor": {"tool": "hand", "needs": ["rear_cap", "front_cap", "hall_board"], "tray": Vector3(-100, -20, -50),
		"verb": "Pull the rotor out of the stator. Keep it centred: the magnets grab the stator teeth.",
		"why": "With the rotor out you can see the winding and the magnets.",
		"put": "hand", "sits_on": ["bearing_front", "bearing_rear"]},
	"bearing_front": {"tool": "bearing_puller", "needs": ["rotor"], "tray": Vector3(-150, -20, -10),
		"verb": "Pull the front bearing off the shaft with the puller (jaws behind the inner ring).",
		"why": "Pulling on the outer ring would load the balls and ruin the bearing.",
		"put": "arbor_press", "sits_on": []},
	"bearing_rear": {"tool": "bearing_puller", "needs": ["rotor"], "tray": Vector3(-150, -20, 20),
		"verb": "Pull the rear bearing off the shaft.",
		"why": "Change bearings in pairs.",
		"put": "arbor_press", "sits_on": []},
}


static func plan(spec: MotorSpec) -> Dictionary:
	return OUTRUNNER if spec.kind == "outrunner" else INRUNNER


## The order a careful technician takes the motor apart (full teardown).
static func order(spec: MotorSpec) -> Array:
	if spec.kind == "outrunner":
		return ["prop_adapter", "circlip", "shim", "bell", "bearing_top", "bearing_bottom", "stator"]
	return ["bolts", "rear_cap", "wave_washer", "hall_board", "front_cap", "rotor", "bearing_front", "bearing_rear"]


## Parts that are inner bearings riding on the rotor's shaft (inrunner).
static func rides_on_rotor(spec: MotorSpec, id: String) -> bool:
	return spec.kind != "outrunner" and (id == "bearing_front" or id == "bearing_rear")


## Which way to press a bearing: onto a shaft = push the inner ring; into a bore = outer.
static func press_ring(spec: MotorSpec) -> String:
	return "outer" if spec.kind == "outrunner" else "inner"


## Short explanation of why a tool doesn't fit the job.
static func wrong_tool(tool: String, part: String) -> String:
	match tool:
		"hand":
			return "It won't come off by hand: it's fastened or pressed in."
		"heat_gun":
			return "Heat isn't needed here, and it can demagnetise magnets above ~150 °C."
		"mallet", "punch":
			return "Hitting it would damage it. Use the tool made for this fastener."
		"bearing_puller", "arbor_press":
			return "This is not a press fit."
		"soldering_iron":
			return "Nothing is soldered here."
	return "%s doesn't fit the %s." % [TOOLS.get(tool, {"name": tool}).name, part.replace("_", " ")]
