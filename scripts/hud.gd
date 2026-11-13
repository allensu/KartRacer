extends CanvasLayer
## On-screen race info: position, lap, timer, item slot, standings, speed,
## drift charge, countdown and the results table.

const Items := preload("res://scripts/items.gd")

var lap_label: Label
var time_label: Label
var speed_label: Label
var drift_label: Label
var center_label: Label
var results_label: Label
var results_panel: Panel
var help_label: Label
var position_label: Label
var standings_label: Label
var item_panel: Panel
var item_label: Label
var _item_style: StyleBoxFlat
var _roll_t := 0.0


func _ready() -> void:
	lap_label = _label(40, Vector2(32, 24))
	time_label = _label(30, Vector2(32, 80))
	speed_label = _label(44, Vector2.ZERO)
	speed_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_label.offset_left = -360
	speed_label.offset_top = -90
	speed_label.offset_right = -32
	speed_label.offset_bottom = -24
	drift_label = _label(28, Vector2.ZERO)
	drift_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	drift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	drift_label.offset_left = -360
	drift_label.offset_top = -140
	drift_label.offset_right = -32
	drift_label.offset_bottom = -95

	center_label = _label(110, Vector2.ZERO)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.offset_bottom = -120

	results_panel = Panel.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.1, 0.78)
	bg.border_color = Color(1.0, 0.85, 0.3, 0.9)
	bg.set_border_width_all(3)
	bg.set_corner_radius_all(18)
	results_panel.add_theme_stylebox_override("panel", bg)
	results_panel.set_anchors_preset(Control.PRESET_CENTER)
	results_panel.offset_left = -300
	results_panel.offset_right = 300
	results_panel.offset_top = -270
	results_panel.offset_bottom = 270
	results_panel.visible = false
	add_child(results_panel)
	results_label = _label(26, Vector2.ZERO)
	remove_child(results_label)
	results_panel.add_child(results_label)
	results_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	help_label = _label(18, Vector2.ZERO)
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.offset_left = 32
	help_label.offset_top = -60
	help_label.offset_right = 900
	help_label.offset_bottom = -20
	help_label.text = "W/Up: gas   S/Down: brake   A/D: steer   Space/Shift: drift   E/Ctrl: use item   R: restart   Esc: menu"
	help_label.offset_right = 1100

	position_label = _label(76, Vector2.ZERO)
	position_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	position_label.offset_left = -360
	position_label.offset_top = 16
	position_label.offset_right = -32
	position_label.offset_bottom = 110

	standings_label = _label(20, Vector2(32, 130))
	standings_label.modulate.a = 0.9

	item_panel = Panel.new()
	_item_style = StyleBoxFlat.new()
	_item_style.bg_color = Color(0, 0, 0, 0.45)
	_item_style.border_color = Color(1, 1, 1, 0.8)
	_item_style.set_border_width_all(4)
	_item_style.set_corner_radius_all(14)
	item_panel.add_theme_stylebox_override("panel", _item_style)
	item_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	item_panel.offset_left = -110
	item_panel.offset_right = 110
	item_panel.offset_top = 18
	item_panel.offset_bottom = 88
	add_child(item_panel)
	item_label = _label(28, Vector2.ZERO)
	remove_child(item_label)
	item_panel.add_child(item_label)
	item_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label.modulate.a = 0.8


func _label(size: int, pos: Vector2) -> Label:
	var l := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.outline_size = max(4, size / 6)
	settings.outline_color = Color(0, 0, 0, 0.85)
	settings.shadow_color = Color(0, 0, 0, 0.4)
	settings.shadow_offset = Vector2(2, 3)
	l.label_settings = settings
	l.position = pos
	add_child(l)
	return l


func set_lap(lap: int, total: int) -> void:
	lap_label.text = "LAP %d / %d" % [mini(lap, total), total]


func set_time(seconds: float) -> void:
	time_label.text = format_time(seconds)


func set_speed(units_per_sec: float) -> void:
	speed_label.text = "%d km/h" % int(absf(units_per_sec) * 3.6)


func set_drift(level: int) -> void:
	var names := ["", "MINI-TURBO", "SUPER TURBO"]
	var colors := [Color.WHITE, Color(0.45, 0.7, 1.0), Color(1.0, 0.55, 0.2)]
	drift_label.text = names[level]
	drift_label.label_settings.font_color = colors[level]


func show_center(text: String, color := Color.WHITE) -> void:
	center_label.text = text
	center_label.label_settings.font_color = color


func set_position(place: int, total: int) -> void:
	position_label.text = "%s / %d" % [ordinal(place), total]
	var colors := [Color(1.0, 0.85, 0.2), Color(0.85, 0.88, 0.95), Color(0.95, 0.6, 0.3)]
	position_label.label_settings.font_color = colors[place - 1] if place <= 3 else Color.WHITE


func set_item(item: String, roll_time: float) -> void:
	if roll_time > 0.0:
		_roll_t += 0.25
		var names := Items.ORDER
		var shown: String = names[int(_roll_t) % names.size()]
		item_label.text = Items.NAMES[shown]
		_item_style.border_color = Items.COLORS[shown]
	elif item != "":
		item_label.text = Items.NAMES[item]
		_item_style.border_color = Items.COLORS[item]
	else:
		item_label.text = ""
		_item_style.border_color = Color(1, 1, 1, 0.5)


func set_standings(standings: Array, player: Node) -> void:
	var lines: Array[String] = []
	for k in standings:
		var marker := "> " if k == player else "   "
		lines.append("%s%d  %s" % [marker, k.place, k.racer_name])
	standings_label.text = "\n".join(lines)


func set_room(code: String) -> void:
	help_label.text = "ROOM %s     " % code + help_label.text.replace("R: restart   Esc: menu", "Esc: leave room")


func show_results(player: Node, standings: Array, laps: Array, footer := "Press Enter or R to race again") -> void:
	var lines := ["RESULTS   You finished %s" % ordinal(player.place), ""]
	for k in standings:
		var t: String = format_time(k.finish_time) if k.finished else "--:--.---"
		var marker := "> " if k == player else "   "
		lines.append("%s%s   %-6s   %s" % [marker, ordinal(k.place), k.racer_name, t])
	lines.append("")
	var best := INF
	for lt in laps:
		best = minf(best, lt)
	lines.append("Best lap  " + format_time(best))
	lines.append(footer)
	results_label.text = "\n".join(lines)
	results_panel.visible = true
	center_label.text = ""
	standings_label.visible = false
	item_panel.visible = false


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


static func format_time(seconds: float) -> String:
	var m := int(seconds / 60.0)
	var s := fmod(seconds, 60.0)
	return "%02d:%06.3f" % [m, s]
