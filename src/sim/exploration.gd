class_name Exploration
extends RefCounted
## Rules for the fog, points of interest, expeditions and survivors who ask to join.
## All the state lives in GameState; these functions only act on it.

const State := SimPerson.State
## Kinds are handed out in this order, so every map has all of them.
const KIND_CYCLE: Array[String] = [
	"farmhouse", "camp", "store", "gas", "clinic", "camp", "police", "farmhouse", "store"]


# --- Map generation --------------------------------------------------------

## Scatters points of interest over the map. Needs the walkable regions to be up to date:
## a place is only used if it can be walked to from `start`.
static func generate_pois(s: GameState, world_seed: int, home: Vector2i, start: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 2
	@warning_ignore("integer_division")
	var wanted := s.width * s.height / Defs.CELLS_PER_POI
	var tries := 0
	while s.pois.size() < wanted and tries < wanted * 200:
		tries += 1
		# The first is a place the family already knows about, a short trip away.
		var first := s.pois.is_empty()
		var cell := Vector2i(rng.randi_range(3, s.width - 5), rng.randi_range(3, s.height - 5))
		if first:
			cell = home + Vector2i(Vector2.from_angle(rng.randf() * TAU) * Defs.FIRST_POI_DISTANCE)
		if not _site_free(s, cell, home, start):
			continue
		var poi := SimPoi.new()
		poi.id = s.pois.size() + 1
		poi.kind = KIND_CYCLE[s.pois.size() % KIND_CYCLE.size()]
		poi.cell = cell
		poi.discovered = first
		# Further from home there is more to take and more waiting inside.
		var dist := Vector2(cell - home).length()
		var info: Dictionary = Defs.POI_KINDS[poi.kind]
		for res: String in info["loot"]:
			poi.loot[res] = roundi(info["loot"][res] * (Defs.LOOT_BASE_FACTOR + dist / Defs.LOOT_DISTANCE))
		if poi.kind == "camp":
			poi.survivors = rng.randi_range(2, 4)
		else:
			poi.lurkers = int(info["lurkers"]) + int(dist / Defs.POI_CELLS_PER_LURKER)
			if rng.randf() < Defs.POI_SURVIVOR_CHANCE:
				poi.survivors = rng.randi_range(1, 2)
		s._register_poi(poi)


## The footprint and a ring around it are open ground, away from home and from other places.
static func _site_free(s: GameState, cell: Vector2i, home: Vector2i, start: Vector2i) -> bool:
	if Vector2(cell - home).length() < Defs.POI_MIN_DISTANCE:
		return false
	for y in range(cell.y - 1, cell.y + SimPoi.SIZE.y + 1):
		for x in range(cell.x - 1, cell.x + SimPoi.SIZE.x + 1):
			var c := Vector2i(x, y)
			if not s.is_walkable(c) or s.building_at(c) != null:
				return false
	for other: SimPoi in s.pois.values():
		if Vector2(other.cell - cell).length() < Defs.POI_SPACING:
			return false
	return s._maybe_connected(start, cell)


# --- Fog -------------------------------------------------------------------

## Explores around a person who has walked into another fog block.
static func look(s: GameState, p: SimPerson) -> void:
	var block := Vector2i(floori(p.pos.x / Defs.FOG_BLOCK), floori(p.pos.y / Defs.FOG_BLOCK))
	if block == p.seen_block or p.inside >= 0:
		return
	p.seen_block = block
	# From the centre of the block rather than from the person, so that what gets explored
	# depends only on the blocks walked through.
	reveal(s, (Vector2(block) + Vector2(0.5, 0.5)) * Defs.FOG_BLOCK, Defs.SIGHT_RADIUS)


static func reveal(s: GameState, pos: Vector2, radius: float) -> void:
	var size := float(Defs.FOG_BLOCK)
	var limit := (radius + size * 0.5) * (radius + size * 0.5)
	for by in range(maxi(0, floori((pos.y - radius) / size)), mini(s._fog_rows, ceili((pos.y + radius) / size) + 1)):
		for bx in range(maxi(0, floori((pos.x - radius) / size)), mini(s._fog_cols, ceili((pos.x + radius) / size) + 1)):
			var i := by * s._fog_cols + bx
			if s.explored[i] != 0:
				continue
			if pos.distance_squared_to((Vector2(bx, by) + Vector2(0.5, 0.5)) * size) > limit:
				continue
			s.explored[i] = 1
			s.revealed.append(Vector2i(bx, by))
			for poi: SimPoi in s.pois.values():
				@warning_ignore("integer_division")
				if not poi.discovered and poi.cell / Defs.FOG_BLOCK == Vector2i(bx, by):
					poi.discovered = true
					s.events.append("Encontrado: %s" % poi.display_name())


# --- Expeditions -----------------------------------------------------------

static func tick_to_poi(s: GameState, p: SimPerson) -> void:
	var poi: SimPoi = s.pois.get(p.expedition)
	if poi == null:
		p.path.clear()
		p.state = State.IDLE
		return
	if poi.lurkers > 0 and poi.center().distance_to(p.pos) <= Defs.POI_WAKE_RADIUS:
		_wake_lurkers(s, poi)
	if not s._advance(p):
		return
	if s._is_adjacent(p.cell(), poi.cell, SimPoi.SIZE):
		_arrive(s, p, poi)
	elif s._approach(p, poi.cell, SimPoi.SIZE) == GameState.Plan.FAIL:
		p.state = State.IDLE


static func tick_looting(s: GameState, p: SimPerson) -> void:
	var poi: SimPoi = s.pois.get(p.expedition)
	if poi == null:
		p.state = State.IDLE
		return
	var effort := Defs.CHILD_WORK_FACTOR if p.is_child(s.day()) else 1.0
	var left := int(poi.loot.get(p.carry_kind, 0))
	if left <= 0 or p.carry_amount >= Defs.LOOT_CAPACITY * effort:
		p.state = State.TO_DROPOFF
		return
	p.work_ticks += 1
	if p.work_ticks >= Defs.LOOT_TICKS_PER_UNIT / effort:
		p.work_ticks = 0
		p.carry_amount += 1
		poi.loot[p.carry_kind] = left - 1


## Back at a drop-off: the trip is over.
static func finish(s: GameState, p: SimPerson, delivered: int) -> void:
	var poi: SimPoi = s.pois.get(p.expedition)
	var place := poi.display_name() if poi != null else "expedição"
	if delivered > 0:
		s.events.append("%s voltou de %s com %d de %s" % [
			p.first_name, place, delivered, String(Defs.RESOURCE_NAMES[p.carry_kind]).to_lower()])
	else:
		s.events.append("%s voltou de %s de mãos vazias" % [p.first_name, place])
	p.expedition = -1
	p.ordered = false
	p.state = State.IDLE


## Too tired to go on and too far from a bed: sleep where they are. The trip goes on
## when they wake up.
static func camp(p: SimPerson) -> void:
	p.path.clear()
	p.pushed = false
	p.state = State.SLEEPING


## Picks the trip up again after sleeping or fighting.
static func resume(s: GameState, p: SimPerson) -> void:
	var poi: SimPoi = s.pois.get(p.expedition)
	var nothing_left := poi == null or (poi.visited and poi.loot_left() == 0)
	p.path.clear()
	p.ordered = true
	p.state = State.TO_DROPOFF if p.carry_amount > 0 or nothing_left else State.TO_POI


static func _arrive(s: GameState, p: SimPerson, poi: SimPoi) -> void:
	if not poi.visited:
		poi.visited = true
		if poi.survivors > 0:
			make_offer(s, poi.survivors, poi.id, Defs.FOUND_OFFER_TICKS)
			poi.survivors = 0
			s.events.append("Sobreviventes encontrados: %s" % poi.display_name())
	# One kind of thing per trip, the most valuable first.
	for kind in Defs.LOOT_ORDER:
		if int(poi.loot.get(kind, 0)) > 0:
			if p.carry_kind != kind:
				p.carry_kind = kind
				p.carry_amount = 0
			p.gather_kind = kind
			p.work_ticks = 0
			p.state = State.LOOTING
			return
	p.state = State.TO_DROPOFF  # stripped bare: go home


static func _wake_lurkers(s: GameState, poi: SimPoi) -> void:
	for cell in s._spread(poi.cell, poi.lurkers):
		s.spawn_zombie(cell)
	poi.lurkers = 0
	s.events.append("Zumbis saem de %s!" % poi.display_name())


# --- Survivors -------------------------------------------------------------

## A group asking to join. `poi_id` is where they were found, or -1 if they came to the base.
## Built from a hash of the tick, so there is no random state to save.
static func make_offer(s: GameState, count: int, poi_id: int, lifetime: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(s.tick * 977 + s._next_offer_id)
	var group := []
	var surname := Defs.SURNAMES[rng.randi() % Defs.SURNAMES.size()]
	for i in count:
		# Sometimes the last of a group is a child of the family it travels with.
		var child := i > 0 and i == count - 1 and rng.randf() < 0.3
		if i > 0 and not child and rng.randf() < 0.5:
			surname = Defs.SURNAMES[rng.randi() % Defs.SURNAMES.size()]
		var sex := "f" if rng.randf() < 0.5 else "m"
		var names := Defs.FEMALE_NAMES if sex == "f" else Defs.MALE_NAMES
		var skills := {}
		if not child:
			for n in rng.randi_range(1, 2):
				skills[Defs.SKILLS[rng.randi() % Defs.SKILLS.size()]] = float(rng.randi_range(1, 5))
		group.append({
			"first_name": names[rng.randi() % names.size()], "surname": surname, "sex": sex,
			"age": rng.randi_range(6, 14) if child else rng.randi_range(18, 55), "skills": skills,
		})
	s.offers.append({"id": s._next_offer_id, "poi": poi_id, "expires": s.tick + lifetime, "people": group})
	s._next_offer_id += 1


## Every dawn there is a chance that people looking for shelter reach the base.
static func arrivals(s: GameState) -> void:
	if s.people.is_empty() or s.day() < Defs.ARRIVAL_FIRST_DAY:
		return
	for offer: Dictionary in s.offers:
		if offer["poi"] < 0:
			return  # one group at the door at a time
	if hash(s.tick * 53 + 11) % 100 >= Defs.ARRIVAL_CHANCE:
		return
	make_offer(s, 1 + hash(s.tick * 71 + 5) % 3, -1, Defs.ARRIVAL_OFFER_TICKS)
	s.events.append("Sobreviventes pedem abrigo")


static func expire_offers(s: GameState) -> void:
	for i in range(s.offers.size() - 1, -1, -1):
		if s.tick >= int(s.offers[i]["expires"]):
			s.offers.remove_at(i)
			s.events.append("Os sobreviventes foram embora")


## Everyone in the group joins, if there are beds for them. Those found at a place start
## there and are told to walk to the base.
static func accept(s: GameState, offer_id: int) -> bool:
	var offer := _find_offer(s, offer_id)
	if offer.is_empty():
		return false
	var group: Array = offer["people"]
	if s.people.size() + group.size() > s.total_beds():
		s.events.append("Falta moradia: construa mais casas antes de aceitar")
		return false
	@warning_ignore("integer_division")
	var door := Vector2i(s.width / 2, s.height / 2)
	var base := s._nearest_dropoff(door)
	if base != null:
		door = base.cell + base.get_def().size
	var poi: SimPoi = s.pois.get(offer["poi"])
	var anchor := poi.cell if poi != null else door
	var cells := s._spread(anchor, group.size())
	var ids: Array[int] = []
	for i in group.size():
		var row: Dictionary = group[i]
		var cell := cells[mini(i, cells.size() - 1)] if not cells.is_empty() else anchor
		var p := s.add_person(cell, row["first_name"], row["surname"], row["sex"], float(row["age"]))
		for skill: String in row["skills"]:
			p.skills[skill] = float(row["skills"][skill])
		ids.append(p.id)
	if poi != null:
		s.order_move(ids, door)
	s.offers.erase(offer)
	if group.size() == 1:
		s.events.append("%s %s se juntou à comunidade" % [group[0]["first_name"], group[0]["surname"]])
	else:
		s.events.append("%d pessoas se juntaram à comunidade" % group.size())
	return true


static func refuse(s: GameState, offer_id: int) -> void:
	var offer := _find_offer(s, offer_id)
	if not offer.is_empty():
		s.offers.erase(offer)


static func _find_offer(s: GameState, offer_id: int) -> Dictionary:
	for offer: Dictionary in s.offers:
		if int(offer["id"]) == offer_id:
			return offer
	return {}
