extends Node2D
## Screen Shake demo: hit the dummy with different strengths, try the hold mode
## (shaking inside a hitstop), a burst of hits in one frame, and the switches
## players get. The graph at the bottom draws the camera offset over the last
## two seconds, one point per frame.

const HISTORY: int = 120

var camera: Camera2D
var shake: ScreenShake
var history: PackedFloat32Array = []
var flash: float = 0.0
var hold_frames: float = 0.0
var status: Label
var hold: CheckBox
var spark: float = 0.0


func _ready() -> void:
	camera = Camera2D.new()
	camera.position = Vector2(480, 270)
	add_child(camera)
	shake = ScreenShake.new()
	shake.camera = camera
	shake.max_offset = 10.0
	camera.add_child(shake)
	history.resize(HISTORY)
	_build_ui()
	if OS.get_cmdline_user_args().has("--autoplay"):
		_autoplay()


## For recording the README clip: a few hits on a schedule.
func _autoplay() -> void:
	for step: Array in [[0.6, 1.3], [1.4, 3.2], [2.3, 4.6]]:
		get_tree().create_timer(step[0]).timeout.connect(_hit.bind(float(step[1])))
	get_tree().create_timer(3.2).timeout.connect(func() -> void:
		hold.button_pressed = true
		_hit(3.2))
	get_tree().create_timer(4.6).timeout.connect(func() -> void: get_tree().quit())


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()  # the interface doesn't shake: only the world does
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(16, 14)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.065, 0.085, 0.92)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	style.border_color = Color(1, 1, 1, 0.08)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title: Label = Label.new()
	title.text = "Screen Shake: hit the dummy. The view moves along the blow, then back."
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	for spec: Array in [["Chop a tree", 1.3], ["Sword hit", 3.2], ["Heavy hit", 4.6], ["You get hit", 3.6]]:
		var b: Button = Button.new()
		b.text = "%s (%.1f px)" % spec
		b.pressed.connect(_hit.bind(float(spec[1])))
		row.add_child(b)
	var burst: Button = Button.new()
	burst.text = "Five hits in one frame"
	burst.pressed.connect(func() -> void:
		for s: float in [1.3, 2.0, 3.2, 1.0, 2.4]:
			shake.add(s, Vector2.RIGHT.rotated(randf_range(-0.4, 0.4)), _hold())
		flash = 1.0
		_say("Five requests in one frame: only the strongest (3.2 px) shakes the view."))
	row.add_child(burst)
	var options: HBoxContainer = HBoxContainer.new()
	box.add_child(options)
	hold = CheckBox.new()
	hold.text = "Shake inside a 4-frame hitstop"
	hold.toggled.connect(func(on: bool) -> void: hold_frames = 4.0 if on else 0.0)
	options.add_child(hold)
	var enabled: CheckBox = CheckBox.new()
	enabled.text = "Screen shake"
	enabled.button_pressed = true
	enabled.toggled.connect(func(on: bool) -> void: shake.enabled = on)
	options.add_child(enabled)
	var reduced: CheckBox = CheckBox.new()
	reduced.text = "Reduced motion"
	reduced.toggled.connect(func(on: bool) -> void: shake.reduced_motion = on)
	options.add_child(reduced)
	var label: Label = Label.new()
	label.text = "  Intensity"
	options.add_child(label)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 2.0
	slider.step = 0.05
	slider.value = 1.0
	slider.custom_minimum_size.x = 140
	slider.value_changed.connect(func(v: float) -> void: shake.intensity = v)
	options.add_child(slider)
	status = Label.new()
	status.modulate = Color(1, 1, 1, 0.75)
	box.add_child(status)
	_say("Space also hits. The interface sits on its own layer, so only the world moves.")


func _hold() -> float:
	return hold_frames / 60.0


func _hit(strength: float) -> void:
	shake.add(strength, Vector2.RIGHT, _hold())
	flash = 1.0
	spark = 1.0
	_say("%.1f px peak%s. The view moved away from the blow and back." % [strength, ", shaken inside the hold and settled 60 ms after it" if hold_frames > 0.0 else ""])


func _say(text: String) -> void:
	status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_hit(3.2)


func _process(delta: float) -> void:
	history.remove_at(0)
	history.append(shake.offset.x)
	flash = maxf(0.0, flash - delta * 7.0)
	spark = maxf(0.0, spark - delta * 9.0)
	queue_redraw()


func _draw() -> void:
	# A floor grid so movement reads, the attacker and the dummy.
	draw_rect(Rect2(-200, -200, 1360, 940), Color("1d1b22"))
	for x: int in range(-200, 1200, 40):
		draw_line(Vector2(x, -200), Vector2(x, 740), Color(1, 1, 1, 0.05))
	for y: int in range(-200, 760, 40):
		draw_line(Vector2(-200, y), Vector2(1160, y), Color(1, 1, 1, 0.05))
	draw_circle(Vector2(400, 300), 26, Color("e9d6a8"))
	draw_rect(Rect2(420, 290, 40, 8), Color("cfd8e6"))
	draw_circle(Vector2(540, 300), 34, Color("c9705b").lerp(Color("fff3d6"), flash))
	if spark > 0.0:
		var reach: float = 18.0 + 30.0 * (1.0 - spark)
		for k: int in 6:
			var d: Vector2 = Vector2.RIGHT.rotated(-0.9 + k * 0.36)
			draw_line(Vector2(508, 300) + d * reach * 0.4, Vector2(508, 300) + d * reach, Color(1, 0.95, 0.8, spark), 3.0)
	# The offset graph, drawn in world space so it shakes too, like everything else in the world.
	var origin: Vector2 = Vector2(260, 470)
	draw_line(origin, origin + Vector2(440, 0), Color(1, 1, 1, 0.2))
	var points: PackedVector2Array = []
	for i: int in HISTORY:
		points.append(origin + Vector2(i * 440.0 / (HISTORY - 1), -history[i] * 8.0))
	draw_polyline(points, Color("8eef97"), 2.0)
	draw_string(ThemeDB.fallback_font, origin + Vector2(0, 28), "camera offset (x), last 2 s", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.5))
