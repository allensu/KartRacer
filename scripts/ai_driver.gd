extends Node
## Drives a kart by filling in its throttle / steer / drift_held, exactly like
## the player's input does. Each driver gets a personality: preferred racing
## line, corner aggression, reaction and how eagerly it uses items.

var kart: CharacterBody3D
var skill := 1.0          # 0.9 .. 1.0, scales top speed
var lane := 0.0           # current lateral offset from the centre line
var lane_bias := 0.0      # preferred side of the road
var drift_threshold := 0.32
var item_patience := 2.0  # average seconds before using an item

var _lane_target := 0.0
var _lane_timer := 0.0
var _stuck_timer := 0.0
var _item_timer := -1.0
var _rng := RandomNumberGenerator.new()


func setup(the_kart: CharacterBody3D, seed_value: int) -> void:
	kart = the_kart
	_rng.seed = seed_value
	skill = _rng.randf_range(0.9, 1.0)
	lane_bias = _rng.randf_range(-3.0, 3.0)
	drift_threshold = _rng.randf_range(0.26, 0.4)
	item_patience = _rng.randf_range(1.0, 3.5)
	lane = lane_bias
	_lane_target = lane_bias
	kart.speed_mult = skill


func _physics_process(delta: float) -> void:
	if kart == null or kart.track == null:
		return
	var track = kart.track
	_update_lane(delta)

	var progress: float = track.progress_of(kart.global_position)
	var look := 9.0 + absf(kart.speed) * 0.45
	var target: Vector3 = track.transform_at(progress + look, lane).origin
	var local: Vector3 = kart.to_local(target)
	var angle := atan2(local.x, -local.z)

	# How sharp is the road further ahead? Used to decide whether to drift.
	var far: Vector3 = kart.to_local(track.transform_at(progress + look + 18.0, lane).origin)
	var far_angle := atan2(far.x, -far.z)

	kart.steer = clampf(angle * 2.6, -1.0, 1.0)
	kart.throttle = 1.0
	if kart.drifting:
		kart.drift_held = kart.drift_time < 2.1 and signf(far_angle) == kart.drift_dir and absf(far_angle) > drift_threshold * 0.5
	else:
		kart.drift_held = absf(far_angle) > drift_threshold and kart.speed > 16.0

	# Gentle catch-up so the pack stays together without feeling unfair.
	var gap: float = kart.race.gap_to_player(kart) if kart.race else 0.0
	kart.speed_mult = skill + clampf(gap / 400.0, -0.04, 0.08)

	_handle_items(delta)
	_handle_stuck(delta)


func _update_lane(delta: float) -> void:
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = _rng.randf_range(1.5, 4.0)
		_lane_target = clampf(lane_bias + _rng.randf_range(-2.5, 2.5), -5.0, 5.0)
	lane = move_toward(lane, _lane_target, 2.0 * delta)


func _handle_items(delta: float) -> void:
	if kart.item == "":
		_item_timer = -1.0
		return
	if _item_timer < 0.0:
		_item_timer = _rng.randf_range(0.4, item_patience * 2.0)
	_item_timer -= delta
	if _item_timer > 0.0:
		return
	# Hold a seeker until there is somebody ahead to chase.
	if kart.item == "seeker" and kart.race and kart.race.kart_ahead_of(kart) == null:
		return
	kart.use_item()


func _handle_stuck(delta: float) -> void:
	if not kart.controls_enabled or kart.spin_time > 0.0:
		_stuck_timer = 0.0
		return
	if absf(kart.speed) < 2.0:
		_stuck_timer += delta
		if _stuck_timer > 2.5:
			kart.respawn()
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
