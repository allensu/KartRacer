extends Node3D
## Procedurally builds the "Sunset Loop" test circuit from a closed spline:
## road surface, curbs, run-off grass, barrier walls, start gantry and scenery.
## Also answers race questions (progress along the lap, grid slots, off-road).

const ROAD_WIDTH := 14.0
const CURB_WIDTH := 1.4
const RUNOFF := 7.0
const WALL_HEIGHT := 1.2
const SEGMENT := 2.0
const TEXTURE_REPEAT := 16.0

# Control points (x, z) of the circuit, driven in this order. Start line is the first point.
const POINTS := [
	Vector2(0, 0), Vector2(0, -110), Vector2(15, -165), Vector2(65, -190),
	Vector2(125, -175), Vector2(150, -125), Vector2(135, -78), Vector2(95, -55),
	Vector2(85, -5), Vector2(115, 35), Vector2(180, 55), Vector2(205, 115),
	Vector2(170, 170), Vector2(95, 185), Vector2(30, 160), Vector2(5, 90),
]

var curve: Curve3D
var length := 0.0
var _pos: PackedVector3Array = []
var _right: PackedVector3Array = []
var _count := 0
var _step := 0.0


func build() -> void:
	_build_curve()
	_build_frames()
	_build_ground()
	_build_road()
	_build_curbs()
	_build_walls()
	_build_start_line()
	_build_scenery()


# ---------------------------------------------------------------- race queries

func progress_of(world_pos: Vector3) -> float:
	return curve.get_closest_offset(to_local(world_pos))


func lateral_distance(world_pos: Vector3) -> float:
	var p := to_local(world_pos)
	var c := curve.get_closest_point(p)
	return Vector2(p.x - c.x, p.z - c.z).length()


func is_offroad(world_pos: Vector3) -> bool:
	return lateral_distance(world_pos) > ROAD_WIDTH * 0.5 + CURB_WIDTH


func transform_at(offset: float, lateral := 0.0) -> Transform3D:
	var f := _frame(offset)
	var basis := Basis.looking_at(f[1], Vector3.UP)
	return Transform3D(basis, to_global(f[0] + f[2] * lateral))


## Starting grid: two staggered columns behind the start line. Slot 0 is pole.
func grid_transform(slot: int) -> Transform3D:
	var row := slot / 2
	var side := -1.0 if slot % 2 == 0 else 1.0
	var t := transform_at(length - 8.0 - row * 7.0 - (slot % 2) * 3.5, side * 3.2)
	t.origin.y = 0.5
	return t


# ---------------------------------------------------------------- construction

func _build_curve() -> void:
	curve = Curve3D.new()
	curve.bake_interval = 0.5
	var n := POINTS.size()
	for i in n + 1:
		var p := _v3(POINTS[i % n])
		var tangent := (_v3(POINTS[(i + 1) % n]) - _v3(POINTS[(i - 1 + n) % n])) * 0.22
		curve.add_point(p, -tangent, tangent)
	length = curve.get_baked_length()


func _build_frames() -> void:
	_count = int(length / SEGMENT)
	_step = length / _count
	_pos.resize(_count)
	_right.resize(_count)
	for i in _count:
		var f := _frame(i * _step)
		_pos[i] = f[0]
		_right[i] = f[2]


func _frame(offset: float) -> Array:
	offset = fposmod(offset, length)
	var p := curve.sample_baked(offset)
	var ahead := curve.sample_baked(fposmod(offset + 1.0, length))
	var behind := curve.sample_baked(fposmod(offset - 1.0, length))
	var fwd := ahead - behind
	fwd.y = 0.0
	fwd = fwd.normalized()
	return [p, fwd, fwd.cross(Vector3.UP).normalized()]


## A flat band alongside the centre line between two lateral offsets.
func _ribbon(inner: float, outer: float, y: float, uv_across := Vector2(0, 1), colors: Array = []) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3(0, y, 0)
	for i in _count:
		var j := (i + 1) % _count
		var a_in := _pos[i] + _right[i] * inner + up
		var a_out := _pos[i] + _right[i] * outer + up
		var b_in := _pos[j] + _right[j] * inner + up
		var b_out := _pos[j] + _right[j] * outer + up
		var va := i * _step / TEXTURE_REPEAT
		var vb := (i + 1) * _step / TEXTURE_REPEAT
		var col: Color = colors[i % colors.size()] if colors.size() > 0 else Color.WHITE
		_quad(st, [a_in, a_out, b_out, b_in],
			[Vector2(uv_across.x, va), Vector2(uv_across.y, va), Vector2(uv_across.y, vb), Vector2(uv_across.x, vb)],
			Vector3.UP, col)
	return st.commit()


func _quad(st: SurfaceTool, v: Array, uv: Array, normal: Vector3, col: Color) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(normal)
		st.set_uv(uv[idx])
		st.add_vertex(v[idx])


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	ground.mesh = plane
	ground.position = Vector3(100, -0.02, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _grass_texture()
	mat.uv1_scale = Vector3(140, 140, 1)
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ground.material_override = mat
	add_child(ground)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)


func _build_road() -> void:
	var road := MeshInstance3D.new()
	road.mesh = _ribbon(-ROAD_WIDTH * 0.5, ROAD_WIDTH * 0.5, 0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _road_texture()
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	road.material_override = mat
	add_child(road)


func _build_curbs() -> void:
	var stripes := [Color(0.85, 0.1, 0.12), Color(0.95, 0.95, 0.95)]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var half := ROAD_WIDTH * 0.5
	for side: float in [-1.0, 1.0]:
		var curb := MeshInstance3D.new()
		curb.mesh = _ribbon(side * half, side * (half + CURB_WIDTH), 0.04, Vector2(0, 1), stripes)
		curb.material_override = mat
		add_child(curb)


func _build_walls() -> void:
	var colors := [Color(0.1, 0.35, 0.85), Color(0.95, 0.95, 0.95)]
	var dist := ROAD_WIDTH * 0.5 + CURB_WIDTH + RUNOFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := StaticBody3D.new()
	add_child(body)
	for side: float in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var faces := PackedVector3Array()
		for i in _count:
			var j := (i + 1) % _count
			var a := _pos[i] + _right[i] * side * dist
			var b := _pos[j] + _right[j] * side * dist
			var h := Vector3(0, WALL_HEIGHT, 0)
			var quad := [a, b, b + h, a + h]
			var normal := -_right[i] * side
			var col: Color = colors[(i / 2) % 2]
			_quad(st, quad, [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], normal, col)
			# A thin cap on top so the barrier reads as a solid block.
			var t := normal * -0.5
			_quad(st, [a + h, b + h, b + h + t, a + h + t], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], Vector3.UP, col.darkened(0.15))
			for idx in [0, 1, 2, 0, 2, 3]:
				faces.append(quad[idx])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		add_child(mi)
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)


func _build_start_line() -> void:
	var t := transform_at(0.0)
	# Checkered strip across the road.
	var line := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROAD_WIDTH, 2.4)
	line.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _checker_texture(12, 2)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	line.material_override = mat
	line.transform = t
	line.position.y = 0.05
	add_child(line)

	# Gantry over the start line.
	var gantry := Node3D.new()
	gantry.transform = t
	add_child(gantry)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.2, 0.2, 0.24)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.35
	var span := ROAD_WIDTH + CURB_WIDTH * 2 + 2.0
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 7.0, 0.7)
		post.mesh = box
		post.material_override = post_mat
		post.position = Vector3(side * span * 0.5, 3.5, 0)
		gantry.add_child(post)
	var banner := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(span + 0.7, 1.6, 0.5)
	banner.mesh = bbox
	var banner_mat := StandardMaterial3D.new()
	banner_mat.albedo_texture = _checker_texture(24, 3)
	banner_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	banner.material_override = banner_mat
	banner.position = Vector3(0, 7.0, 0)
	gantry.add_child(banner)


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113
	var clear := ROAD_WIDTH * 0.5 + CURB_WIDTH + RUNOFF + 5.0
	var spots: Array[Transform3D] = []
	var tries := 0
	while spots.size() < 160 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(-140, 340), 0, rng.randf_range(-300, 300))
		var c := curve.get_closest_point(p)
		if Vector2(p.x - c.x, p.z - c.z).length() < clear:
			continue
		var s := rng.randf_range(0.8, 1.6)
		spots.append(Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 2.0
	trunk.radial_segments = 8
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.26, 0.15)
	trunk.material = trunk_mat
	_multimesh(trunk, spots, Vector3(0, 1.0, 0))

	var leaves := CylinderMesh.new()
	leaves.top_radius = 0.0
	leaves.bottom_radius = 2.2
	leaves.height = 4.5
	leaves.radial_segments = 10
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.13, 0.42, 0.2)
	leaf_mat.roughness = 0.9
	leaves.material = leaf_mat
	_multimesh(leaves, spots, Vector3(0, 3.8, 0))

	# Distant hills to give the horizon some shape.
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.32, 0.5, 0.36)
	hill_mat.roughness = 1.0
	for k in 14:
		var angle := k * TAU / 14.0 + rng.randf_range(-0.1, 0.1)
		var hill := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var r := rng.randf_range(60, 110)
		sphere.radius = r
		sphere.height = r * rng.randf_range(0.7, 1.1)
		sphere.material = hill_mat
		hill.mesh = sphere
		hill.position = Vector3(100 + cos(angle) * 520, -r * 0.15, sin(angle) * 520)
		add_child(hill)


func _multimesh(mesh: Mesh, spots: Array[Transform3D], lift: Vector3) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var t := spots[i]
		mm.set_instance_transform(i, Transform3D(t.basis, t.origin + t.basis * lift))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# ---------------------------------------------------------------- textures

func _road_texture() -> ImageTexture:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in h:
		for x in w:
			var g := 0.28 + rng.randf_range(-0.03, 0.03)
			var c := Color(g, g, g * 1.04)
			var u := float(x) / w
			if (u > 0.03 and u < 0.055) or (u > 0.945 and u < 0.97):
				c = Color(0.92, 0.92, 0.88)
			elif u > 0.493 and u < 0.507 and y < h / 2:
				c = Color(0.95, 0.82, 0.2)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _grass_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in n:
		for x in n:
			var v := rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(0.22 + v, 0.42 + v * 1.5, 0.16 + v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _checker_texture(cols: int, rows: int) -> ImageTexture:
	var img := Image.create(cols, rows, false, Image.FORMAT_RGB8)
	for y in rows:
		for x in cols:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.05, 0.05, 0.05))
	return ImageTexture.create_from_image(img)


static func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0, p.y)
