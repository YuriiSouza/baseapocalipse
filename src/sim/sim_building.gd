class_name SimBuilding
extends RefCounted

var id := 0
var def_id := ""
var cell := Vector2i.ZERO
var progress := 0
var hp := 0

# Crop plots only. A plot is fallow (needs planting), growing or ripe.
## Planting work done so far.
var work := 0
## Tick the crop becomes ripe, or 0 when nothing is growing.
var ripe_tick := 0
## Food left to harvest.
var stock := 0

# People inside. Not saved: rebuilt from the people on load.
## Asleep in a bed.
var occupants := 0
## Hiding from zombies, or guards shooting from a tower.
var sheltered := 0


func get_def() -> BuildingDef:
	return Defs.building(def_id)


func is_complete() -> bool:
	return progress >= get_def().build_ticks


func is_fallow() -> bool:
	return is_complete() and get_def().crop_yield > 0 and stock == 0 and ripe_tick == 0


func is_damaged() -> bool:
	return hp < get_def().max_hp


func rect() -> Rect2i:
	return Rect2i(cell, get_def().size)


## Distance from a point in cell space to the nearest edge of the footprint; 0 inside it.
func distance_to(point: Vector2) -> float:
	var area := Rect2(rect())
	return point.distance_to(point.clamp(area.position, area.end))


func to_dict() -> Dictionary:
	return {
		"id": id, "def_id": def_id, "cell": [cell.x, cell.y], "progress": progress, "hp": hp,
		"work": work, "ripe_tick": ripe_tick, "stock": stock,
	}


static func from_dict(d: Dictionary) -> SimBuilding:
	var b := SimBuilding.new()
	b.id = int(d["id"])
	b.def_id = d["def_id"]
	b.cell = Vector2i(int(d["cell"][0]), int(d["cell"][1]))
	b.progress = int(d["progress"])
	b.hp = int(d["hp"])
	b.work = int(d["work"])
	b.ripe_tick = int(d["ripe_tick"])
	b.stock = int(d["stock"])
	return b
