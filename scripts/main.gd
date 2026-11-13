extends Node3D
## Sets up the world and runs an 8-racer Grand Prix race: countdown, laps,
## live standings, items, and the results table.

const InputSetup := preload("res://scripts/input_setup.gd")
const TrackScript := preload("res://scripts/track.gd")
const KartScript := preload("res://scripts/kart.gd")
const AiDriver := preload("res://scripts/ai_driver.gd")
const Items := preload("res://scripts/items.gd")
const CameraScript := preload("res://scripts/chase_camera.gd")
const HudScript := preload("res://scripts/hud.gd")

const TOTAL_LAPS := 3
const COUNTDOWN := 3.0
const PLAYER_SLOT := 5
# Every racer in the field. Index 0 is the player.
const ROSTER := [
	["YOU", Color(0.85, 0.12, 0.15)],
	["Blaze", Color(1.0, 0.5, 0.05)],
	["Pip", Color(0.95, 0.85, 0.1)],
	["Rocco", Color(0.15, 0.65, 0.25)],
	["Nova", Color(0.1, 0.45, 0.95)],
	["Taro", Color(0.55, 0.25, 0.8)],
	["Mika", Color(1.0, 0.45, 0.7)],
	["Juno", Color(0.9, 0.9, 0.92)],
]
const ITEM_ROWS := [0.18, 0.47, 0.76]
const ITEM_LANES := [-4.5, -1.5, 1.5, 4.5]

enum State { COUNTDOWN, RACING, FINISHED }

var track: Node3D
var kart: CharacterBody3D  # the player's kart
var karts: Array[CharacterBody3D] = []
var standings: Array[CharacterBody3D] = []
var cam: Camera3D
var hud: CanvasLayer

var state := State.COUNTDOWN
var countdown := COUNTDOWN + 0.6
var race_time := 0.0
var lap_times: Array[float] = []
var _lap_start := 0.0
var _go_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	InputSetup.ensure()
	_rng.randomize()
	_build_environment()

	track = TrackScript.new()
	add_child(track)
	track.build()
	_place_item_boxes()
	_spawn_field()

	cam = CameraScript.new()
	add_child(cam)
	cam.target = kart
	cam.current = true
	cam.snap()

	hud = HudScript.new()
	add_child(hud)
	hud.set_lap(1, TOTAL_LAPS)
	hud.set_time(0.0)
	_update_standings()


func _spawn_field() -> void:
	# Opponents fill the grid slots around the player.
	var slots: Array[int] = []
	for s in ROSTER.size():
		if s != PLAYER_SLOT:
			slots.append(s)
	for i in ROSTER.size():
		var k: CharacterBody3D = KartScript.new()
		k.racer_name = ROSTER[i][0]
		k.body_color = ROSTER[i][1]
		k.is_player = i == 0
		k.track = track
		k.race = self
		k.transform = track.grid_transform(PLAYER_SLOT if i == 0 else slots[i - 1])
		add_child(k)
		k.lap_completed.connect(_on_lap_completed.bind(k))
		if i == 0:
			kart = k
		else:
			_attach_ai(k, i)
		karts.append(k)


func _attach_ai(k: CharacterBody3D, seed_value: int) -> void:
	var ai: Node = AiDriver.new()
	ai.name = "AI"
	k.add_child(ai)
	ai.setup(k, seed_value * 7919 + _rng.randi() % 1000)


func _place_item_boxes() -> void:
	for row in ITEM_ROWS:
		for lane in ITEM_LANES:
			var box: Area3D = Items.ItemBox.new()
			var t: Transform3D = track.transform_at(track.length * row, lane)
			box.position = t.origin
			track.add_child(box)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart") or (state == State.FINISHED and Input.is_action_just_pressed("confirm")):
		get_tree().reload_current_scene()
		return

	match state:
		State.COUNTDOWN:
			countdown -= delta
			if countdown <= 0.0:
				state = State.RACING
				for k in karts:
					k.controls_enabled = true
				_go_timer = 1.0
				hud.show_center("GO!", Color(0.4, 1.0, 0.4))
			elif countdown <= COUNTDOWN:
				hud.show_center(str(ceili(countdown)), Color(1.0, 0.85, 0.2))
		State.RACING, State.FINISHED:
			race_time += delta
			if _go_timer > 0.0:
				_go_timer -= delta
				if _go_timer <= 0.0:
					hud.show_center("")

	_update_standings()
	if state != State.FINISHED:
		hud.set_time(race_time)
	hud.set_speed(kart.speed)
	hud.set_drift(kart.drift_level())
	hud.set_position(kart.place, karts.size())
	hud.set_item(kart.item, kart.item_roll_time)
	hud.set_standings(standings, kart)
	if state == State.FINISHED and _go_timer <= 0.0:
		hud.show_results(kart, standings, lap_times)


func _on_lap_completed(lap: int, k: CharacterBody3D) -> void:
	if lap >= TOTAL_LAPS:
		k.finished = true
		k.finish_time = race_time
	if k != kart:
		return
	lap_times.append(race_time - _lap_start)
	_lap_start = race_time
	if lap >= TOTAL_LAPS:
		state = State.FINISHED
		hud.set_time(race_time)
		hud.show_center("FINISH!", Color(1.0, 0.9, 0.3))
		_go_timer = 2.5
		# Let the computer drive the player's kart on a cool-down lap.
		kart.is_player = false
		_attach_ai(kart, 99)
	else:
		hud.set_lap(lap + 1, TOTAL_LAPS)
		hud.show_center("FINAL LAP" if lap + 1 == TOTAL_LAPS else "LAP %d" % (lap + 1), Color(1, 1, 1))
		_go_timer = 1.5


# ---------------------------------------------------------------- race queries used by karts and AI

func _update_standings() -> void:
	standings = karts.duplicate()
	standings.sort_custom(func(a, b):
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.finish_time < b.finish_time
		return a.race_progress() > b.race_progress())
	for i in standings.size():
		standings[i].place = i + 1


func kart_ahead_of(k: CharacterBody3D) -> CharacterBody3D:
	var i := standings.find(k)
	return standings[i - 1] if i > 0 else null


## Positive when `k` is behind the player (metres), negative when ahead.
func gap_to_player(k: CharacterBody3D) -> float:
	if k == kart or kart.finished:
		return 0.0
	return kart.race_progress() - k.race_progress()


func roll_item(k: CharacterBody3D) -> String:
	return Items.roll(k.place, karts.size(), _rng)


func spawn_oil(k: CharacterBody3D) -> void:
	var oil: Area3D = Items.OilSlick.new()
	oil.owner_kart = k
	var back := k.global_transform.basis.z
	back.y = 0.0
	oil.position = k.global_position + back.normalized() * 2.8
	oil.position.y = 0.0
	add_child(oil)


func spawn_seeker(k: CharacterBody3D) -> void:
	var s: Node3D = Items.Seeker.new()
	s.owner_kart = k
	s.track = track
	s.target = kart_ahead_of(k)
	var fwd := -k.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	add_child(s)
	s.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), k.global_position + fwd * 2.8 + Vector3.UP * 0.8)


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
