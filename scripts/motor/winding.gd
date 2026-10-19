class_name Winding
extends RefCounted
## Concentrated (one coil per tooth) three-phase windings.
##
## A winding is an Array of coils, one per tooth: {"phase": 0|1|2, "sign": +1|-1, "turns": n}.
## As text it is the usual hobby notation, one letter per tooth: A B C = wound clockwise
## (seen from the open end of the tooth), a b c = counter-clockwise. "AabBCcaABbcC" is the
## classic 12N14P dLRK layout.
##
## design() finds the best layout for any slot/pole combination with the star-of-slots
## method: tooth i sees the rotor's field shifted by i·(P/2)·360°/Q electrical degrees;
## each phase takes the teeth whose phasors fall into its two opposite 60° sectors.

const LETTERS := ["A", "B", "C"]


## Electrical angle (degrees, 0..360) of tooth i's EMF phasor.
static func tooth_angle(i: int, slots: int, poles: int) -> float:
	return fposmod(float(i) * (poles / 2) * 360.0 / slots, 360.0)


## Best balanced layout for Q slots and P poles, or [] if the combination can't carry a
## balanced 3-phase winding.
static func design(slots: int, poles: int, turns := 1) -> Array:
	if slots % 3 != 0 or poles % 2 != 0 or slots <= 0:
		return []
	var best: Array = []
	var best_score := -1.0
	# Try sector offsets; keep the one that is balanced with the highest winding factor.
	var offset := 0.0
	while offset < 60.0:
		var coils: Array = []
		var counts := [0, 0, 0]
		for i in slots:
			var a := fposmod(tooth_angle(i, slots, poles) - offset, 360.0)
			var sector := int(floor(a / 60.0)) % 6
			# sectors: 0 A+, 1 B-, 2 C+, 3 A-, 4 B+, 5 C-  (phase B leads A by 240°)
			var phase: int = [0, 1, 2, 0, 1, 2][sector]
			var sign: int = [1, -1, 1, -1, 1, -1][sector]
			coils.append({"phase": phase, "sign": sign, "turns": turns})
			counts[phase] += 1
		if counts[0] == counts[1] and counts[1] == counts[2]:
			var kw := winding_factor(coils, slots, poles)
			if kw > best_score + 1e-6:
				best_score = kw
				best = coils
		offset += 2.5
	return best


## Fundamental winding factor of phase A (0..1): distribution factor |Σ signed phasors| /
## number of coils, times the pitch factor of a coil around one tooth, sin(180°·(P/2)/Q).
static func winding_factor(coils: Array, slots: int, poles: int) -> float:
	var sum := Vector2.ZERO
	var n := 0
	for i in coils.size():
		var c: Dictionary = coils[i]
		if c.phase != 0 or c.turns == 0:
			continue
		var a := deg_to_rad(tooth_angle(i, slots, poles))
		sum += Vector2(cos(a), sin(a)) * c.sign
		n += 1
	var kp := absf(sin(PI * (poles / 2) / float(slots)))
	return sum.length() / n * kp if n > 0 else 0.0


static func to_text(coils: Array) -> String:
	var s := ""
	for c: Dictionary in coils:
		var l: String = LETTERS[c.phase]
		s += l if c.sign > 0 else l.to_lower()
	return s


## Like to_text, with "·" for teeth that are not wound (turns = 0).
static func to_text_partial(coils: Array) -> String:
	var s := ""
	for c: Dictionary in coils:
		if c.turns <= 0:
			s += "·"
			continue
		var l: String = LETTERS[c.phase]
		s += l if c.sign > 0 else l.to_lower()
	return s


static func from_text(text: String, turns := 1) -> Array:
	var coils: Array = []
	for ch in text.strip_edges():
		var up := ch.to_upper()
		var phase := LETTERS.find(up)
		if phase < 0:
			return []
		coils.append({"phase": phase, "sign": 1 if ch == up else -1, "turns": turns})
	return coils


## True when `guess` describes the same motor as `truth`: the same layout up to renaming
## the leads, swapping all directions, starting on another tooth, or reading the teeth in
## the other direction (all of which a reverse engineer cannot or need not tell apart).
static func equivalent(guess: String, truth: String) -> bool:
	guess = guess.strip_edges()
	truth = truth.strip_edges()
	if guess.length() != truth.length() or guess.is_empty():
		return false
	var t := from_text(truth)
	var g := from_text(guess)
	if t.is_empty() or g.is_empty():
		return false
	var n := t.size()
	var perms := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	for reverse in [false, true]:
		for shift in n:
			for perm: Array in perms:
				for flip in [1, -1]:
					var ok := true
					for i in n:
						var j := (shift + (n - i if reverse else i)) % n
						var tc: Dictionary = t[j]
						var gc: Dictionary = g[i]
						if gc.phase != perm[tc.phase] or gc.sign != tc.sign * flip:
							ok = false
							break
					if ok:
						return true
	return false


## Problems with a (re)wound layout, as short sentences; empty when it is a working winding.
static func check(coils: Array, slots: int, poles: int) -> Array[String]:
	var issues: Array[String] = []
	if coils.size() != slots:
		issues.append("%d of %d teeth are wound" % [coils.size(), slots])
		return issues
	var counts := [0, 0, 0]
	var turn_set := {}
	for c: Dictionary in coils:
		if c.turns <= 0:
			continue
		counts[c.phase] += 1
		turn_set[c.turns] = true
	if counts[0] != counts[1] or counts[1] != counts[2]:
		issues.append("phases are unbalanced (A %d, B %d, C %d coils)" % counts)
	if turn_set.size() > 1:
		issues.append("teeth have different turn counts")
	var kw := winding_factor(coils, slots, poles)
	if kw < 0.8:
		issues.append("coil directions fight each other (winding factor %.2f)" % kw)
	# The three phases must be 120° apart (electrically).
	var ph: Array[Vector2] = []
	for p in 3:
		var v := Vector2.ZERO
		for i in coils.size():
			var c: Dictionary = coils[i]
			if c.phase == p and c.turns > 0:
				var a := deg_to_rad(tooth_angle(i, slots, poles))
				v += Vector2(cos(a), sin(a)) * c.sign
		ph.append(v)
	if ph[0].length() > 0.01 and ph[1].length() > 0.01 and ph[2].length() > 0.01:
		for p in 3:
			var ang := rad_to_deg(absf(ph[p].angle_to(ph[(p + 1) % 3])))
			if absf(ang - 120.0) > 15.0:
				issues.append("phases are not 120° apart (%s→%s: %.0f°)" % [LETTERS[p], LETTERS[(p + 1) % 3], ang])
				break
	return issues
