extends Node3D
## Sets up the world and runs a time-trial race: countdown, laps, results.

const InputSetup := preload("res://scripts/input_setup.gd")
const TrackScript := preload("res://scripts/track.gd")
const KartScript := preload("res://scripts/kart.gd")
const CameraScript := preload("res://scripts/chase_camera.gd")
const HudScript := preload("res://scripts/hud.gd")

const TOTAL_LAPS := 3
const COUNTDOWN := 3.0

enum State { COUNTDOWN, RACING, FINISHED }

var track: Node3D
var kart: CharacterBody3D
var cam: Camera3D
var hud: CanvasLayer

var state := State.COUNTDOWN
var countdown := COUNTDOWN + 0.6
var race_time := 0.0
var lap_times: Array[float] = []
var _lap_start := 0.0
var _go_timer := 0.0


func _ready() -> void:
	InputSetup.ensure()
	_build_environment()

	track = TrackScript.new()
	add_child(track)
	track.build()

	kart = KartScript.new()
	kart.track = track
	kart.transform = track.grid_transform(0)
	add_child(kart)
	kart.lap_completed.connect(_on_lap_completed)

	cam = CameraScript.new()
	add_child(cam)
	cam.target = kart
	cam.current = true
	cam.snap()

	hud = HudScript.new()
	add_child(hud)
	hud.set_lap(1, TOTAL_LAPS)
	hud.set_time(0.0)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart") or (state == State.FINISHED and Input.is_action_just_pressed("confirm")):
		get_tree().reload_current_scene()
		return

	match state:
		State.COUNTDOWN:
			countdown -= delta
			if countdown <= 0.0:
				state = State.RACING
				kart.controls_enabled = true
				_go_timer = 1.0
				hud.show_center("GO!", Color(0.4, 1.0, 0.4))
			elif countdown <= COUNTDOWN:
				hud.show_center(str(ceili(countdown)), Color(1.0, 0.85, 0.2))
		State.RACING:
			race_time += delta
			if _go_timer > 0.0:
				_go_timer -= delta
				if _go_timer <= 0.0:
					hud.show_center("")
		State.FINISHED:
			pass

	hud.set_time(race_time)
	hud.set_speed(kart.speed)
	hud.set_drift(kart.drift_level())


func _on_lap_completed(lap: int) -> void:
	lap_times.append(race_time - _lap_start)
	_lap_start = race_time
	if lap >= TOTAL_LAPS:
		state = State.FINISHED
		kart.finished = true
		kart.controls_enabled = false
		hud.show_center("FINISH!", Color(1.0, 0.9, 0.3))
		hud.show_results(race_time, lap_times)
	else:
		hud.set_lap(lap + 1, TOTAL_LAPS)
		hud.show_center("FINAL LAP" if lap + 1 == TOTAL_LAPS else "LAP %d" % (lap + 1), Color(1, 1, 1))
		_go_timer = 1.5


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.45, 0.85)
	sky_mat.sky_horizon_color = Color(0.85, 0.78, 0.7)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.55)
	sky_mat.ground_bottom_color = Color(0.25, 0.3, 0.22)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.8, 0.85)
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
