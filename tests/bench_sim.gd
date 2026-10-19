extends SceneTree
## Timing of the drive simulation: godot --headless --path . -s tests/bench_sim.gd

func _init() -> void:
	var t0 := Time.get_ticks_usec()
	var st := MotorState.new(MotorSpec.drone_2212())
	var t1 := Time.get_ticks_usec()
	var sim := DriveSim.new(st)
	var t2 := Time.get_ticks_usec()
	sim.throttle = 1.0
	sim.start()
	for i in 30:
		sim.advance(1.0 / 60.0)
	var t3 := Time.get_ticks_usec()
	print("state %.0f ms, learn %.0f ms, sim %.0f ms per simulated second" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0 / 0.5])
	quit()
