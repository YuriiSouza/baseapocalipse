class_name GameState
extends RefCounted
## The whole simulation: state plus the rules that advance it one tick at a time.
## No nodes and no rendering here. The view reads this object and changes it only
## through the order_* / place_building / set_job methods.

const TICKS_PER_SECOND := 10
const SAVE_VERSION := 5
const NO_CELL := Vector2i(-1, -1)
## Tick of the day at which night falls and new zombies reach the map edge.
const DUSK_TICK := int((Defs.NIGHT_START - Defs.START_HOUR) / 24.0 * Defs.DAY_TICKS)

enum Terrain { GRASS, WATER }
enum Plan { OK, FAIL, WAIT }

var width := 0
var height := 0
var tick := 0
var terrain := PackedByteArray()
var nodes := {}  # Vector2i -> {"kind": String, "amount": int}
var buildings := {}  # id -> SimBuilding
var people := {}  # id -> SimPerson
var zombies := {}  # id -> SimZombie
var animals := {}  # id -> SimAnimal
var stockpile := {}  # resource kind -> int
## Everyone who died: {"name", "age", "cause", "day"}.
var memorial := []
## False stops new zombies from arriving at the map edge.
var zombies_enabled := true
## True while zombies are attacking; used to announce an attack only once.
var alarm := false
## Messages for the player since the view last cleared this. Not saved.
var events: Array[String] = []
## Shots fired this tick, as [from, to] in cell space, for the view to draw. Not saved.
var shots := []

var _next_id := 1
## Resource kind -> last place the community found it, so most searches are a lookup.
var _source_hints := {}
## Resource kind -> tick until which it is assumed to be out of range.
var _no_source_until := {}
## Noise bucket -> gunshot noise still echoing there.
var _shot_noise := {}

# Derived or per-tick data, not saved.
var _grid := AStarGrid2D.new()
var _solid := PackedByteArray()  # 1 where people cannot walk; mirrors _grid
var _region := PackedInt32Array()  # cell -> region label, -1 for solid cells
var _region_parent := PackedInt32Array()  # union-find over region labels
var _relabel_tick := 0
var _occupied := {}  # Vector2i -> building id
var _people_index: SpatialIndex
var _zombie_index: SpatialIndex
var _paths_left := 0
var _decisions_left := 0
var _work_cache_tick := -1
var _work_count := {}  # work type -> people doing it
var _sites: Array[SimBuilding] = []  # under construction or damaged
var _fallow: Array[SimBuilding] = []  # crop plots waiting to be planted
var _ripe: Array[SimBuilding] = []  # crop plots ready to harvest
var _threats: Array[SimZombie] = []  # zombies that were hostile at the start of this tick
var _threat_cache := {}  # 8-cell block -> nearest hostile zombie, per tick
var _homes_in_use: Array[SimBuilding] = []  # buildings with people inside
var _noise := PackedFloat32Array()
var _noise_cols := 0
var _noise_rows := 0


static func new_game(world_seed: int, size := Defs.MAP_SIZE) -> GameState:
	var s := GameState.new()
	s.width = size
	s.height = size
	s.terrain.resize(size * size)
	for kind in Defs.RESOURCE_KINDS:
		s.stockpile[kind] = int(Defs.STARTING_STOCKPILE.get(kind, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var water := FastNoiseLite.new()
	water.seed = world_seed
	water.frequency = 0.035
	var forest := FastNoiseLite.new()
	forest.seed = world_seed + 1
	forest.frequency = 0.08

	@warning_ignore("integer_division")
	var home := Vector2i(size / 2, size / 2)
	for y in size:
		for x in size:
			var c := Vector2i(x, y)
			if (c - home).length() < 7.0:
				continue  # keep the starting area clear
			if water.get_noise_2d(x, y) < -0.38:
				s.terrain[y * size + x] = Terrain.WATER
			elif forest.get_noise_2d(x, y) > 0.22:
				s.nodes[c] = _make_node("tree")
			else:
				var roll := rng.randf()
				if roll < 0.006:
					s.nodes[c] = _make_node("berries")
				elif roll < 0.008:
					s.nodes[c] = _make_node("wreck")

	# Guaranteed surroundings of the family home, all inside the cleared radius:
	# a patch of woods, berry bushes, a pond and the car they arrived in.
	for y in range(-3, 1):
		for x in range(-5, -3):
			s.nodes[home + Vector2i(x, y)] = _make_node("tree")
	for offset: Vector2i in [Vector2i(4, -2), Vector2i(4, -1), Vector2i(5, -1)]:
		s.nodes[home + offset] = _make_node("berries")
	for offset: Vector2i in [Vector2i(0, -6), Vector2i(1, -6), Vector2i(0, -5), Vector2i(1, -5)]:
		var c := home + offset
		s.terrain[c.y * size + c.x] = Terrain.WATER
	s.nodes[home + Vector2i(4, 4)] = _make_node("wreck")

	s._rebuild_derived()

	var house := SimBuilding.new()
	house.id = s._take_id()
	house.def_id = "house"
	house.cell = home - Vector2i.ONE
	house.progress = house.get_def().build_ticks
	house.hp = house.get_def().max_hp
	s._register_building(house)

	# The family: two adults with a couple of skills each, and two children.
	var surname := Defs.SURNAMES[rng.randi() % Defs.SURNAMES.size()]
	var male := Defs.MALE_NAMES.duplicate()
	var female := Defs.FEMALE_NAMES.duplicate()
	var father := s.add_person(home + Vector2i(1, 1), _take_name(male, rng), surname, "m", rng.randi_range(32, 40))
	var mother := s.add_person(home + Vector2i(2, 1), _take_name(female, rng), surname, "f", rng.randi_range(30, 38))
	father.spouse = mother.id
	mother.spouse = father.id
	for parent: SimPerson in [father, mother]:
		for i in 2:
			parent.skills[Defs.SKILLS[rng.randi() % Defs.SKILLS.size()]] = float(rng.randi_range(2, 4))
	var child_cells: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2)]
	var child_ages: Array[int] = [rng.randi_range(10, 13), rng.randi_range(6, 9)]
	for i in 2:
		var sex := "f" if rng.randf() < 0.5 else "m"
		var child_name := _take_name(female if sex == "f" else male, rng)
		var child := s.add_person(home + child_cells[i], child_name, surname, sex, child_ages[i])
		child.mother = mother.id
		child.father = father.id

	# Wildlife away from the house, and a few zombies much further out: the place is isolated.
	@warning_ignore("integer_division")
	var herd := size * size / Defs.CELLS_PER_ANIMAL
	var tries := 0
	while s.animals.size() < herd and tries < herd * 20:
		tries += 1
		var c := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		if s.is_walkable(c) and (c - home).length() > 10.0:
			s.spawn_animal(c)
	tries = 0
	while s.zombies.size() < Defs.ZOMBIES_AT_START and tries < 2000:
		tries += 1
		var c := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		if s.is_walkable(c) and (c - home).length() > Defs.ZOMBIE_START_DISTANCE:
			s.spawn_zombie(c)
	return s


static func _make_node(kind: String) -> Dictionary:
	return {"kind": kind, "amount": int(Defs.NODE_KINDS[kind]["amount"])}


static func _take_name(pool: Array[String], rng: RandomNumberGenerator) -> String:
	var i := rng.randi() % pool.size()
	var picked := pool[i]
	pool.remove_at(i)
	return picked


# --- Queries ---------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func terrain_at(c: Vector2i) -> int:
	return terrain[c.y * width + c.x]


## True if people can walk on the cell. Gates and traps are walkable buildings.
func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and _solid[c.y * width + c.x] == 0


func building_at(c: Vector2i) -> SimBuilding:
	return buildings.get(_occupied.get(c, -1))


## Days start at dawn (START_HOUR); the first day is 1.
func day() -> int:
	@warning_ignore("integer_division")
	return 1 + tick / Defs.DAY_TICKS


func hour() -> float:
	return fmod(Defs.START_HOUR + 24.0 * (tick % Defs.DAY_TICKS) / Defs.DAY_TICKS, 24.0)


func is_night() -> bool:
	var h := hour()
	return h >= Defs.NIGHT_START or h < Defs.NIGHT_END


func year() -> int:
	@warning_ignore("integer_division")
	return 1 + (day() - 1) / Defs.DAYS_PER_YEAR


func is_over() -> bool:
	return people.is_empty()


## Zombies chasing people or tearing down buildings right now.
func threat_count() -> int:
	return _threats.size()


func total_beds() -> int:
	var total := 0
	for b: SimBuilding in buildings.values():
		if b.is_complete():
			total += b.get_def().beds
	return total


func can_afford(cost: Dictionary) -> bool:
	for kind: String in cost:
		if stockpile[kind] < cost[kind]:
			return false
	return true


func can_place(def_id: String, cell: Vector2i) -> bool:
	var size := Defs.building(def_id).size
	for y in size.y:
		for x in size.x:
			var c := cell + Vector2i(x, y)
			if not is_walkable(c) or _occupied.has(c):
				return false
	var footprint := Rect2i(cell, size)
	for id in _people_index.query(Vector2(cell) + Vector2(size) * 0.5, maxf(size.x, size.y)):
		if footprint.has_point((people[id] as SimPerson).cell()):
			return false
	return true


## Ids of people within `radius` cells of `pos`.
func people_near(pos: Vector2, radius: float) -> Array[int]:
	var out: Array[int] = []
	var limit := radius * radius
	for id in _people_index.query(pos, radius):
		if pos.distance_squared_to((people[id] as SimPerson).pos) <= limit:
			out.append(id)
	return out


## True while a building still takes work: construction, repair, or a crop plot to plant.
func building_needs_work(b: SimBuilding) -> bool:
	return not b.is_complete() or b.is_damaged() or b.is_fallow()


## How short the community is of a resource: 0 at or above its target stock, 1 with none.
func need(kind: String) -> float:
	var target := 0.0
	match kind:
		"food":
			target = people.size() * Defs.RATIONS_PER_DAY * Defs.FOOD_TARGET_DAYS
		"water":
			target = people.size() * Defs.RATIONS_PER_DAY * Defs.WATER_TARGET_DAYS
		"wood":
			target = Defs.WOOD_TARGET
		"scrap":
			target = Defs.SCRAP_TARGET
	if target <= 0.0:
		return 0.0
	return clampf(1.0 - stockpile[kind] / target, 0.0, 1.0)


## What gathering at this cell gives: a resource kind, or "" if there is nothing to gather.
func source_yield(cell: Vector2i) -> String:
	if nodes.has(cell):
		return Defs.NODE_KINDS[nodes[cell]["kind"]]["yields"]
	var b := building_at(cell)
	if b != null:
		if b.is_complete() and b.get_def().is_water_source:
			return "water"
		return "food" if b.stock > 0 else ""
	if in_bounds(cell) and terrain_at(cell) == Terrain.WATER:
		return "water"
	return ""


## Nearest reachable source of the given yield around `center`, or NO_CELL.
## Searches ring by ring outwards, so the cost follows the distance to the first hit.
func nearest_source(center: Vector2i, yields: String, radius := Defs.RETARGET_RADIUS) -> Vector2i:
	if center == NO_CELL:
		return NO_CELL
	for r in range(0, radius + 1):
		var best := NO_CELL
		var best_dist := INF
		for y in range(center.y - r, center.y + r + 1):
			# Full rows at the top and bottom of the ring, only the two ends in between.
			var full_row := r == 0 or y == center.y - r or y == center.y + r
			for x in range(center.x - r, center.x + r + 1, 1 if full_row else 2 * r):
				var c := Vector2i(x, y)
				if source_yield(c) != yields:
					continue
				var dist := float((c - center).length_squared())
				if dist < best_dist and _source_reachable(c):
					best = c
					best_dist = dist
		if best != NO_CELL:
			return best
	return NO_CELL


# --- Orders (the only way the view changes the simulation) -----------------

func order_move(ids: Array[int], cell: Vector2i) -> void:
	var cells := _spread(cell, ids.size())
	for i in mini(ids.size(), cells.size()):
		var p := _commandable(ids[i])
		if p == null:
			continue
		p.dest = cells[i]
		p.state = SimPerson.State.MOVING


func order_gather(ids: Array[int], cell: Vector2i) -> void:
	var yields := source_yield(cell)
	if yields == "":
		return
	if not _source_reachable(cell):
		# Clicked deep in a lake or a forest: use the closest spot that can be reached.
		cell = nearest_source(cell, yields)
		if cell == NO_CELL:
			return
	for id in ids:
		var p := _commandable(id)
		if p != null:
			_begin_gather(p, cell, yields)


## Construction, repair, or planting a fallow crop plot.
func order_build(ids: Array[int], building_id: int) -> void:
	if not buildings.has(building_id):
		return
	for id in ids:
		var p := _commandable(id)
		if p == null:
			continue
		p.target_building = building_id
		p.state = SimPerson.State.TO_BUILD


## Allows or forbids a kind of work. Forbidding it stops anyone doing it right now.
func set_job(ids: Array[int], work: String, allowed: bool) -> void:
	for id in ids:
		var p: SimPerson = people.get(id)
		if p == null:
			continue
		p.jobs[work] = allowed
		p.idle_until = 0
		if not allowed and p.work == work:
			p.work = ""
			p.path.clear()
			p.state = SimPerson.State.IDLE
		if not allowed and work == "guard" and p.state == SimPerson.State.DEFENDING:
			_stand_down(p)


## Returns the new building id, or -1 if it cannot be placed or paid for.
func place_building(def_id: String, cell: Vector2i) -> int:
	var def := Defs.building(def_id)
	if not can_place(def_id, cell) or not can_afford(def.cost):
		return -1
	_pay(def.cost)
	var b := SimBuilding.new()
	b.id = _take_id()
	b.def_id = def_id
	b.cell = cell
	b.hp = def.max_hp
	_register_building(b)
	return b.id


func add_person(cell: Vector2i, first_name: String, surname: String, sex: String, age_years: float) -> SimPerson:
	var p := SimPerson.new()
	p.id = _take_id()
	p.first_name = first_name
	p.surname = surname
	p.sex = sex
	p.birth_day = day() - roundi(age_years * Defs.DAYS_PER_YEAR)
	for skill in Defs.SKILLS:
		p.skills[skill] = 0.0
	for work in Defs.WORK_TYPES:
		p.jobs[work] = age_years >= Defs.ADULT_AGE or work not in Defs.ADULT_ONLY_WORK
	p.pos = Vector2(cell) + Vector2(0.5, 0.5)
	p.prev_pos = p.pos
	_add_person(p)
	return p


## A generic adult stranger, named from the id so no random state is needed.
func spawn_person(cell: Vector2i) -> SimPerson:
	var n := _next_id
	var sex := "f" if n % 2 == 0 else "m"
	var names := Defs.FEMALE_NAMES if sex == "f" else Defs.MALE_NAMES
	return add_person(cell, names[n % names.size()], Defs.SURNAMES[n % Defs.SURNAMES.size()], sex, 25.0)


func spawn_zombie(cell: Vector2i) -> SimZombie:
	var z := SimZombie.new()
	z.id = _take_id()
	z.pos = Vector2(cell) + Vector2(0.5, 0.5)
	z.prev_pos = z.pos
	zombies[z.id] = z
	_zombie_index.add(z.id, z.pos)
	return z


func clear_zombies() -> void:
	zombies.clear()
	_zombie_index = SpatialIndex.new(width, height)


func spawn_animal(cell: Vector2i) -> SimAnimal:
	var a := SimAnimal.new()
	a.id = _take_id()
	a.pos = Vector2(cell) + Vector2(0.5, 0.5)
	a.prev_pos = a.pos
	animals[a.id] = a
	return a


# --- Tick ------------------------------------------------------------------

func step() -> void:
	tick += 1
	_paths_left = Defs.PATHS_PER_TICK
	_decisions_left = Defs.WORK_DECISIONS_PER_TICK
	shots.clear()
	_survey()
	for p: SimPerson in people.values():
		p.prev_pos = p.pos
		if _tick_needs(p):
			_tick_person(p)
	for z: SimZombie in zombies.values():
		z.prev_pos = z.pos
		_tick_zombie(z)
	for a: SimAnimal in animals.values():
		a.prev_pos = a.pos
		_tick_animal(a)
	var time_of_day := tick % Defs.DAY_TICKS
	if time_of_day == 0:
		_respawn_animals()
	elif time_of_day == DUSK_TICK and zombies_enabled:
		_zombies_arrive()


## Start-of-tick pass over zombies and buildings: who is attacking, which buildings have
## people inside, ripening crops, and the noise the community is making.
func _survey() -> void:
	_threats.clear()
	_threat_cache.clear()
	for z: SimZombie in zombies.values():
		if z.hostile:
			_threats.append(z)
	if _threats.is_empty():
		alarm = false
	elif not alarm:
		alarm = true
		events.append("Zumbis atacando!")

	_noise.fill(0.0)
	var home_noise := Defs.NOISE_HOME + (Defs.NOISE_LIGHT if is_night() else 0.0)
	_homes_in_use.clear()
	for b: SimBuilding in buildings.values():
		if b.ripe_tick > 0 and tick >= b.ripe_tick:
			b.ripe_tick = 0
			b.stock = b.get_def().crop_yield
		if b.occupants + b.sheltered > 0:
			_homes_in_use.append(b)
		if b.is_complete() and b.get_def().beds > 0:
			_noise[_noise_bucket(Vector2(b.cell))] += home_noise
	for p: SimPerson in people.values():
		var quiet := p.state == SimPerson.State.IDLE or p.state == SimPerson.State.SLEEPING
		if p.inside < 0 and not quiet:
			_noise[_noise_bucket(p.pos)] += Defs.NOISE_PERSON
	for bucket: int in _shot_noise.keys():
		var echo: float = _shot_noise[bucket] * Defs.NOISE_SHOT_DECAY
		if echo < 0.05:
			_shot_noise.erase(bucket)
		else:
			_shot_noise[bucket] = echo
			_noise[bucket] += echo


## Hunger, thirst, tiredness, wounds and health. Returns false if the person died this tick.
func _tick_needs(p: SimPerson) -> bool:
	var per_tick := 1.0 / Defs.DAY_TICKS
	var ration := 1.0 / Defs.RATIONS_PER_DAY
	p.satiety = maxf(0.0, p.satiety - per_tick)
	p.hydration = maxf(0.0, p.hydration - per_tick)
	if p.state == SimPerson.State.SLEEPING:
		var comfort := 1.0 if p.inside >= 0 else Defs.GROUND_SLEEP_FACTOR
		p.energy = minf(1.0, p.energy + Defs.SLEEP_GAIN * comfort * per_tick)
	elif p.state != SimPerson.State.SHELTERED:  # hiding indoors is restful enough
		p.energy = maxf(0.0, p.energy - Defs.ENERGY_DRAIN * per_tick)

	# Meals come straight from the community stock, wherever the person is.
	if p.satiety <= 1.0 - ration and stockpile["food"] >= 1:
		stockpile["food"] -= 1
		p.satiety += ration
	if p.hydration <= 1.0 - ration and stockpile["water"] >= 1:
		stockpile["water"] -= 1
		p.hydration += ration

	# Wounds are treated once the danger has passed, not in the middle of a fight.
	if p.wounded and stockpile["medicine"] >= 1 and p.state != SimPerson.State.DEFENDING \
			and p.state != SimPerson.State.TO_SHELTER and _nearest_zombie(p.pos, Defs.FLEE_RADIUS) == null:
		stockpile["medicine"] -= 1
		p.wounded = false
		p.health = minf(1.0, p.health + Defs.TREATMENT_HEAL)
		events.append("%s recebeu tratamento" % p.full_name())

	var damage := 0.0
	var cause := ""
	if p.wounded:
		damage += Defs.WOUND_DRAIN
		cause = "infecção"
	if p.energy <= 0.0:
		damage += Defs.DAMAGE_EXHAUSTION
		cause = "exaustão"
	if p.satiety <= 0.0:
		damage += Defs.DAMAGE_HUNGER
		cause = "fome"
	if p.hydration <= 0.0:
		damage += Defs.DAMAGE_THIRST
		cause = "sede"
	if damage > 0.0:
		p.health -= damage * per_tick
		if p.health <= 0.0:
			_kill(p, cause)
			return false
	elif p.satiety > 0.3 and p.hydration > 0.3:
		p.health = minf(1.0, p.health + Defs.HEALTH_REGEN * per_tick)
	return true


func _hurt_person(p: SimPerson, amount: float, cause: String) -> void:
	p.health -= amount
	p.wounded = true
	if p.health <= 0.0:
		_kill(p, cause)


func _kill(p: SimPerson, cause: String) -> void:
	_go_outside(p)
	_people_index.remove(p.id, p.pos)
	people.erase(p.id)
	memorial.append({"name": p.full_name(), "age": int(p.age(day())), "cause": cause, "day": day()})
	events.append("%s morreu: %s" % [p.full_name(), cause])


func _tick_person(p: SimPerson) -> void:
	var facing_danger := p.state == SimPerson.State.DEFENDING or p.state == SimPerson.State.TO_SHELTER \
			or p.state == SimPerson.State.SHELTERED
	if not facing_danger and p.state != SimPerson.State.SLEEPING and p.state != SimPerson.State.TO_BED:
		var pushing := p.pushed and p.state != SimPerson.State.IDLE
		if p.energy <= (Defs.EXHAUSTED if pushing else Defs.TIRED):
			_go_to_bed(p)
	if not zombies.is_empty() and (tick + p.id) % Defs.THREAT_CHECK_TICKS == 0:
		_react_to_threat(p)

	match p.state:
		SimPerson.State.IDLE:
			p.ordered = false
			p.work = ""
			if tick >= p.idle_until and _decisions_left > 0:
				_decisions_left -= 1
				_choose_work(p)

		SimPerson.State.MOVING:
			if _advance(p) and (p.cell() == p.dest or _plan(p, p.dest) == Plan.FAIL):
				p.state = SimPerson.State.IDLE

		SimPerson.State.TO_RESOURCE:
			if source_yield(p.target_cell) == "":
				_retarget_or_deliver(p)
			elif _advance(p):
				var spot := _source_rect(p.target_cell)
				if _is_adjacent(p.cell(), spot.position, spot.size):
					p.work_ticks = 0
					p.state = SimPerson.State.GATHERING
				elif _approach(p, spot.position, spot.size) == Plan.FAIL:
					p.state = SimPerson.State.IDLE

		SimPerson.State.GATHERING:
			if source_yield(p.target_cell) == "":
				_retarget_or_deliver(p)
				return
			if p.carry_kind != p.gather_kind:
				p.carry_kind = p.gather_kind
				p.carry_amount = 0
			var effort := Defs.CHILD_WORK_FACTOR if p.is_child(day()) else 1.0
			p.work_ticks += 1
			if p.work_ticks >= Defs.GATHER_TICKS_PER_UNIT / effort:
				p.work_ticks = 0
				p.carry_amount += 1
				_take_from_source(p.target_cell)
			if p.carry_amount >= Defs.CARRY_CAPACITY * effort:
				p.state = SimPerson.State.TO_DROPOFF

		SimPerson.State.TO_DROPOFF:
			if not _advance(p):
				return
			var drop := _nearest_dropoff(p.cell())
			if drop == null:
				p.state = SimPerson.State.IDLE
			elif _is_adjacent(p.cell(), drop.cell, drop.get_def().size):
				if p.carry_amount > 0:
					stockpile[p.carry_kind] += p.carry_amount
					p.carry_amount = 0
				if p.work != "" and need(p.gather_kind) <= 0.0:
					p.state = SimPerson.State.IDLE  # the community has enough of this
				elif source_yield(p.target_cell) == p.gather_kind:
					p.state = SimPerson.State.TO_RESOURCE
				else:
					_retarget_or_deliver(p)
			elif _approach(p, drop.cell, drop.get_def().size) == Plan.FAIL:
				p.state = SimPerson.State.IDLE

		SimPerson.State.TO_BUILD:
			var site: SimBuilding = buildings.get(p.target_building)
			if site == null or not building_needs_work(site):
				p.path.clear()
				p.state = SimPerson.State.IDLE
			elif _advance(p):
				if _is_adjacent(p.cell(), site.cell, site.get_def().size):
					p.state = SimPerson.State.BUILDING
				elif _approach(p, site.cell, site.get_def().size) == Plan.FAIL:
					p.state = SimPerson.State.IDLE

		SimPerson.State.BUILDING:
			var site: SimBuilding = buildings.get(p.target_building)
			if site == null:
				p.state = SimPerson.State.IDLE
			elif not site.is_complete():
				site.progress += 1
			elif site.is_damaged():
				site.hp = mini(site.get_def().max_hp, site.hp + Defs.REPAIR_PER_TICK)
			elif site.is_fallow():
				site.work += 1
				if site.work >= Defs.PLANT_TICKS:
					site.work = 0
					site.ripe_tick = tick + Defs.GROW_TICKS
			else:
				p.state = SimPerson.State.IDLE

		SimPerson.State.TO_HUNT:
			var prey: SimAnimal = animals.get(p.hunt_target)
			if prey == null:
				p.path.clear()
				p.state = SimPerson.State.IDLE
			elif p.pos.distance_to(prey.pos) <= Defs.HUNT_RANGE:
				p.path.clear()
				p.work_ticks = 0
				p.state = SimPerson.State.HUNTING
			elif _advance(p) and _plan(p, prey.cell()) == Plan.FAIL:
				p.state = SimPerson.State.IDLE

		SimPerson.State.HUNTING:
			var prey: SimAnimal = animals.get(p.hunt_target)
			if prey == null:
				p.state = SimPerson.State.IDLE
			elif p.pos.distance_to(prey.pos) > Defs.HUNT_RANGE + 2.0:
				p.state = SimPerson.State.TO_HUNT  # it wandered off
			else:
				p.work_ticks += 1
				if p.work_ticks >= Defs.HUNT_TICKS:
					animals.erase(prey.id)
					var carcass := _drop_node(prey.cell(), "carcass")
					if carcass == NO_CELL:
						p.state = SimPerson.State.IDLE
					else:
						_begin_gather(p, carcass, "food")

		SimPerson.State.TO_BED:
			var house: SimBuilding = buildings.get(p.bed_building)
			if house == null or not _has_free_bed(house):
				house = _nearest_free_bed(p.cell())
				p.bed_building = house.id if house != null else -1
				p.path.clear()
			if house == null:
				p.state = SimPerson.State.SLEEPING  # no bed anywhere: sleep on the ground
			elif _advance(p):
				var size := house.get_def().size
				if _is_adjacent(p.cell(), house.cell, size):
					house.occupants += 1
					p.inside = house.id
					p.state = SimPerson.State.SLEEPING
				elif _approach(p, house.cell, size) == Plan.FAIL:
					p.state = SimPerson.State.SLEEPING

		SimPerson.State.SLEEPING:
			if p.energy >= 1.0:
				_go_outside(p)
				p.state = SimPerson.State.IDLE

		SimPerson.State.TO_SHELTER:
			var refuge: SimBuilding = buildings.get(p.shelter_building)
			if refuge == null:
				p.path.clear()
				p.state = SimPerson.State.IDLE
			elif _advance(p):
				var size := refuge.get_def().size
				if _is_adjacent(p.cell(), refuge.cell, size):
					p.state = SimPerson.State.SHELTERED
					p.inside = refuge.id
					refuge.sheltered += 1
				elif _approach(p, refuge.cell, size) == Plan.FAIL:
					p.state = SimPerson.State.IDLE

		SimPerson.State.SHELTERED:
			if (tick + p.id) % 20 == 0 and _nearest_zombie(p.pos, Defs.SAFE_RADIUS) == null:
				_go_outside(p)
				p.state = SimPerson.State.IDLE

		SimPerson.State.DEFENDING:
			_tick_defending(p)


func _go_to_bed(p: SimPerson) -> void:
	p.ordered = false
	p.pushed = false
	p.work = ""
	p.path.clear()
	p.bed_building = -1
	p.state = SimPerson.State.TO_BED


## Leaves whatever building the person is in. Call before changing the state, which is
## what tells a bed from a hiding place.
func _go_outside(p: SimPerson) -> void:
	var b: SimBuilding = buildings.get(p.inside)
	if b != null:
		if p.state == SimPerson.State.SLEEPING:
			b.occupants -= 1
		else:
			b.sheltered -= 1
	p.inside = -1


## The person to give an order to, woken up or called out if needed. Null if there is
## no such person or they are too exhausted to obey.
func _commandable(id: int) -> SimPerson:
	var p: SimPerson = people.get(id)
	if p == null or p.energy <= Defs.EXHAUSTED:
		return null
	_go_outside(p)
	p.ordered = true
	p.pushed = p.energy <= Defs.TIRED
	p.work = ""
	p.path.clear()
	return p


func _begin_gather(p: SimPerson, cell: Vector2i, yields: String) -> void:
	p.target_cell = cell
	p.gather_kind = yields
	p.work_ticks = 0
	p.state = SimPerson.State.TO_RESOURCE


func _take_from_source(cell: Vector2i) -> void:
	if nodes.has(cell):
		var node: Dictionary = nodes[cell]
		node["amount"] -= 1
		if node["amount"] <= 0:
			nodes.erase(cell)
			_set_solid(cell, false)
		return
	var plot := building_at(cell)
	if plot != null and plot.stock > 0:
		plot.stock -= 1


func _has_free_bed(b: SimBuilding) -> bool:
	return b.is_complete() and b.occupants < b.get_def().beds


func _nearest_free_bed(from: Vector2i) -> SimBuilding:
	var free: Array[SimBuilding] = []
	for b: SimBuilding in buildings.values():
		if _has_free_bed(b):
			free.append(b)
	return _nearest_building(free, from)


## The source a person was working on is gone: move to a similar one nearby,
## otherwise bring back whatever is being carried.
func _retarget_or_deliver(p: SimPerson) -> void:
	p.path.clear()
	var next := nearest_source(p.target_cell, p.gather_kind)
	if next != NO_CELL and p.carry_amount < Defs.CARRY_CAPACITY:
		p.target_cell = next
		p.state = SimPerson.State.TO_RESOURCE
	elif p.carry_amount > 0:
		p.state = SimPerson.State.TO_DROPOFF
	else:
		p.state = SimPerson.State.IDLE


# --- Defence ---------------------------------------------------------------

## Guards go and fight; everyone else runs for a building to hide in. People under a
## direct order, or already indoors, are left alone.
func _react_to_threat(p: SimPerson) -> void:
	if p.ordered:
		return
	if p.state == SimPerson.State.DEFENDING or p.state == SimPerson.State.TO_SHELTER:
		return
	var guard: bool = p.jobs.get("guard", false)
	if p.inside >= 0:
		# Indoors is safe. Only a guard asleep in bed gets up, and only for an actual attack.
		if guard and p.state == SimPerson.State.SLEEPING and _nearest_threat(p.pos, Defs.GUARD_RADIUS) != null:
			_go_outside(p)
		else:
			return
	if guard:
		# Whatever is right here comes first; otherwise go help where the attack is.
		var z := _nearest_zombie(p.pos, Defs.FLEE_RADIUS)
		if z == null:
			z = _nearest_threat(p.pos, Defs.GUARD_RADIUS)
		if z != null:
			p.work = ""
			p.path.clear()
			p.fight_target = z.id
			p.cooldown = 0
			p.post = -1
			if stockpile["ammo"] > 0:
				var tower := _nearest_free_tower(p.pos)
				p.post = tower.id if tower != null else -1
			p.state = SimPerson.State.DEFENDING
	elif _nearest_zombie(p.pos, Defs.FLEE_RADIUS) != null:
		var homes: Array[SimBuilding] = []
		for b: SimBuilding in buildings.values():
			if b.is_complete() and b.get_def().beds > 0:
				homes.append(b)
		var refuge := _nearest_building(homes, p.cell())
		if refuge != null:
			p.work = ""
			p.path.clear()
			p.shelter_building = refuge.id
			p.state = SimPerson.State.TO_SHELTER


## Shoots while there is ammunition (from a tower when one is free), otherwise fights
## hand to hand. Goes back to normal life when no zombie is left nearby.
func _tick_defending(p: SimPerson) -> void:
	p.cooldown = maxi(0, p.cooldown - 1)
	var armed: bool = stockpile["ammo"] > 0
	var tower: SimBuilding = buildings.get(p.post)
	if tower == null or not armed:
		# A tower is no use without ammunition: come down and fight on the ground.
		p.post = -1
		if p.inside >= 0:
			_go_outside(p)
	var origin := p.pos
	var reach := Defs.GUN_RANGE if armed else Defs.MELEE_RANGE
	if p.inside >= 0:
		origin = Vector2(tower.cell) + Vector2(0.5, 0.5)
		reach = Defs.TOWER_RANGE

	var z: SimZombie = zombies.get(p.fight_target)
	if z == null or (tick + p.id) % 10 == 0:
		z = _nearest_zombie(origin, reach if armed else Defs.FLEE_RADIUS)
		if z == null:
			z = _nearest_threat(origin, Defs.GUARD_RADIUS)
		if z == null:
			_stand_down(p)
			return
		p.fight_target = z.id

	if origin.distance_to(z.pos) <= reach:
		if p.cooldown == 0:
			if armed:
				_shoot(p, z, origin)
			else:
				p.cooldown = Defs.MELEE_TICKS
				_hurt_zombie(z, Defs.MELEE_DAMAGE + 0.03 * float(p.skills.get("combat", 0.0)))
	elif p.inside >= 0:
		pass  # out of range from the tower: wait for it to come closer
	elif p.post >= 0:
		if tower.sheltered >= tower.get_def().guard_slots:
			p.post = -1
		elif _advance(p):
			var size := tower.get_def().size
			if _is_adjacent(p.cell(), tower.cell, size):
				p.inside = tower.id
				tower.sheltered += 1
			elif _approach(p, tower.cell, size) == Plan.FAIL:
				p.post = -1
	elif tick >= p.idle_until and _advance(p) and _plan(p, z.cell()) == Plan.FAIL:
		p.idle_until = tick + Defs.IDLE_RETRY_TICKS  # cannot be reached: hold this position


func _stand_down(p: SimPerson) -> void:
	_go_outside(p)
	p.post = -1
	p.fight_target = -1
	p.path.clear()
	p.state = SimPerson.State.IDLE


func _shoot(p: SimPerson, z: SimZombie, origin: Vector2) -> void:
	stockpile["ammo"] -= 1
	p.cooldown = Defs.SHOT_TICKS
	shots.append([origin, z.pos])
	var bucket := _noise_bucket(origin)
	_shot_noise[bucket] = float(_shot_noise.get(bucket, 0.0)) + Defs.NOISE_SHOT
	var chance := Defs.GUN_HIT_CHANCE + 5 * int(p.skills.get("combat", 0.0))
	if hash(tick * 131 + p.id) % 100 < chance:
		_hurt_zombie(z, Defs.GUN_DAMAGE)


func _hurt_zombie(z: SimZombie, amount: float) -> void:
	z.health -= amount
	if z.health <= 0.0 and zombies.has(z.id):
		zombies.erase(z.id)
		_zombie_index.remove(z.id, z.pos)


func _damage_building(b: SimBuilding, amount: int) -> void:
	b.hp -= amount
	if b.hp > 0:
		return
	for p: SimPerson in people.values():
		if p.inside == b.id:
			p.inside = -1
			p.state = SimPerson.State.IDLE  # thrown out into the open
	buildings.erase(b.id)
	var def := b.get_def()
	for y in def.size.y:
		for x in def.size.x:
			var c := b.cell + Vector2i(x, y)
			_occupied.erase(c)
			if not def.passable:
				_set_solid(c, false)
	if def.trap_damage <= 0.0:
		events.append("%s foi destruída" % def.display_name)


func _nearest_zombie(pos: Vector2, radius: float) -> SimZombie:
	var best: SimZombie = null
	var best_dist := radius * radius
	for id in _zombie_index.query(pos, radius):
		var z: SimZombie = zombies[id]
		var dist := pos.distance_squared_to(z.pos)
		if dist <= best_dist:
			best = z
			best_dist = dist
	return best


## A zombie that is attacking someone or something, close to `pos`. The answer is worked
## out once per tick for each 8-cell block and shared by everyone standing in it, so a
## crowd of guards does not scan every attacker each: it is the attacker nearest to the
## block, not necessarily to the person.
func _nearest_threat(pos: Vector2, radius: float) -> SimZombie:
	if _threats.is_empty():
		return null
	var block := Vector2i(floori(pos.x / 8.0), floori(pos.y / 8.0))
	if not _threat_cache.has(block):
		var center := (Vector2(block) + Vector2(0.5, 0.5)) * 8.0
		var best: SimZombie = null
		var best_dist := INF
		for z in _threats:
			var dist := center.distance_squared_to(z.pos)
			if dist < best_dist:
				best = z
				best_dist = dist
		_threat_cache[block] = best
	var found: SimZombie = _threat_cache[block]
	if found != null and zombies.has(found.id) and pos.distance_to(found.pos) <= radius:
		return found
	return null


func _nearest_free_tower(pos: Vector2) -> SimBuilding:
	var best: SimBuilding = null
	var best_dist := Defs.TOWER_SEARCH_RADIUS
	for b: SimBuilding in buildings.values():
		if not b.is_complete() or b.sheltered >= b.get_def().guard_slots:
			continue
		var dist := b.distance_to(pos)
		if dist <= best_dist:
			best = b
			best_dist = dist
	return best


# --- Automatic work --------------------------------------------------------

## An idle person picks the allowed work the community needs most.
func _choose_work(p: SimPerson) -> void:
	_refresh_work_cache()
	var options := []  # [score, work type]
	for work in Defs.WORK_TYPES:
		if p.jobs.get(work, false):
			var score := _work_score(p, work)
			if score > 0.05:
				options.append([score, work])
	options.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for option: Array in options:
		var work: String = option[1]
		if _start_work(p, work):
			p.path.clear()
			p.work = work
			p.last_work = work
			_work_count[work] = int(_work_count.get(work, 0)) + 1
			return
	p.idle_until = tick + Defs.IDLE_RETRY_TICKS


## Higher is more urgent. Shrinks with the number of people already on that work,
## which is what spreads people across the community's needs.
func _work_score(p: SimPerson, work: String) -> float:
	var score := 0.0
	match work:
		"build":
			score = 3.0 if not _sites.is_empty() else 0.0
		"farm":
			if not _fallow.is_empty():
				score = 2.0
			elif not _ripe.is_empty():
				score = 1.5 * need("food")
		"water":
			score = 1.2 * need("water")
		"forage":
			score = need("food")
		"hunt":
			score = 0.8 * need("food") if not animals.is_empty() else 0.0
		"wood":
			score = 0.5 * need("wood")
		"scrap":
			score = 0.3 * need("scrap")
	if work == p.last_work:
		score *= 1.3
	return score / (1.0 + 0.5 * int(_work_count.get(work, 0)))


## Points the person at a concrete target for this work. False if there is none.
func _start_work(p: SimPerson, work: String) -> bool:
	match work:
		"build":
			var site := _nearest_building(_sites, p.cell())
			if site == null:
				return false
			p.target_building = site.id
			p.state = SimPerson.State.TO_BUILD
		"farm":
			var plot := _nearest_building(_fallow, p.cell())
			if plot != null:
				p.target_building = plot.id
				p.state = SimPerson.State.TO_BUILD
			else:
				plot = _nearest_building(_ripe, p.cell())
				if plot == null:
					return false
				_begin_gather(p, plot.cell, "food")
		"hunt":
			var prey := _nearest_prey(p)
			if prey == null:
				return false
			p.hunt_target = prey.id
			p.state = SimPerson.State.TO_HUNT
		_:
			var kind: String = Defs.WORK_YIELD[work]
			var cell := _find_work_source(p, kind)
			if cell == NO_CELL:
				return false
			_begin_gather(p, cell, kind)
	return true


## Where to gather a resource. Reuses the last place found, so the full search around
## the drop-off is rare: it runs when that place is used up, and a miss is remembered
## for a while instead of being searched again.
func _find_work_source(p: SimPerson, kind: String) -> Vector2i:
	var hint: Vector2i = _source_hints.get(kind, NO_CELL)
	if hint != NO_CELL and source_yield(hint) == kind:
		return hint
	if int(_no_source_until.get(kind, 0)) > tick:
		return NO_CELL
	var base := _nearest_dropoff(p.cell())
	if base == null:
		return NO_CELL
	var found := nearest_source(hint, kind)
	if found == NO_CELL or (found - base.cell).length() > Defs.WORK_RADIUS:
		found = nearest_source(base.cell, kind, Defs.WORK_RADIUS)
		if found == NO_CELL:
			_no_source_until[kind] = tick + Defs.NO_SOURCE_TICKS
			return NO_CELL
	_source_hints[kind] = found
	return found


func _nearest_prey(p: SimPerson) -> SimAnimal:
	var base := _nearest_dropoff(p.cell())
	var center := Vector2(base.cell) if base != null else p.pos
	var limit := Defs.HUNT_RADIUS * Defs.HUNT_RADIUS
	var best: SimAnimal = null
	var best_dist := INF
	for a: SimAnimal in animals.values():
		if a.pos.distance_squared_to(center) > limit:
			continue
		var dist := a.pos.distance_squared_to(p.pos)
		if dist < best_dist:
			best = a
			best_dist = dist
	return best


## Counts and lists the work scores need, gathered once per tick and only if someone decides.
func _refresh_work_cache() -> void:
	if _work_cache_tick == tick:
		return
	_work_cache_tick = tick
	_work_count.clear()
	for p: SimPerson in people.values():
		if p.work != "":
			_work_count[p.work] = int(_work_count.get(p.work, 0)) + 1
	_sites.clear()
	_fallow.clear()
	_ripe.clear()
	for b: SimBuilding in buildings.values():
		if not b.is_complete() or b.is_damaged():
			_sites.append(b)
		elif b.is_fallow():
			_fallow.append(b)
		elif b.stock > 0:
			_ripe.append(b)


# --- Zombies and animals ---------------------------------------------------

func _tick_zombie(z: SimZombie) -> void:
	# Zombies re-decide only every few ticks, staggered by id so the cost is spread out.
	if (tick + z.id) % Defs.ZOMBIE_THINK_TICKS == 0:
		_zombie_think(z)

	var chased: SimPerson = people.get(z.target)
	if chased != null and chased.inside >= 0:
		z.goal = chased.pos  # went indoors: head for where it was last seen
		z.lured = true
		z.target = -1
		chased = null
	var wall: SimBuilding = buildings.get(z.siege)
	if wall == null:
		z.siege = -1
	z.hostile = chased != null or wall != null

	var dest := SimZombie.NO_GOAL
	var speed := Defs.ZOMBIE_WANDER_SPEED
	if chased != null and z.pos.distance_to(chased.pos) < Defs.ZOMBIE_ATTACK_RANGE:
		if tick >= z.next_attack:
			z.next_attack = tick + Defs.ZOMBIE_ATTACK_TICKS
			_hurt_person(chased, Defs.ZOMBIE_DAMAGE, "zumbis")
		return
	if wall != null:
		# Whatever blocked its way is torn down before it goes on.
		if wall.distance_to(z.pos) <= Defs.ZOMBIE_ATTACK_RANGE + 0.1:
			if tick >= z.next_attack:
				z.next_attack = tick + Defs.ZOMBIE_ATTACK_TICKS
				_damage_building(wall, Defs.ZOMBIE_STRUCTURE_DAMAGE)
			return
		dest = Vector2(wall.cell) + Vector2(wall.get_def().size) * 0.5
		speed = Defs.ZOMBIE_CHASE_SPEED
	elif chased != null:
		dest = chased.pos
		speed = Defs.ZOMBIE_CHASE_SPEED
	elif z.goal != SimZombie.NO_GOAL:
		if z.pos.distance_squared_to(z.goal) < 4.0:
			z.goal = SimZombie.NO_GOAL
			z.lured = false
			z.blocked = 0
		else:
			dest = z.goal

	var purposeful := dest != SimZombie.NO_GOAL
	if purposeful and tick >= z.detour_until:
		z.heading = z.pos.direction_to(dest)
	if z.heading == Vector2.ZERO:
		return
	if is_night():
		speed *= Defs.ZOMBIE_NIGHT_FACTOR
	var moved := _slide(z.pos, z.heading * speed, true)
	if moved.distance_to(z.pos) < speed * 0.3:
		_zombie_blocked(z, purposeful)
		return
	var from_cell := z.cell()
	_zombie_index.move(z.id, z.pos, moved)
	z.pos = moved
	if z.cell() != from_cell:
		var trap := building_at(z.cell())
		if trap != null and trap.is_complete() and trap.get_def().trap_damage > 0.0:
			_hurt_zombie(z, trap.get_def().trap_damage)
			_damage_building(trap, Defs.TRAP_WEAR)


func _zombie_think(z: SimZombie) -> void:
	var sight := Defs.ZOMBIE_SIGHT * (Defs.ZOMBIE_NIGHT_FACTOR if is_night() else 1.0)
	var had_target := z.target >= 0
	z.target = -1
	var best := sight * sight
	for id in _people_index.query(z.pos, sight):
		var p: SimPerson = people[id]
		if p.inside >= 0:
			continue  # indoors: out of sight and out of reach
		var dist := z.pos.distance_squared_to(p.pos)
		if dist < best:
			best = dist
			z.target = id
	if z.target >= 0:
		# Someone in sight matters more than the building it was busy with. If that
		# building is in the way it will simply be attacked again.
		z.siege = -1
		if not had_target:
			z.blocked = 0
		return
	if buildings.has(z.siege):
		return
	for b in _homes_in_use:
		if b.distance_to(z.pos) <= Defs.ZOMBIE_SMELL:
			z.siege = b.id  # smells the people inside
			return
	@warning_ignore("integer_division")
	if (tick / Defs.ZOMBIE_THINK_TICKS + z.id) % 10 == 0:
		_zombie_listen(z)
	if z.goal == SimZombie.NO_GOAL:
		# Roam: after a pause, set off for a random place anywhere on the map. This is what
		# brings zombies from the map edge past the settlement, where they may hear it.
		# Hash-based, so there is no RNG state to save.
		var r := hash(z.id * 7919 + tick)
		z.heading = Vector2.ZERO
		if r % 4 == 0:
			var r2 := hash(r)
			@warning_ignore("integer_division")
			z.goal = Vector2(2 + r2 % (width - 4), 2 + (r2 / width) % (height - 4))
			z.lured = false


## Heads for the loudest place within earshot, if any is loud enough.
func _zombie_listen(z: SimZombie) -> void:
	var bx := clampi(floori(z.pos.x / Defs.NOISE_BUCKET), 0, _noise_cols - 1)
	var by := clampi(floori(z.pos.y / Defs.NOISE_BUCKET), 0, _noise_rows - 1)
	var best := Defs.HEAR_MIN / (Defs.HEAR_NIGHT_FACTOR if is_night() else 1.0)
	var found := Vector2i(-1, -1)
	for dy in range(-Defs.HEAR_RADIUS, Defs.HEAR_RADIUS + 1):
		var y := by + dy
		if y < 0 or y >= _noise_rows:
			continue
		for dx in range(-Defs.HEAR_RADIUS, Defs.HEAR_RADIUS + 1):
			var x := bx + dx
			if x < 0 or x >= _noise_cols:
				continue
			var score := _noise[y * _noise_cols + x] / (1.0 + dx * dx + dy * dy)
			if score > best:
				best = score
				found = Vector2i(x, y)
	if found.x < 0:
		return
	var r := hash(z.id * 31 + tick)
	@warning_ignore("integer_division")
	var jitter := Vector2(r % 13 - 6, (r / 13) % 13 - 6)
	var point := (Vector2(found) + Vector2(0.5, 0.5)) * Defs.NOISE_BUCKET + jitter
	z.goal = point.clamp(Vector2.ONE, Vector2(width - 1, height - 1))
	z.lured = true


## Something is in the way. A building gets attacked; anything else is walked around,
## with longer detours each time it happens again.
func _zombie_blocked(z: SimZombie, purposeful: bool) -> void:
	if not purposeful:
		z.heading = Vector2.ZERO
		return
	var probes: Array[Vector2] = [
		z.heading * 0.8, Vector2(signf(z.heading.x) * 0.8, 0.0), Vector2(0.0, signf(z.heading.y) * 0.8)]
	for probe in probes:
		var at := z.pos + probe
		var b := building_at(Vector2i(floori(at.x), floori(at.y)))
		if b != null and b.get_def().trap_damage <= 0.0:
			z.siege = b.id
			return
	z.blocked = mini(z.blocked + 1, 5)
	z.heading = z.heading.rotated((PI / 2.0) * (1.0 if z.id % 2 == 0 else -1.0))
	z.detour_until = tick + (Defs.ZOMBIE_DETOUR_TICKS << (z.blocked - 1))


## More zombies reach the map edge each dusk as the days pass and the community grows.
func _zombies_arrive() -> void:
	var count := int(Defs.ZOMBIE_DAILY_BASE + Defs.ZOMBIE_DAILY_GROWTH * day() + Defs.ZOMBIE_PER_PERSON * people.size())
	for i in count:
		if zombies.size() >= Defs.ZOMBIE_CAP:
			return
		var r := hash(tick * 17 + i)
		@warning_ignore("integer_division")
		var depth := (r / 7) % 6
		var along := r % width
		var cell := Vector2i(along, depth)
		@warning_ignore("integer_division")
		match (r / 3) % 4:
			1:
				cell = Vector2i(along, height - 1 - depth)
			2:
				cell = Vector2i(depth, along % height)
			3:
				cell = Vector2i(width - 1 - depth, along % height)
		if is_walkable(cell):
			spawn_zombie(cell)


func _tick_animal(a: SimAnimal) -> void:
	if (tick + a.id) % Defs.ANIMAL_THINK_TICKS == 0:
		var r := hash(a.id * 104729 + tick)
		a.heading = Vector2.ZERO if r % 2 == 0 else Vector2.from_angle((r % 628) / 100.0)
	if a.heading == Vector2.ZERO:
		return
	var moved := _slide(a.pos, a.heading * Defs.ANIMAL_SPEED, false)
	if moved == a.pos:
		a.heading = Vector2.ZERO
	a.pos = moved


## Keeps wildlife from being hunted to extinction: a few new animals a day, away from people.
func _respawn_animals() -> void:
	@warning_ignore("integer_division")
	var herd := width * height / Defs.CELLS_PER_ANIMAL
	for i in Defs.ANIMAL_RESPAWN_PER_DAY:
		if animals.size() >= herd:
			return
		var r := hash(tick * 31 + i)
		@warning_ignore("integer_division")
		var cell := Vector2i(r % width, (r / width) % height)
		if is_walkable(cell) and people_near(Vector2(cell), 20.0).is_empty():
			spawn_animal(cell)


## Movement without pathfinding: go straight, or slide along whatever is in the way.
## Returns the starting position when fully blocked.
func _slide(from: Vector2, step: Vector2, zombie: bool) -> Vector2:
	if _is_open(from + step, zombie):
		return from + step
	if step.x != 0.0 and _is_open(from + Vector2(step.x, 0.0), zombie):
		return from + Vector2(step.x, 0.0)
	if step.y != 0.0 and _is_open(from + Vector2(0.0, step.y), zombie):
		return from + Vector2(0.0, step.y)
	return from


## Zombies are also stopped by gates, which people and animals walk through.
func _is_open(at: Vector2, zombie: bool) -> bool:
	var c := Vector2i(floori(at.x), floori(at.y))
	if not is_walkable(c):
		return false
	if zombie:
		var b := building_at(c)
		return b == null or b.get_def().trap_damage > 0.0
	return true


func _noise_bucket(pos: Vector2) -> int:
	var x := clampi(floori(pos.x / Defs.NOISE_BUCKET), 0, _noise_cols - 1)
	var y := clampi(floori(pos.y / Defs.NOISE_BUCKET), 0, _noise_rows - 1)
	return y * _noise_cols + x


# --- Movement and pathfinding ----------------------------------------------

## Moves along the current path. Returns true once there is nothing left to walk.
func _advance(p: SimPerson) -> bool:
	if p.path.is_empty():
		return true
	var next := p.path[0]
	if not is_walkable(next):
		p.path.clear()  # the world changed since this path was planned
		return true
	var target := Vector2(next) + Vector2(0.5, 0.5)
	var from := p.pos
	p.pos = p.pos.move_toward(target, Defs.PERSON_SPEED)
	_people_index.move(p.id, from, p.pos)
	if p.pos.is_equal_approx(target):
		p.path.remove_at(0)
	return p.path.is_empty()


## WAIT means this tick's pathfinding budget is spent: keep the state and retry next tick.
func _plan(p: SimPerson, to: Vector2i) -> Plan:
	if not is_walkable(to):
		return Plan.FAIL
	if _paths_left <= 0:
		return Plan.WAIT
	_paths_left -= 1
	# A failed search floods the whole map, so rule out the hopeless ones first.
	if not _maybe_connected(p.cell(), to):
		return Plan.FAIL
	var found := _grid.get_id_path(p.cell(), to)
	if found.is_empty():
		# The regions said it was reachable: they are out of date.
		if tick - _relabel_tick >= Defs.RELABEL_MIN_TICKS:
			_relabel()
		return Plan.FAIL
	found.remove_at(0)  # drop the cell the person is standing on
	p.path = found
	return Plan.OK


## Connected regions of walkable cells, so an unreachable target is rejected without
## searching. Opening a cell joins regions on the spot. Blocking one may split a region,
## which is not tracked: the labels can then say "connected" for places that are not,
## never the other way round, and a search that fails anyway triggers a fresh labelling.
func _maybe_connected(a: Vector2i, b: Vector2i) -> bool:
	var ra := _region[a.y * width + a.x]
	var rb := _region[b.y * width + b.x]
	if ra < 0 or rb < 0:
		return true  # standing on something solid: let the search decide
	return _region_root(ra) == _region_root(rb)


func _region_root(label: int) -> int:
	while _region_parent[label] != label:
		_region_parent[label] = _region_parent[_region_parent[label]]
		label = _region_parent[label]
	return label


func _relabel() -> void:
	_relabel_tick = tick
	_region_parent.clear()
	for y in height:
		for x in width:
			var i := y * width + x
			if _solid[i] != 0:
				_region[i] = -1
				continue
			var left := _region[i - 1] if x > 0 else -1
			var up := _region[i - width] if y > 0 else -1
			if left < 0 and up < 0:
				_region[i] = _region_parent.size()
				_region_parent.append(_region_parent.size())
			elif left >= 0 and up >= 0:
				_region[i] = left
				_region_parent[_region_root(up)] = _region_root(left)
			else:
				_region[i] = maxi(left, up)


## The single place where a cell becomes blocked or free for people.
func _set_solid(c: Vector2i, solid: bool) -> void:
	var i := c.y * width + c.x
	_grid.set_point_solid(c, solid)
	_solid[i] = 1 if solid else 0
	if solid:
		_region[i] = -1
		return
	_region[i] = _region_parent.size()
	_region_parent.append(_region[i])
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n := c + offset
		if in_bounds(n) and _region[n.y * width + n.x] >= 0:
			_region_parent[_region_root(_region[n.y * width + n.x])] = _region_root(_region[i])


## Plans a path to any free cell touching the given footprint.
func _approach(p: SimPerson, cell: Vector2i, size: Vector2i) -> Plan:
	if _paths_left <= 0:
		return Plan.WAIT
	var from := p.cell()
	var ring := _ring(cell, size)
	ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - from).length_squared() < (b - from).length_squared())
	for c in ring:
		var result := _plan(p, c)
		if result != Plan.FAIL:
			return result
	return Plan.FAIL


func _is_adjacent(from: Vector2i, cell: Vector2i, size: Vector2i) -> bool:
	return Rect2i(cell - Vector2i.ONE, size + Vector2i(2, 2)).has_point(from)


## Walkable cells surrounding a footprint.
func _ring(cell: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var footprint := Rect2i(cell, size)
	for y in range(cell.y - 1, cell.y + size.y + 1):
		for x in range(cell.x - 1, cell.x + size.x + 1):
			var c := Vector2i(x, y)
			if not footprint.has_point(c) and is_walkable(c):
				out.append(c)
	return out


## What a gatherer has to stand next to: the whole building for a well or a crop plot,
## the single cell otherwise.
func _source_rect(cell: Vector2i) -> Rect2i:
	var b := building_at(cell)
	if b != null:
		return b.rect()
	return Rect2i(cell, Vector2i.ONE)


func _source_reachable(cell: Vector2i) -> bool:
	var spot := _source_rect(cell)
	return not _ring(spot.position, spot.size).is_empty()


## Up to `count` distinct walkable cells, closest to `center` first.
func _spread(center: Vector2i, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := 0
	while out.size() < count and r < 16:
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				var on_ring := maxi(absi(x - center.x), absi(y - center.y)) == r
				if on_ring and out.size() < count and is_walkable(Vector2i(x, y)):
					out.append(Vector2i(x, y))
		r += 1
	return out


func _nearest_dropoff(from: Vector2i) -> SimBuilding:
	var drops: Array[SimBuilding] = []
	for b: SimBuilding in buildings.values():
		if b.is_complete() and b.get_def().is_dropoff:
			drops.append(b)
	return _nearest_building(drops, from)


func _nearest_building(list: Array[SimBuilding], from: Vector2i) -> SimBuilding:
	var best: SimBuilding = null
	var best_dist := INF
	for b in list:
		var dist := float((b.cell - from).length_squared())
		if dist < best_dist:
			best = b
			best_dist = dist
	return best


# --- Internals -------------------------------------------------------------

func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


func _pay(cost: Dictionary) -> void:
	for kind: String in cost:
		stockpile[kind] -= int(cost[kind])


## Puts a resource node on the free cell closest to `cell`. Returns where, or NO_CELL.
func _drop_node(cell: Vector2i, kind: String) -> Vector2i:
	for spot in _spread(cell, 4):
		if not _occupied.has(spot):
			nodes[spot] = _make_node(kind)
			_set_solid(spot, true)
			return spot
	return NO_CELL


func _add_person(p: SimPerson) -> void:
	people[p.id] = p
	_people_index.add(p.id, p.pos)
	var b: SimBuilding = buildings.get(p.inside)
	if b != null:
		if p.state == SimPerson.State.SLEEPING:
			b.occupants += 1
		else:
			b.sheltered += 1


## Requires _rebuild_derived() to have run.
func _register_building(b: SimBuilding) -> void:
	buildings[b.id] = b
	var def := b.get_def()
	for y in def.size.y:
		for x in def.size.x:
			var c := b.cell + Vector2i(x, y)
			_occupied[c] = b.id
			if not def.passable:
				_set_solid(c, true)


## Builds everything that is derived from the saved state: pathfinding grid, spatial
## indexes and the noise grid.
func _rebuild_derived() -> void:
	_people_index = SpatialIndex.new(width, height)
	_zombie_index = SpatialIndex.new(width, height)
	_noise_cols = ceili(float(width) / Defs.NOISE_BUCKET)
	_noise_rows = ceili(float(height) / Defs.NOISE_BUCKET)
	_noise.resize(_noise_cols * _noise_rows)
	_grid.region = Rect2i(0, 0, width, height)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	_solid.resize(width * height)
	_solid.fill(0)
	_region.resize(width * height)
	_region.fill(-1)
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if terrain_at(c) == Terrain.WATER or nodes.has(c):
				_set_solid(c, true)
	_relabel()


# --- Save / load -----------------------------------------------------------

func to_dict() -> Dictionary:
	var node_rows := []
	for c: Vector2i in nodes:
		node_rows.append([c.x, c.y, nodes[c]["kind"], nodes[c]["amount"]])
	var hint_rows := {}
	for kind: String in _source_hints:
		var c: Vector2i = _source_hints[kind]
		hint_rows[kind] = [c.x, c.y]
	var echo_rows := []
	for bucket: int in _shot_noise:
		echo_rows.append([bucket, _shot_noise[bucket]])
	return {
		"version": SAVE_VERSION,
		"width": width,
		"height": height,
		"tick": tick,
		"next_id": _next_id,
		"zombies_enabled": zombies_enabled,
		"alarm": alarm,
		"terrain": Marshalls.raw_to_base64(terrain),
		"stockpile": stockpile.duplicate(),
		"memorial": memorial.duplicate(true),
		"source_hints": hint_rows,
		"no_source_until": _no_source_until.duplicate(),
		"shot_noise": echo_rows,
		"nodes": node_rows,
		"buildings": buildings.values().map(func(b: SimBuilding) -> Dictionary: return b.to_dict()),
		"people": people.values().map(func(p: SimPerson) -> Dictionary: return p.to_dict()),
		"zombies": zombies.values().map(func(z: SimZombie) -> Dictionary: return z.to_dict()),
		"animals": animals.values().map(func(a: SimAnimal) -> Dictionary: return a.to_dict()),
	}


## The int() casts keep this working for data that went through JSON, where every
## number comes back as a float.
static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.width = int(d["width"])
	s.height = int(d["height"])
	s.tick = int(d["tick"])
	s._next_id = int(d["next_id"])
	s.zombies_enabled = d["zombies_enabled"]
	s.alarm = d["alarm"]
	s.terrain = Marshalls.base64_to_raw(d["terrain"])
	for kind in Defs.RESOURCE_KINDS:
		s.stockpile[kind] = int(d["stockpile"].get(kind, 0))
	for row: Dictionary in d["memorial"]:
		s.memorial.append({"name": row["name"], "age": int(row["age"]), "cause": row["cause"], "day": int(row["day"])})
	for kind: String in d["source_hints"]:
		s._source_hints[kind] = Vector2i(int(d["source_hints"][kind][0]), int(d["source_hints"][kind][1]))
	for kind: String in d["no_source_until"]:
		s._no_source_until[kind] = int(d["no_source_until"][kind])
	for row: Array in d["shot_noise"]:
		s._shot_noise[int(row[0])] = float(row[1])
	for row: Array in d["nodes"]:
		s.nodes[Vector2i(int(row[0]), int(row[1]))] = {"kind": row[2], "amount": int(row[3])}
	s._rebuild_derived()
	for row: Dictionary in d["buildings"]:
		s._register_building(SimBuilding.from_dict(row))
	for row: Dictionary in d["people"]:
		s._add_person(SimPerson.from_dict(row))
	for row: Dictionary in d["zombies"]:
		var z := SimZombie.from_dict(row)
		s.zombies[z.id] = z
		s._zombie_index.add(z.id, z.pos)
	for row: Dictionary in d["animals"]:
		var a := SimAnimal.from_dict(row)
		s.animals[a.id] = a
	return s
