extends SceneTree
## Headless load test of the simulation at the target scale:
##   godot --headless --path . -s res://tests/load_test.gd
## Prints the cost of a tick. At 5x speed the game runs 50 ticks per second.

const PEOPLE := 150
const ZOMBIES := 500
const TICKS := 1800  # one full day, so it covers work, bedtime and sleep
const GATHERED: Array[String] = ["wood", "food", "scrap", "water"]


func _init() -> void:
	var t := Time.get_ticks_usec()
	var s := GameState.new_game(777)
	print("new_game %dx%d: %.0f ms, %d resource nodes" % [s.width, s.height, _ms(t), s.nodes.size()])
	@warning_ignore("integer_division")
	var home := Vector2i(s.width / 2, s.height / 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# Enough to live on, but below the targets, so automatic work has plenty to do.
	s.stockpile["food"] = 1200
	s.stockpile["water"] = 600
	s.stockpile["wood"] = 300
	s.stockpile["ammo"] = 3000
	s.stockpile["medicine"] = 200
	s.clear_zombies()
	for offset: Vector2i in [Vector2i(-6, 6), Vector2i(-9, 6), Vector2i(-6, 9), Vector2i(-9, 9)]:
		s.place_building("garden", home + offset)

	# A third of the people follow direct orders far from home; the rest work on their own.
	for cell in s._spread(home + Vector2i(0, 5), PEOPLE - s.people.size()):
		s.spawn_person(cell)
	var working := 0
	for p: SimPerson in s.people.values():
		if p.id % 3 != 0:
			continue
		var probe := home + Vector2i(rng.randi_range(-40, 40), rng.randi_range(-40, 40))
		var source := s.nearest_source(probe, GATHERED[p.id % GATHERED.size()], 12)
		if source != GameState.NO_CELL:
			s.order_gather([p.id] as Array[int], source)
			working += 1

	# Zombies: half near the settlement (so they chase), half spread over the map.
	while s.zombies.size() < ZOMBIES:
		@warning_ignore("integer_division")
		var reach := 45 if s.zombies.size() % 2 == 0 else s.width / 2 - 1
		var cell := home + Vector2i(rng.randi_range(-reach, reach), rng.randi_range(-reach, reach))
		if s.is_walkable(cell):
			s.spawn_zombie(cell)
	print("people: %d (%d under orders), zombies: %d, animals: %d" % [
		s.people.size(), working, s.zombies.size(), s.animals.size()])

	var before: Dictionary = s.stockpile.duplicate()
	var samples := PackedFloat32Array()
	for i in TICKS:
		t = Time.get_ticks_usec()
		s.step()
		samples.append(_ms(t))
	samples.sort()
	var total := 0.0
	for v in samples:
		total += v
	@warning_ignore("integer_division")
	print("tick ms  avg %.3f  p50 %.3f  p99 %.3f  max %.3f" % [
		total / TICKS, samples[TICKS / 2], samples[TICKS * 99 / 100], samples[TICKS - 1]])
	print("at 5x (50 ticks/s) the simulation uses %.1f%% of each second" % (total / TICKS * 50.0 / 10.0))

	var chasing := 0
	for z: SimZombie in s.zombies.values():
		if z.target >= 0:
			chasing += 1
	var states := {}
	for p: SimPerson in s.people.values():
		var state_name: String = SimPerson.State.keys()[p.state]
		states[state_name] = int(states.get(state_name, 0)) + 1
	print("alive: %d, zombies chasing: %d, people by state: %s" % [s.people.size(), chasing, states])
	var change := PackedStringArray()
	for kind in Defs.RESOURCE_KINDS:
		change.append("%s %+d" % [kind, s.stockpile[kind] - before[kind]])
	print("stock change: ", ", ".join(change))

	t = Time.get_ticks_usec()
	var saved := var_to_bytes(s.to_dict())
	@warning_ignore("integer_division")
	print("save: %.0f ms, %d KB" % [_ms(t), saved.size() / 1024])
	t = Time.get_ticks_usec()
	GameState.from_dict(bytes_to_var(saved))
	print("load: %.0f ms" % _ms(t))
	quit()


func _ms(since_usec: int) -> float:
	return (Time.get_ticks_usec() - since_usec) / 1000.0
