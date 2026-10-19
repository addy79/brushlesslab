class_name Haptics
extends Node
## Controller vibration (OpenXR "haptic" action) for physical moments: a fist
## on the table, a phone buzzing in the room, the last seconds of a countdown.
## On the desktop nothing vibrates; `history` records what would have.

const PATTERNS := {
	"thump": [[0.0, 1.0, 0.12, 0.0], [0.0, 0.4, 0.1, 0.14]],
	"phone": [[160.0, 0.5, 0.35, 0.0], [160.0, 0.5, 0.35, 0.5]],
	"tick": [[0.0, 0.25, 0.02, 0.0]],
	"click": [[0.0, 0.3, 0.02, 0.0]],
}

var left: XRController3D
var right: XRController3D
var enabled := true
var history: Array[String] = []


func play(pattern: String, hands := "both") -> void:
	if not enabled or not PATTERNS.has(pattern):
		return
	history.append(pattern)
	if history.size() > 50:
		history.pop_front()
	for ctrl: XRController3D in [left, right]:
		if ctrl == null or not ctrl.get_is_active():
			continue
		if hands != "both" and (hands == "left") != (ctrl == left):
			continue
		for p: Array in PATTERNS[pattern]:
			ctrl.trigger_haptic_pulse("haptic", p[0], p[1], p[2], p[3])
