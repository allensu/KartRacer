extends Control
## Title screen: single player, create an online room, or join one by code.
## Also shows the room lobby until the host starts the race.

const RACE_SCENE := "res://scenes/main.tscn"
const InputSetup := preload("res://scripts/input_setup.gd")
const Roster := preload("res://scripts/roster.gd")
const TrackScript := preload("res://scripts/track.gd")

var _main_box: VBoxContainer
var _lobby_box: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _room_label: Label
var _players_label: Label
var _start_button: Button
var _waiting_label: Label
var _busy := false
var _track_box: VBoxContainer
var _char_buttons: Array[Button] = []
var _track_buttons: Array[Button] = []


func _ready() -> void:
	InputSetup.ensure()
	_build_ui()
	Net.status_changed.connect(_set_status)
	Net.failed.connect(_on_failed)
	Net.lobby_changed.connect(_refresh_lobby)
	Net.race_starting.connect(_on_race_starting)
	Net.room_closed.connect(_on_room_closed)
	_name_edit.text = Net.player_name if Net.player_name != "Player" else ""
	_refresh_choices()
	Sfx.play_music()
	if Net.room_code != "":
		_refresh_lobby()  # back from a race, still in the room
	else:
		_show_main()


# ---------------------------------------------------------------- actions

func _on_single() -> void:
	Net.leave()
	Net.mode = Net.Mode.SINGLE
	get_tree().change_scene_to_file(RACE_SCENE)


func _on_create() -> void:
	if _busy:
		return
	_busy = true
	Net.create_room(_player_name())


func _on_join() -> void:
	if _busy:
		return
	var code := _code_edit.text.strip_edges().to_upper()
	if code.length() != 4:
		_set_status("Enter the 4-letter room code")
		return
	_busy = true
	Net.join_room(code, _player_name())


func _on_start() -> void:
	Net.start_race()


func _on_leave() -> void:
	Net.leave()
	_show_main()
	_set_status("")


func _on_race_starting() -> void:
	get_tree().change_scene_to_file(RACE_SCENE)


func _on_failed(text: String) -> void:
	_busy = false
	_set_status(text)


func _on_room_closed(reason: String) -> void:
	_busy = false
	_show_main()
	_set_status(reason)


func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Player"


# ---------------------------------------------------------------- views

func _show_main() -> void:
	_main_box.visible = true
	_lobby_box.visible = false
	_track_box.visible = true


func _refresh_lobby() -> void:
	_busy = false
	if Net.room_code == "":
		_show_main()
		return
	_main_box.visible = false
	_lobby_box.visible = true
	_track_box.visible = Net.is_host()
	_room_label.text = "ROOM  " + Net.room_code
	var lines: Array[String] = []
	for i in Net.MAX_PLAYERS:
		if i < Net.players.size():
			var p: Dictionary = Net.players[i]
			var tags := ""
			if int(p.id) == Net.host_id:
				tags += "  (host)"
			if int(p.id) == Net.my_id:
				tags += "  < you"
			var ch: Dictionary = Roster.CHARACTERS[clampi(int(p.get("char", 0)), 0, Roster.count() - 1)]
			lines.append("%d.  %s  [%s]%s" % [i + 1, p.name, ch.name, tags])
		else:
			lines.append("%d.  -- open --" % (i + 1))
	_players_label.text = "\n".join(lines)
	_start_button.visible = Net.is_host()
	_waiting_label.visible = not Net.is_host()
	_set_status("Share the room code with friends. Empty spots are filled by AI racers.")


func _pick_char(i: int) -> void:
	Net.char_id = i
	Sfx.play("pickup", -8.0)
	_refresh_choices()


func _pick_track(id: String) -> void:
	Net.track_id = id
	Sfx.play("beep", -8.0)
	_refresh_choices()


func _refresh_choices() -> void:
	for i in _char_buttons.size():
		_char_buttons[i].button_pressed = i == Net.char_id
	for i in _track_buttons.size():
		_track_buttons[i].button_pressed = TrackScript.TRACK_ORDER[i] == Net.track_id


func _set_status(text: String) -> void:
	_status.text = text


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.09, 0.16)
	add_child(bg)
	var stripes := ColorRect.new()
	stripes.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stripes.offset_top = -12
	stripes.color = Color(0.85, 0.12, 0.15)
	add_child(stripes)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.custom_minimum_size = Vector2(520, 0)
	center.add_child(root)

	var title := _label("KARTRACER", 60, Color(1.0, 0.85, 0.2))
	root.add_child(title)
	root.add_child(_label("3 laps  -  8 racers  -  items", 22, Color(0.8, 0.85, 1.0)))

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	root.add_child(_main_box)
	_name_edit = _line_edit("Your name", 12)
	_main_box.add_child(_name_edit)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for i in Roster.count():
		var ch: Dictionary = Roster.CHARACTERS[i]
		var b := _choice_button(ch.name, ch.color)
		b.pressed.connect(_pick_char.bind(i))
		grid.add_child(b)
		_char_buttons.append(b)
	_main_box.add_child(grid)
	_main_box.add_child(_button("Single Player", _on_single))
	_main_box.add_child(_button("Create Online Room", _on_create))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	_code_edit = _line_edit("Room code", 4)
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_submitted.connect(func(_t): _on_join())
	join_row.add_child(_code_edit)
	var join := _button("Join Room", _on_join)
	join.custom_minimum_size.x = 200
	join_row.add_child(join)
	_main_box.add_child(join_row)

	_track_box = VBoxContainer.new()
	var track_row := HBoxContainer.new()
	track_row.add_theme_constant_override("separation", 8)
	for id in TrackScript.TRACK_ORDER:
		var layout: Dictionary = TrackScript.LAYOUTS[id]
		var b := _choice_button(layout.name, layout.walls[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick_track.bind(id))
		track_row.add_child(b)
		_track_buttons.append(b)
	_track_box.add_child(track_row)
	root.add_child(_track_box)
	root.move_child(_track_box, root.get_children().find(_main_box))

	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 12)
	_lobby_box.visible = false
	root.add_child(_lobby_box)
	_room_label = _label("ROOM", 44, Color.WHITE)
	_lobby_box.add_child(_room_label)
	_players_label = _label("", 26, Color(0.9, 0.92, 1.0))
	_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lobby_box.add_child(_players_label)
	_start_button = _button("Start Race", _on_start)
	_lobby_box.add_child(_start_button)
	_waiting_label = _label("Waiting for the host to start...", 22, Color(0.8, 0.85, 1.0))
	_lobby_box.add_child(_waiting_label)
	_lobby_box.add_child(_button("Leave Room", _on_leave))

	_status = _label("", 18, Color(1.0, 0.75, 0.6))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 50)
	root.add_child(_status)

	var help := _label("Drive: WASD / arrows   Drift: Space   Item: E   Menu: Esc", 16, Color(0.6, 0.65, 0.8))
	root.add_child(help)


func _choice_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(124, 46)
	b.add_theme_font_size_override("font_size", 20)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.45)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.border_color = color.darkened(0.2)
	var picked := normal.duplicate()
	picked.bg_color = color
	picked.border_color = Color.WHITE
	picked.set_border_width_all(4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", picked)
	b.add_theme_stylebox_override("hover_pressed", picked)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var light := color.get_luminance() > 0.6
	b.add_theme_color_override("font_pressed_color", Color.BLACK if light else Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.BLACK if light else Color.WHITE)
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	return b


func _line_edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 52)
	e.add_theme_font_size_override("font_size", 24)
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return e
