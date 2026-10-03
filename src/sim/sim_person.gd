class_name SimPerson
extends RefCounted
## A member of the community. Positions are in cell space; the centre of cell (x, y)
## is (x + 0.5, y + 0.5).

enum State {
	IDLE, MOVING, TO_RESOURCE, GATHERING, TO_DROPOFF, TO_BUILD, BUILDING,
	TO_BED, SLEEPING, TO_HUNT, HUNTING, TO_SHELTER, SHELTERED, DEFENDING,
}

## Fields copied as they are by to_dict / from_dict.
const SAVED: Array[String] = [
	"id", "first_name", "surname", "sex", "birth_day", "mother", "father", "spouse",
	"satiety", "hydration", "energy", "health", "wounded",
	"state", "ordered", "pushed", "work", "last_work", "idle_until",
	"bed_building", "inside", "target_building", "hunt_target",
	"shelter_building", "fight_target", "post", "cooldown",
	"gather_kind", "carry_kind", "carry_amount", "work_ticks",
]

var id := 0
var first_name := ""
var surname := ""
var sex := "f"
## Day the person was born; negative for anyone born before the game started.
var birth_day := 0
var mother := -1
var father := -1
var spouse := -1
## Skill id -> level (float).
var skills := {}
## Work type -> allowed (bool). The person only picks work that is allowed here.
var jobs := {}

# Needs: 1 is fine, 0 is critical.
var satiety := 1.0
var hydration := 1.0
var energy := 1.0
var health := 1.0
## Hurt by a zombie. Health drains and does not recover until treated with medicine.
var wounded := false

var pos := Vector2.ZERO
var state := State.IDLE
## Following a direct order from the player; lasts until the task ends or the person sleeps.
var ordered := false
## Ordered to keep going while tired; cleared when the person goes to bed.
var pushed := false
## Work type picked automatically, or "" when idle, asleep or under a direct order.
var work := ""
## Last work picked, favoured a little so people do not flip between jobs.
var last_work := ""
## With nothing to do, the tick at which to look for work again.
var idle_until := 0
var bed_building := -1
## Building the person is inside (asleep, hiding, or on guard in a tower), or -1 when
## out in the open. Zombies cannot see or reach people who are inside.
var inside := -1
var shelter_building := -1
## Zombie being fought, or -1.
var fight_target := -1
## Tower the guard is heading to or shooting from, or -1 to fight on the ground.
var post := -1
## Ticks until the next shot or blow.
var cooldown := 0
var dest := Vector2i(-1, -1)
var target_cell := Vector2i(-1, -1)
var target_building := -1
var hunt_target := -1
var gather_kind := ""
var carry_kind := ""
var carry_amount := 0
var work_ticks := 0

# Not saved: the path is re-planned on demand, prev_pos only feeds render interpolation.
var path: Array[Vector2i] = []
var prev_pos := Vector2.ZERO


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func full_name() -> String:
	return "%s %s" % [first_name, surname]


func age(day: int) -> float:
	return float(day - birth_day) / Defs.DAYS_PER_YEAR


func is_child(day: int) -> bool:
	return age(day) < Defs.ADULT_AGE


func to_dict() -> Dictionary:
	var d := {
		"x": pos.x,
		"y": pos.y,
		"dest": [dest.x, dest.y],
		"target_cell": [target_cell.x, target_cell.y],
		"skills": skills.duplicate(),
		"jobs": jobs.duplicate(),
	}
	for field in SAVED:
		d[field] = get(field)
	return d


## Integer fields are cast back in case the data went through JSON, which turns every
## number into a float.
static func from_dict(d: Dictionary) -> SimPerson:
	var p := SimPerson.new()
	for field in SAVED:
		var value: Variant = d[field]
		p.set(field, int(value) if typeof(p.get(field)) == TYPE_INT else value)
	p.pos = Vector2(d["x"], d["y"])
	p.prev_pos = p.pos
	p.dest = Vector2i(int(d["dest"][0]), int(d["dest"][1]))
	p.target_cell = Vector2i(int(d["target_cell"][0]), int(d["target_cell"][1]))
	for skill: String in d["skills"]:
		p.skills[skill] = float(d["skills"][skill])
	for work_type: String in d["jobs"]:
		p.jobs[work_type] = bool(d["jobs"][work_type])
	return p
