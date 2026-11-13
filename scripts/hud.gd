extends CanvasLayer
## On-screen race info: lap, timer, speed, drift charge, countdown and results.

var lap_label: Label
var time_label: Label
var speed_label: Label
var drift_label: Label
var center_label: Label
var results_label: Label
var help_label: Label


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

	results_label = _label(34, Vector2.ZERO)
	results_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	results_label.offset_top = 120
	results_label.visible = false

	help_label = _label(18, Vector2.ZERO)
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.offset_left = 32
	help_label.offset_top = -60
	help_label.offset_right = 900
	help_label.offset_bottom = -20
	help_label.text = "W/Up: gas   S/Down: brake   A/D: steer   Space/Shift: drift (hold while turning)   R: restart"
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


func show_results(total: float, laps: Array) -> void:
	var lines := ["FINISH!  Total  " + format_time(total)]
	var best := INF
	for t in laps:
		best = minf(best, t)
	for i in laps.size():
		var mark := "   (best)" if laps[i] == best else ""
		lines.append("Lap %d   %s%s" % [i + 1, format_time(laps[i]), mark])
	lines.append("")
	lines.append("Press Enter or R to race again")
	results_label.text = "\n".join(lines)
	results_label.visible = true


static func format_time(seconds: float) -> String:
	var m := int(seconds / 60.0)
	var s := fmod(seconds, 60.0)
	return "%02d:%06.3f" % [m, s]
