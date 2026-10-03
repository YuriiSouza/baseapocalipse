class_name SimAnimal
extends RefCounted
## Wild game. Wanders without pathfinding; hunters turn it into a carcass.

var id := 0
var pos := Vector2.ZERO
## Unit vector, or zero when standing still.
var heading := Vector2.ZERO

# Not saved: only feeds render interpolation.
var prev_pos := Vector2.ZERO


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func to_dict() -> Dictionary:
	return {"id": id, "x": pos.x, "y": pos.y, "hx": heading.x, "hy": heading.y}


static func from_dict(d: Dictionary) -> SimAnimal:
	var a := SimAnimal.new()
	a.id = int(d["id"])
	a.pos = Vector2(d["x"], d["y"])
	a.prev_pos = a.pos
	a.heading = Vector2(d["hx"], d["hy"])
	return a
