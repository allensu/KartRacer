extends SceneTree
## Online smoke test: run one host and one or more clients against a relay.
##   node server/server.js &
##   godot --headless -s res://tests/net_test.gd -- host ws://localhost:8080 3 /tmp/room.txt
##   godot --headless -s res://tests/net_test.gd -- client ws://localhost:8080 3 /tmp/room.txt
## Every player's kart is driven by an AI driver. Passes when this computer
## sees all human karts finish and received state for every remote kart.

const AiDriver := preload("res://scripts/ai_driver.gd")

var role := "host"
var expected := 2
var code_file := ""
var net: Node
var main: Node
var frames := 0
var started := false
var finished_frame := -1
var events := {"oil": 0, "seek": 0, "rm": 0}
var joined := false
var quit_at := -1
var exit_code := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	expected = int(args[2])
	code_file = args[3]
	net = root.get_node("Net")
	net.server_url = args[1]
	net.failed.connect(func(t): print("[%s] failed: %s" % [role, t]); quit(2))
	net.race_starting.connect(func(): change_scene_to_file("res://scenes/main.tscn"))
	net.message.connect(func(_f, d):
		var t: String = d.get("t", "")
		if events.has(t):
			events[t] += 1)
	if role == "host":
		net.lobby_changed.connect(_on_lobby)
		net.create_room("Host")
	process_frame.connect(_tick)


func _on_lobby() -> void:
	if net.players.size() == 1:
		var f := FileAccess.open(code_file, FileAccess.WRITE)
		f.store_string(net.room_code)
		f.close()
		print("[host] room ", net.room_code)
	if net.players.size() == expected and not started:
		started = true
		print("[host] %d players, starting" % expected)
		net.start_race()


func _tick() -> void:
	frames += 1
	if quit_at > 0:
		if frames >= quit_at:
			quit(exit_code)
		return
	if role == "client" and not joined and frames % 60 == 0 and FileAccess.file_exists(code_file):
		var code := FileAccess.get_file_as_string(code_file).strip_edges()
		if code.length() == 4:
			joined = true
			net.join_room(code, "Guest%d" % (OS.get_process_id() % 100))
	var scene := current_scene
	if scene == null or not scene.has_method("spawn_oil"):
		if frames > 60 * 120:
			print("[%s] FAIL: race never started" % role)
			quit(1)
		return
	main = scene
	if main.kart.get_node_or_null("TestAI") == null and not main.kart.finished:
		main.kart.is_player = false
		var ai: Node = AiDriver.new()
		ai.name = "TestAI"
		main.kart.add_child(ai)
		ai.setup(main.kart, OS.get_process_id())
	if main.kart.finished and finished_frame < 0:
		finished_frame = frames
	var humans_done: bool = main.human_karts.all(func(k): return k.finished)
	if finished_frame > 0 and (humans_done or frames - finished_frame > 60 * 40):
		var remote_ok := true
		for k in main.karts:
			if k.is_remote and not k._net_has_state:
				remote_ok = false
		var order := []
		for k in main.standings:
			order.append("%s%s(%s)" % [k.racer_name, "*" if k.is_remote else "", "%.1f" % k.finish_time if k.finished else "L%d" % k.lap])
		print("[%s] humans=%d remote_karts=%d all_have_state=%s humans_done=%s events=%s" % [
			role, main.human_karts.size(), main.karts.filter(func(k): return k.is_remote).size(), remote_ok, humans_done, events])
		print("[%s] standings: %s" % [role, " ".join(order)])
		var ok: bool = remote_ok and humans_done and main.human_karts.size() == expected
		print("[%s] %s" % [role, "PASS" if ok else "FAIL"])
		# Keep sending our final state for a moment so the others see us finish.
		exit_code = 0 if ok else 1
		quit_at = frames + 180
	elif frames > 60 * 400:
		print("[%s] FAIL: timeout" % role)
		quit(1)
