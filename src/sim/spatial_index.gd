class_name SpatialIndex
extends RefCounted
## Uniform bucket grid over cell space, for "who is near this point" queries
## without scanning every entity.

const BUCKET := 8

var _cols := 0
var _rows := 0
var _buckets: Array[Array] = []


func _init(width: int, height: int) -> void:
	_cols = ceili(float(width) / BUCKET)
	_rows = ceili(float(height) / BUCKET)
	_buckets.resize(_cols * _rows)
	for i in _buckets.size():
		_buckets[i] = []


func add(id: int, pos: Vector2) -> void:
	_buckets[_key(pos)].append(id)


func remove(id: int, pos: Vector2) -> void:
	_buckets[_key(pos)].erase(id)


func move(id: int, from: Vector2, to: Vector2) -> void:
	var a := _key(from)
	var b := _key(to)
	if a != b:
		_buckets[a].erase(id)
		_buckets[b].append(id)


## Ids in every bucket touching the circle. A superset: callers still check the exact distance.
func query(center: Vector2, radius: float) -> Array[int]:
	var out: Array[int] = []
	var x0 := _bucket_coord(center.x - radius, _cols)
	var x1 := _bucket_coord(center.x + radius, _cols)
	var y0 := _bucket_coord(center.y - radius, _rows)
	var y1 := _bucket_coord(center.y + radius, _rows)
	for by in range(y0, y1 + 1):
		for bx in range(x0, x1 + 1):
			out.append_array(_buckets[by * _cols + bx])
	return out


func _key(pos: Vector2) -> int:
	return _bucket_coord(pos.y, _rows) * _cols + _bucket_coord(pos.x, _cols)


func _bucket_coord(v: float, count: int) -> int:
	return clampi(floori(v / BUCKET), 0, count - 1)
