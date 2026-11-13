extends RefCounted
## Registers the game's input actions at startup, so keyboard and gamepad
## bindings live in code instead of hand-edited project.godot entries.

const KEYS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"drift": [KEY_SPACE, KEY_SHIFT],
	"use_item": [KEY_E, KEY_CTRL, KEY_J],
	"restart": [KEY_R],
	"confirm": [KEY_ENTER],
	"menu": [KEY_ESCAPE],
}

const PAD_BUTTONS := {
	"accelerate": [JOY_BUTTON_A],
	"brake": [JOY_BUTTON_X],
	"drift": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER],
	"use_item": [JOY_BUTTON_B, JOY_BUTTON_Y],
	"restart": [JOY_BUTTON_BACK],
	"confirm": [JOY_BUTTON_START],
}


static func ensure() -> void:
	if InputMap.has_action("menu"):
		return  # already registered (e.g. after a scene reload)
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in PAD_BUTTONS:
		for button in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	_add_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)


static func _add_axis(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
