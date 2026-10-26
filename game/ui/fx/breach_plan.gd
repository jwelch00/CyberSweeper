class_name BreachPlan
extends RefCounted
## The boot's "I'm in" beat (design/MOTION.md, 1): how the session-key crack
## climbs to 100%, and whether, where and how hard it hits ACCESS DENIED on the
## way. An exact port of FX.breachPlan in design/shared/fx.js, so a boot seed
## plays the same here as in the motion lab.

const MS_PER_PCT := 9.0
const DENIED_MS := 260.0
const ODDS_CLEAN := 0.40
const ODDS_ONE := 0.40
const ODDS_DOUBLE := 0.05
const KINDS: Array[String] = ["clean", "one", "99", "double"]

var seed := 0
var kind := "clean"
## [{at, drop, proxy}] in percent; proxy is the "RETRYING VIA PROXY n" number.
var stalls: Array[Dictionary] = []
## [{t0, t1, p0, p1, denied}]: progress p0 -> p1 over ms t0 -> t1.
var segs: Array[Dictionary] = []
var total_ms := 0.0
## Session key, four groups of four hex digits.
var key := ""


static func make(p_seed: int, force := "") -> BreachPlan:
	var p := BreachPlan.new()
	p.seed = p_seed
	var r := JsPort.Mulberry.new(p_seed)
	var roll := r.next()
	if force in KINDS:
		p.kind = force
	elif roll < ODDS_CLEAN:
		p.kind = "clean"
	elif roll < ODDS_CLEAN + ODDS_ONE:
		p.kind = "one"
	elif roll < 1.0 - ODDS_DOUBLE:
		p.kind = "99"
	else:
		p.kind = "double"
	var raw: Array = []
	match p.kind:
		"one":
			var at := 25.0 + r.next() * 65.0
			raw.append([at, 8.0 + r.next() * 14.0])
		"99":
			raw.append([99.0, 10.0 + r.next() * 12.0])
		"double":
			var a := 20.0 + r.next() * 30.0
			var d1 := 6.0 + r.next() * 10.0
			var at2 := a + 25.0 + r.next() * 25.0
			raw.append([a, d1])
			raw.append([at2, 8.0 + r.next() * 12.0])
	for x in raw:
		p.stalls.append({"at": JsPort.round_js(x[0]), "drop": JsPort.round_js(x[1]), "proxy": 2 + int(r.next() * 8.0)})
	var t := 0.0
	var pct := 0.0
	for x in p.stalls:
		var t1: float = t + (x.at - pct) * MS_PER_PCT
		p.segs.append({"t0": t, "t1": t1, "p0": pct, "p1": float(x.at), "denied": false})
		t = t1
		p.segs.append({"t0": t, "t1": t + DENIED_MS, "p0": float(x.at), "p1": float(x.at - x.drop), "denied": true,
			"proxy": x.proxy})
		t += DENIED_MS
		pct = float(x.at) - float(x.drop)
	p.segs.append({"t0": t, "t1": t + (100.0 - pct) * MS_PER_PCT, "p0": pct, "p1": 100.0, "denied": false})
	p.total_ms = t + (100.0 - pct) * MS_PER_PCT
	var groups: Array[String] = []
	for i in 4:
		groups.append("%04X" % int(r.next() * 65536.0))
	p.key = "-".join(groups)
	return p


## Progress (0..100) at `ms` into the breach, and the segment it's in (empty
## once done). During a denial the counter holds for the first 40% of the
## beat, then shows the drop.
func at(ms: float) -> Dictionary:
	for g in segs:
		if ms < g.t1:
			var f: float = (ms - g.t0) / maxf(1e-6, g.t1 - g.t0)
			var p: float = (g.p0 if f < 0.4 else g.p1) if g.denied else g.p0 + (g.p1 - g.p0) * f
			return {"p": p, "seg": g}
	return {"p": 100.0, "seg": {}}
