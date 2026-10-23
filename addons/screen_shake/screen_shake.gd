@icon("res://addons/screen_shake/icon.svg")
class_name ScreenShake
extends Node
## Screen shake that makes hits feel heavy without making anyone sick.
##
## The view moves along the line of the blow (away from the hit and back), never
## at random. It eases in over a frame instead of jumping, the strongest event
## of a frame wins so a sweep through five enemies is one shake, a new shake
## starts from wherever the view is, and every shake has a hard limit. Shake only
## moves the picture: Camera2D.offset or Camera3D h_offset/v_offset, never the
## camera's position, your aim or your physics.
##
##   $ScreenShake.add(3.0, hit_direction)              # a recoil
##   $ScreenShake.add(3.0, hit_direction, 4.0 / 60.0)  # shaken inside a 4-frame hitstop
##
## From Mytheria (cobomakesgames.com/blog/screen-shake-in-games/).

## Emitted when a request is accepted as the frame's strongest event.
signal shake_started(strength: float, direction: Vector2)

## The camera to shake. Leave empty to use the parent if it's a camera.
@export var camera: Node
## Turn this off from your settings menu (a Screen shake switch).
@export var enabled: bool = true
## Reduced motion: no shake at all.
@export var reduced_motion: bool = false
## Multiplies every request: a "shake strength" slider.
@export_range(0.0, 2.0, 0.05) var intensity: float = 1.0
## Hard limit on the offset, in pixels (2D) or metres (3D), whatever happens.
@export_range(0.0, 64.0, 0.1, "or_greater") var max_offset: float = 6.0
## Requests at or above this strength get the heavier recoil with one return swing.
@export_range(0.0, 64.0, 0.1, "or_greater") var heavy_strength: float = 2.2
## Seconds the view takes to settle after a hold (a hitstop) ends.
@export_range(0.0, 0.5, 0.005) var settle_seconds: float = 0.06
## Keep shaking at real speed when Engine.time_scale is used for slow motion or a global freeze.
@export var ignore_time_scale: bool = true

## The offset applied this frame.
var offset: Vector2 = Vector2.ZERO

var _pending_strength: float = 0.0
var _pending_direction: Vector2 = Vector2.ZERO
var _pending_hold: float = 0.0
var _strength: float = 0.0
var _direction: Vector2 = Vector2.RIGHT
var _hold: float = 0.0
var _duration: float = 0.0
var _age: float = INF
var _carry: Vector2 = Vector2.ZERO
var _last_usec: int = 0
## 1 / the hold envelope's largest magnitude, so `strength` is always the peak offset.
var _hold_norm: float = 1.0


func _ready() -> void:
	if camera == null and (get_parent() is Camera2D or get_parent() is Camera3D):
		camera = get_parent()
	process_priority = 1000  # after gameplay code has queued its hits for this frame
	_last_usec = Time.get_ticks_usec()


## Requests a shake. `strength` is the peak offset (pixels in 2D, metres in 3D),
## `direction` the direction of the blow (the view moves away from the hit, along
## it, then back). `hold` > 0 shakes inside a freeze of that many seconds (a
## hitstop) and settles right after it. Within one frame only the strongest
## request is used.
func add(strength: float, direction: Vector2, hold: float = 0.0) -> void:
	if strength <= _pending_strength or not is_finite(strength):
		return
	_pending_strength = strength
	_pending_direction = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.UP
	_pending_hold = maxf(0.0, hold)


## Stops any shake at once.
func stop() -> void:
	_age = INF
	_carry = Vector2.ZERO
	_pending_strength = 0.0
	offset = Vector2.ZERO
	_apply()


## The global mouse position as if the view weren't shaking (2D), so aiming never jitters with the shake.
func unshaken_mouse_position() -> Vector2:
	var cam: Camera2D = camera as Camera2D
	if cam == null:
		return get_viewport().get_mouse_position()
	return cam.get_global_mouse_position() - offset


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var dt: float = (now - _last_usec) / 1000000.0 if ignore_time_scale else delta
	_last_usec = now
	advance(dt)
	_apply()


## Moves the shake forward by `dt` seconds and returns the offset. _process calls
## this; call it yourself to drive the shake from your own clock (replays, tests).
func advance(dt: float) -> Vector2:
	if _pending_strength > 0.0:
		_start(_pending_strength * intensity, _pending_direction, _pending_hold)
		_pending_strength = 0.0
	if not enabled or reduced_motion or intensity <= 0.0:
		_age = INF
		_carry = Vector2.ZERO
		offset = Vector2.ZERO
		return offset
	_age += maxf(0.0, dt)
	if _age >= _duration:
		offset = Vector2.ZERO
		return offset
	var progress: float = _age / _duration
	var envelope: float = hold_envelope(_age, _hold, settle_seconds) * _hold_norm if _hold > 0.0 else (heavy_envelope(progress) if _strength >= heavy_strength else light_envelope(progress))
	var carried: Vector2 = _carry * (1.0 - smoothstep(0.0, 0.3, progress))
	offset = (carried + _direction * _strength * envelope).limit_length(max_offset)
	return offset


func is_shaking() -> bool:
	return _age < _duration


func _start(strength: float, direction: Vector2, hold: float) -> void:
	if not enabled or reduced_motion or strength <= 0.0:
		return
	_carry = offset  # a new shake starts where the view is, never a jump back to the middle
	_strength = strength
	_direction = -direction  # away from the hit
	_hold = hold
	if hold > 0.0:
		_duration = maxf(hold, 0.05) + settle_seconds
		var peak: float = 0.0
		for i: int in 241:
			peak = maxf(peak, absf(hold_envelope(_duration * i / 240.0, hold, settle_seconds)))
		_hold_norm = 1.0 / maxf(peak, 0.0001)
	else:
		_duration = 0.26 if strength >= heavy_strength * 1.6 else (0.24 if strength >= heavy_strength else 0.14)
	_age = 0.0
	shake_started.emit(strength, direction)


func _apply() -> void:
	if camera is Camera2D:
		(camera as Camera2D).offset = offset
	elif camera is Camera3D:
		(camera as Camera3D).h_offset = offset.x
		(camera as Camera3D).v_offset = -offset.y


## One soft recoil and return, no side-to-side reversals: for light, frequent hits.
static func light_envelope(progress: float) -> float:
	return smoothstep(0.0, 0.18, progress) * (1.0 - smoothstep(0.1, 1.0, progress))


## One recoil, then a single smaller return swing that settles by the end: for heavy hits.
static func heavy_envelope(progress: float) -> float:
	if progress < 0.5:
		return sin(PI * progress * 2.0)
	return -0.38 * sin(PI * (progress - 0.5) * 2.0)


## A damped jolt that reaches full strength one frame after contact (never a jump),
## reverses about one and a half times inside the hold, then settles linearly.
static func hold_envelope(age: float, hold: float, settle: float) -> float:
	if age < 0.0:
		return 0.0
	var h: float = maxf(hold, 0.05)
	var wave: float = cos(TAU * age / (h * 0.66)) * exp(-age / (h * 0.6)) * smoothstep(0.0, 1.0 / 60.0, age)
	if age <= h:
		return wave
	return wave * clampf(1.0 - (age - h) / maxf(settle, 0.0001), 0.0, 1.0)
