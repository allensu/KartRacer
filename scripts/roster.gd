extends RefCounted
## The eight original racers. Players pick one; AI racers take the rest.

const CHARACTERS := [
	{"name": "Ruby", "color": Color(0.85, 0.12, 0.15), "helmet": Color(1.0, 0.85, 0.85)},
	{"name": "Blaze", "color": Color(1.0, 0.5, 0.05), "helmet": Color(0.15, 0.15, 0.18)},
	{"name": "Pip", "color": Color(0.95, 0.85, 0.1), "helmet": Color(0.2, 0.55, 1.0)},
	{"name": "Rocco", "color": Color(0.15, 0.65, 0.25), "helmet": Color(0.95, 0.95, 0.95)},
	{"name": "Nova", "color": Color(0.1, 0.45, 0.95), "helmet": Color(0.95, 0.85, 0.2)},
	{"name": "Taro", "color": Color(0.55, 0.25, 0.8), "helmet": Color(0.3, 0.95, 0.75)},
	{"name": "Mika", "color": Color(1.0, 0.45, 0.7), "helmet": Color(1.0, 1.0, 1.0)},
	{"name": "Juno", "color": Color(0.9, 0.9, 0.92), "helmet": Color(0.9, 0.15, 0.3)},
]


static func count() -> int:
	return CHARACTERS.size()
