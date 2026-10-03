class_name Defs
extends RefCounted
## Static game content and balance values.

const RESOURCE_KINDS: Array[String] = ["food", "water", "wood", "scrap", "medicine", "ammo"]
const RESOURCE_NAMES := {
	"food": "Comida", "water": "Água", "wood": "Madeira",
	"scrap": "Sucata", "medicine": "Remédios", "ammo": "Munição",
}
const STARTING_STOCKPILE := {"food": 40, "water": 40, "wood": 30, "scrap": 0, "medicine": 5, "ammo": 20}

## Gatherable map nodes. Water is gathered from water terrain and never runs out.
const NODE_KINDS := {
	"tree": {"yields": "wood", "amount": 100},
	"berries": {"yields": "food", "amount": 80},
	"wreck": {"yields": "scrap", "amount": 60},
	"carcass": {"yields": "food", "amount": 40},
}

const BUILDINGS := {
	"house": preload("res://data/buildings/house.tres"),
	"storage": preload("res://data/buildings/storage.tres"),
	"garden": preload("res://data/buildings/garden.tres"),
	"well": preload("res://data/buildings/well.tres"),
	"fence": preload("res://data/buildings/fence.tres"),
	"palisade": preload("res://data/buildings/palisade.tres"),
	"wall": preload("res://data/buildings/wall.tres"),
	"gate": preload("res://data/buildings/gate.tres"),
	"tower": preload("res://data/buildings/tower.tres"),
	"trap": preload("res://data/buildings/trap.tres"),
}

const SKILLS: Array[String] = ["foraging", "hunting", "building", "farming", "medicine", "mechanics", "combat"]
const SKILL_NAMES := {
	"foraging": "coleta", "hunting": "caça", "building": "construção", "farming": "agricultura",
	"medicine": "medicina", "mechanics": "mecânica", "combat": "combate",
}

const MALE_NAMES: Array[String] = ["João", "Pedro", "Lucas", "Miguel", "Rafael", "Carlos", "André", "Mateus", "Tiago", "Bruno"]
const FEMALE_NAMES: Array[String] = ["Ana", "Maria", "Júlia", "Clara", "Beatriz", "Helena", "Laura", "Sofia", "Lívia", "Marina"]
const SURNAMES: Array[String] = ["Silva", "Souza", "Oliveira", "Santos", "Pereira", "Costa", "Almeida", "Ferreira"]

# --- Time ---
const DAY_TICKS := 1800  # 3 minutes at 1x
const DAYS_PER_YEAR := 12
const START_HOUR := 6.0  # a day number starts at dawn
const NIGHT_START := 21.0
const NIGHT_END := 5.0

# --- People ---
const ADULT_AGE := 16.0
const PERSON_SPEED := 0.15  # cells per tick
const CARRY_CAPACITY := 10
const GATHER_TICKS_PER_UNIT := 6
const CHILD_WORK_FACTOR := 0.5
const RETARGET_RADIUS := 8

# Needs go from 1 (fine) down to 0. Rates are per day.
const RATIONS_PER_DAY := 4  # food and water units each person consumes
const ENERGY_DRAIN := 1.05  # awake 16h costs 0.7
const SLEEP_GAIN := 2.1  # 8h in a bed restores 0.7
const GROUND_SLEEP_FACTOR := 0.5
const TIRED := 0.3  # goes to bed on its own
const EXHAUSTED := 0.1  # goes to bed even against orders
const DAMAGE_THIRST := 0.67  # health per day; death in about 1.5 days
const DAMAGE_HUNGER := 0.34
const DAMAGE_EXHAUSTION := 0.2
const HEALTH_REGEN := 0.1

# --- Automatic work ---
## Kinds of work a person can be allowed to do, in the order the HUD lists them.
## "guard" is not picked like the others: it decides whether the person fights or hides
## when zombies show up.
const WORK_TYPES: Array[String] = ["build", "farm", "water", "forage", "hunt", "wood", "scrap", "guard"]
const WORK_NAMES := {
	"build": "Construir", "farm": "Horta", "water": "Água", "forage": "Coletar comida",
	"hunt": "Caçar", "wood": "Lenha", "scrap": "Sucata", "guard": "Defender",
}
## Work that is plain gathering, and the resource it brings in.
const WORK_YIELD := {"water": "water", "forage": "food", "wood": "wood", "scrap": "scrap"}
## Children are not given these by default.
const ADULT_ONLY_WORK: Array[String] = ["build", "hunt", "guard"]
## Stock the community tries to keep. Work on a resource stops once its target is met.
const FOOD_TARGET_DAYS := 4
const WATER_TARGET_DAYS := 2
const WOOD_TARGET := 80
const SCRAP_TARGET := 40
## How far from a drop-off people look for something to gather, in cells.
const WORK_RADIUS := 35
const WORK_DECISIONS_PER_TICK := 6
## How long someone with nothing to do waits before looking again.
const IDLE_RETRY_TICKS := 50
## How long a resource is assumed missing after a full search found none in range.
const NO_SOURCE_TICKS := 300

const PLANT_TICKS := 150
const GROW_TICKS := 5400  # 3 days

const HUNT_RADIUS := 40.0  # cells from the hunter's drop-off
const HUNT_RANGE := 3.0
const HUNT_TICKS := 50
const CELLS_PER_ANIMAL := 400  # wildlife density the map is kept at
const ANIMAL_RESPAWN_PER_DAY := 6
const ANIMAL_THINK_TICKS := 20
const ANIMAL_SPEED := 0.03

# --- Simulation budget ---
const MAP_SIZE := 256
## A* searches allowed per tick; people past the budget wait for the next tick.
const PATHS_PER_TICK := 8
## Least time between full recomputations of the walkable regions.
const RELABEL_MIN_TICKS := 100

# --- Zombies ---
const ZOMBIE_THINK_TICKS := 5
const ZOMBIE_SIGHT := 10.0  # cells
const ZOMBIE_WANDER_SPEED := 0.04  # cells per tick
const ZOMBIE_CHASE_SPEED := 0.1
const ZOMBIE_NIGHT_FACTOR := 1.3  # speed and sight at night
const ZOMBIE_ATTACK_RANGE := 0.8
const ZOMBIE_ATTACK_TICKS := 10
const ZOMBIE_DAMAGE := 0.12  # health per hit on a person
const ZOMBIE_STRUCTURE_DAMAGE := 3  # hit points per hit on a building
## A zombie this close to a building with people inside starts tearing it down.
const ZOMBIE_SMELL := 4.0
const ZOMBIE_DETOUR_TICKS := 20  # doubles each time it is blocked again, up to 5 times
const ZOMBIE_CAP := 500
const ZOMBIES_AT_START := 12
const ZOMBIE_START_DISTANCE := 70.0  # cells from the family home
# Zombies arriving at the map edge every dusk: base + growth * day + per_person * people.
const ZOMBIE_DAILY_BASE := 1.0
const ZOMBIE_DAILY_GROWTH := 0.1
const ZOMBIE_PER_PERSON := 0.1

# --- Noise: what draws zombies that cannot see anyone ---
const NOISE_BUCKET := 16  # cells
const NOISE_PERSON := 1.0  # someone awake and busy, outdoors
const NOISE_HOME := 0.3  # a building people live in
const NOISE_LIGHT := 0.7  # added to homes at night
const NOISE_SHOT := 4.0
const NOISE_SHOT_DECAY := 0.98  # per tick
const HEAR_RADIUS := 4  # buckets
## Noise divided by (1 + distance² in buckets) has to beat this to be heard.
const HEAR_MIN := 0.6
const HEAR_NIGHT_FACTOR := 1.5

# --- Defence ---
const THREAT_CHECK_TICKS := 5
const FLEE_RADIUS := 8.0  # a zombie this close makes people react
const SAFE_RADIUS := 12.0  # sheltered people come out when no zombie is this close
const GUARD_RADIUS := 25.0  # guards go after zombies attacking within this distance
const TOWER_SEARCH_RADIUS := 15.0
const GUN_RANGE := 6.0
const TOWER_RANGE := 9.0
const GUN_DAMAGE := 0.5  # zombies have 1.0 health
const GUN_HIT_CHANCE := 60  # percent, plus 5 per combat level
const SHOT_TICKS := 15
const MELEE_RANGE := 1.2
const MELEE_DAMAGE := 0.25  # plus 0.03 per combat level
const MELEE_TICKS := 10
const WOUND_DRAIN := 0.1  # health per day while a wound is untreated
const TREATMENT_HEAL := 0.2
const REPAIR_PER_TICK := 1
const TRAP_WEAR := 10  # hit points a trap loses each time it goes off


static func building(id: String) -> BuildingDef:
	return BUILDINGS[id]


static func format_cost(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind: String in cost:
		parts.append("%d %s" % [int(cost[kind]), String(RESOURCE_NAMES[kind]).to_lower()])
	return ", ".join(parts)
