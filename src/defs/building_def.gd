class_name BuildingDef
extends Resource
## Static description of a building type. Instances live in data/buildings/*.tres.

@export var id := ""
@export var display_name := ""
@export var size := Vector2i.ONE
## Resource kind -> amount.
@export var cost: Dictionary = {}
@export var build_ticks := 100
@export var pop_cap := 0
@export var is_dropoff := false
@export var trains_villagers := false
@export var buildable := true
@export var color := Color.WHITE
@export var height_px := 24.0
