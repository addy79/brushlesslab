#!/usr/bin/env python3
"""Builds BrushlessLab-slides.odp: a native OpenDocument presentation with
slide transitions and an entrance animation on every element (they play
automatically, one after another, when a slide appears)."""
import os
import sys
import zipfile
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "img")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "BrushlessLab-slides.odp")

W, H = 28.0, 15.75
BG = "#16181d"
PANEL = "#1f232b"
PANEL2 = "#272c36"
AMBER = "#e8955a"
BLUE = "#4fc3c9"
GREEN = "#7fd18b"
ROSE = "#ef8fa0"
LILAC = "#b9a2f0"
TEXT = "#e8ecf4"
MUTED = "#a3abb8"
FONT = "Noto Sans"

# --- styles collected while building -----------------------------------------------------------------
para_styles = {}   # key -> name
gr_styles = {}
images = []


def pstyle(size, color=TEXT, bold=False, align="start", italic=False, space_after=0.15, indent=0.0, line=110):
    key = (size, color, bold, align, italic, space_after, indent, line)
    if key not in para_styles:
        para_styles[key] = "P%d" % (len(para_styles) + 1)
    return para_styles[key]


def gstyle(fill="none", stroke="none", stroke_color="#000000", stroke_w=0.0, valign="top", pad=0.1, arrow=False, shadow=False):
    key = (fill, stroke, stroke_color, stroke_w, valign, pad, arrow, shadow)
    if key not in gr_styles:
        gr_styles[key] = "gr%d" % (len(gr_styles) + 1)
    return gr_styles[key]


class Slide:
    def __init__(self, transition=("fade", "crossfade")):
        self.shapes = []
        self.anims = []      # (ids, effect, delay)
        self.n = 0
        self.transition = transition
        self.notes = ""

    def _id(self):
        self.n += 1
        return "s%d_%d" % (id(self) % 100000, self.n)

    def animate(self, ids, effect="fade", delay=0.0, dur=0.6):
        if isinstance(ids, str):
            ids = [ids]
        self.anims.append((ids, effect, delay, dur))

    # paragraphs: list of (text, style-name) or plain strings with a default style
    def text(self, x, y, w, h, paras, style=None, valign="top", fill="none", anim=None, delay=0.0):
        sid = self._id()
        st = gstyle(fill=fill, valign=valign, pad=0.15 if fill != "none" else 0.05)
        body = ""
        for p in paras:
            if isinstance(p, str):
                p = (p, style)
            body += '<text:p text:style-name="%s">%s</text:p>' % (p[1], fmt(p[0]))
        self.shapes.append('<draw:frame draw:style-name="%s" draw:layer="layout" svg:width="%.2fcm" svg:height="%.2fcm" svg:x="%.2fcm" svg:y="%.2fcm" draw:id="%s" xml:id="%s"><draw:text-box>%s</draw:text-box></draw:frame>'
                           % (st, w, h, x, y, sid, sid, body))
        if anim:
            self.animate(sid, anim, delay)
        return sid

    def card(self, x, y, w, h, paras, fill=PANEL, radius=0.35, style=None, valign="top", anim=None, delay=0.0, stroke=None):
        """A rounded background with a text box on top (text in a shape doesn't wrap in every viewer)."""
        rid = self._id()
        st = gstyle(fill=fill, stroke="solid" if stroke else "none", stroke_color=stroke or "#000000", stroke_w=0.06)
        self.shapes.append('<draw:rect draw:style-name="%s" draw:layer="layout" svg:width="%.2fcm" svg:height="%.2fcm" svg:x="%.2fcm" svg:y="%.2fcm" draw:corner-radius="%.2fcm" draw:id="%s" xml:id="%s"/>'
                           % (st, w, h, x, y, radius, rid, rid))
        ids = [rid]
        if paras:
            tid = self._id()
            tst = gstyle(valign=valign, pad=0.35)
            body = ""
            for p in paras:
                if isinstance(p, str):
                    p = (p, style)
                body += '<text:p text:style-name="%s">%s</text:p>' % (p[1], fmt(p[0]))
            self.shapes.append('<draw:frame draw:style-name="%s" draw:layer="layout" svg:width="%.2fcm" svg:height="%.2fcm" svg:x="%.2fcm" svg:y="%.2fcm" draw:id="%s" xml:id="%s"><draw:text-box>%s</draw:text-box></draw:frame>'
                               % (tst, w, h, x, y, tid, tid, body))
            ids.append(tid)
        if anim:
            self.animate(ids, anim, delay)
        return rid

    def circle(self, x, y, d, fill, anim=None, delay=0.0):
        sid = self._id()
        st = gstyle(fill=fill)
        self.shapes.append('<draw:ellipse draw:style-name="%s" draw:layer="layout" svg:width="%.2fcm" svg:height="%.2fcm" svg:x="%.2fcm" svg:y="%.2fcm" draw:id="%s" xml:id="%s"/>'
                           % (st, d, d, x, y, sid, sid))
        if anim:
            self.animate(sid, anim, delay)
        return sid

    def image(self, x, y, w, h, name, anim=None, delay=0.0, border=None):
        sid = self._id()
        if name not in images:
            images.append(name)
        st = gstyle(stroke="solid" if border else "none", stroke_color=border or "#000000", stroke_w=0.05)
        self.shapes.append('<draw:frame draw:style-name="%s" draw:layer="layout" svg:width="%.2fcm" svg:height="%.2fcm" svg:x="%.2fcm" svg:y="%.2fcm" draw:id="%s" xml:id="%s"><draw:image xlink:href="Pictures/%s" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/></draw:frame>'
                           % (st, w, h, x, y, sid, sid, name))
        if anim:
            self.animate(sid, anim, delay)
        return sid

    def arrow(self, x1, y1, x2, y2, color=MUTED, anim=None, delay=0.0):
        sid = self._id()
        st = gstyle(stroke="solid", stroke_color=color, stroke_w=0.07, arrow=True)
        self.shapes.append('<draw:line draw:style-name="%s" draw:layer="layout" svg:x1="%.2fcm" svg:y1="%.2fcm" svg:x2="%.2fcm" svg:y2="%.2fcm" draw:id="%s" xml:id="%s"/>'
                           % (st, x1, y1, x2, y2, sid, sid))
        if anim:
            self.animate(sid, anim, delay)
        return sid

    def bar(self, x, y, w, h, fill, anim=None, delay=0.0):
        return self.card(x, y, w, h, [], fill=fill, radius=0.0, anim=anim, delay=delay)


def fmt(s):
    """**bold** spans; everything else escaped."""
    out = ""
    parts = s.split("**")
    for i, part in enumerate(parts):
        e = escape(part)
        out += '<text:span text:style-name="Tb">%s</text:span>' % e if i % 2 == 1 else e
    return out


# --- animation XML ------------------------------------------------------------------------------------

EFFECTS = {
    "fade": ("ooo-entrance-fade-in", "", lambda t, d: '<anim:transitionFilter smil:dur="%ss" smil:targetElement="%s" smil:type="fade" smil:subtype="crossfade"/>' % (d, t)),
    "wipe": ("ooo-entrance-wipe", ' presentation:preset-sub-type="from-left"', lambda t, d: '<anim:transitionFilter smil:dur="%ss" smil:targetElement="%s" smil:type="barWipe" smil:subtype="leftToRight"/>' % (d, t)),
    "rise": ("ooo-entrance-fly-in", ' presentation:preset-sub-type="from-bottom"', lambda t, d:
             '<anim:animate smil:dur="%ss" smil:fill="hold" smil:targetElement="%s" smil:attributeName="x" smil:values="x;x" smil:keyTimes="0;1" presentation:additive="base"/>'
             '<anim:animate smil:dur="%ss" smil:fill="hold" smil:targetElement="%s" smil:attributeName="y" smil:values="1+height/2;y" smil:keyTimes="0;1" presentation:additive="base"/>' % (d, t, d, t)),
    "zoom": ("ooo-entrance-zoom", ' presentation:preset-sub-type="in"', lambda t, d:
             '<anim:animateTransform smil:dur="%ss" smil:fill="hold" smil:targetElement="%s" smil:from="0,0" smil:to="1,1" svg:type="scale"/>' % (d, t)),
}


def timing(slide):
    if not slide.anims:
        return ""
    t = 0.0
    groups = ""
    for ids, effect, delay, dur in slide.anims:
        preset, sub, body = EFFECTS[effect]
        inner = ""
        for i, tid in enumerate(ids):
            node = "after-previous" if i == 0 else "with-previous"
            inner += ('<anim:par smil:begin="0s" smil:fill="hold" presentation:node-type="%s" presentation:preset-class="entrance" presentation:preset-id="%s"%s>'
                      '<anim:set smil:begin="0s" smil:dur="0.001s" smil:fill="hold" smil:targetElement="%s" smil:attributeName="visibility" smil:to="visible"/>%s</anim:par>'
                      % (node, preset, sub, tid, body(tid, dur)))
        groups += '<anim:par smil:begin="%.2fs">%s</anim:par>' % (t + delay, inner)
        t += delay + dur * 0.55   # the next one starts while this one is finishing
    return ('<anim:par presentation:node-type="timing-root"><anim:seq presentation:node-type="main-sequence">'
            '<anim:par smil:begin="0s">%s</anim:par></anim:seq></anim:par>' % groups)


# --- the deck ---------------------------------------------------------------------------------------------

SHOTS = os.path.join(HERE, "..", "..", "screenshots")
SHOT_W, SHOT_H = 941, 1050
slides = []


def shot(name):
    """Copies a screenshot from the app's autotest into img/ (so the deck is rebuilt from fresh ones)."""
    import shutil
    os.makedirs(IMG, exist_ok=True)
    shutil.copy(os.path.join(SHOTS, name), os.path.join(IMG, name))
    return name


def heading(s, title, kicker=None, color=AMBER, w=25):
    if kicker:
        s.text(1.4, 0.75, w, 0.7, [kicker], style=pstyle(12, color, True), anim="fade")
    s.text(1.4, 1.25, w, 1.4, [title], style=pstyle(28, TEXT, True), anim="wipe")
    s.bar(1.45, 2.65, 2.2, 0.09, color, anim="wipe", delay=0.0)


def bullets(items, size=15, color=TEXT, after=0.25):
    st = pstyle(size, color, False, space_after=after, indent=0.55)
    return [("•  " + i, st) for i in items]


def bench_slide(number, title, color, image, items, takeaway):
    """Text on the left, the app's screenshot of that bench on the right."""
    s = Slide(("pushWipe", "fromRight"))
    heading(s, title, "BENCH %d" % number, color=color, w=13.5)
    h = 13.6
    w = h * SHOT_W / SHOT_H
    s.image(28.0 - w - 0.8, 1.05, w, h, shot(image), anim="fade", border="#33384a")
    s.text(1.4, 3.3, 13.6, 8.6, bullets(items, size=14.5, after=0.3), anim="rise")
    s.card(1.4, 12.0, 13.4, 2.6, [(takeaway, pstyle(13.5, color, line=118))], anim="zoom", delay=0.1)
    slides.append(s)


# 1 Title
s = Slide(("fade", "fadeOverColor"))
s.circle(19.5, -3.5, 13, "#1d2027")
s.circle(22.5, 8.5, 9, "#1b1e25")
s.image(20.6, 3.0, 5.6, 5.6, "icon.png", anim="zoom")
s.text(1.6, 3.3, 18, 2.4, ["Brushless Lab"], style=pstyle(54, TEXT, True), anim="rise")
s.text(1.6, 5.7, 17.5, 2.4, ["Reverse-engineer and service brushless motors in VR"], style=pstyle(22, AMBER, line=115), anim="fade")
s.bar(1.65, 8.4, 3.2, 0.1, BLUE, anim="wipe")
s.text(1.6, 8.9, 17.5, 3.0, ["A six-bench virtual workshop: take a motor apart, measure it, find the fault, repair or rewind it, and prove it on a test stand.",
                             ("Godot 4.7 · Meta Quest and desktop · October 2026", pstyle(13, MUTED))], style=pstyle(15, TEXT, line=120, space_after=0.35), anim="fade", delay=0.2)
slides.append(s)

# 2 The problem
s = Slide()
heading(s, "Everywhere, yet hard to learn", "THE PROBLEM")
cards = [("Everywhere", "Drones, e-bikes, power tools, fans, pumps, HVAC, robots, hard drives, electric cars.", BLUE),
         ("Hard to learn hands-on", "Practice motors cost money, get damaged, and a real fault is rarely there on the day you need it.", AMBER),
         ("Invisible physics", "Flux, back-EMF, current and bearing defects can't be seen. Students learn formulas without ever seeing what they describe.", GREEN),
         ("Skills that matter", "Reverse-engineering an unknown motor, diagnosing it and rewinding it are real workshop skills, and they are rarely taught.", ROSE)]
for i, (t, b, c) in enumerate(cards):
    x = 1.4 + (i % 2) * 12.8
    y = 3.4 + (i // 2) * 5.4
    s.card(x, y, 12.2, 4.9, [(t, pstyle(19, c, True, space_after=0.25)), (b, pstyle(14.5, TEXT, line=120))], anim="zoom", delay=0.06)
slides.append(s)

# 3 The idea: six benches
s = Slide(("pushWipe", "fromRight"))
heading(s, "One motor, six benches", "THE IDEA", color=BLUE)
benches = [("1", "Job Desk", "ticket, datasheet, report", AMBER),
           ("2", "Teardown", "right tool, right order", BLUE),
           ("3", "Electrical", "R, L, insulation, back-EMF", GREEN),
           ("4", "Inspect & Repair", "magnets, coils, shaft", ROSE),
           ("5", "Winding", "rewind, star of slots", LILAC),
           ("6", "Test Stand", "ESC, spectra, final test", AMBER)]
for i, (n, t, b, c) in enumerate(benches):
    x = 1.4 + i * 4.3
    s.circle(x + 1.25, 4.0, 1.5, c, anim="zoom", delay=0.04)
    s.text(x + 1.25, 4.15, 1.5, 1.2, [n], style=pstyle(22, BG, True, align="center"))
    s.card(x, 6.0, 3.9, 3.6, [(t, pstyle(15.5, c, True, align="center", space_after=0.2)), (b, pstyle(12.5, TEXT, align="center", line=115))], anim="rise", delay=0.04)
    if i < 5:
        s.arrow(x + 2.95, 4.75, x + 5.35, 4.75, color=MUTED, anim="fade")
s.text(1.4, 10.4, 25, 3.5, bullets([
    "Everything you measure goes into a **notebook**, and the desk grades your report against the hidden truth.",
    "Mistakes have consequences: the wrong tool, a bearing pressed on the wrong ring, a forgotten shim or a magnet glued the wrong way round are all recorded.",
    "**Guided** mode shows the next step and explains it; **Expert** mode shows nothing.",
], size=14.5, after=0.25), anim="fade", delay=0.1)
slides.append(s)

# 4 Three kinds of job
s = Slide()
heading(s, "Three kinds of job", "WHAT YOU DO", color=GREEN)
jobs = [("Reverse-engineer", "A mystery outrunner with its label worn off. Work out the teeth, magnets, winding layout, star or delta, KV, resistance and stator size, so a winder could copy it.", "10 real slot/pole combinations, generated from a seed", AMBER),
        ("Service", "A customer's motor and a complaint (\"grinding noise\", \"runs hot\", \"trips the controller\"). Find the hidden fault, repair it, and pass the final test.", "9 faults, or none: \"customer says it's weak\"", BLUE),
        ("Free lab", "A healthy motor to explore: every instrument, every part, the test stand.", "for a first visit or for teaching", GREEN)]
for i, (t, b, foot, c) in enumerate(jobs):
    x = 1.4 + i * 8.5
    s.card(x, 3.4, 8.0, 7.6, [(t, pstyle(19, c, True, space_after=0.3)), (b, pstyle(14, TEXT, line=122, space_after=0.35)), (foot, pstyle(12.5, MUTED, italic=True))], anim="rise", delay=0.08)
s.text(1.4, 11.6, 25, 3.0, [("Motors on the bench", pstyle(15, AMBER, True, space_after=0.2))] + bullets([
    "**Drone outrunner 2212-920KV**: 12 teeth, 14 magnets, star, sensorless, 10×4.5 propeller on 3S.",
    "**Industrial inrunner 57BL-24V**: 190 KV, Hall sensors, 608 bearings, dynamometer brake.",
], size=13.5, after=0.15), anim="fade", delay=0.1)
slides.append(s)

# 5–9 Benches
bench_slide(2, "Teardown and reassembly", BLUE, "bench_2_stripped.png", [
    "Choose a tool, then click a part. It only comes off if nothing still holds it and the tool fits.",
    "Each step explains the shop-floor reason, e.g. heat the stator to 120 °C before pushing it off, because prying it cold cracks the varnish.",
    "Hand checks: turn the shaft (84 cogging notches on 12N14P, grinding, scraping), spin and rock each bearing.",
    "Parts go onto a tray in order and go back on in reverse.",
], "Thirteen tools, two motor designs, and the order is enforced, as it would be on a real bench.")

bench_slide(3, "Electrical tests", GREEN, "bench_3_backemf_scope.png", [
    "4-wire milliohm meter vs a normal multimeter: shows why 0.1 Ω windings need the right instrument.",
    "LCR meter at 1 kHz, 500 V insulation tester to the frame, Hall sensor tester.",
    "Spin it with a drill and read the scope: KV = rpm ÷ peak line volts; pole pairs = 60·f ÷ rpm.",
    "Uneven EMF peaks reveal a weak, flipped or missing magnet.",
], "Readings come from the motor's real condition: a shorted phase makes two lead pairs read low.")

bench_slide(4, "Inspect and repair", ROSE, "bench_4_traced.png", [
    "Count teeth and magnets, measure the stator with calipers (size code, e.g. 2808).",
    "Trace each coil's phase and direction, read the lead joints: star or delta.",
    "Gauss meter or magnetic viewing film on every magnet; dial indicator for shaft runout.",
    "Repairs: bearings, shaft, re-glue a magnet (the right way round), new bell, clean grit, re-solder joints, Hall sensor.",
], "Inspection confirms what the instruments suggested; nothing is labelled for you.")

bench_slide(5, "Rewinding", LILAC, "bench_5_layout.png", [
    "Wind each tooth with a phase letter: A B C clockwise, a b c counter-clockwise.",
    "The star of slots shows every coil's EMF phasor and the three phase sums: they must be equal and 120° apart.",
    "Winding factor computed live (0.933 for the classic 12N14P AabBCcaABbcC).",
    "Turns per tooth and star/delta set the KV: copy the original or the motor comes back different.",
], "A wrong coil is caught by the physics: unbalanced phases, a lower KV, a failed test.")

bench_slide(6, "Test stand", AMBER, "bench_6_bearing_envelope.png", [
    "Six-step ESC: sensorless start-up and back-EMF zero crossings, or Hall sensors.",
    "Live speed, current, power, efficiency, thrust or torque, winding temperature, scope, and the motor's sound.",
    "Vibration spectrum with shaft (1×, 2×) and bearing (BPFO, BPFI) markers, the envelope spectrum, and the ISO 10816 zone.",
    "Final test: starts, no-load speed ≈ KV × V, low current, zone A/B, cool, balanced, insulated.",
], "A worn bearing shows up as a line at its defect frequency, not as a scripted message.")

# 10 Faults and their symptoms
s = Slide()
heading(s, "Nine faults, found the way a technician finds them", "SERVICE JOBS", color=ROSE)
faults = [("Worn bearing", "grinds by hand; BPFO line in the envelope spectrum"),
          ("Bent shaft", "big 1× vibration peak (zone D); dial indicator runout"),
          ("Shorted turns", "two lead pairs read low, inductance lower still; runs hot"),
          ("Open phase", "two lead pairs read open; stutters, loses sync"),
          ("Insulation fault", "megger well below 1 MΩ; the controller trips"),
          ("Loose magnet", "rattle and knock once per turn; Gauss sweep shifted"),
          ("Demagnetised", "KV too high, weak torque; low Gauss readings"),
          ("Metal debris", "scraping by hand; grit visible on the magnets"),
          ("Dead Hall sensor", "jerky start; the tester shows a stuck code (57BL)")]
for i, (t, b) in enumerate(faults):
    x = 1.4 + (i % 3) * 8.5
    y = 3.3 + (i // 3) * 3.6
    s.card(x, y, 8.0, 3.2, [(t, pstyle(16, ROSE, True, space_after=0.15)), (b, pstyle(13, TEXT, line=118))], anim="zoom", delay=0.04)
s.text(1.4, 14.2, 25, 0.9, ["Symptoms are not scripted: each fault changes the motor's state, and every instrument reads from it."], style=pstyle(13, MUTED, italic=True), anim="fade")
slides.append(s)

# 11 Where the numbers come from
s = Slide(("pushWipe", "fromRight"))
heading(s, "Computed, not scripted", "WHERE THE NUMBERS COME FROM", color=BLUE)
chain = [("Design", "slots, poles, turns, wire, magnets, bearings", BLUE),
         ("Condition", "wear, damage, repairs, your rewind", AMBER),
         ("Flux model", "magnet arcs → tooth flux → λ(θ) → back-EMF and torque", GREEN),
         ("Drive simulation", "six-step ESC; circuit and rotor solved every 20 µs", LILAC),
         ("Instruments", "meters, scope, spectra, sound, hand feel", ROSE)]
for i, (t, b, c) in enumerate(chain):
    x = 1.4 + i * 5.2
    s.card(x, 3.4, 4.6, 4.9, [(t, pstyle(16, c, True, align="center", space_after=0.2)), (b, pstyle(12.5, TEXT, align="center", line=115))], anim="rise", delay=0.05)
    if i < 4:
        s.arrow(x + 4.65, 5.85, x + 5.15, 5.85, color=MUTED, anim="fade")
s.text(1.4, 8.8, 25, 6.0, bullets([
    "**Standard methods**: star-of-slots windings, back-EMF from flux linkage, bearing defect frequencies from the real ball geometry, ISO 10816 severity zones.",
    "**Calibrated** once: the flux scale is set so a healthy motor's back-EMF matches its rated KV. Everything else follows.",
    "**Typical values, not measurements**: friction, inertia, heat flow and vibration amplitudes are realistic for these sizes but hand-tuned.",
    "70 physics checks: KV 920 from the EMF, 84 cogging steps, no-load ≈ KV × V, 550–1000 g thrust, each fault's signature.",
], size=13.5, after=0.25), anim="fade", delay=0.1)
slides.append(s)

# 12 Built to run on a headset
s = Slide()
heading(s, "Physics that fits on a headset", "PERFORMANCE", color=GREEN)
s.card(1.4, 3.4, 8.0, 6.0, [("Detailed model", pstyle(17, BLUE, True, space_after=0.2)), ("20 µs steps, back-EMF zero-crossing detector modelled", pstyle(13.5, TEXT, line=118, space_after=0.3)), ("≈ 125 ms", pstyle(30, BLUE, True)), ("desktop CPU per simulated second", pstyle(12, MUTED))], anim="rise")
s.card(10.0, 3.4, 8.0, 6.0, [("Fast model (Quest)", pstyle(17, GREEN, True, space_after=0.2)), ("100 µs steps, ESC assumed in sync with the rotor", pstyle(13.5, TEXT, line=118, space_after=0.3)), ("≈ 45 ms", pstyle(30, GREEN, True)), ("about 3× cheaper", pstyle(12.5, MUTED))], anim="rise", delay=0.1)
s.card(18.6, 3.4, 8.0, 6.0, [("Same answers", pstyle(17, AMBER, True, space_after=0.2)), ("speed within 3–4 %, current within 8 %", pstyle(13.5, TEXT, line=118, space_after=0.2)), ("same fault signatures: repaired motors pass and unrepaired ones fail on both", pstyle(13.5, TEXT, line=118))], anim="rise", delay=0.2)
s.text(1.4, 10.1, 25, 5.0, bullets([
    "The simulation runs within a time budget each frame. If a computer can't keep up, it runs in slow motion and says so.",
    "A desktop that falls behind switches to the fast model by itself; there is also a switch on the test stand.",
    "Every 3D part is built in code from the motor's design, so there are no model files to load and the app stays small (Quest APK ≈ 90 MB).",
], size=13.5, after=0.25), anim="fade", delay=0.1)
slides.append(s)

# 13 Grading
s = Slide(("pushWipe", "fromRight"))
heading(s, "How it is graded", "FEEDBACK", color=AMBER, w=13.5)
h = 13.6
w = h * SHOT_W / SHOT_H
s.image(28.0 - w - 0.8, 1.05, w, h, shot("bench_1_report.png"), anim="fade", border="#33384a")
s.card(1.4, 3.4, 6.5, 3.0, [("40", pstyle(30, AMBER, True)), ("diagnosis", pstyle(13.5, TEXT))], anim="zoom")
s.card(8.3, 3.4, 6.5, 3.0, [("40", pstyle(30, BLUE, True)), ("repair: nothing left wrong", pstyle(13.5, TEXT))], anim="zoom", delay=0.05)
s.card(1.4, 6.8, 6.5, 3.0, [("20", pstyle(30, GREEN, True)), ("final test passed", pstyle(13.5, TEXT))], anim="zoom", delay=0.05)
s.card(8.3, 6.8, 6.5, 3.0, [("−3", pstyle(30, ROSE, True)), ("per workshop mistake (max −20)", pstyle(13.5, TEXT))], anim="zoom", delay=0.05)
s.text(1.4, 10.3, 13.5, 4.5, bullets([
    "Reverse-engineering: each datasheet field (teeth, magnets, winding, connection, KV, resistance, size) against the real design.",
    "The report lists what was right, what was wrong and the true answer.",
], size=14, after=0.3), anim="fade", delay=0.1)
slides.append(s)

# 14 Status
s = Slide()
heading(s, "Built and tested, and what is still missing", "STATUS", color=GREEN)
s.card(1.4, 3.4, 12.2, 9.8, [("Done", pstyle(19, GREEN, True, space_after=0.3))] + bullets([
    "Six benches, three motors (one generated), nine faults, grading.",
    "Desktop executable (Linux) and a Quest build.",
    "70 automatic physics checks and 60 end-to-end checks that play complete jobs through the real interface and take screenshots.",
    "README with the method and the source of every number.",
], size=13.5, after=0.3), anim="rise")
s.card(14.4, 3.4, 12.2, 9.8, [("Not yet done", pstyle(19, ROSE, True, space_after=0.3))] + bullets([
    "Tried on a real headset: frame rate, controller feel and the VR panels need a Quest session.",
    "Checked against a real motor: measure a 2212 (KV, resistance, thrust, vibration) and tune the constants.",
    "Field-oriented control (FOC) drives; jobs with two faults at once.",
    "Tried with students: usability and learning gains.",
], size=13.5, after=0.3), anim="rise", delay=0.15)
s.text(1.4, 13.6, 25, 1.0, ["A training simulator, not a design tool: absolute numbers are realistic in size, not exact."], style=pstyle(13, MUTED, italic=True), anim="fade")
slides.append(s)

# 15 Next steps
s = Slide(("pushWipe", "fromRight"))
heading(s, "Next steps", "PLAN", color=AMBER)
phases = [("Step 1", "Headset", "Install on Quest 3S; frame rate on the test stand; VR panel comfort.", BLUE),
          ("Step 2", "Real bench data", "Measure a real 2212 and a 57BL; fit friction, heat and vibration constants.", GREEN),
          ("Step 3", "Class trial", "A lab session with students: pre/post quiz, time per job, feedback.", AMBER),
          ("Step 4", "More content", "FOC drive, two-fault jobs, more motor sizes, an instructor view.", ROSE)]
s.bar(1.6, 6.05, 24.8, 0.08, "#33384a", anim="wipe")
for i, (when, t, b, c) in enumerate(phases):
    x = 1.4 + i * 6.45
    s.circle(x + 2.65, 5.65, 0.85, c, anim="zoom", delay=0.05)
    s.text(x, 3.6, 6.0, 1.2, [when], style=pstyle(13, c, True, align="center"), anim="fade")
    s.card(x, 7.0, 6.0, 5.6, [(t, pstyle(17, c, True, align="center", space_after=0.25)), (b, pstyle(13.5, TEXT, align="center", line=118))], anim="rise", delay=0.05)
slides.append(s)

# Close
s = Slide(("fade", "fadeOverColor"))
s.circle(-4, -4, 12, "#1d2027")
s.circle(20, 7, 12, "#1b1e25")
s.image(11.3, 2.2, 5.4, 5.4, "icon.png", anim="zoom")
s.text(2, 8.2, 24, 1.9, ["Brushless Lab"], style=pstyle(44, TEXT, True, align="center"), anim="rise")
s.text(2, 10.2, 24, 1.2, ["Open the motor. Measure it. Fix it. Prove it."], style=pstyle(22, AMBER, align="center"), anim="fade")
s.text(2, 12.0, 24, 1.0, ["Thank you. Questions are welcome."], style=pstyle(15, MUTED, align="center"), anim="fade", delay=0.3)
slides.append(s)


# --- XML -------------------------------------------------------------------------------------------------

NS = ('xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
      'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" '
      'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0" '
      'xmlns:smil="urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0" xmlns:anim="urn:oasis:names:tc:opendocument:xmlns:animation:1.0" '
      'xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xml="http://www.w3.org/XML/1998/namespace" '
      'office:version="1.3"')

FONTS = '<office:font-face-decls><style:font-face style:name="%s" svg:font-family="&apos;%s&apos;" style:font-pitch="variable"/></office:font-face-decls>' % (FONT, FONT)


def auto_styles():
    out = ""
    for key, name in gr_styles.items():
        fill, stroke, sc, sw, valign, pad, arrow, shadow = key
        props = 'draw:stroke="%s" svg:stroke-color="%s" svg:stroke-width="%.2fcm" ' % (stroke, sc, sw)
        props += ('draw:fill="solid" draw:fill-color="%s" ' % fill) if fill != "none" else 'draw:fill="none" '
        props += 'draw:textarea-vertical-align="%s" draw:auto-grow-height="false" draw:auto-grow-width="false" fo:padding-top="%.2fcm" fo:padding-bottom="%.2fcm" fo:padding-left="%.2fcm" fo:padding-right="%.2fcm" ' % (valign, pad, pad, pad, pad)
        if arrow:
            props += 'draw:marker-end="Arrow" draw:marker-end-width="0.35cm" draw:marker-end-center="false" '
        props += 'fo:wrap-option="wrap" draw:shadow="hidden"'
        out += '<style:style style:name="%s" style:family="graphic"><style:graphic-properties %s/></style:style>' % (name, props)
    for key, name in para_styles.items():
        size, color, bold, align, italic, after, indent, line = key
        pp = 'fo:text-align="%s" fo:margin-top="0cm" fo:margin-bottom="%.2fcm" fo:line-height="%d%%"' % (align, after, line)
        if indent:
            pp += ' fo:margin-left="%.2fcm" fo:text-indent="-%.2fcm"' % (indent, indent)
        tp = 'style:font-name="%s" fo:font-size="%.1fpt" fo:color="%s" fo:font-weight="%s" fo:font-style="%s"' % (FONT, size, color, "bold" if bold else "normal", "italic" if italic else "normal")
        out += '<style:style style:name="%s" style:family="paragraph"><style:paragraph-properties %s/><style:text-properties %s/></style:style>' % (name, pp, tp)
    out += '<style:style style:name="Tb" style:family="text"><style:text-properties fo:font-weight="bold"/></style:style>'
    for i, s in enumerate(slides):
        ttype, tsub = s.transition
        extra = ' smil:fadeColor="#000000"' if tsub == "fadeOverColor" else ""
        out += ('<style:style style:name="dp%d" style:family="drawing-page"><style:drawing-page-properties presentation:background-visible="true" '
                'presentation:background-objects-visible="true" presentation:transition-type="manual" smil:type="%s" smil:subtype="%s"%s presentation:transition-speed="medium"/></style:style>'
                % (i + 1, ttype, tsub, extra))
    return out


def content():
    pages = ""
    for i, s in enumerate(slides):
        pages += '<draw:page draw:name="Slide %d" draw:style-name="dp%d" draw:master-page-name="Default" presentation:presentation-page-layout-name="AL0T19">%s%s</draw:page>' % (
            i + 1, i + 1, "".join(s.shapes), timing(s))
    return ('<?xml version="1.0" encoding="UTF-8"?><office:document-content %s>%s<office:automatic-styles>%s</office:automatic-styles>'
            '<office:body><office:presentation>%s<presentation:settings presentation:mouse-visible="true"/></office:presentation></office:body></office:document-content>'
            % (NS, FONTS, auto_styles(), pages))


def styles():
    return ('<?xml version="1.0" encoding="UTF-8"?><office:document-styles %s>%s<office:styles>'
            '<draw:marker draw:name="Arrow" svg:viewBox="0 0 20 30" svg:d="M10 0l-10 30h20z"/>'
            '<style:default-style style:family="graphic"><style:graphic-properties draw:shadow="hidden"/>'
            '<style:paragraph-properties fo:text-align="start"/><style:text-properties style:font-name="%s" fo:font-size="16pt" fo:color="%s"/></style:default-style>'
            '<style:presentation-page-layout style:name="AL0T19"/>'
            '</office:styles><office:automatic-styles>'
            '<style:page-layout style:name="PM1"><style:page-layout-properties fo:margin-top="0cm" fo:margin-bottom="0cm" fo:margin-left="0cm" fo:margin-right="0cm" fo:page-width="%.2fcm" fo:page-height="%.2fcm" style:print-orientation="landscape"/></style:page-layout>'
            '<style:style style:name="Mdp1" style:family="drawing-page"><style:drawing-page-properties draw:background-size="full" draw:fill="solid" draw:fill-color="%s"/></style:style>'
            '</office:automatic-styles><office:master-styles>'
            '<style:master-page style:name="Default" style:page-layout-name="PM1" draw:style-name="Mdp1"/>'
            '</office:master-styles></office:document-styles>' % (NS, FONTS, FONT, TEXT, W, H, BG))


def meta():
    return ('<?xml version="1.0" encoding="UTF-8"?><office:document-meta %s><office:meta><dc:title>Brushless Lab</dc:title>'
            '<dc:description>Reverse-engineer and service brushless motors in VR</dc:description><meta:generator>make_odp.py</meta:generator>'
            '</office:meta></office:document-meta>' % NS)


def manifest():
    items = '<manifest:file-entry manifest:full-path="/" manifest:version="1.3" manifest:media-type="application/vnd.oasis.opendocument.presentation"/>'
    for f in ("content.xml", "styles.xml", "meta.xml"):
        items += '<manifest:file-entry manifest:full-path="%s" manifest:media-type="text/xml"/>' % f
    for name in images:
        mt = "image/png" if name.endswith(".png") else "image/jpeg"
        items += '<manifest:file-entry manifest:full-path="Pictures/%s" manifest:media-type="%s"/>' % (name, mt)
    return ('<?xml version="1.0" encoding="UTF-8"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">%s</manifest:manifest>' % items)


c = content()
with zipfile.ZipFile(OUT, "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/vnd.oasis.opendocument.presentation", compress_type=zipfile.ZIP_STORED)
    z.writestr("content.xml", c, compress_type=zipfile.ZIP_DEFLATED)
    z.writestr("styles.xml", styles(), compress_type=zipfile.ZIP_DEFLATED)
    z.writestr("meta.xml", meta(), compress_type=zipfile.ZIP_DEFLATED)
    z.writestr("META-INF/manifest.xml", manifest(), compress_type=zipfile.ZIP_DEFLATED)
    for name in images:
        z.write(os.path.join(IMG, name), "Pictures/" + name, compress_type=zipfile.ZIP_STORED)
print("%s: %d slides, %d animated elements, %d images" % (OUT, len(slides), sum(len(s.anims) for s in slides), len(images)))
