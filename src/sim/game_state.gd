class_name GameState
extends RefCounted
## The whole simulation: state plus the rules that advance it one tick at a time.
## No nodes and no rendering here. The view reads this object and changes it only
## through the order_* / place_building / queue_villager methods.

const TICKS_PER_SECOND := 10
const TICKS_PER_YEAR := 600
const NO_CELL := Vector2i(-1, -1)

enum Terrain { GRASS, WATER }

var width := 0
var height := 0
var tick := 0
var terrain := PackedByteArray()
var nodes := {}  # Vector2i -> {"kind": String, "amount": int}
var buildings := {}  # id -> SimBuilding
var units := {}  # id -> SimUnit
var stockpile := {}  # resource kind -> int

var _next_id := 1
var _grid := AStarGrid2D.new()
var _occupied := {}  # Vector2i -> building id


static func new_game(world_seed: int, size := 64) -> GameState:
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
				elif roll < 0.011:
					s.nodes[c] = _make_node("stone")
				elif roll < 0.015:
					s.nodes[c] = _make_node("gold")

	# Guaranteed starting resources, all inside the cleared radius.
	for y in range(-3, 1):
		for x in range(-5, -3):
			s.nodes[home + Vector2i(x, y)] = _make_node("tree")
	for offset: Vector2i in [Vector2i(4, -2), Vector2i(4, -1), Vector2i(5, -1)]:
		s.nodes[home + offset] = _make_node("berries")
	for offset: Vector2i in [Vector2i(-3, 5), Vector2i(-2, 5)]:
		s.nodes[home + offset] = _make_node("stone")
	for offset: Vector2i in [Vector2i(4, 4), Vector2i(5, 4)]:
		s.nodes[home + offset] = _make_node("gold")

	s._rebuild_grid()

	var tc := SimBuilding.new()
	tc.id = s._take_id()
	tc.def_id = "town_center"
	tc.cell = home - Vector2i.ONE
	tc.progress = tc.get_def().build_ticks
	s._register_building(tc)

	for offset: Vector2i in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]:
		s._spawn_unit(home + offset)
	return s


static func _make_node(kind: String) -> Dictionary:
	return {"kind": kind, "amount": int(Defs.NODE_KINDS[kind]["amount"])}


# --- Queries ---------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func terrain_at(c: Vector2i) -> int:
	return terrain[c.y * width + c.x]


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not _grid.is_point_solid(c)


func building_at(c: Vector2i) -> SimBuilding:
	return buildings.get(_occupied.get(c, -1))


func pop_cap() -> int:
	var total := 0
	for b: SimBuilding in buildings.values():
		if b.is_complete():
			total += b.get_def().pop_cap
	return total


func year() -> int:
	@warning_ignore("integer_division")
	return 1 + tick / TICKS_PER_YEAR


func can_afford(cost: Dictionary) -> bool:
	for kind: String in cost:
		if stockpile[kind] < cost[kind]:
			return false
	return true


func can_place(def_id: String, cell: Vector2i) -> bool:
	var size := Defs.building(def_id).size
	for y in size.y:
		for x in size.x:
			if not is_walkable(cell + Vector2i(x, y)):
				return false
	var footprint := Rect2i(cell, size)
	for u: SimUnit in units.values():
		if footprint.has_point(u.cell()):
			return false
	return true


# --- Orders (the only way the view changes the simulation) -----------------

func order_move(ids: Array[int], cell: Vector2i) -> void:
	var cells := _spread(cell, ids.size())
	for i in mini(ids.size(), cells.size()):
		var u: SimUnit = units.get(ids[i])
		if u == null:
			continue
		u.path.clear()
		u.dest = cells[i]
		u.state = SimUnit.State.MOVING


func order_gather(ids: Array[int], cell: Vector2i) -> void:
	if not nodes.has(cell):
		return
	var yields: String = Defs.NODE_KINDS[nodes[cell]["kind"]]["yields"]
	for id in ids:
		var u: SimUnit = units.get(id)
		if u == null:
			continue
		u.path.clear()
		u.target_cell = cell
		u.gather_kind = yields
		u.work_ticks = 0
		u.state = SimUnit.State.TO_RESOURCE


func order_build(ids: Array[int], building_id: int) -> void:
	if not buildings.has(building_id):
		return
	for id in ids:
		var u: SimUnit = units.get(id)
		if u == null:
			continue
		u.path.clear()
		u.target_building = building_id
		u.state = SimUnit.State.TO_BUILD


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
	_register_building(b)
	return b.id


func queue_villager(building_id: int) -> bool:
	var b: SimBuilding = buildings.get(building_id)
	if b == null or not b.is_complete() or not b.get_def().trains_villagers:
		return false
	if not can_afford(Defs.VILLAGER_COST):
		return false
	_pay(Defs.VILLAGER_COST)
	b.train_queue += 1
	return true


# --- Tick ------------------------------------------------------------------

func step() -> void:
	tick += 1
	for u: SimUnit in units.values():
		u.prev_pos = u.pos
		_tick_unit(u)
	for b: SimBuilding in buildings.values():
		_tick_building(b)


func _tick_unit(u: SimUnit) -> void:
	match u.state:
		SimUnit.State.MOVING:
			if _advance(u) and (u.cell() == u.dest or not _plan(u, u.dest)):
				u.state = SimUnit.State.IDLE

		SimUnit.State.TO_RESOURCE:
			if not nodes.has(u.target_cell):
				_retarget_or_deliver(u)
			elif _advance(u):
				if _is_adjacent(u.cell(), u.target_cell, Vector2i.ONE):
					u.work_ticks = 0
					u.state = SimUnit.State.GATHERING
				elif not _approach(u, u.target_cell, Vector2i.ONE):
					u.state = SimUnit.State.IDLE

		SimUnit.State.GATHERING:
			if not nodes.has(u.target_cell):
				_retarget_or_deliver(u)
				return
			if u.carry_kind != u.gather_kind:
				u.carry_kind = u.gather_kind
				u.carry_amount = 0
			u.work_ticks += 1
			if u.work_ticks >= Defs.GATHER_TICKS_PER_UNIT:
				u.work_ticks = 0
				u.carry_amount += 1
				var node: Dictionary = nodes[u.target_cell]
				node["amount"] -= 1
				if node["amount"] <= 0:
					nodes.erase(u.target_cell)
					_grid.set_point_solid(u.target_cell, false)
			if u.carry_amount >= Defs.CARRY_CAPACITY:
				u.state = SimUnit.State.TO_DROPOFF

		SimUnit.State.TO_DROPOFF:
			if not _advance(u):
				return
			var drop := _nearest_dropoff(u.cell())
			if drop == null:
				u.state = SimUnit.State.IDLE
			elif _is_adjacent(u.cell(), drop.cell, drop.get_def().size):
				if u.carry_amount > 0:
					stockpile[u.carry_kind] += u.carry_amount
					u.carry_amount = 0
				if nodes.has(u.target_cell):
					u.state = SimUnit.State.TO_RESOURCE
				else:
					_retarget_or_deliver(u)
			elif not _approach(u, drop.cell, drop.get_def().size):
				u.state = SimUnit.State.IDLE

		SimUnit.State.TO_BUILD:
			var site: SimBuilding = buildings.get(u.target_building)
			if site == null or site.is_complete():
				u.path.clear()
				u.state = SimUnit.State.IDLE
			elif _advance(u):
				if _is_adjacent(u.cell(), site.cell, site.get_def().size):
					u.state = SimUnit.State.BUILDING
				elif not _approach(u, site.cell, site.get_def().size):
					u.state = SimUnit.State.IDLE

		SimUnit.State.BUILDING:
			var site: SimBuilding = buildings.get(u.target_building)
			if site == null or site.is_complete():
				u.state = SimUnit.State.IDLE
			else:
				site.progress += 1


func _tick_building(b: SimBuilding) -> void:
	if b.train_queue <= 0 or not b.is_complete() or units.size() >= pop_cap():
		return
	b.train_progress += 1
	if b.train_progress < Defs.VILLAGER_TRAIN_TICKS:
		return
	var exits := _ring(b.cell, b.get_def().size)
	if exits.is_empty():
		return  # boxed in: keep the villager ready until a cell frees up
	b.train_progress = 0
	b.train_queue -= 1
	_spawn_unit(exits[0])


## The resource a villager was working on is gone: move to a similar one nearby,
## otherwise bring back whatever is being carried.
func _retarget_or_deliver(u: SimUnit) -> void:
	u.path.clear()
	var next := _nearest_node(u.target_cell, u.gather_kind)
	if next != NO_CELL and u.carry_amount < Defs.CARRY_CAPACITY:
		u.target_cell = next
		u.state = SimUnit.State.TO_RESOURCE
	elif u.carry_amount > 0:
		u.state = SimUnit.State.TO_DROPOFF
	else:
		u.state = SimUnit.State.IDLE


# --- Movement and pathfinding ----------------------------------------------

## Moves along the current path. Returns true once there is nothing left to walk.
func _advance(u: SimUnit) -> bool:
	if u.path.is_empty():
		return true
	var next := u.path[0]
	if not is_walkable(next):
		u.path.clear()  # the world changed since this path was planned
		return true
	var target := Vector2(next) + Vector2(0.5, 0.5)
	u.pos = u.pos.move_toward(target, Defs.VILLAGER_SPEED)
	if u.pos.is_equal_approx(target):
		u.path.remove_at(0)
	return u.path.is_empty()


func _plan(u: SimUnit, to: Vector2i) -> bool:
	if not is_walkable(to):
		return false
	var p := _grid.get_id_path(u.cell(), to)
	if p.is_empty():
		return false
	p.remove_at(0)  # drop the cell the unit is standing on
	u.path = p
	return true


## Plans a path to any free cell touching the given footprint.
func _approach(u: SimUnit, cell: Vector2i, size: Vector2i) -> bool:
	var from := u.cell()
	var ring := _ring(cell, size)
	ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - from).length_squared() < (b - from).length_squared())
	for c in ring:
		if _plan(u, c):
			return true
	return false


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


## Up to `count` distinct walkable cells, closest to `center` first.
func _spread(center: Vector2i, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := 0
	while out.size() < count and r < 8:
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				var on_ring := maxi(absi(x - center.x), absi(y - center.y)) == r
				if on_ring and out.size() < count and is_walkable(Vector2i(x, y)):
					out.append(Vector2i(x, y))
		r += 1
	return out


func _nearest_node(center: Vector2i, yields: String) -> Vector2i:
	var best := NO_CELL
	if center == NO_CELL:
		return best
	var best_dist := INF
	var r := Defs.RETARGET_RADIUS
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			var c := Vector2i(x, y)
			if not nodes.has(c) or Defs.NODE_KINDS[nodes[c]["kind"]]["yields"] != yields:
				continue
			var dist := float((c - center).length_squared())
			if dist < best_dist and not _ring(c, Vector2i.ONE).is_empty():
				best = c
				best_dist = dist
	return best


func _nearest_dropoff(from: Vector2i) -> SimBuilding:
	var best: SimBuilding = null
	var best_dist := INF
	for b: SimBuilding in buildings.values():
		if not b.is_complete() or not b.get_def().is_dropoff:
			continue
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


func _spawn_unit(cell: Vector2i) -> SimUnit:
	var u := SimUnit.new()
	u.id = _take_id()
	u.pos = Vector2(cell) + Vector2(0.5, 0.5)
	u.prev_pos = u.pos
	units[u.id] = u
	return u


## Requires the grid to be built already.
func _register_building(b: SimBuilding) -> void:
	buildings[b.id] = b
	var size := b.get_def().size
	for y in size.y:
		for x in size.x:
			var c := b.cell + Vector2i(x, y)
			_occupied[c] = b.id
			_grid.set_point_solid(c, true)


func _rebuild_grid() -> void:
	_grid.region = Rect2i(0, 0, width, height)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if terrain_at(c) == Terrain.WATER or nodes.has(c):
				_grid.set_point_solid(c, true)


# --- Save / load -----------------------------------------------------------

func to_dict() -> Dictionary:
	var node_rows := []
	for c: Vector2i in nodes:
		node_rows.append([c.x, c.y, nodes[c]["kind"], nodes[c]["amount"]])
	var building_rows := []
	for b: SimBuilding in buildings.values():
		building_rows.append(b.to_dict())
	var unit_rows := []
	for u: SimUnit in units.values():
		unit_rows.append(u.to_dict())
	return {
		"version": 1,
		"width": width,
		"height": height,
		"tick": tick,
		"next_id": _next_id,
		"terrain": Marshalls.raw_to_base64(terrain),
		"stockpile": stockpile.duplicate(),
		"nodes": node_rows,
		"buildings": building_rows,
		"units": unit_rows,
	}


## JSON turns every number into a float, hence the int() casts.
static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.width = int(d["width"])
	s.height = int(d["height"])
	s.tick = int(d["tick"])
	s._next_id = int(d["next_id"])
	s.terrain = Marshalls.base64_to_raw(d["terrain"])
	for kind in Defs.RESOURCE_KINDS:
		s.stockpile[kind] = int(d["stockpile"].get(kind, 0))
	for row: Array in d["nodes"]:
		s.nodes[Vector2i(int(row[0]), int(row[1]))] = {"kind": row[2], "amount": int(row[3])}
	s._rebuild_grid()
	for row: Dictionary in d["buildings"]:
		s._register_building(SimBuilding.from_dict(row))
	for row: Dictionary in d["units"]:
		var u := SimUnit.from_dict(row)
		s.units[u.id] = u
	return s
