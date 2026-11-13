extends SceneTree
## Headless smoke test: an autopilot drives the player kart around the track
## and the test passes if it finishes all laps in a sane time.
## Run: godot --headless -s res://tests/autodrive_test.gd

var main: Node
var frames := 0
var drift_seen := false
var boost_seen := false


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	Engine.max_fps = 0
	physics_frame.connect(_drive)


func _drive() -> void:
	frames += 1
	var kart = main.kart
	var track = main.track
	kart.is_player = false
	var ahead: float = track.progress_of(kart.global_position) + 18.0
	var target: Vector3 = track.transform_at(ahead).origin
	var to_target: Vector3 = kart.to_local(target)
	var angle := atan2(to_target.x, -to_target.z)
	kart.steer = clampf(angle * 2.5, -1.0, 1.0)
	kart.throttle = 1.0
	kart.drift_held = (kart.drifting and kart.drift_time < 1.2) or (absf(angle) > 0.1 and kart.speed > 15.0)
	drift_seen = drift_seen or kart.drifting
	boost_seen = boost_seen or kart.boost_time > 0.0
	if frames % 600 == 0:
		print("t=%.0fs lap=%d speed=%.1f offroad=%s pos=%s" % [frames / 60.0, kart.lap, kart.speed, kart.offroad, kart.global_position.round()])
	if main.state == main.State.FINISHED:
		print("FINISHED in %.2fs laps=%s drift=%s boost=%s" % [main.race_time, main.lap_times, drift_seen, boost_seen])
		quit(0)
	elif frames > 60 * 400:
		print("FAIL: did not finish, lap=%d" % kart.lap)
		quit(1)
