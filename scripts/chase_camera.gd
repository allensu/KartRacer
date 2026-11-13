extends Camera3D
## Smooth third-person camera behind a kart; widens its field of view with speed.

const DISTANCE := 6.5
const HEIGHT := 2.6
const LOOK_AHEAD := 3.0
const BASE_FOV := 70.0

var target: Node3D


func snap() -> void:
	if target:
		global_position = _desired()
		look_at(_look_point(), Vector3.UP)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(_desired(), 1.0 - exp(-7.0 * delta))
	look_at(_look_point(), Vector3.UP)
	var speed_ratio := clampf(absf(target.speed) / 30.0, 0.0, 1.5)
	var want_fov := BASE_FOV + speed_ratio * 10.0 + (8.0 if target.boost_time > 0.0 else 0.0)
	fov = lerpf(fov, want_fov, 1.0 - exp(-4.0 * delta))


func _heading() -> Vector3:
	var fwd := -target.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized()


func _desired() -> Vector3:
	return target.global_position - _heading() * DISTANCE + Vector3.UP * HEIGHT


func _look_point() -> Vector3:
	return target.global_position + Vector3.UP * 1.2 + _heading() * LOOK_AHEAD
