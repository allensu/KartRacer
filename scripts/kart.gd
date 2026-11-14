extends CharacterBody3D
## Arcade kart: accelerate, brake/reverse, steer, hop-drift with mini-turbo.
## Driven by `throttle`, `steer` and `drift_held`, which the player's input
## fills in here and the AI driver fills in for opponents, so both share physics.
## Also holds the racer's item slot and reacts to being hit.

signal lap_completed(lap: int)

const MAX_SPEED := 30.0
const ACCEL := 18.0
const BRAKE := 38.0
const REVERSE_MAX := 9.0
const COAST_DRAG := 7.0
const TURN_RATE := 2.1
const GRAVITY := 32.0
const OFFROAD_FACTOR := 0.55
const BOOST_FACTOR := 1.4
const DRIFT_MIN_SPEED := 11.0
# Seconds of drifting needed for each mini-turbo level, and the boost it gives.
const DRIFT_LEVELS := [0.9, 1.9]
const DRIFT_BOOSTS := [0.7, 1.3]
const SPARK_COLORS := [Color(1.0, 0.9, 0.5), Color(0.35, 0.65, 1.0), Color(1.0, 0.45, 0.15)]

@export var is_player := true
## Remote karts are driven by another computer: no local physics, they just
## follow the state received over the network.
var is_remote := false
## True when this computer simulates the kart (and so decides hits, laps, items).
var owned: bool:
	get:
		return not is_remote
@export var body_color := Color(0.85, 0.12, 0.15)
@export var helmet_color := Color(1.0, 0.85, 0.85)

var track: Node3D
var race: Node  # main.gd: spawns items, ranks racers
var racer_name := "YOU"
var controls_enabled := false
var speed_mult := 1.0

var throttle := 0.0
var steer := 0.0
var drift_held := false

var speed := 0.0
var drifting := false
var drift_dir := 0.0
var drift_time := 0.0
var boost_time := 0.0
var offroad := false
var spin_time := 0.0
var shield_time := 0.0

var item := ""
var item_roll_time := 0.0  # item roulette still spinning; can't use yet

var lap := 1
var finished := false
var finish_time := 0.0
var place := 1
var _passed_half := false
var _last_progress := 0.0

var _model: Node3D
var _front_wheels: Array[Node3D] = []
var _wheel_spinners: Array[Node3D] = []
var _sparks: Array[CPUParticles3D] = []
var _flames: CPUParticles3D
var _drift_visual := 0.0
var _spin_visual := 0.0
var _shield_mesh: MeshInstance3D
var _engine_player: AudioStreamPlayer
var _last_level := 0
var _dust: CPUParticles3D
var _net_target := Vector3.ZERO
var _net_velocity := Vector3.ZERO
var _net_yaw := 0.0
var _net_progress := 0.0
var _net_has_state := false


func _ready() -> void:
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 0.7, 2.3)
	shape.shape = box
	shape.position.y = 0.45
	add_child(shape)
	_build_model()
	if track:
		_last_progress = track.progress_of(global_position)


func _physics_process(delta: float) -> void:
	if is_remote:
		_remote_update(delta)
		_update_visuals(delta)
		return
	if is_player and not finished:
		_read_input()
	if item_roll_time > 0.0:
		item_roll_time -= delta
	if shield_time > 0.0:
		shield_time -= delta
	if spin_time > 0.0:
		spin_time -= delta
		drifting = false
	if not controls_enabled or spin_time > 0.0:
		throttle = 0.0
		steer = 0.0
		drift_held = false

	offroad = track != null and track.is_offroad(global_position)
	_update_speed(delta)
	_update_drift(delta)
	_update_heading(delta)
	_update_velocity(delta)
	move_and_slide()
	_after_move()
	_track_progress()
	_update_visuals(delta)
	_update_engine_sound()
	var lvl := drift_level()
	if lvl > _last_level:
		_sfx("spark", -4.0)
	_last_level = lvl

	if global_position.y < -15.0:
		respawn()


func _read_input() -> void:
	throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	drift_held = Input.is_action_pressed("drift")
	if Input.is_action_just_pressed("use_item"):
		use_item()


func _update_speed(delta: float) -> void:
	var top := MAX_SPEED * speed_mult * (OFFROAD_FACTOR if offroad and boost_time <= 0.0 else 1.0)
	if boost_time > 0.0:
		boost_time -= delta
		speed = move_toward(speed, MAX_SPEED * BOOST_FACTOR, 70.0 * delta)
	elif speed > top:
		speed = move_toward(speed, top, 25.0 * delta)
	elif throttle > 0.05:
		speed = move_toward(speed, top, ACCEL * throttle * delta)
	elif throttle < -0.05:
		if speed > 0.0:
			speed = move_toward(speed, 0.0, BRAKE * -throttle * delta)
		else:
			speed = move_toward(speed, -REVERSE_MAX, ACCEL * 0.6 * -throttle * delta)
	else:
		speed = move_toward(speed, 0.0, COAST_DRAG * delta)


func _update_drift(delta: float) -> void:
	if not drifting:
		if drift_held and abs(steer) > 0.3 and speed > DRIFT_MIN_SPEED and is_on_floor():
			drifting = true
			drift_dir = signf(steer)
			drift_time = 0.0
			velocity.y = 5.0  # little hop into the drift
		return
	if not drift_held or speed < DRIFT_MIN_SPEED * 0.7:
		var level := drift_level()
		if level > 0 and drift_held == false:
			boost(DRIFT_BOOSTS[level - 1])
		drifting = false
		return
	# Steering into the drift charges faster than steering out of it.
	drift_time += delta * (0.75 + 0.5 * clampf(steer * drift_dir, 0.0, 1.0))


func drift_level() -> int:
	if not drifting:
		return 0
	var level := 0
	for threshold in DRIFT_LEVELS:
		if drift_time >= threshold:
			level += 1
	return level


func boost(seconds: float) -> void:
	if boost_time <= 0.0:
		_sfx("boost", -4.0)
	boost_time = maxf(boost_time, seconds)


func _update_heading(delta: float) -> void:
	var grip := clampf(absf(speed) / 6.0, 0.0, 1.0)
	var turn := steer
	if drifting:
		# Locked into the drift direction; steering widens or tightens the arc.
		turn = drift_dir * (0.95 + 0.55 * steer * drift_dir)
	var rate := TURN_RATE * (1.25 if drifting else 1.0)
	rotation.y -= turn * rate * grip * signf(speed) * delta


func _update_velocity(delta: float) -> void:
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var target := fwd * speed
	if drifting:
		target -= right * drift_dir * absf(speed) * 0.28
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var traction := 3.5 if drifting else (5.0 if offroad else 9.0)
	horizontal = horizontal.lerp(target, 1.0 - exp(-traction * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta


func _after_move() -> void:
	if get_slide_collision_count() == 0:
		return
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) < 0.5:
			# Hit a wall: bleed speed based on how head-on the impact was.
			var fwd := -global_transform.basis.z
			var head_on := clampf(-fwd.dot(n), 0.0, 1.0)
			if head_on > 0.4 and absf(speed) > 8.0:
				_sfx("bump", -3.0)
			speed *= 1.0 - 0.6 * head_on
			if head_on > 0.6:
				drifting = false


func _track_progress() -> void:
	if track == null or finished:
		return
	var p: float = track.progress_of(global_position)
	var length: float = track.length
	if p > length * 0.4 and p < length * 0.6:
		_passed_half = true
	var d := p - _last_progress
	if d < -length * 0.5 and _passed_half:
		_passed_half = false
		lap_completed.emit(lap)
		lap += 1
	_last_progress = p


func race_progress() -> float:
	## Total distance covered, for ranking racers.
	if is_remote:
		return _net_progress
	if track == null:
		return 0.0
	var p := _last_progress
	if not _passed_half and p > track.length * 0.6:
		p -= track.length  # still behind the line on the opening lap
	return (lap - 1) * track.length + p


# ---------------------------------------------------------------- sound

## True for the kart the camera follows on this computer.
func is_local_view() -> bool:
	return race != null and race.kart == self


func _sfx(name: String, volume_db := 0.0) -> void:
	if is_local_view():
		Sfx.play(name, volume_db)


func _update_engine_sound() -> void:
	if not is_local_view():
		return
	if _engine_player == null:
		_engine_player = AudioStreamPlayer.new()
		_engine_player.stream = Sfx.engine_stream()
		_engine_player.volume_db = -14.0
		add_child(_engine_player)
		_engine_player.play()
	var ratio := clampf(absf(speed) / MAX_SPEED, 0.0, 1.5)
	_engine_player.pitch_scale = 0.55 + ratio * 1.2 + (0.25 if boost_time > 0.0 else 0.0)


# ---------------------------------------------------------------- network

## Compact snapshot sent to other players ~20 times a second.
func get_net_state() -> Array:
	var p := global_position
	var flags := (1 if spin_time > 0.0 else 0) | (2 if shield_time > 0.0 else 0) | (4 if boost_time > 0.0 else 0)
	return [
		snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
		snappedf(rotation.y, 0.001), snappedf(speed, 0.01),
		int(drift_dir) if drifting else 0, drift_level(), flags,
		lap, snappedf(race_progress(), 0.1), finished, snappedf(finish_time, 0.001),
	]


func apply_net_state(s: Array) -> void:
	if s.size() < 12:
		return
	var pos := Vector3(s[0], s[1], s[2])
	if _net_has_state:
		_net_velocity = (pos - _net_target) * 20.0  # snapshots arrive at ~20 Hz
		if _net_velocity.length() > 80.0:
			_net_velocity = Vector3.ZERO  # teleport (respawn): don't extrapolate
	else:
		global_position = pos
		rotation.y = s[3]
	_net_has_state = true
	_net_target = pos
	_net_yaw = s[3]
	speed = s[4]
	drift_dir = s[5]
	drifting = drift_dir != 0.0
	drift_time = [0.0, DRIFT_LEVELS[0] + 0.01, DRIFT_LEVELS[1] + 0.01][clampi(int(s[6]), 0, 2)]
	var flags := int(s[7])
	spin_time = 0.3 if flags & 1 else 0.0
	shield_time = 1.0 if flags & 2 else 0.0
	boost_time = 0.3 if flags & 4 else 0.0
	lap = int(s[8])
	_net_progress = s[9]
	finished = bool(s[10])
	finish_time = s[11]


func _remote_update(delta: float) -> void:
	if not _net_has_state:
		return
	_net_target += _net_velocity * delta
	_net_velocity *= exp(-2.0 * delta)
	var gap := _net_target - global_position
	if gap.length() > 25.0:
		global_position = _net_target
	else:
		global_position += gap * (1.0 - exp(-12.0 * delta))
	rotation.y = lerp_angle(rotation.y, _net_yaw, 1.0 - exp(-12.0 * delta))


# ---------------------------------------------------------------- items

func give_random_item() -> void:
	if item != "" or race == null or is_remote:
		return
	item = race.roll_item(self)
	item_roll_time = 1.0 if is_player else 0.0
	_sfx("pickup", -4.0)


func use_item() -> void:
	if item == "" or item_roll_time > 0.0 or not controls_enabled or spin_time > 0.0:
		return
	var used := item
	item = ""
	match used:
		"nitro":
			boost(1.6)
		"oil":
			_sfx("oil")
			race.spawn_oil(self)
		"seeker":
			_sfx("seeker", -3.0)
			race.spawn_seeker(self)
		"shield":
			_sfx("shield")
			shield_time = 10.0


## Called by oil slicks and seekers. A shield absorbs one hit.
func hit() -> void:
	if shield_time > 0.0:
		shield_time = 0.0
		return
	if spin_time > 0.0:
		return
	spin_time = 1.2
	_sfx("hit")
	if is_local_view() and race.cam:
		race.cam.shake(0.6)
	speed *= 0.25
	boost_time = 0.0
	drifting = false
	velocity.y = 4.0


func respawn() -> void:
	if track == null:
		return
	var t: Transform3D = track.transform_at(track.progress_of(global_position))
	t.origin.y += 1.0
	global_transform = t
	velocity = Vector3.ZERO
	speed = 0.0
	drifting = false


# ---------------------------------------------------------------- visuals

func _update_visuals(delta: float) -> void:
	var target_yaw := -drift_dir * 0.4 if drifting else 0.0
	_drift_visual = lerpf(_drift_visual, target_yaw, 1.0 - exp(-10.0 * delta))
	if spin_time > 0.0:
		_spin_visual += 13.0 * delta
	else:
		_spin_visual = lerp_angle(_spin_visual, 0.0, 1.0 - exp(-12.0 * delta))
	_model.rotation.y = _drift_visual + _spin_visual
	_shield_mesh.visible = shield_time > 0.0
	if _shield_mesh.visible:
		_shield_mesh.rotation.y += delta * 2.0
	_model.rotation.z = lerpf(_model.rotation.z, -steer * 0.05 * clampf(speed / MAX_SPEED, 0, 1), 0.2)
	for w in _front_wheels:
		w.rotation.y = -steer * 0.45
	for s in _wheel_spinners:
		s.rotation.x -= speed * delta / 0.33

	var level := drift_level()
	for p in _sparks:
		p.emitting = drifting and is_on_floor()
		p.color = SPARK_COLORS[level]
	_flames.emitting = boost_time > 0.0
	_dust.emitting = offroad and absf(speed) > 6.0 and spin_time <= 0.0


func _mat(color: Color, metallic := 0.0, roughness := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var paint := _mat(body_color, 0.3, 0.35)
	var dark := _mat(Color(0.12, 0.12, 0.14), 0.2, 0.6)
	var chrome := _mat(Color(0.8, 0.8, 0.85), 0.9, 0.2)

	# Chassis, nose cone, side pods.
	_box(Vector3(1.3, 0.3, 2.2), Vector3(0, 0.42, 0), paint, _model)
	_box(Vector3(0.9, 0.24, 0.7), Vector3(0, 0.38, -1.35), paint, _model)
	_box(Vector3(1.6, 0.12, 0.35), Vector3(0, 0.3, -1.65), dark, _model)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.3, 0.28, 1.0), Vector3(side * 0.78, 0.4, 0.05), paint, _model)
	# Seat and rear wing.
	_box(Vector3(0.7, 0.65, 0.18), Vector3(0, 0.85, 0.6), dark, _model)
	_box(Vector3(1.5, 0.08, 0.4), Vector3(0, 1.05, 1.05), paint, _model)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.06, 0.45, 0.2), Vector3(side * 0.5, 0.8, 1.0), dark, _model)

	# Driver: torso, helmet, visor.
	var torso := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.24
	cyl.bottom_radius = 0.3
	cyl.height = 0.6
	torso.mesh = cyl
	torso.material_override = _mat(Color(0.95, 0.95, 0.95))
	torso.position = Vector3(0, 0.88, 0.35)
	_model.add_child(torso)
	var helmet := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.3
	sph.height = 0.6
	helmet.mesh = sph
	helmet.material_override = _mat(helmet_color, 0.2, 0.25)
	helmet.position = Vector3(0, 1.35, 0.3)
	_model.add_child(helmet)
	_box(Vector3(0.42, 0.14, 0.12), Vector3(0, 1.38, 0.04), _mat(Color(0.1, 0.15, 0.25), 0.8, 0.1), _model)
	# Steering wheel.
	_box(Vector3(0.4, 0.06, 0.06), Vector3(0, 0.82, -0.15), dark, _model)

	# Exhaust pipes.
	for side: float in [-1.0, 1.0]:
		var pipe := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.08
		pc.bottom_radius = 0.08
		pc.height = 0.4
		pipe.mesh = pc
		pipe.material_override = chrome
		pipe.rotation.x = PI / 2
		pipe.position = Vector3(side * 0.3, 0.5, 1.2)
		_model.add_child(pipe)

	# Wheels.
	var tyre := _mat(Color(0.08, 0.08, 0.08), 0.0, 0.9)
	for z: float in [-0.85, 0.8]:
		for side: float in [-1.0, 1.0]:
			var steer_node := Node3D.new()
			steer_node.position = Vector3(side * 0.82, 0.33, z)
			_model.add_child(steer_node)
			var spin := Node3D.new()
			steer_node.add_child(spin)
			var wheel := MeshInstance3D.new()
			var wc := CylinderMesh.new()
			wc.top_radius = 0.33
			wc.bottom_radius = 0.33
			wc.height = 0.32 if z < 0 else 0.42
			wc.radial_segments = 16
			wheel.mesh = wc
			wheel.material_override = tyre
			wheel.rotation.z = PI / 2
			spin.add_child(wheel)
			_box(Vector3(wc.height + 0.02, 0.12, 0.4), Vector3.ZERO, chrome, spin)
			_wheel_spinners.append(spin)
			if z < 0:
				_front_wheels.append(steer_node)

	# Drift sparks at the rear wheels.
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.07, 0.07, 0.07)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mesh.material = spark_mat
	for side: float in [-1.0, 1.0]:
		var p := CPUParticles3D.new()
		p.mesh = spark_mesh
		p.amount = 28
		p.lifetime = 0.35
		p.emitting = false
		p.direction = Vector3(side * 0.4, 0.6, 1.0)
		p.spread = 30.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0, -14, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		p.position = Vector3(side * 0.82, 0.08, 0.95)
		_model.add_child(p)
		_sparks.append(p)

	# Dust kicked up when driving on grass / sand.
	_dust = CPUParticles3D.new()
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.25
	dust_mesh.height = 0.5
	var dust_mat := StandardMaterial3D.new()
	dust_mat.vertex_color_use_as_albedo = true
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mesh.material = dust_mat
	_dust.mesh = dust_mesh
	_dust.amount = 24
	_dust.lifetime = 0.7
	_dust.local_coords = false
	_dust.emitting = false
	_dust.direction = Vector3(0, 0.6, 1)
	_dust.spread = 35.0
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 3.5
	_dust.gravity = Vector3(0, -1.0, 0)
	_dust.scale_amount_min = 0.8
	_dust.scale_amount_max = 2.0
	_dust.position = Vector3(0, 0.2, 1.0)
	var dust_grad := Gradient.new()
	dust_grad.set_color(0, Color(0.75, 0.65, 0.48, 0.6))
	dust_grad.set_color(1, Color(0.75, 0.65, 0.48, 0.0))
	_dust.color_ramp = dust_grad
	add_child(_dust)

	# Shield bubble.
	_shield_mesh = MeshInstance3D.new()
	var bubble := SphereMesh.new()
	bubble.radius = 1.7
	bubble.height = 2.6
	_shield_mesh.mesh = bubble
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.albedo_color = Color(0.35, 0.8, 1.0, 0.22)
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.emission_enabled = true
	bubble_mat.emission = Color(0.1, 0.4, 0.6)
	bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mesh.material_override = bubble_mat
	_shield_mesh.position.y = 0.8
	_shield_mesh.visible = false
	add_child(_shield_mesh)

	# Boost flames from the exhausts.
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.12
	flame_mesh.height = 0.24
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mesh.material = flame_mat
	_flames = CPUParticles3D.new()
	_flames.mesh = flame_mesh
	_flames.amount = 30
	_flames.lifetime = 0.25
	_flames.emitting = false
	_flames.direction = Vector3(0, 0.1, 1)
	_flames.spread = 12.0
	_flames.initial_velocity_min = 4.0
	_flames.initial_velocity_max = 6.0
	_flames.gravity = Vector3.ZERO
	_flames.position = Vector3(0, 0.5, 1.45)
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_flames.emission_box_extents = Vector3(0.3, 0.02, 0.02)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6))
	grad.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	_flames.color_ramp = grad
	_model.add_child(_flames)
