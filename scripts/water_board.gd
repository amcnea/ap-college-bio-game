extends Node2D

const COLS := 5
const ROWS := 6
const TILE := 76.0
const ORIGIN := Vector2(88, 200)
const NEG := -1
const POS := 1
const SNAP := 46.0

var waters: Array = []
var methanol_pos := Vector2(360, 1120)
var methanol_angle := 0.0
var dragging := false
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
			var center := ORIGIN + Vector2(c * TILE, r * TILE)
			waters.append({
				"o": center,
				"h1": center + Vector2(-26, 20),
				"h2": center + Vector2(26, 20),
			})

func _methanol() -> Dictionary:
	var dir := Vector2.RIGHT.rotated(methanol_angle)
	var c := methanol_pos
	var oh_o: Vector2 = c + dir * 34.0
	var oh_h: Vector2 = oh_o + dir * 18.0
	var ch3: Vector2 = c - dir * 38.0
	return {"c": c, "oh_o": oh_o, "oh_h": oh_h, "ch3": ch3}

func _lattice_center() -> Vector2:
	return ORIGIN + Vector2((COLS - 1) * TILE, (ROWS - 1) * TILE) * 0.5

func _update_bonds() -> void:
	bonds.clear()
	# Water-water lattice (orthogonal neighbors): H-bonds only, not covalent.
	for r in ROWS:
		for c in COLS:
			var i: int = r * COLS + c
			var w = waters[i]
			if c + 1 < COLS:
				var right = waters[i + 1]
				bonds.append({"a": w.h2, "b": right.o, "kind": "water_water"})
			if r + 1 < ROWS:
				var down = waters[i + COLS]
				bonds.append({"a": w.h1, "b": down.o, "kind": "water_water"})
	# Hydroxyl-water H-bonds: opposite partials within SNAP. Methyl never participates.
	var m := _methanol()
	var oh_sites := [{"p": m.oh_o, "q": NEG}, {"p": m.oh_h, "q": POS}]
	for w in waters:
		var w_sites := [{"p": w.o, "q": NEG}, {"p": w.h1, "q": POS}, {"p": w.h2, "q": POS}]
		for a in oh_sites:
			for b in w_sites:
				if int(a.q) != int(b.q) and a.p.distance_to(b.p) <= SNAP:
					bonds.append({"a": a.p, "b": b.p, "kind": "oh_water"})

func _oh_bond_count() -> int:
	var n := 0
	for b in bonds:
		if b.kind == "oh_water":
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
	elif event is InputEventMouseMotion and dragging:
		pos = event.position
		pressed = true
		moving = true
	else:
		return
	_handle_pointer(pos, pressed, moving, released)

func _handle_pointer(pos: Vector2, pressed: bool, moving: bool, released: bool) -> void:
	started = true
	if pressed and not moving and not dragging:
		touch_down = pos
		did_drag = false
		if pos.distance_to(methanol_pos) < 78.0:
			dragging = true
			drag_offset = methanol_pos - pos
	if moving and dragging:
		if pos.distance_to(touch_down) > 14.0:
			did_drag = true
		methanol_pos = pos + drag_offset
		queue_redraw()
	if released:
		if dragging and not did_drag:
			methanol_angle += PI * 0.5
		dragging = false
		queue_redraw()

func _process(delta: float) -> void:
	if result != "":
		return
	_update_bonds()
	var oh := _oh_bond_count()
	var m := _methanol()
	if oh >= 1:
		hold_time += delta
		fail_time = 0.0
		if hold_time >= 1.5:
			result = "win"
	elif started:
		hold_time = 0.0
		fail_time += delta
		var lattice := _lattice_center()
		var methyl_pocket := m.ch3.distance_to(lattice) + 24.0 < m.oh_o.distance_to(lattice)
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
	methanol_pos = Vector2(360, 1120)
	methanol_angle = 0.0
	dragging = false
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, Vector2(720, 1280)), Color(0.07, 0.12, 0.22))
	draw_string(font, Vector2(28, 52), "Hold a shape", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.93, 0.96, 1.0))
	draw_string(font, Vector2(28, 86), "Drag methanol. Tap to face. OH sticks. CH3 is dead.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.8, 0.9))
	_update_bonds()
	for b in bonds:
		var col := Color(0.45, 0.85, 0.95, 0.35)
		if b.kind == "oh_water":
			col = Color(0.55, 0.95, 1.0, 0.9)
		_draw_bond(b.a, b.b, col)
	for w in waters:
		_draw_h2o(w, font)
	var m := _methanol()
	_draw_methanol(m, font)
	if result == "win":
		_draw_banner(font, "Held a shape", "Tap to retry", Color(0.15, 0.42, 0.28))
	elif result == "fail":
		_draw_banner(font, fail_reason, "Tap to retry", Color(0.42, 0.16, 0.16))

func _draw_bond(a: Vector2, b: Vector2, col: Color) -> void:
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

func _draw_h2o(w: Dictionary, font: Font) -> void:
	draw_circle(w.o, 16.0, Color(0.82, 0.24, 0.2))
	draw_circle(w.h1, 9.0, Color(0.93, 0.95, 1.0))
	draw_circle(w.h2, 9.0, Color(0.93, 0.95, 1.0))
	draw_line(w.o, w.h1, Color(0.85, 0.85, 0.9), 3.0, true)
	draw_line(w.o, w.h2, Color(0.85, 0.85, 0.9), 3.0, true)
	draw_string(font, w.o + Vector2(-10, -20), "δ−", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.7, 0.65))
	draw_string(font, w.h1 + Vector2(-18, 22), "δ+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1))
	draw_string(font, w.h2 + Vector2(2, 22), "δ+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1))

func _draw_methanol(m: Dictionary, font: Font) -> void:
	draw_line(m.ch3, m.oh_o, Color(0.4, 0.4, 0.45), 6.0, true)
	draw_circle(m.c, 16.0, Color(0.22, 0.22, 0.25))
	draw_circle(m.ch3, 18.0, Color(0.5, 0.5, 0.46))
	draw_circle(m.oh_o, 14.0, Color(0.88, 0.22, 0.18))
	draw_circle(m.oh_h, 9.0, Color(0.93, 0.95, 1.0))
	draw_line(m.oh_o, m.oh_h, Color(0.85, 0.85, 0.9), 3.0, true)
	draw_string(font, m.ch3 + Vector2(-18, 6), "CH3", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.15, 0.15, 0.12))
	draw_string(font, m.oh_o + Vector2(-12, -18), "OH", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.8))
	draw_string(font, m.c + Vector2(-6, 5), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.92))

func _draw_banner(font: Font, title: String, sub: String, bg: Color) -> void:
	draw_rect(Rect2(40, 520, 640, 200), bg)
	draw_string(font, Vector2(60, 590), title, HORIZONTAL_ALIGNMENT_LEFT, 600, 26, Color.WHITE)
	draw_string(font, Vector2(60, 640), sub, HORIZONTAL_ALIGNMENT_LEFT, 600, 22, Color(0.9, 0.9, 0.9))
