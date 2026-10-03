class_name Almanac
extends RefCounted
## What the passing of time brings from outside: seasons and the firewood they demand,
## migrating hordes, illness and herds. All the state lives in GameState.

const SIDES: Array[String] = ["norte", "sul", "oeste", "leste"]


## 0 spring, 1 summer, 2 autumn, 3 winter. The game starts in spring.
static func season(s: GameState) -> int:
	@warning_ignore("integer_division")
	return ((s.day() - 1) % Defs.DAYS_PER_YEAR) * 4 / Defs.DAYS_PER_YEAR


static func is_winter(s: GameState) -> bool:
	return season(s) == 3


## Firewood the community burns in a day of this season.
static func firewood_per_day(s: GameState) -> int:
	return ceili(s.people.size() * Defs.FIREWOOD_PER_PERSON[season(s)])


## Runs at dawn.
static func daily(s: GameState) -> void:
	_burn_firewood(s)
	_rot(s)
	if s.zombies_enabled and s.day() == s.next_horde_day - 1:
		s.events.append("Uma horda foi avistada ao %s. Chega amanhã ao anoitecer." % SIDES[_horde_side(s)])
	if s.events_enabled and s.day() >= Defs.EVENTS_FIRST_DAY:
		_random_event(s)


## Runs at dusk.
static func dusk(s: GameState) -> void:
	if s.zombies_enabled and s.day() >= s.next_horde_day:
		_horde(s)


## The day's firewood comes out of the stock at dawn. Smoke from the fires can be seen
## from afar; with no wood in winter everyone goes cold.
static func _burn_firewood(s: GameState) -> void:
	var needed := firewood_per_day(s)
	var burned := mini(needed, s.stockpile["wood"])
	s.stockpile["wood"] -= burned
	s.heating = burned > 0
	var was_cold := s.cold
	s.cold = is_winter(s) and burned < needed
	if s.cold and not was_cold:
		s.events.append("Acabou a lenha: a comunidade passa frio")


## A horde walks in from one edge of the map and across to the other side, passing
## somewhere near the middle. Whether it finds the base depends on how close it passes
## and on how much noise the base makes.
static func _horde(s: GameState) -> void:
	var side := _horde_side(s)
	@warning_ignore("integer_division")
	var count := mini(Defs.HORDE_MAX, Defs.HORDE_BASE + Defs.HORDE_PER_YEAR * (s.year() - 1) + s.people.size() / Defs.HORDE_PEOPLE_PER_ZOMBIE)
	count = mini(count, Defs.ZOMBIE_CAP - s.zombies.size())
	var r := hash(s.next_horde_day * 7919)
	# Across the map through a point up to HORDE_SPREAD cells off the centre.
	@warning_ignore("integer_division")
	var through := Vector2(s.width / 2, s.height / 2) \
			+ Vector2(r % (2 * Defs.HORDE_SPREAD) - Defs.HORDE_SPREAD, (r / 97) % (2 * Defs.HORDE_SPREAD) - Defs.HORDE_SPREAD)
	var from := Vector2(through.x, 2.0)
	var to := Vector2(through.x, s.height - 3.0)
	match side:
		1:
			from = Vector2(through.x, s.height - 3.0)
			to = Vector2(through.x, 2.0)
		2:
			from = Vector2(2.0, through.y)
			to = Vector2(s.width - 3.0, through.y)
		3:
			from = Vector2(s.width - 3.0, through.y)
			to = Vector2(2.0, through.y)
	var arrived := 0
	for cell in s._spread(Vector2i(from), count):
		var z := s.spawn_zombie(cell)
		z.goal = to
		z.migrating = true
		arrived += 1
	s.events.append("Uma horda de %d zumbis entrou pelo %s" % [arrived, SIDES[side]])
	s.next_horde_day = s.day() + maxi(Defs.HORDE_MIN_INTERVAL, Defs.HORDE_INTERVAL - (s.year() - 1))


## Old zombies fall apart, which keeps them from piling up on the map for ever.
static func _rot(s: GameState) -> void:
	var today := s.day()
	for z: SimZombie in s.zombies.values():
		if today - z.spawn_day > Defs.ZOMBIE_LIFE_DAYS and not z.hostile:
			s._remove_zombie(z)


static func _horde_side(s: GameState) -> int:
	return hash(s.next_horde_day * 104729) % 4


static func _random_event(s: GameState) -> void:
	var r := hash(s.tick * 2713 + 3) % 100
	if r < Defs.ILLNESS_CHANCE:
		var ids: Array = s.people.keys()
		if ids.is_empty():
			return
		@warning_ignore("integer_division")
		var p: SimPerson = s.people[ids[(hash(s.tick * 31) / 7) % ids.size()]]
		if not p.wounded:
			p.wounded = true
			s.events.append("%s adoeceu e precisa de remédio" % p.full_name())
	elif r < Defs.ILLNESS_CHANCE + Defs.HERD_CHANCE:
		@warning_ignore("integer_division")
		var center := Vector2i(s.width / 2, s.height / 2) \
				+ Vector2i(Vector2.from_angle((hash(s.tick * 17) % 628) / 100.0) * Defs.HERD_DISTANCE)
		var herd := 0
		for cell in s._spread(center, Defs.HERD_SIZE):
			s.spawn_animal(cell)
			herd += 1
		if herd > 0:
			s.events.append("Uma manada passa perto da base")
