extends Control
## Top-down map of the track with a dot for every racer.

var track: Node3D
var karts: Array = []
var me: Node3D
var _points := PackedVector2Array()
var _scale := 1.0
var _offset := Vector2.ZERO


func setup(the_track: Node3D, the_karts: Array, local_kart: Node3D) -> void:
	track = the_track
	karts = the_karts
	me = local_kart
	var line: PackedVector3Array = track.centerline()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in line:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var pad := 14.0
	_scale = minf((size.x - pad * 2.0) / (hi.x - lo.x), (size.y - pad * 2.0) / (hi.y - lo.y))
	_offset = (size - (hi - lo) * _scale) * 0.5 - lo * _scale
	_points.clear()
	for i in range(0, line.size(), 2):
		_points.append(_map(line[i]))
	_points.append(_points[0])


func _map(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * _scale + _offset


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _points.size() < 2:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	draw_polyline(_points, Color(0, 0, 0, 0.7), 9.0, true)
	draw_polyline(_points, Color(0.85, 0.85, 0.9, 0.95), 5.0, true)
	var start := _map(track.transform_at(0.0).origin)
	draw_circle(start, 4.0, Color(1, 1, 1))
	for k in karts:
		if k == me:
			continue
		draw_circle(_map(k.global_position), 5.0, Color(0, 0, 0, 0.8))
		draw_circle(_map(k.global_position), 4.0, k.body_color)
	if me:
		var p := _map(me.global_position)
		draw_circle(p, 8.0, Color(1, 1, 1))
		draw_circle(p, 6.0, me.body_color)
