extends RefCounted
## Item definitions plus the in-world objects: item boxes, oil slicks and the
## homing seeker. Everything is built from primitive meshes in code.

const NAMES := {
	"nitro": "NITRO",
	"oil": "OIL SLICK",
	"seeker": "SEEKER",
	"shield": "SHIELD",
}
const COLORS := {
	"nitro": Color(1.0, 0.55, 0.1),
	"oil": Color(0.55, 0.3, 0.75),
	"seeker": Color(1.0, 0.2, 0.25),
	"shield": Color(0.3, 0.8, 1.0),
}
# Odds for [nitro, oil, seeker, shield] when leading vs. when last.
const ODDS_FRONT := [2.0, 5.0, 1.0, 4.0]
const ODDS_BACK := [5.0, 1.0, 4.0, 1.5]
const ORDER := ["nitro", "oil", "seeker", "shield"]


## Pick an item; racers further back get better catch-up items.
static func roll(position: int, field_size: int, rng: RandomNumberGenerator) -> String:
	var t := 0.0 if field_size <= 1 else float(position - 1) / float(field_size - 1)
	var total := 0.0
	var weights: Array[float] = []
	for i in ORDER.size():
		var w := lerpf(ODDS_FRONT[i], ODDS_BACK[i], t)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in ORDER.size():
		r -= weights[i]
		if r <= 0.0:
			return ORDER[i]
	return ORDER[-1]


static func unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _is_kart(body: Node) -> bool:
	return body is CharacterBody3D and body.has_method("hit")


## A spinning translucent cube. Driving through it gives an item and it
## reappears a few seconds later.
class ItemBox extends Area3D:
	const RESPAWN := 3.0
	var _cube: MeshInstance3D
	var _inner: MeshInstance3D
	var _timer := 0.0
	var _t := 0.0

	func _ready() -> void:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.2, 2.4, 2.2)
		shape.shape = box
		shape.position.y = 1.0
		add_child(shape)
		_cube = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.6, 1.6, 1.6)
		_cube.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.8, 1.0, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.6, 1.0)
		mat.emission_energy_multiplier = 1.4
		mat.metallic = 0.5
		mat.roughness = 0.1
		_cube.material_override = mat
		_cube.position.y = 1.2
		add_child(_cube)
		_inner = MeshInstance3D.new()
		var q := SphereMesh.new()
		q.radius = 0.32
		q.height = 0.64
		_inner.mesh = q
		_inner.material_override = load("res://scripts/items.gd").unshaded(Color(1.0, 0.95, 0.4))
		_cube.add_child(_inner)
		body_entered.connect(_on_body_entered)

	func _process(delta: float) -> void:
		_t += delta
		_cube.rotation = Vector3(_t * 0.7, _t * 1.3, 0.0)
		_cube.position.y = 1.2 + sin(_t * 2.5 + position.x) * 0.15
		if _timer > 0.0:
			_timer -= delta
			if _timer <= 0.0:
				_cube.visible = true
				set_deferred("monitoring", true)

	func _on_body_entered(body: Node) -> void:
		if _timer > 0.0 or not (body is CharacterBody3D and body.has_method("give_random_item")):
			return
		body.give_random_item()
		_cube.visible = false
		_timer = RESPAWN
		set_deferred("monitoring", false)


## A puddle that spins out the first kart to touch it.
class OilSlick extends Area3D:
	var owner_kart: Node
	var _grace := 0.6

	func _ready() -> void:
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.3
		cyl.height = 1.5
		shape.shape = cyl
		add_child(shape)
		var puddle := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.4
		mesh.bottom_radius = 1.4
		mesh.height = 0.04
		puddle.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.05, 0.2)
		mat.metallic = 0.9
		mat.roughness = 0.05
		puddle.material_override = mat
		puddle.position.y = 0.06
		add_child(puddle)
		body_entered.connect(_on_body_entered)

	func _process(delta: float) -> void:
		_grace -= delta

	func _on_body_entered(body: Node) -> void:
		if not (body is CharacterBody3D and body.has_method("hit")):
			return
		if body == owner_kart and _grace > 0.0:
			return
		body.hit()
		queue_free()


## A missile that follows the track to the kart ahead and spins it out.
class Seeker extends Node3D:
	const SPEED := 52.0
	const LIFETIME := 9.0
	var owner_kart: Node
	var target: Node3D
	var track: Node3D
	var _life := 0.0
	var _trail: CPUParticles3D

	func _ready() -> void:
		var body := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.28
		mesh.height = 1.2
		body.mesh = mesh
		body.rotation.x = PI / 2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.15, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.05, 0.05)
		mat.metallic = 0.4
		mat.roughness = 0.3
		body.material_override = mat
		add_child(body)
		_trail = CPUParticles3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.15
		pm.height = 0.3
		var pmat := StandardMaterial3D.new()
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.vertex_color_use_as_albedo = true
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.material = pmat
		_trail.mesh = pm
		_trail.amount = 24
		_trail.lifetime = 0.4
		_trail.local_coords = false
		_trail.direction = Vector3(0, 0, 1)
		_trail.spread = 10.0
		_trail.initial_velocity_min = 1.0
		_trail.initial_velocity_max = 2.0
		_trail.gravity = Vector3.ZERO
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.9, 0.5))
		grad.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
		_trail.color_ramp = grad
		_trail.position.z = 0.6
		add_child(_trail)

	func _physics_process(delta: float) -> void:
		_life += delta
		if _life > LIFETIME or (target != null and not is_instance_valid(target)):
			queue_free()
			return
		var aim: Vector3
		if target == null:
			aim = global_position - global_transform.basis.z * 10.0
		else:
			var to_target := target.global_position - global_position
			var my_progress: float = track.progress_of(global_position)
			var their_progress: float = track.progress_of(target.global_position)
			var ahead := fposmod(their_progress - my_progress, track.length)
			if ahead > 20.0 and to_target.length() > 20.0:
				aim = track.transform_at(my_progress + 12.0).origin
			else:
				aim = target.global_position
			if to_target.length() < 1.8:
				target.hit()
				queue_free()
				return
		aim.y = 0.8
		var dir := (aim - global_position)
		dir.y = 0.0
		if dir.length() > 0.01:
			var want := Basis.looking_at(dir.normalized(), Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(want, clampf(10.0 * delta, 0.0, 1.0)).orthonormalized()
		global_position += -global_transform.basis.z * SPEED * delta
		global_position.y = 0.8
