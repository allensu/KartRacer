extends SceneTree
## Renders a few gameplay screenshots for review (needs a real renderer):
##   xvfb-run godot --rendering-driver opengl3 --fixed-fps 60 -s res://tests/screenshots.gd -- OUT_DIR
## Shots: approaching item boxes, a seeker in flight, and the results screen.

const AiDriver := preload("res://scripts/ai_driver.gd")

var main: Node
var frames := 0
var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	physics_frame.connect(_tick)


func _shot(name: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _tick() -> void:
	frames += 1
	var k = main.kart
	if frames == 1:
		k.is_player = false
		var ai: Node = AiDriver.new()
		k.add_child(ai)
		ai.setup(k, 4242)
	if frames == 300:
		# Jump the whole field to just before the second row of item boxes.
		var base: float = main.track.length * 0.47 - 45.0
		for i in main.karts.size():
			var kk = main.karts[i]
			var ofs: float = base + 12.0 if kk == k else base - (i / 4) * 8.0
			var lat: float = 0.0 if kk == k else -4.5 + (i % 4) * 3.0
			kk.global_transform = main.track.transform_at(ofs, lat)
			kk.global_position.y = 0.5
			kk.speed = 25.0
		main.cam.snap()
	if frames == 330:
		_shot("items_ahead")
	if frames == 420:
		k.item = "seeker"
		k.use_item()
	if frames == 440:
		_shot("seeker")
	if frames == 470:
		k.shield_time = 5.0
		k.item = "oil"
		_shot("item_slot_shield")
	if frames == 480:
		# Fast-forward to the results screen.
		k.lap = 3
		k._passed_half = true
		k.lap_completed.emit(3)
		k.lap = 4
	if frames == 660:
		_shot("results")
		quit(0)
