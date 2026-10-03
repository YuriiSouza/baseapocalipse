class_name SimZombie
extends RefCounted
## Deliberately cheap: no pathfinding, just a heading, obstacle sliding and detours.

const NO_GOAL := Vector2(-1.0, -1.0)
const SAVED: Array[String] = [
	"id", "health", "target", "siege", "lured", "hostile", "next_attack", "detour_until", "blocked"]

var id := 0
var pos := Vector2.ZERO
var health := 1.0
## Unit vector, or zero when standing still.
var heading := Vector2.ZERO
## Id of the person being chased, or -1.
var target := -1
## Id of the building being torn down, or -1.
var siege := -1
## Place it is walking to, or NO_GOAL while it stands around.
var goal := NO_GOAL
## The goal is a noise it heard or the place its prey was last seen, rather than
## somewhere it is roaming to.
var lured := false
## Chasing someone or attacking a building. Guards go after hostile zombies.
var hostile := false
var next_attack := 0
## While the tick is below this, the heading is a detour around an obstacle and is kept.
var detour_until := 0
## Times in a row it got blocked; each one makes the next detour longer.
var blocked := 0

# Not saved: only feeds render interpolation.
var prev_pos := Vector2.ZERO


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func to_dict() -> Dictionary:
	var d := {"x": pos.x, "y": pos.y, "hx": heading.x, "hy": heading.y, "gx": goal.x, "gy": goal.y}
	for field in SAVED:
		d[field] = get(field)
	return d


static func from_dict(d: Dictionary) -> SimZombie:
	var z := SimZombie.new()
	for field in SAVED:
		var value: Variant = d[field]
		z.set(field, int(value) if typeof(z.get(field)) == TYPE_INT else value)
	z.pos = Vector2(d["x"], d["y"])
	z.prev_pos = z.pos
	z.heading = Vector2(d["hx"], d["hy"])
	z.goal = Vector2(d["gx"], d["gy"])
	return z
