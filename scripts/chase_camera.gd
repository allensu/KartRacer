extends Camera3D
## Smooth third-person camera behind a kart; widens its field of view with speed.

const DISTANCE := 5.8
const HEIGHT := 2.6
const LOOK_AHEAD := 3.0
const BASE_FOV := 70.0

var target: Node3D
var _shake := 0.0
var _speed_lines: CPUParticles3D


func _ready() -> void:
	# Streaks that rush past the camera while boosting.
	_speed_lines = CPUParticles3D.new()
	var streak := BoxMesh.new()
	streak.size = Vector3(0.03, 0.03, 2.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material = mat
	_speed_lines.mesh = streak
	_speed_lines.amount = 40
	_speed_lines.lifetime = 0.35
	_speed_lines.emitting = false
	_speed_lines.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_speed_lines.emission_box_extents = Vector3(4.0, 2.5, 0.5)
	_speed_lines.direction = Vector3(0, 0, 1)
	_speed_lines.spread = 0.0
	_speed_lines.initial_velocity_min = 40.0
	_speed_lines.initial_velocity_max = 55.0
	_speed_lines.gravity = Vector3.ZERO
	_speed_lines.particle_flag_align_y = false
	_speed_lines.position = Vector3(0, 0, -9.0)
	add_child(_speed_lines)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func snap() -> void:
	if target:
		global_position = _desired()
		look_at(_look_point(), Vector3.UP)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(_desired(), 1.0 - exp(-14.0 * delta))
	look_at(_look_point(), Vector3.UP)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.5)
		h_offset = randf_range(-1.0, 1.0) * _shake * 0.4
		v_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	else:
		h_offset = 0.0
		v_offset = 0.0
	_speed_lines.emitting = target.boost_time > 0.0
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
