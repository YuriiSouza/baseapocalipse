class_name SimPoi
extends RefCounted
## A point of interest: an abandoned place with a finite amount of loot, maybe zombies
## inside and maybe people hiding in it.

const SIZE := Vector2i(2, 2)

var id := 0
var kind := ""
var cell := Vector2i.ZERO
## Resource kind -> units left to take.
var loot := {}
## Zombies inside. They come out when someone gets close.
var lurkers := 0
## People hiding here, who ask to join when the place is first reached.
var survivors := 0
## The community knows where it is. Expeditions can only be sent to discovered places.
var discovered := false
## Someone has been here, so what is left is known.
var visited := false


func display_name() -> String:
	return Defs.POI_KINDS[kind]["name"]


func loot_left() -> int:
	var total := 0
	for res: String in loot:
		total += int(loot[res])
	return total


## Centre of the footprint in cell space.
func center() -> Vector2:
	return Vector2(cell) + Vector2(SIZE) * 0.5


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "cell": [cell.x, cell.y], "loot": loot.duplicate(),
		"lurkers": lurkers, "survivors": survivors, "discovered": discovered, "visited": visited,
	}


static func from_dict(d: Dictionary) -> SimPoi:
	var poi := SimPoi.new()
	poi.id = int(d["id"])
	poi.kind = d["kind"]
	poi.cell = Vector2i(int(d["cell"][0]), int(d["cell"][1]))
	for res: String in d["loot"]:
		poi.loot[res] = int(d["loot"][res])
	poi.lurkers = int(d["lurkers"])
	poi.survivors = int(d["survivors"])
	poi.discovered = d["discovered"]
	poi.visited = d["visited"]
	return poi
