class_name Defs
extends RefCounted
## Static game content and balance values.

const RESOURCE_KINDS: Array[String] = ["food", "wood", "stone", "gold"]
const RESOURCE_NAMES := {"food": "Comida", "wood": "Madeira", "stone": "Pedra", "gold": "Ouro"}
const STARTING_STOCKPILE := {"food": 200, "wood": 200, "stone": 100, "gold": 0}

## Gatherable map nodes.
const NODE_KINDS := {
	"tree": {"yields": "wood", "amount": 100},
	"berries": {"yields": "food", "amount": 150},
	"stone": {"yields": "stone", "amount": 250},
	"gold": {"yields": "gold", "amount": 250},
}

const BUILDINGS := {
	"town_center": preload("res://data/buildings/town_center.tres"),
	"house": preload("res://data/buildings/house.tres"),
}

const VILLAGER_COST := {"food": 50}
const VILLAGER_TRAIN_TICKS := 120
const VILLAGER_SPEED := 0.15  # cells per tick
const CARRY_CAPACITY := 10
const GATHER_TICKS_PER_UNIT := 6
const RETARGET_RADIUS := 8


static func building(id: String) -> BuildingDef:
	return BUILDINGS[id]


static func format_cost(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind: String in cost:
		parts.append("%d %s" % [int(cost[kind]), String(RESOURCE_NAMES[kind]).to_lower()])
	return ", ".join(parts)
