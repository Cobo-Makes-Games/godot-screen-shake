extends SceneTree
## Headless checks: godot --headless --path . --script tests/test_screen_shake.gd

var failures: int = 0


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _shaker(camera: Node = null) -> ScreenShake:
	var s: ScreenShake = ScreenShake.new()
	s.camera = camera
	s.ignore_time_scale = false
	root.add_child(s)
	s.set_process(false)  # driven by advance() so the test controls time
	return s


## The largest offset over `seconds` sampled at `fps`, and the offset at the end.
func run(s: ScreenShake, seconds: float, fps: float) -> Dictionary:
	var peak: float = 0.0
	var steps: int = int(round(seconds * fps))
	for i: int in steps:
		peak = maxf(peak, s.advance(1.0 / fps).length())
	return {"peak": peak, "end": s.offset}


func _initialize() -> void:
	await process_frame
	var s: ScreenShake = _shaker()
	s.add(3.0, Vector2.RIGHT)
	check(s.advance(0.0) == Vector2.ZERO, "no jump on the frame of the hit: the offset starts at zero")
	var first: Vector2 = s.advance(1.0 / 60.0)
	check(first.x < 0.0 and absf(first.y) < 0.0001, "moves away from the hit along its line (hit to the right, view moves left)")
	var r: Dictionary = run(s, 1.0, 60.0)
	check(r.end == Vector2.ZERO and not s.is_shaking(), "settles back to exactly zero")

	s.add(1.0, Vector2.RIGHT)
	s.add(3.0, Vector2.UP)
	s.add(2.0, Vector2.LEFT)
	var peak: float = run(s, 0.5, 120.0).peak
	check(absf(peak - 3.0) < 0.15, "a burst of hits in one frame shakes once, with the strongest (peak %.2f)" % peak)

	s.max_offset = 4.0
	s.add(100.0, Vector2.RIGHT)
	check(run(s, 0.5, 60.0).peak <= 4.0001, "a huge request never passes max_offset")
	s.max_offset = 6.0

	s.add(2.5, Vector2.RIGHT, 4.0 / 60.0)
	var fine: float = 0.0
	for i: int in 40:
		fine = maxf(fine, s.advance(1.0 / 600.0).length())
	check(fine > 2.45 and fine <= 2.5001, "inside a 4-frame hold the shake peaks at the requested strength (%.2f of 2.5)" % fine)
	s.stop()
	s.add(2.5, Vector2.RIGHT, 4.0 / 60.0)
	var inside: float = 0.0
	for i: int in 4:
		inside = maxf(inside, s.advance(1.0 / 60.0).length())
	check(inside > 1.8, "at 60 fps the frames inside the hold show most of it (%.2f)" % inside)
	var after: Dictionary = run(s, s.settle_seconds + 0.02, 120.0)
	check(after.end == Vector2.ZERO, "settles within settle_seconds after the hold")

	# Same shake sampled at 30 and 144 frames a second: the offsets agree at the same moments.
	var a: ScreenShake = _shaker()
	var b: ScreenShake = _shaker()
	a.add(3.0, Vector2.RIGHT)
	b.add(3.0, Vector2.RIGHT)
	a.advance(0.0)
	b.advance(0.0)
	var worst: float = 0.0
	for k: int in 6:
		var pa: Vector2 = a.advance(1.0 / 30.0)
		var pb: Vector2 = Vector2.ZERO
		for j: int in 4:
			pb = b.advance(1.0 / 120.0)
		worst = maxf(worst, (pa - pb).length())
	check(worst < 0.0001, "identical at any frame rate (difference %.6f)" % worst)

	# A new shake starts where the view is.
	s.add(3.0, Vector2.RIGHT)
	s.advance(0.0)
	for i: int in 3:
		s.advance(1.0 / 60.0)
	var before: Vector2 = s.offset
	s.add(1.0, Vector2.UP)
	var continued: Vector2 = s.advance(0.001)
	check((continued - before).length() < 0.3, "a second hit continues from the current view, no snap (moved %.3f)" % (continued - before).length())

	s.stop()
	s.enabled = false
	s.add(3.0, Vector2.RIGHT)
	check(run(s, 0.3, 60.0).peak == 0.0, "the Screen shake switch turns it off")
	s.enabled = true
	s.reduced_motion = true
	s.add(3.0, Vector2.RIGHT)
	check(run(s, 0.3, 60.0).peak == 0.0, "reduced motion turns it off")
	s.reduced_motion = false
	s.intensity = 0.5
	s.add(3.0, Vector2.RIGHT, 0.0)
	var half: float = run(s, 0.5, 240.0).peak
	check(half < 1.6 and half > 1.2, "intensity scales the shake (peak %.2f at 0.5)" % half)

	var cam2: Camera2D = Camera2D.new()
	root.add_child(cam2)
	var c2: ScreenShake = _shaker(cam2)
	c2.add(3.0, Vector2.DOWN)
	c2.advance(0.0)
	c2.advance(1.0 / 60.0)
	c2._apply()
	check(cam2.offset == c2.offset and cam2.offset.y < 0.0, "drives Camera2D.offset, never its position")
	check(cam2.position == Vector2.ZERO, "the camera's position is untouched")
	var cam3: Camera3D = Camera3D.new()
	root.add_child(cam3)
	var c3: ScreenShake = _shaker(cam3)
	c3.add(0.2, Vector2.RIGHT)
	c3.advance(0.0)
	c3.advance(1.0 / 60.0)
	c3._apply()
	check(cam3.h_offset < 0.0 and cam3.position == Vector3.ZERO, "drives Camera3D h_offset/v_offset")

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
