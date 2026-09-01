extends Node2D

const COLS := 5
const ROWS := 6
const TILE := 76.0
const ORIGIN := Vector2(88, 200)
const NEG := -1
const POS := 1
const SNAP := 46.0
const SHOVE_RADIUS := 110.0
const COHESION_MIN := 28
const METHANOL_START := Vector2(400, 1120)
const TAIL_START := Vector2(160, 1120)

var waters: Array = []
var methanol_pos := METHANOL_START
var methanol_angle := 0.0
var tail_pos := TAIL_START
var dragging := ""
var drag_offset := Vector2.ZERO
var touch_down := Vector2.ZERO
var did_drag := false
var bonds: Array = []
var hold_time := 0.0
var fail_time := 0.0
var started := false
var result := ""
var fail_reason := ""

func _ready() -> void:
	_build_water()

func _build_water() -> void:
	waters.clear()
	for r in ROWS:
		for c in COLS:
			var rest := ORIGIN + Vector2(c * TILE, r * TILE)
			waters.append({"rest": rest, "offset": Vector2.ZERO})

func _water_o(w: Dictionary) -> Vector2:
	var rest: Vector2 = w.rest
	var off: Vector2 = w.offset
	return rest + off

func _water_h1(w: Dictionary) -> Vector2:
	return _water_o(w) + Vector2(-26, 20)

func _water_h2(w: Dictionary) -> Vector2:
	return _water_o(w) + Vector2(26, 20)

func _methanol() -> Dictionary:
	var dir := Vector2.RIGHT.rotated(methanol_angle)
	var c := methanol_pos
	var oh_o: Vector2 = c + dir * 34.0
	var oh_h: Vector2 = oh_o + dir * 18.0
	var ch3: Vector2 = c - dir * 38.0
	return {"c": c, "oh_o": oh_o, "oh_h": oh_h, "ch3": ch3}

func _lattice_rect() -> Rect2:
	return Rect2(ORIGIN - Vector2(TILE * 0.4, TILE * 0.4), Vector2(float(COLS) * TILE, float(ROWS) * TILE))

func _lattice_center() -> Vector2:
	return ORIGIN + Vector2((COLS - 1) * TILE, (ROWS - 1) * TILE) * 0.5

func _apply_shove(delta: float) -> void:
	# Fatty tail shoves water. Methanol does not bounce or shove (miscible).
	for w in waters:
		var rest: Vector2 = w.rest
		var off: Vector2 = w.offset
		var center: Vector2 = rest + off
		var away: Vector2 = center - tail_pos
		var dist: float = away.length()
		var target := Vector2.ZERO
		if dist < SHOVE_RADIUS and dist > 0.5:
			target = away.normalized() * (SHOVE_RADIUS - dist)
		w.offset = off.lerp(target, minf(1.0, delta * 10.0))

func _update_bonds() -> void:
	bonds.clear()
	var n: int = waters.size()
	for i in n:
		var wa: Dictionary = waters[i]
		var ao: Vector2 = _water_o(wa)
		var ah1: Vector2 = _water_h1(wa)
		var ah2: Vector2 = _water_h2(wa)
		var a_sites := [{"p": ao, "q": NEG}, {"p": ah1, "q": POS}, {"p": ah2, "q": POS}]
		for j in range(i + 1, n):
			var wb: Dictionary = waters[j]
			var bo: Vector2 = _water_o(wb)
			var bh1: Vector2 = _water_h1(wb)
			var bh2: Vector2 = _water_h2(wb)
			var b_sites := [{"p": bo, "q": NEG}, {"p": bh1, "q": POS}, {"p": bh2, "q": POS}]
			for a in a_sites:
				for b in b_sites:
					var ap: Vector2 = a.p
					var bp: Vector2 = b.p
					if int(a.q) != int(b.q) and ap.distance_to(bp) <= SNAP:
						bonds.append({"a": ap, "b": bp, "kind": "water_water"})
	var m := _methanol()
	var oh_o: Vector2 = m.oh_o
	var oh_h: Vector2 = m.oh_h
	var oh_sites := [{"p": oh_o, "q": NEG}, {"p": oh_h, "q": POS}]
	for w in waters:
		var wo: Vector2 = _water_o(w)
		var wh1: Vector2 = _water_h1(w)
		var wh2: Vector2 = _water_h2(w)
		var w_sites := [{"p": wo, "q": NEG}, {"p": wh1, "q": POS}, {"p": wh2, "q": POS}]
		for a in oh_sites:
			for b in w_sites:
				var ap2: Vector2 = a.p
				var bp2: Vector2 = b.p
				if int(a.q) != int(b.q) and ap2.distance_to(bp2) <= SNAP:
					bonds.append({"a": ap2, "b": bp2, "kind": "oh_water"})

func _count_kind(kind: String) -> int:
	var n := 0
	for b in bonds:
		if str(b.kind) == kind:
			n += 1
	return n

func _unhandled_input(event: InputEvent) -> void:
	if result != "":
		var tap := false
		if event is InputEventScreenTouch and event.pressed:
			tap = true
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			tap = true
		if tap:
			_retry()
		return
	var pos := Vector2.ZERO
	var pressed := false
	var moving := false
	var released := false
	if event is InputEventScreenTouch:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		pos = event.position
		pressed = true
		moving = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and dragging != "":
		pos = event.position
		pressed = true
		moving = true
	else:
		return
	_handle_pointer(pos, pressed, moving, released)

func _handle_pointer(pos: Vector2, pressed: bool, moving: bool, released: bool) -> void:
	started = true
	if pressed and not moving and dragging == "":
		touch_down = pos
		did_drag = false
		var d_m: float = pos.distance_to(methanol_pos)
		var d_t: float = pos.distance_to(tail_pos)
		if d_m < 78.0 and d_m <= d_t:
			dragging = "methanol"
			drag_offset = methanol_pos - pos
		elif d_t < 90.0:
			dragging = "tail"
			drag_offset = tail_pos - pos
	if moving and dragging != "":
		if pos.distance_to(touch_down) > 14.0:
			did_drag = true
		if dragging == "methanol":
			methanol_pos = pos + drag_offset
		elif dragging == "tail":
			tail_pos = pos + drag_offset
		queue_redraw()
	if released:
		if dragging == "methanol" and not did_drag:
			methanol_angle += PI * 0.5
		dragging = ""
		queue_redraw()

func _process(delta: float) -> void:
	if result != "":
		return
	_apply_shove(delta)
	_update_bonds()
	var oh: int = _count_kind("oh_water")
	var ww: int = _count_kind("water_water")
	var m := _methanol()
	var tail_in: bool = _lattice_rect().has_point(tail_pos)
	if oh >= 1 and ww >= COHESION_MIN:
		hold_time += delta
		fail_time = 0.0
		if hold_time >= 1.5:
			result = "win"
	elif started:
		hold_time = 0.0
		fail_time += delta
		if tail_in and ww < COHESION_MIN:
			if fail_time >= 0.45:
				result = "fail"
				fail_reason = "Too few H-bonds — cohesion died."
		else:
			var lattice := _lattice_center()
			var ch3: Vector2 = m.ch3
			var oh_o: Vector2 = m.oh_o
			var methyl_pocket: bool = ch3.distance_to(lattice) + 24.0 < oh_o.distance_to(lattice)
			if methyl_pocket and fail_time >= 2.0:
				result = "fail"
				fail_reason = "Hydroxyl in a methyl pocket — it won't stay."
			elif fail_time >= 3.5:
				result = "fail"
				fail_reason = "Too few H-bonds — cohesion died."
	queue_redraw()

func _retry() -> void:
	result = ""
	fail_reason = ""
	hold_time = 0.0
	fail_time = 0.0
	started = false
	methanol_pos = METHANOL_START
	methanol_angle = 0.0
	tail_pos = TAIL_START
	dragging = ""
	_build_water()
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, Vector2(720, 1280)), Color(0.07, 0.12, 0.22))
	draw_string(font, Vector2(28, 48), "Hold a shape", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0.93, 0.96, 1.0))
	draw_string(font, Vector2(28, 78), "Drag methanol or tail. Tap methanol to face.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.8, 0.9))
	draw_string(font, Vector2(28, 98), "OH sticks. CH3 is dead. Tail shoves water. Pull OH to break H-bonds.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.65, 0.76, 0.86))
	_update_bonds()
	for b in bonds:
		var col := Color(0.45, 0.85, 0.95, 0.35)
		if str(b.kind) == "oh_water":
			col = Color(0.55, 0.95, 1.0, 0.9)
		var from_pt: Vector2 = b.a
		var to_pt: Vector2 = b.b
		_draw_hbond(from_pt, to_pt, col)
	for w in waters:
		_draw_h2o(w, font)
	_draw_tail(font)
	var m := _methanol()
	_draw_methanol(m, font)
	if result == "win":
		_draw_banner(font, "Held a shape", "Tap to retry", Color(0.15, 0.42, 0.28))
	elif result == "fail":
		_draw_banner(font, fail_reason, "Tap to retry", Color(0.42, 0.16, 0.16))

func _draw_hbond(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 1.0:
		return
	var dir := d / length
	var i := 0.0
	while i < length:
		var p1 := a + dir * i
		var p2 := a + dir * minf(i + 6.0, length)
		draw_line(p1, p2, col, 3.0, true)
		i += 12.0

func _draw_covalent(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, Color(0.85, 0.85, 0.9), 3.5, true)

func _draw_h2o(w: Dictionary, font: Font) -> void:
	var o: Vector2 = _water_o(w)
	var h1: Vector2 = _water_h1(w)
	var h2: Vector2 = _water_h2(w)
	_draw_covalent(o, h1)
	_draw_covalent(o, h2)
	draw_circle(o, 16.0, Color(0.82, 0.24, 0.2))
	draw_circle(h1, 9.0, Color(0.93, 0.95, 1.0))
	draw_circle(h2, 9.0, Color(0.93, 0.95, 1.0))
	draw_string(font, o + Vector2(-10, -20), "δ−", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.7, 0.65))
	draw_string(font, h1 + Vector2(-18, 22), "δ+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1))
	draw_string(font, h2 + Vector2(2, 22), "δ+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1))

func _draw_tail(font: Font) -> void:
	var r := Rect2(tail_pos - Vector2(50, 16), Vector2(100, 32))
	draw_rect(r, Color(0.72, 0.58, 0.32))
	draw_string(font, tail_pos + Vector2(-16, 6), "tail", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.18, 0.12, 0.06))

func _draw_methanol(m: Dictionary, font: Font) -> void:
	var c: Vector2 = m.c
	var ch3: Vector2 = m.ch3
	var oh_o: Vector2 = m.oh_o
	var oh_h: Vector2 = m.oh_h
	_draw_covalent(ch3, c)
	_draw_covalent(c, oh_o)
	_draw_covalent(oh_o, oh_h)
	draw_circle(c, 16.0, Color(0.22, 0.22, 0.25))
	draw_circle(ch3, 18.0, Color(0.5, 0.5, 0.46))
	draw_circle(oh_o, 14.0, Color(0.88, 0.22, 0.18))
	draw_circle(oh_h, 9.0, Color(0.93, 0.95, 1.0))
	draw_string(font, ch3 + Vector2(-18, 6), "CH3", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.15, 0.15, 0.12))
	draw_string(font, oh_o + Vector2(-12, -18), "OH", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.8))
	draw_string(font, c + Vector2(-6, 5), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.92))

func _draw_banner(font: Font, title: String, sub: String, bg: Color) -> void:
	draw_rect(Rect2(40, 520, 640, 200), bg)
	draw_string(font, Vector2(60, 590), title, HORIZONTAL_ALIGNMENT_LEFT, 600, 26, Color.WHITE)
	draw_string(font, Vector2(60, 640), sub, HORIZONTAL_ALIGNMENT_LEFT, 600, 22, Color(0.9, 0.9, 0.9))
