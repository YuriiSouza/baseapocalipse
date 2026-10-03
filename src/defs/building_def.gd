class_name BuildingDef
extends Resource
## Static description of a building type. Instances live in data/buildings/*.tres.

@export var id := ""
@export var display_name := ""
@export var size := Vector2i.ONE
## Resource kind -> amount.
@export var cost: Dictionary = {}
@export var build_ticks := 100
## Damage it takes before it is destroyed.
@export var max_hp := 100
## People who can sleep here at the same time. Buildings with beds also shelter people from zombies.
@export var beds := 0
## People deliver what they carry to buildings with this set.
@export var is_dropoff := false
## Water can be drawn here without limit.
@export var is_water_source := false
## Food per harvest. Above zero makes this a crop plot that must be planted and then ripens.
@export var crop_yield := 0
## People and animals walk through it. Zombies do too only if it is a trap.
@export var passable := false
## Health a zombie loses when stepping on it. Above zero makes this a trap.
@export var trap_damage := 0.0
## Guards who can shoot from inside, out of reach of zombies.
@export var guard_slots := 0
## Recipes are made here.
@export var is_workshop := false
## Skill -> level the community must know before this can be built.
@export var requires: Dictionary = {}
## Placed by dragging, one per cell (fences and walls).
@export var drag_place := false
@export var buildable := true
@export var color := Color.WHITE
@export var height_px := 24.0
