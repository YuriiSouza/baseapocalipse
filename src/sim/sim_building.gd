class_name SimBuilding
extends RefCounted

var id := 0
var def_id := ""
var cell := Vector2i.ZERO
var progress := 0
var train_queue := 0
var train_progress := 0


func get_def() -> BuildingDef:
	return Defs.building(def_id)


func is_complete() -> bool:
	return progress >= get_def().build_ticks


func to_dict() -> Dictionary:
	return {
		"id": id,
		"def_id": def_id,
		"cell": [cell.x, cell.y],
		"progress": progress,
		"train_queue": train_queue,
		"train_progress": train_progress,
	}


static func from_dict(d: Dictionary) -> SimBuilding:
	var b := SimBuilding.new()
	b.id = int(d["id"])
	b.def_id = d["def_id"]
	b.cell = Vector2i(int(d["cell"][0]), int(d["cell"][1]))
	b.progress = int(d["progress"])
	b.train_queue = int(d["train_queue"])
	b.train_progress = int(d["train_progress"])
	return b
