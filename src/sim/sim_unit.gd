class_name SimUnit
extends RefCounted
## A villager. Positions are in cell space; the centre of cell (x, y) is (x + 0.5, y + 0.5).

enum State { IDLE, MOVING, TO_RESOURCE, GATHERING, TO_DROPOFF, TO_BUILD, BUILDING }

var id := 0
var pos := Vector2.ZERO
var state := State.IDLE
var dest := Vector2i(-1, -1)
var target_cell := Vector2i(-1, -1)
var target_building := -1
var gather_kind := ""
var carry_kind := ""
var carry_amount := 0
var work_ticks := 0

# Not saved: the path is re-planned on demand, prev_pos only feeds render interpolation.
var path: Array[Vector2i] = []
var prev_pos := Vector2.ZERO


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func to_dict() -> Dictionary:
	return {
		"id": id,
		"x": pos.x,
		"y": pos.y,
		"state": int(state),
		"dest": [dest.x, dest.y],
		"target_cell": [target_cell.x, target_cell.y],
		"target_building": target_building,
		"gather_kind": gather_kind,
		"carry_kind": carry_kind,
		"carry_amount": carry_amount,
		"work_ticks": work_ticks,
	}


static func from_dict(d: Dictionary) -> SimUnit:
	var u := SimUnit.new()
	u.id = int(d["id"])
	u.pos = Vector2(d["x"], d["y"])
	u.prev_pos = u.pos
	u.state = int(d["state"]) as State
	u.dest = Vector2i(int(d["dest"][0]), int(d["dest"][1]))
	u.target_cell = Vector2i(int(d["target_cell"][0]), int(d["target_cell"][1]))
	u.target_building = int(d["target_building"])
	u.gather_kind = d["gather_kind"]
	u.carry_kind = d["carry_kind"]
	u.carry_amount = int(d["carry_amount"])
	u.work_ticks = int(d["work_ticks"])
	return u
