class_name Iso
extends RefCounted
## Cell space <-> isometric world space. A cell is a 64x32 diamond.

const HALF_W := 32.0
const HALF_H := 16.0


static func to_world(c: Vector2) -> Vector2:
	return Vector2((c.x - c.y) * HALF_W, (c.x + c.y) * HALF_H)


static func to_cell(p: Vector2) -> Vector2:
	var a := p.x / HALF_W
	var b := p.y / HALF_H
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


static func cell_at(p: Vector2) -> Vector2i:
	var c := to_cell(p)
	return Vector2i(floori(c.x), floori(c.y))


## Corners of a footprint in the order top, right, bottom, left, raised by `lift` pixels.
static func diamond(cell: Vector2, size := Vector2.ONE, lift := 0.0) -> PackedVector2Array:
	var up := Vector2(0.0, -lift)
	return PackedVector2Array([
		to_world(cell) + up,
		to_world(cell + Vector2(size.x, 0.0)) + up,
		to_world(cell + size) + up,
		to_world(cell + Vector2(0.0, size.y)) + up,
	])
