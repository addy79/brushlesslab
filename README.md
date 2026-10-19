# Brushless Lab: reverse-engineer and service brushless motors in VR

A Godot 4.7 VR app (Meta Quest, plus a full desktop mode) for learning how brushless (BLDC) motors are built, how to work out an unknown motor's design, and how to find and repair the faults that real motors come back with. You work at a six-bench workshop: take the motor apart with the right tools, measure it, inspect it, repair or rewind it, and prove the repair on a test stand.

It is a **training simulator, not a design tool**. The physics is computed rather than scripted, but its constants are typical values, not measurements of real motors. See [Where do the numbers come from?](#where-do-the-numbers-come-from) and [Status and limits](#status-and-limits).

## At a glance

| | |
|---|---|
| Language / engine | GDScript, Godot 4.7.2 (Forward+ on desktop, Mobile on Quest, OpenXR) |
| Platforms | Linux desktop (`BrushlessLab.x86_64` in this folder, mouse and keyboard); Meta Quest (Android export preset `Quest`) |
| Motors | **Drone outrunner 2212‑920KV** (12 teeth, 14 magnets, sensorless); **industrial inrunner 57BL‑24V** (190 KV, Hall sensors, 608 bearings); **mystery outrunners** generated from a seed (10 real slot/pole combinations, star or delta, random KV and size) |
| Jobs | **Reverse-engineer** a mystery motor (slots, poles, winding layout, connection, KV, resistance, stator size); **Service** a customer's motor with one of 9 hidden faults (or none); **Free lab** |
| Faults | Worn bearing, bent shaft, shorted turns, open phase, insulation fault to the frame, loose magnet, demagnetised magnets, metal debris, dead Hall sensor |
| Benches | 1 Job Desk · 2 Teardown · 3 Electrical · 4 Inspect & Repair · 5 Winding · 6 Test Stand |
| Grading | Datasheet fields against the hidden design (reverse); diagnosis 40 + repair 40 + final test 20 (service); −3 per workshop mistake (wrong tool, bearing pressed on the wrong ring, shim left out, magnet glued the wrong way round, bad rewind), at most −20 |
| Tests | `godot --headless --path . -s tests/model_test.gd` (physics, 70 checks) and `godot --path . -- --autotest` (whole app, windowed, 60 checks, writes `screenshots/`) |
| Slides | `docs/slides/BrushlessLab-slides.odp` (animated, 16 slides) and a PDF copy; regenerate with `python3 docs/slides/make_slides.py` after a new autotest. Also in `~/VR APPs/VR apps proposals /odp/BrushlessLab_proposal.odp` |

## How to run it

**Desktop (Linux):** double-click or run `./BrushlessLab.x86_64` from this folder. Keep `libgodotopenxrvendors.so` next to it. Without a headset it starts in desktop mode.

**From the source:** `godot --path .` (Godot 4.7.2). Open the project in the editor to change it.

**Quest:** a debug build is in `build/brushlesslab-quest.apk` (about 90 MB). Install it with `adb install -r build/brushlesslab-quest.apk` while the headset is plugged in, then open *Brushless Lab* from Unknown Sources. To rebuild it: `godot --headless --path . --export-debug "Quest" build/brushlesslab-quest.apk` (needs JDK 17, the Android SDK and Godot's Android build template, which is in `android/`).

Command-line options (after `--`): `--station=N`, `--mode=reverse|service|free`, `--motor=2212|57BL|mystery`, `--fault=ID`, `--seed=N`, `--expert` (no hints), `--xr-preview` (shows the VR panel layout on the desktop), `--autotest`.

### Controls

| Desktop | VR (Quest controllers) |
|---|---|
| Left-click: parts, tools, buttons | Trigger: point and press |
| Hold right mouse button: look around | Left stick: walk |
| W A S D move (physical keys, so Z Q S D on AZERTY), Q/E down/up, Shift faster | Right stick: snap turn and fly |
| 1–6: go to a bench, R: reset the view | A/X: next bench, B/Y: previous bench |
| H: help card, F1: toggle VR, F12: screenshot | |

## A job, bench by bench

1. **Job Desk.** Pick a job and read the customer's ticket ("Grinding noise", "Wobble after a crash", "Runs hot, weak", "Trips the controller"...). Fill in the datasheet or the diagnosis, then hand in the report. Everything you measure lands in the **notebook** (bottom left), and the report uses it.
2. **Teardown.** Pick a tool from the rack and click a part. A part only comes off if nothing still holds it and the tool fits (circlip pliers for the circlip, a hex key for grub screws, a bearing puller or press for bearings). Parts go to the tray in order; click them again to fit them back. Hand checks give the feel a technician relies on: turn the shaft (cogging notches, grinding, scraping), spin and rock each bearing.
3. **Electrical.** Resistance of each lead pair with a 4-wire milliohm meter (or a normal multimeter, which shows why that's useless at 0.1 Ω), inductance with an LCR meter at 1 kHz, insulation to the frame with a 500 V tester, back-EMF with a drill and an oscilloscope (gives KV and the pole count), and a Hall sensor tester on the 57BL.
4. **Inspect & Repair.** With the motor open: count teeth and magnets, measure the stator with calipers, trace each coil's phase and direction, read the lead joints (star or delta), check every magnet with a Gauss meter or magnetic viewing film, measure shaft runout with a dial indicator, look for burnt coils and debris. Repairs: new bearings (pressed on the right ring), a new shaft, re-glue a magnet (the right way round) or fit a new bell or rotor with fresh magnets, clean debris off the magnets, re-solder the lead joints, a new Hall sensor. Burnt or shorted windings go to the winding bench.
5. **Winding.** With the stator stripped, choose a letter (A, B, C = clockwise, a, b, c = counter-clockwise) and click teeth to wind them. The phasor star shows each coil's back-EMF phasor and the three phase sums, which must come out equal and 120° apart. Turns per tooth and star/delta set the KV: copy the original or the motor comes back with a different KV.
6. **Test Stand.** The motor on a thrust/torque stand, driven by a six-step ESC. Live speed, current, power and efficiency, thrust (propeller) or torque (dynamometer brake), winding temperature, the oscilloscope on lead A, the vibration spectrum with shaft and bearing markers, the envelope spectrum, the ISO 10816 zone, and the motor's sound. The **final test** (full throttle, no load, 3 s) must pass: it starts and runs, no-load speed within −7 %…+12 % of KV × V, low no-load current, vibration zone A or B, cool winding, balanced lead resistances, smooth hand spin, insulation above 100 MΩ.

**Guided** mode shows the next step and the hints; **Expert** mode hides them.

## Where do the numbers come from?

Every reading is **computed from the motor's design and condition**. Nothing is a recorded clip or a scripted symptom. A fault changes the motor's state (a bearing's wear, a magnet's strength, the turns shorted in one phase...), and every instrument then reads from that state. So a demagnetised motor really does spin faster with less torque, and a shorted phase really does read low on two lead pairs.

| What | How it is computed | Source of the constants |
|---|---|---|
| Winding layouts | Star-of-slots method (`scripts/motor/winding.gd`): tooth *i* sees the rotor field shifted by *i*·(P/2)·360°/Q electrical; each phase takes the teeth in its two opposite 60° sectors. Winding factor from the phasor sums | Standard textbook method; tested against known layouts (12N14P dLRK `AabBCcaABbcC`, kw 0.933, and 9 other combinations) |
| Back-EMF and torque | Air-gap flux model (`magnetics.gd`): each magnet is a soft-edged arc of field; tooth flux is the integral over the tooth face; phase flux linkage λ(θ) sums the coils; e = (dλ/dθ)·ω, tabulated over one turn | Shape constants (magnet arc 0.86, tooth face 0.82 of the pitch, edge softness) are typical; the overall scale is **calibrated once so the healthy motor's peak line EMF matches its rated KV** |
| Resistance, inductance | Copper resistance from turns, wire size and temperature (0.393 %/°C); inductance per pair; shorted turns and open joints change them | 2212: 105 mΩ, 34 µH (typical datasheet values for this size); 57BL from typical 57 mm BLDC datasheets |
| Drive and test stand | Time-domain simulation (`drive_sim.gd`): six-step ESC, two leads driven, V·d = R·i + L·di/dt + e solved exactly every 20 µs, free-wheel diodes, current limit, battery sag. Sensorless start ramp and closed-loop back-EMF zero crossings, or Hall sensors. J·dω/dt = torque − friction − cogging − load − shorted-turn drag | Prop torque and thrust coefficients sized for a 10×4.5 prop (about 900 g at full throttle on 3S); friction, inertia and ESC behaviour are typical, hand-tuned values |
| Heating | One lumped winding temperature: copper and iron loss in, speed-dependent cooling out | Thermal resistance and capacity are estimates |
| Vibration | Accelerometer signal at 10 kHz: unbalance and runout (1×, 2×), bearing defect impacts at BPFO/BPFI that ring a 2.9 kHz resonance, torque ripple, magnet knocks, debris. Hann-window FFT, envelope (demodulated) spectrum, velocity RMS in mm/s | Bearing defect frequencies from the real ball count and diameters (693ZZ, 608ZZ...); severity zones from ISO 10816-1 class I; amplitudes tuned so a healthy motor lands in zone A/B and a bent shaft in zone D |
| Mystery motors | A seed picks a real slot/pole combination, size, turns, star/delta; KV and resistance follow from the turns and size, scaled from the 2212, with ±5–8 % spread | Generated, not real products |

The physics test (`tests/model_test.gd`) checks these against the expected engineering results: KV from the back-EMF = 920, 14 EMF zero crossings per turn on a 14-magnet motor, 84 cogging steps on 12N14P, no-load speed ≈ KV × V, prop load 550–1000 g thrust at 60–92 % efficiency, a bent shaft in zone D, a worn bearing's BPFO line in the envelope spectrum, shorted turns heating up, an open phase failing to run, a ground fault tripping the controller, the 57BL at 4,560 rpm, and a dead Hall sensor running rough.

### Fast model on the headset

The detailed drive simulation takes about 125 ms of desktop CPU per simulated second, and the Quest's CPU is several times slower. So the test stand on the Quest starts in a **fast model**: 100 µs steps, and the ESC is assumed to commutate exactly where its zero-crossing detector would, instead of modelling the detector. It is about 3× cheaper (about 45 ms per simulated second on desktop) and gives the same results within a few per cent (no-load speed within 3 %, prop speed within 4 %, current within 8 %, and the same fault signatures). The physics test and the autotest check that the two models agree. On any device the simulation also runs within a time budget per frame. If the computer still can't keep up, it runs in slow motion and says so, and a desktop that falls behind switches to the fast model by itself. There's a **Fast simulation** switch on the test stand.

## How it was built

- **Engine and language:** Godot 4.7.2, all GDScript, no external assets. Every 3D part (laminations, coils as actually wound, magnets, bearings, shaft, fasteners, tools and benches) is built in code from the motor's design (`scripts/build/`). This is why a rewound or damaged motor looks the way it is.
- **Structure:** `scripts/motor/` (design, state, winding, flux, drive simulation, faults, vibration), `scripts/course/` (session, jobs, grading, teardown order per motor), `scripts/stations/` (the six benches), `scripts/ui/` (desktop HUD and drawer, VR panels drawn from the same 2D interface), `scripts/core/` (XR and desktop input, grabbing, haptics, sound).
- **VR:** OpenXR with the Godot OpenXR Vendors plugin. Each bench's panel is a 2D interface in a SubViewport on a 3D panel next to the bench, and the controller laser acts as the mouse.
- **Testing:** the physics test runs headless. The autotest plays complete jobs through the real interface (service a worn bearing, rewind a motor, reverse-engineer a mystery motor, replace a Hall sensor on the 57BL, make deliberate mistakes, check that unrepaired motors fail the final test) and saves screenshots of every bench.

## Status and limits

- Tested on desktop (Linux). **Not yet tested on a Quest headset.** The VR layout has only been checked with `--xr-preview`, and the fast model's real-time speed on the Quest is estimated, not measured.
- The ESC is six-step (trapezoidal) only, with no field-oriented control (FOC).
- Constants are typical values for these motor sizes. They were not fitted to measurements of a real motor, so treat absolute numbers (exact amps, grams, degrees) as realistic in size, not exact.
- One fault per service job. Real returns sometimes have two.
