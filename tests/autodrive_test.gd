extends SceneTree
## Headless smoke test: the player's kart is handed to an AI driver and the
## full 8-kart race runs. Passes if the player finishes 3 laps, the AI field
## finishes too, and drifting, boosts, items and hits all happened.
## Run: godot --headless --fixed-fps 60 -s res://tests/autodrive_test.gd [-- canyon]

const AiDriver := preload("res://scripts/ai_driver.gd")

var main: Node
var frames := 0
var seen := {"drift": false, "boost": false, "item": false, "spin": false, "shield": false}
var player_done_frame := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		root.get_node("Net").track_id = args[0]  # e.g. -- canyon
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	physics_frame.connect(_tick)


func _tick() -> void:
	frames += 1
	if frames == 1:
		main.kart.is_player = false
		var ai: Node = AiDriver.new()
		main.kart.add_child(ai)
		ai.setup(main.kart, 12345)
	for k in main.karts:
		seen.drift = seen.drift or k.drifting
		seen.boost = seen.boost or k.boost_time > 0.0
		seen.item = seen.item or k.item != ""
		seen.spin = seen.spin or k.spin_time > 0.0
		seen.shield = seen.shield or k.shield_time > 0.0
	if frames % 1200 == 0:
		var order := []
		for k in main.standings:
			order.append("%s(L%d)" % [k.racer_name, k.lap])
		print("t=%.0fs  %s" % [frames / 60.0, " ".join(order)])
	if main.kart.finished and player_done_frame < 0:
		player_done_frame = frames
		print("Player finished %s in %.2fs, laps=%s" % [main.hud.ordinal(main.kart.place), main.kart.finish_time, main.lap_times])
	var all_done: bool = main.karts.all(func(k): return k.finished)
	if all_done or (player_done_frame > 0 and frames - player_done_frame > 60 * 60):
		var done: int = main.karts.filter(func(k): return k.finished).size()
		print("Finished karts: %d/8  features seen: %s" % [done, seen])
		var ok: bool = done >= 6 and seen.values().all(func(v): return v)
		print("PASS" if ok else "FAIL")
		quit(0 if ok else 1)
	elif frames > 60 * 420:
		print("FAIL: timeout, player lap=%d seen=%s" % [main.kart.lap, seen])
		quit(1)
