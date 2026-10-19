class_name Vibration
extends RefCounted
## Spectrum analysis of the accelerometer samples: Hann window + radix-2 FFT, the envelope
## (demodulated) spectrum used for bearing faults, and the overall vibration velocity in
## mm/s RMS that ISO 10816 / 20816 severity zones are based on.

## ISO 10816-1 class I (small machines) zone limits, mm/s RMS.
const ZONES := [[0.71, "A  good"], [1.8, "B  acceptable"], [4.5, "C  unsatisfactory"], [INF, "D  unacceptable"]]


## In-place iterative FFT. re and im must have a power-of-two length.
static func fft(re: PackedFloat64Array, im: PackedFloat64Array) -> void:
	var n := re.size()
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var t := re[i]
			re[i] = re[j]
			re[j] = t
			t = im[i]
			im[i] = im[j]
			im[j] = t
	var size := 2
	while size <= n:
		var half := size >> 1
		var ang := -TAU / size
		var wr := cos(ang)
		var wi := sin(ang)
		var start := 0
		while start < n:
			var cr := 1.0
			var ci := 0.0
			for k in half:
				var a := start + k
				var b := a + half
				var tr := re[b] * cr - im[b] * ci
				var ti := re[b] * ci + im[b] * cr
				re[b] = re[a] - tr
				im[b] = im[a] - ti
				re[a] += tr
				im[a] += ti
				var ncr := cr * wr - ci * wi
				ci = cr * wi + ci * wr
				cr = ncr
			start += size
		size <<= 1


## Single-sided amplitude spectrum (same units as the samples, peak) of `samples` sampled at
## `rate`. Returns {"freq": PackedFloat32Array, "amp": PackedFloat32Array, "df": Hz}.
static func spectrum(samples: PackedFloat32Array, rate: float) -> Dictionary:
	var n := 1
	while n * 2 <= samples.size():
		n *= 2
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(n)
	im.resize(n)
	var mean := 0.0
	var off := samples.size() - n
	for i in n:
		mean += samples[off + i]
	mean /= n
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * i / (n - 1))
		re[i] = (samples[off + i] - mean) * w
		im[i] = 0.0
	fft(re, im)
	var freq := PackedFloat32Array()
	var amp := PackedFloat32Array()
	var half := n / 2
	freq.resize(half)
	amp.resize(half)
	for k in half:
		freq[k] = k * rate / n
		amp[k] = 2.0 * sqrt(re[k] * re[k] + im[k] * im[k]) / (n * 0.5)   # Hann coherent gain 0.5
	return {"freq": freq, "amp": amp, "df": rate / n}


## Envelope spectrum: high-pass (> 1 kHz), rectify, smooth, then the spectrum. Repetitive
## impacts (a ball rolling over a spall) show up as lines at their repetition rate.
static func envelope_spectrum(samples: PackedFloat32Array, rate: float) -> Dictionary:
	var env := PackedFloat32Array()
	env.resize(samples.size())
	var hp_prev_x := 0.0
	var hp_prev_y := 0.0
	var rc := 1.0 / (TAU * 1000.0)
	var alpha := rc / (rc + 1.0 / rate)
	var lp := 0.0
	var beta := 1.0 - exp(-TAU * 600.0 / rate)
	for i in samples.size():
		var x := samples[i]
		var y := alpha * (hp_prev_y + x - hp_prev_x)
		hp_prev_x = x
		hp_prev_y = y
		lp += (absf(y) - lp) * beta
		env[i] = lp
	return spectrum(env, rate)


## Overall velocity (mm/s RMS) between f_lo and f_hi from an acceleration spectrum (m/s²).
static func velocity_rms(spec: Dictionary, f_lo := 10.0, f_hi := 1000.0) -> float:
	var freq: PackedFloat32Array = spec.freq
	var amp: PackedFloat32Array = spec.amp
	var sum := 0.0
	for k in freq.size():
		var f := freq[k]
		if f < f_lo or f > f_hi:
			continue
		var v := amp[k] / (TAU * f) * 1000.0     # peak mm/s
		sum += v * v * 0.5
	# Hann window spreads each line over ~1.5 bins: correct the energy
	return sqrt(sum / 1.5)


static func zone(v_rms: float) -> String:
	for z: Array in ZONES:
		if v_rms <= z[0]:
			return z[1]
	return "D  unacceptable"


## Amplitude of the strongest bin within ±tol·f of f.
static func peak_near(spec: Dictionary, f: float, tol := 0.03) -> float:
	var freq: PackedFloat32Array = spec.freq
	var amp: PackedFloat32Array = spec.amp
	var best := 0.0
	var df: float = spec.df
	var lo := int(maxf(f * (1.0 - tol) / df - 1.0, 0.0))
	var hi := mini(int(f * (1.0 + tol) / df + 2.0), freq.size() - 1)
	for k in range(lo, hi + 1):
		best = maxf(best, amp[k])
	return best
