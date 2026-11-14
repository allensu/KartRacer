extends Node3D
## Sets up the world and runs an 8-racer race: countdown, laps, live
## standings, items and the results table. Works offline (you + 7 AI) and
## online (up to 4 players + AI), see Net (scripts/net.gd).
##
## Online, every computer simulates the karts it owns (its own kart; the host
## also owns the AI karts) and sends their state ~20 times a second. Item
## spawns are sent as events, and a hit is decided by the computer that owns
## the kart being hit.

const InputSetup := preload("res://scripts/input_setup.gd")
const TrackScript := preload("res://scripts/track.gd")
const KartScript := preload("res://scripts/kart.gd")
const AiDriver := preload("res://scripts/ai_driver.gd")
const Items := preload("res://scripts/items.gd")
const CameraScript := preload("res://scripts/chase_camera.gd")
const HudScript := preload("res://scripts/hud.gd")
const Roster := preload("res://scripts/roster.gd")

const TOTAL_LAPS := 3
const FIELD_SIZE := 8
const COUNTDOWN := 3.0
const NET_SEND_INTERVAL := 0.05
# Grid slot for each kart index: humans start mid-pack, AI fill the rest.
const GRID_ORDER := [5, 4, 6, 7, 3, 2, 1, 0]
const ITEM_ROWS := [0.18, 0.47, 0.76]
const ITEM_LANES := [-4.5, -1.5, 1.5, 4.5]

enum State { COUNTDOWN, RACING, FINISHED }

var track: Node3D
var kart: CharacterBody3D  # the local player's kart
var karts: Array[CharacterBody3D] = []
var human_karts: Array[CharacterBody3D] = []
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

var online := false
var _send_timer := 0.0
var _item_seq := 0
var _net_items := {}  # net id -> oil slick / seeker node
var _leaving := -1.0
var _last_count := 0


func _ready() -> void:
	InputSetup.ensure()
	online = Net.is_online()
	_rng.randomize()

	track = TrackScript.new()
	add_child(track)
	track.build(Net.track_id)
	_build_environment()
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
	hud.setup_minimap(track, karts, kart)
	Sfx.play_music()
	if online:
		hud.set_room(Net.room_code)
		Net.message.connect(_on_net_message)
		Net.room_closed.connect(_on_room_closed)
		Net.returned_to_lobby.connect(_go_to_menu)
	_update_standings()


func _spawn_field() -> void:
	var humans: Array = Net.race_players if online else [{"id": 0, "name": "YOU", "char": Net.char_id}]
	var my_id: int = Net.my_id if online else 0
	var i_own_ai: bool = not online or Net.is_host()
	# Humans keep their chosen racer; AI take the unused racers in roster order.
	var chars: Array[int] = []
	for h in humans:
		chars.append(clampi(int(h.get("char", 0)), 0, Roster.count() - 1))
	for c in Roster.count():
		if not chars.has(c) and chars.size() < FIELD_SIZE:
			chars.append(c)
	for i in FIELD_SIZE:
		var k: CharacterBody3D = KartScript.new()
		var is_human := i < humans.size()
		var ch: Dictionary = Roster.CHARACTERS[chars[i] if i < chars.size() else i % Roster.count()]
		k.racer_name = str(humans[i].name) if is_human else ch.name
		k.body_color = ch.color
		k.helmet_color = ch.helmet
		k.is_player = is_human and int(humans[i].id) == my_id
		k.is_remote = (is_human and not k.is_player) or (not is_human and not i_own_ai)
		k.track = track
		k.race = self
		k.transform = track.grid_transform(GRID_ORDER[i])
		add_child(k)
		k.lap_completed.connect(_on_lap_completed.bind(k))
		if k.is_player:
			kart = k
		elif not is_human and i_own_ai:
			_attach_ai(k, i + (Net.race_seed if online else 0))
		if is_human:
			human_karts.append(k)
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
	if _leaving >= 0.0:
		_leaving -= delta
		if _leaving < 0.0:
			_go_to_menu()
		return
	if Input.is_action_just_pressed("menu"):
		_quit_race()
		return
	if Input.is_action_just_pressed("restart") and not online:
		get_tree().reload_current_scene()
		return
	if state == State.FINISHED and Input.is_action_just_pressed("confirm"):
		if not online:
			get_tree().reload_current_scene()
			return
		if Net.is_host():
			Net.back_to_lobby()
			_go_to_menu()
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
				Sfx.play("go")
			elif countdown <= COUNTDOWN:
				hud.show_center(str(ceili(countdown)), Color(1.0, 0.85, 0.2))
				if ceili(countdown) != _last_count:
					_last_count = ceili(countdown)
					Sfx.play("beep")
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
		var footer := "Press Enter or R to race again"
		if online:
			footer = "Press Enter to return to the lobby" if Net.is_host() else "Waiting for the host..."
		hud.show_results(kart, standings, lap_times, footer)


func _physics_process(delta: float) -> void:
	if not online:
		return
	_send_timer += delta
	if _send_timer < NET_SEND_INTERVAL:
		return
	_send_timer = 0.0
	var states := []
	for i in karts.size():
		if karts[i].owned:
			states.append([i] + karts[i].get_net_state())
	Net.relay({"t": "s", "k": states})


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
		Sfx.play("finish")
		_go_timer = 2.5
		# Let the computer drive the player's kart on a cool-down lap.
		kart.is_player = false
		_attach_ai(kart, 99)
	else:
		hud.set_lap(lap + 1, TOTAL_LAPS)
		Sfx.play("lap")
		hud.show_center("FINAL LAP" if lap + 1 == TOTAL_LAPS else "LAP %d" % (lap + 1), Color(1, 1, 1))
		_go_timer = 1.5


func _quit_race() -> void:
	if online:
		Net.leave()
	_go_to_menu()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_room_closed(reason: String) -> void:
	hud.show_center(reason, Color(1.0, 0.5, 0.4))
	_leaving = 3.0


# ---------------------------------------------------------------- network events

func _on_net_message(_from: int, d: Dictionary) -> void:
	match d.get("t", ""):
		"s":
			for entry in d.get("k", []):
				var idx := int(entry[0])
				if idx >= 0 and idx < karts.size() and karts[idx].is_remote:
					karts[idx].apply_net_state(entry.slice(1))
		"oil":
			_make_oil(karts[int(d.k)], Vector3(d.p[0], 0.0, d.p[1]), str(d.id))
		"seek":
			var target: CharacterBody3D = karts[int(d.target)] if int(d.target) >= 0 else null
			_make_seeker(karts[int(d.k)], target, Vector3(d.p[0], 0.8, d.p[1]), float(d.r), str(d.id))
		"rm":
			var node = _net_items.get(str(d.id))
			if node != null and is_instance_valid(node):
				node.queue_free()
			_net_items.erase(str(d.id))


func on_item_consumed(net_id: String) -> void:
	_net_items.erase(net_id)
	if online and net_id != "":
		Net.relay({"t": "rm", "id": net_id})


func _next_item_id() -> String:
	_item_seq += 1
	return "%d-%d" % [Net.my_id, _item_seq]


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


## How far (metres) `k` is behind the best-placed human; negative when ahead.
## AI use this for gentle catch-up.
func gap_to_player(k: CharacterBody3D) -> float:
	var best := -INF
	for h in human_karts:
		if not h.finished:
			best = maxf(best, h.race_progress())
	if best == -INF or human_karts.has(k):
		return 0.0
	return best - k.race_progress()


func roll_item(k: CharacterBody3D) -> String:
	return Items.roll(k.place, karts.size(), _rng)


func spawn_oil(k: CharacterBody3D) -> void:
	var back := k.global_transform.basis.z
	back.y = 0.0
	var pos := k.global_position + back.normalized() * 2.8
	var id := _next_item_id()
	_make_oil(k, pos, id)
	if online:
		Net.relay({"t": "oil", "id": id, "k": karts.find(k), "p": [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01)]})


func spawn_seeker(k: CharacterBody3D) -> void:
	var fwd := -k.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pos := k.global_position + fwd * 2.8
	var target := kart_ahead_of(k)
	var yaw := atan2(-fwd.x, -fwd.z)
	var id := _next_item_id()
	_make_seeker(k, target, pos, yaw, id)
	if online:
		Net.relay({"t": "seek", "id": id, "k": karts.find(k), "target": karts.find(target) if target else -1,
			"p": [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01)], "r": snappedf(yaw, 0.001)})


func _make_oil(k: CharacterBody3D, pos: Vector3, id: String) -> void:
	var oil: Area3D = Items.OilSlick.new()
	oil.owner_kart = k
	oil.net_id = id
	oil.race = self
	oil.position = Vector3(pos.x, 0.0, pos.z)
	add_child(oil)
	_net_items[id] = oil


func _make_seeker(k: CharacterBody3D, target: CharacterBody3D, pos: Vector3, yaw: float, id: String) -> void:
	var s: Node3D = Items.Seeker.new()
	s.owner_kart = k
	s.track = track
	s.target = target
	s.net_id = id
	s.race = self
	add_child(s)
	s.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.8, pos.z))
	_net_items[id] = s


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = track.theme.sky_top
	sky_mat.sky_horizon_color = track.theme.sky_horizon
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
	env.fog_light_color = track.theme.fog
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = track.theme.sun
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
