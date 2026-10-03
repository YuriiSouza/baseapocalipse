extends SceneTree
## Headless smoke test of the simulation:
##   godot --headless --path . -s res://tests/sim_smoke.gd

const SEED := 12345
const State := SimPerson.State

var _failures := 0


func _init() -> void:
	_test_family()
	_test_orders()
	_test_needs()
	_test_sleep()
	_test_death()
	_test_auto_work()
	_test_production()
	_test_year()
	_test_scale_systems()
	_test_combat()
	_test_fortifications()
	_test_attraction()
	_test_siege()
	_test_save_load()
	print("FAILED: %d" % _failures if _failures > 0 else "ALL OK")
	quit(1 if _failures > 0 else 0)


func _test_family() -> void:
	print("-- family")
	var s := _new_game()
	var adults := _by_age(s, false)
	var children := _by_age(s, true)
	_check(adults.size() == 2 and children.size() == 2, "2 adults and 2 children")
	_check(adults[0].spouse == adults[1].id and adults[1].spouse == adults[0].id, "the adults are married")
	_check(adults[0].sex != adults[1].sex, "wife and husband")
	var parents_ok := true
	var names := {}
	for p: SimPerson in s.people.values():
		names[p.first_name] = true
		if p.surname != adults[0].surname:
			parents_ok = false
	for c in children:
		if not (s.people.has(c.mother) and s.people.has(c.father)):
			parents_ok = false
	_check(parents_ok, "children point to both parents and share the surname")
	_check(names.size() == 4, "four different first names")
	var skilled := 0
	for a in adults:
		for skill: String in a.skills:
			if a.skills[skill] > 0.0:
				skilled += 1
	_check(skilled >= 2, "adults start with skills (%d)" % skilled)
	_check(s.total_beds() == 4, "the house has 4 beds")
	_check(s.hour() == Defs.START_HOUR and s.day() == 1, "starts on day 1 at dawn")
	_check(adults[0].jobs["hunt"] and adults[0].jobs["build"], "adults may do every kind of work")
	_check(not children[0].jobs["hunt"] and not children[0].jobs["build"] and children[0].jobs["forage"],
		"children do not hunt or build by default")
	_check(s.animals.size() > 100, "the map has wildlife (%d)" % s.animals.size())


## Direct orders, with automatic work switched off.
func _test_orders() -> void:
	print("-- direct orders")
	var s := _manual(_new_game())
	var home := _home(s)
	var adults := _by_age(s, false)
	var kids := _by_age(s, true)
	var before: Dictionary = s.stockpile.duplicate()
	s.order_gather(_ids([adults[0]]), home + Vector2i(-4, 0))  # tree
	s.order_gather(_ids([adults[1]]), home + Vector2i(0, -6))  # pond
	s.order_gather(_ids([kids[0]]), home + Vector2i(4, -1))  # berries
	s.order_gather(_ids([kids[1]]), home + Vector2i(4, 4))  # the car
	_run(s, 500)
	for kind: String in ["wood", "scrap"]:
		_check(s.stockpile[kind] > before[kind], "%s delivered (%d -> %d)" % [kind, before[kind], s.stockpile[kind]])
	_check(kids[0].carry_kind == "food" and adults[1].carry_kind == "water", "food and water are being gathered")
	_check(s.stockpile["wood"] - before["wood"] > s.stockpile["scrap"] - before["scrap"],
		"an adult gathers faster than a child")
	_check(adults[0].ordered and adults[0].work == "", "an ordered person is not on automatic work")

	s.stockpile["wood"] = 200
	s.stockpile["scrap"] = 50
	var site := home + Vector2i(3, 6)
	_check(s.can_place("storage", site), "storage site is free")
	var storage_id := s.place_building("storage", site)
	s.order_build(_ids([adults[0]]), storage_id)
	_run(s, 300)
	_check((s.buildings[storage_id] as SimBuilding).is_complete(), "storage built")
	_check(not s.can_place("storage", site), "cannot build on top of a building")
	_check(adults[0].state == State.IDLE and not adults[0].ordered, "the order ends when the task is done")
	var house_id := s.place_building("house", home + Vector2i(-4, 3))
	s.order_build(_ids(adults), house_id)
	_run(s, 400)
	_check(s.total_beds() == 8, "second house raises beds to 8")
	adults[0].energy = 1.0  # it is evening by now; keep bedtime out of this check
	s.order_move(_ids([adults[0]]), home + Vector2i(0, 5))
	_run(s, 200)
	_check(adults[0].cell() == home + Vector2i(0, 5), "move order reaches destination")


func _test_needs() -> void:
	print("-- needs")
	var s := _manual(_new_game())
	_run(s, Defs.DAY_TICKS + 10)
	var eaten: int = Defs.STARTING_STOCKPILE["food"] - s.stockpile["food"]
	var drunk: int = Defs.STARTING_STOCKPILE["water"] - s.stockpile["water"]
	_check(eaten == 16 and drunk == 16, "4 people eat and drink 16 rations a day (%d, %d)" % [eaten, drunk])
	var healthy := true
	for p: SimPerson in s.people.values():
		if p.health < 1.0 or p.satiety < 0.7:
			healthy = false
	_check(healthy, "a fed family stays healthy")


func _test_sleep() -> void:
	print("-- sleep")
	var s := _manual(_new_game())
	var home := _home(s)
	_run(s, 1350)
	var house: SimBuilding = s.buildings.values()[0]
	var asleep := 0
	for p: SimPerson in s.people.values():
		if p.state == State.SLEEPING and p.inside == house.id:
			asleep += 1
	_check(asleep == 4 and house.occupants == 4, "everyone sleeps in the house at night (%d)" % asleep)
	_check(s.is_night(), "bedtime falls at night (%.1fh)" % s.hour())

	var sleeper := _by_age(s, true)[0]
	s.order_move(_ids([sleeper]), home + Vector2i(3, 3))
	_check(sleeper.state == State.MOVING and sleeper.inside < 0 and house.occupants == 3, "an order wakes a sleeper")
	sleeper.energy = Defs.EXHAUSTED
	s.step()
	# Still next to the house, so it is back in bed within the same tick.
	_check(sleeper.state == State.SLEEPING and sleeper.inside == house.id, "an exhausted person goes to bed despite orders")
	s.order_move(_ids([sleeper]), home + Vector2i(3, 3))
	_check(sleeper.state == State.SLEEPING, "an exhausted person refuses orders")

	# Ordered while merely tired: keeps working instead of going straight back to bed.
	var tired := _by_age(s, true)[1]
	tired.energy = 0.2
	s.order_move(_ids([tired]), home + Vector2i(6, 6))
	_run(s, 5)
	_check(tired.state == State.MOVING and tired.pushed, "a tired person obeys and pushes on")

	_run(s, 800)
	var awake := 0
	for p: SimPerson in s.people.values():
		if p.state != State.SLEEPING and p.state != State.TO_BED:
			awake += 1
	_check(awake >= 3 and house.occupants <= 1, "people wake up rested (%d awake)" % awake)

	# No beds: sleep on the ground, which restores energy more slowly.
	var s2 := _manual(_new_game())
	(s2.buildings.values()[0] as SimBuilding).progress = 0
	var p2: SimPerson = s2.people.values()[0]
	p2.energy = Defs.TIRED
	s2.step()
	s2.step()
	_check(p2.state == State.SLEEPING and p2.inside < 0, "without a bed, sleeps on the ground")


func _test_death() -> void:
	print("-- death")
	var s := _manual(_new_game())
	s.stockpile["water"] = 0
	_run(s, Defs.DAY_TICKS * 2)
	_check(s.people.size() == 4, "nobody dies of thirst within 2 days")
	_run(s, Defs.DAY_TICKS)
	_check(s.is_over(), "without water everyone is dead by day 3")
	_check(s.memorial.size() == 4 and s.memorial[0]["cause"] == "sede", "the memorial records 4 deaths by thirst")
	_check(s.events.size() == 4, "each death raises an event")
	_check((s.buildings.values()[0] as SimBuilding).occupants == 0, "the dead free their beds")

	var s2 := _manual(_new_game())
	s2.stockpile["food"] = 0
	s2.stockpile["water"] = 500
	_run(s2, Defs.DAY_TICKS * 3)
	_check(s2.people.size() == 4, "nobody starves within 3 days")
	_run(s2, Defs.DAY_TICKS * 2)
	_check(s2.is_over() and s2.memorial[0]["cause"] == "fome", "without food everyone starves by day 5")

	var idle := _manual(_new_game())
	_run(idle, Defs.DAY_TICKS * 6)
	_check(idle.is_over(), "a family that does no work at all is dead after 6 days")


func _test_auto_work() -> void:
	print("-- automatic work")
	var s := _new_game()
	var home := _home(s)
	var adults := _by_age(s, false)
	var kids := _by_age(s, true)

	# Low on everything: people spread over the needs instead of piling on one.
	s.stockpile["food"] = 5
	s.stockpile["water"] = 5
	s.stockpile["wood"] = 0
	_run(s, 20)
	var works := {}
	for p: SimPerson in s.people.values():
		works[p.work] = true
	# Food and water are both critical and outweigh wood, so the four split between those two.
	_check(not works.has("") and works.has("water") and (works.has("forage") or works.has("hunt")),
		"everyone picks work, split between water and food %s" % [works.keys()])
	_run(s, 600)
	_check(s.stockpile["water"] > 5 and s.stockpile["food"] > 5 and s.stockpile["wood"] > 0,
		"stock grows with no orders given (food %d, water %d, wood %d)" % [
			s.stockpile["food"], s.stockpile["water"], s.stockpile["wood"]])

	# A construction site is picked up by an adult, never by a child.
	s.stockpile["wood"] = 200
	var site_id := s.place_building("storage", home + Vector2i(3, 6))
	_run(s, 400)
	_check((s.buildings[site_id] as SimBuilding).is_complete(), "a construction site gets built without orders")
	_check(kids[0].last_work != "build" and kids[1].last_work != "build", "children did not build")

	# Forbidding a kind of work stops it at once and keeps it stopped.
	var everyone := _ids(adults + kids)
	s.stockpile["water"] = 0
	_run(s, 30)
	s.set_job(everyone, "water", false)
	var stopped := true
	for p: SimPerson in s.people.values():
		if p.work == "water":
			stopped = false
	_run(s, 200)
	for p: SimPerson in s.people.values():
		if p.work == "water":
			stopped = false
	_check(stopped, "forbidden work is dropped and not picked again")
	s.set_job(everyone, "water", true)

	# Once every target is met, nobody works.
	for kind: String in ["food", "water", "wood", "scrap"]:
		s.stockpile[kind] = 500
	for p: SimPerson in s.people.values():
		p.energy = 1.0
	_run(s, 400)
	var resting := 0
	for p: SimPerson in s.people.values():
		if p.state == State.IDLE and p.work == "":
			resting += 1
	_check(resting == 4, "with every target met, everyone rests (%d of 4)" % resting)

	# A direct order overrides automatic work until the person sleeps.
	s.stockpile["water"] = 0
	s.order_gather(_ids([adults[0]]), home + Vector2i(-4, 0))
	_run(s, 100)
	_check(adults[0].ordered and adults[0].gather_kind == "wood", "a direct order overrides automatic work")
	adults[0].energy = Defs.TIRED
	_run(s, 700)
	adults[0].energy = 1.0  # wake up now
	s.stockpile["water"] = 0  # make sure there is something to do
	_run(s, 30)
	_check(not adults[0].ordered and adults[0].work != "", "after sleeping the person is back on automatic work")


func _test_production() -> void:
	print("-- garden, well, hunting")
	var s := _new_game()
	var home := _home(s)
	var adults := _by_age(s, false)
	s.stockpile["wood"] = 300
	s.stockpile["scrap"] = 100
	s.stockpile["water"] = 500

	var garden: SimBuilding = s.buildings[s.place_building("garden", home + Vector2i(-3, 3))]
	_run(s, 600)
	_check(garden.is_complete() and garden.ripe_tick > 0, "a garden is built and planted without orders")
	# Take away every other food source so the harvest is what feeds the family.
	for cell: Vector2i in s.nodes.keys():
		if s.nodes[cell]["kind"] == "berries":
			s.nodes.erase(cell)
	s.animals.clear()
	s.stockpile["food"] = 30
	_run(s, garden.ripe_tick - s.tick + 5)
	_check(garden.stock == garden.get_def().crop_yield, "the crop ripens after %d days" % (Defs.GROW_TICKS / Defs.DAY_TICKS))
	var food_before: int = s.stockpile["food"]
	_run(s, 700)
	_check(garden.stock == 0 and s.stockpile["food"] > food_before, "the harvest is brought in (%d -> %d)" % [
		food_before, s.stockpile["food"]])
	_check(garden.ripe_tick > s.tick, "the garden is planted again")

	# A well next to the house beats walking to the pond.
	var s2 := _new_game()
	var home2 := _home(s2)
	s2.stockpile["wood"] = 100
	s2.stockpile["scrap"] = 50
	var well: SimBuilding = s2.buildings[s2.place_building("well", home2 + Vector2i(1, -2))]
	_check(s2.source_yield(well.cell) == "", "a well under construction gives no water")
	_run(s2, 500)
	_check(well.is_complete() and s2.source_yield(well.cell) == "water", "the well is built and gives water")
	s2.stockpile["water"] = 0
	_run(s2, 200)
	var at_well := 0
	for p: SimPerson in s2.people.values():
		if p.work == "water" and p.target_cell == well.cell:
			at_well += 1
	_check(at_well > 0 and s2.stockpile["water"] > 0, "water is drawn from the well (%d people)" % at_well)

	# Hunting: stalk, kill, carry the meat home.
	var s3 := _new_game()
	var home3 := _home(s3)
	for cell: Vector2i in s3.nodes.keys():
		if s3.nodes[cell]["kind"] == "berries":
			s3.nodes.erase(cell)
	s3.animals.clear()
	s3.stockpile["water"] = 500
	s3.stockpile["wood"] = 500
	s3.stockpile["scrap"] = 500
	s3.stockpile["food"] = 0
	var prey := s3.spawn_animal(home3 + Vector2i(6, 8))
	_run(s3, 30)
	var hunters := 0
	for p: SimPerson in s3.people.values():
		if p.work == "hunt":
			hunters += 1
			_check(not p.is_child(s3.day()), "the hunter is an adult")
	_check(hunters > 0, "with no other food, adults go hunting (%d)" % hunters)
	_run(s3, 600)
	_check(not s3.animals.has(prey.id), "the animal is killed")
	_check(s3.stockpile["food"] > 0 or s3.people.values().any(func(p: SimPerson) -> bool: return p.satiety > 0.5),
		"the meat reaches the stock")
	_check(adults.size() == 2, "sanity")


## The stage 2 criterion: a family left completely alone lives through a whole year.
func _test_year() -> void:
	print("-- a year without orders")
	var s := _new_game()
	_run(s, Defs.DAY_TICKS * Defs.DAYS_PER_YEAR)
	var worst := 1.0
	for p: SimPerson in s.people.values():
		worst = minf(worst, p.health)
	_check(s.people.size() == 4 and worst > 0.9, "all 4 alive and healthy after a year (%d alive, worst health %.2f)" % [
		s.people.size(), worst])
	_check(s.year() == 2, "the calendar is in year 2")
	print("      stock after a year: ", s.stockpile, ", animals: ", s.animals.size())


func _test_scale_systems() -> void:
	print("-- scale systems")
	var s := _manual(_new_game())
	var home := _home(s)
	var probe := Vector2(home) + Vector2(1.5, 1.5)
	var brute := 0
	for p: SimPerson in s.people.values():
		if p.pos.distance_to(probe) <= 6.0:
			brute += 1
	_check(brute == 4 and s.people_near(probe, 6.0).size() == brute, "people_near matches brute force")
	_check(s.people_near(Vector2(5, 5), 6.0).is_empty(), "people_near is empty far from everyone")

	var crowd: Array[int] = []
	for i in 16:
		@warning_ignore("integer_division")
		crowd.append(s.spawn_person(home + Vector2i(2 + i % 8, 6 + i / 8)).id)
	_manual(s)
	s.order_move(crowd, home + Vector2i(-6, 8))
	s.step()
	var planned := 0
	for id in crowd:
		if not (s.people[id] as SimPerson).path.is_empty():
			planned += 1
	_check(planned == Defs.PATHS_PER_TICK, "paths planned per tick are capped at %d (%d)" % [Defs.PATHS_PER_TICK, planned])
	_run(s, 400)
	var arrived := 0
	for id in crowd:
		if (s.people[id] as SimPerson).state == State.IDLE:
			arrived += 1
	_check(arrived == crowd.size(), "everyone still arrives (%d of %d)" % [arrived, crowd.size()])

	_check(s.nearest_source(home, "water", 10) != GameState.NO_CELL, "the pond is found from home")
	_check(s.nearest_source(Vector2i(3, 3), "nothing", 6) == GameState.NO_CELL, "an unknown resource is not found")


func _test_combat() -> void:
	print("-- zombies: combat, shelter, wounds")
	# No guards: everyone hides in the house, the zombie tears it down and kills them.
	var s := _manual(_new_game())
	var home := _home(s)
	var house: SimBuilding = s.buildings.values()[0]
	var z := s.spawn_zombie(home + Vector2i(2, 7))
	_run(s, 12)
	_check(z.target >= 0 and z.hostile, "a zombie goes after a person it can see")
	_run(s, 40)
	_check(house.sheltered == 4, "people who do not fight hide in the house (%d)" % house.sheltered)
	_check(s.events.has("Zumbis atacando!"), "the attack is announced")
	_run(s, 200)
	_check(z.siege == house.id and house.is_damaged(), "the zombie attacks the house they are hiding in")
	_run(s, 1500)
	_check(not s.buildings.has(house.id), "the house is torn down")
	_check(s.is_over() and s.memorial[0]["cause"] == "zumbis", "and everyone is killed")

	# Guards with ammunition shoot it; the children hide and come back out afterwards.
	s = _new_game()
	home = _home(s)
	house = s.buildings.values()[0]
	var adults := _by_age(s, false)
	var kids := _by_age(s, true)
	z = s.spawn_zombie(home + Vector2i(2, 9))
	_run(s, 25)
	_check(adults[0].state == State.DEFENDING and adults[1].state == State.DEFENDING, "adults defend")
	_check(kids[0].state in [State.TO_SHELTER, State.SHELTERED], "children run for shelter")
	_run(s, 300)
	_check(not s.zombies.has(z.id), "the zombie is shot dead")
	_check(s.stockpile["ammo"] < 20, "ammunition is spent (%d left)" % s.stockpile["ammo"])
	_check(kids[0].inside < 0 and house.sheltered == 0 and not s.alarm, "the children come out when it is over")
	_check(adults[0].state != State.DEFENDING, "the guards go back to normal life")

	# No ammunition: hand to hand. The fighters get hurt and are treated with medicine.
	s = _new_game()
	home = _home(s)
	adults = _by_age(s, false)
	s.stockpile["ammo"] = 0
	z = s.spawn_zombie(home + Vector2i(2, 6))
	var z2 := s.spawn_zombie(home + Vector2i(3, 6))
	_run(s, 400)
	_check(not s.zombies.has(z.id) and not s.zombies.has(z2.id), "two zombies are beaten hand to hand")
	_check(s.stockpile["medicine"] < 5, "the wounded are treated (%d medicine left)" % s.stockpile["medicine"])
	_check(not adults[0].wounded and not adults[1].wounded, "nobody is left wounded")

	# A wound with no medicine keeps draining health.
	s = _manual(_new_game())
	s.stockpile["medicine"] = 0
	s.stockpile["food"] = 500
	s.stockpile["water"] = 500
	var victim: SimPerson = s.people.values()[0]
	victim.wounded = true
	_run(s, Defs.DAY_TICKS)
	_check(victim.wounded and is_equal_approx(victim.health, 1.0 - Defs.WOUND_DRAIN), "an untreated wound drains health (%.2f)" % victim.health)
	s.stockpile["medicine"] = 1
	s.step()
	_check(not victim.wounded and s.stockpile["medicine"] == 0, "medicine cures it")

	# A guard asleep in bed gets up when the house is attacked.
	s = _new_game()
	home = _home(s)
	adults = _by_age(s, false)
	for p: SimPerson in s.people.values():
		p.energy = Defs.TIRED
	_run(s, 20)
	_check(adults[0].state == State.SLEEPING and adults[0].inside >= 0, "the family is asleep indoors")
	z = s.spawn_zombie(home + Vector2i(3, 2))
	_run(s, 60)
	_check(adults[0].state == State.DEFENDING or not s.zombies.has(z.id), "a sleeping guard wakes up to defend the house")
	_run(s, 300)
	_check(not s.zombies.has(z.id) and s.people.size() == 4, "the attack on the sleeping house is beaten off")


func _test_fortifications() -> void:
	print("-- fortifications")
	var s := _manual(_new_game())
	var home := _home(s)
	s.stockpile["wood"] = 5000
	s.stockpile["scrap"] = 500
	var gate := _built(s, "gate", home + Vector2i(2, 5))
	var fence := _built(s, "fence", home + Vector2i(3, 5))
	var at_gate := Vector2(gate.cell) + Vector2(0.5, 0.5)
	_check(s.is_walkable(gate.cell) and not s.is_walkable(fence.cell), "people walk through a gate but not a fence")
	_check(s._is_open(at_gate, false) and not s._is_open(at_gate, true), "a gate stops zombies")
	_check(not s.can_place("fence", gate.cell), "nothing can be built on a gate")

	# A fence line in the way of a zombie gets torn down.
	s = _manual(_new_game())
	home = _home(s)
	s.stockpile["wood"] = 5000
	for p: SimPerson in s.people.values():
		p.energy = Defs.TIRED  # everyone indoors and asleep, out of sight
	_run(s, 20)
	for x in range(-6, 7):
		_built(s, "fence", home + Vector2i(x, 12))
	var fences := s.buildings.size()
	var z := s.spawn_zombie(home + Vector2i(0, 15))
	z.goal = Vector2(home) + Vector2(0.5, 8.5)
	_run(s, 400)
	_check(s.buildings.size() < fences, "a zombie breaks through a fence in its way")
	_check(z.pos.y < home.y + 12.0, "and goes on past it (y %.1f)" % (z.pos.y - home.y))

	# Traps hurt zombies that step on them and wear out.
	s = _manual(_new_game())
	home = _home(s)
	s.stockpile["wood"] = 5000
	s.stockpile["scrap"] = 500
	for p: SimPerson in s.people.values():
		p.energy = Defs.TIRED
	_run(s, 20)
	var trap := _built(s, "trap", home + Vector2i(0, 12))
	var trap2 := _built(s, "trap", home + Vector2i(0, 11))
	z = s.spawn_zombie(home + Vector2i(0, 14))
	z.goal = Vector2(home) + Vector2(0.5, 8.5)
	_run(s, 45)
	_check(is_equal_approx(z.health, 0.5) and trap.hp == trap.get_def().max_hp - Defs.TRAP_WEAR, "a trap hurts the zombie and wears")
	_run(s, 60)
	_check(not s.zombies.has(z.id) and trap2.hp < trap2.get_def().max_hp, "a second trap finishes it")

	# Guards climb a tower and shoot from it.
	s = _new_game()
	home = _home(s)
	s.stockpile["wood"] = 5000
	s.stockpile["scrap"] = 500
	s.stockpile["ammo"] = 100
	var tower := _built(s, "tower", home + Vector2i(3, -3))
	z = s.spawn_zombie(home + Vector2i(3, 9))
	var manned := 0
	for i in 150:
		s.step()
		manned = maxi(manned, tower.sheltered)
	_check(manned >= 1, "guards go up the tower (%d)" % manned)
	_check(not s.zombies.has(z.id) and tower.sheltered == 0, "they shoot the zombie and come down")

	# Damage gets repaired without orders.
	s = _new_game()
	var house: SimBuilding = s.buildings.values()[0]
	house.hp = 100
	_run(s, 400)
	_check(not house.is_damaged(), "a damaged house is repaired without orders")


func _test_attraction() -> void:
	print("-- noise and arrivals")
	var s := _new_game()
	var home := _home(s)
	s.stockpile["food"] = 0  # keeps everyone busy outdoors
	_run(s, 100)
	var near := s.spawn_zombie(home + Vector2i(0, 30))
	var far := s.spawn_zombie(home + Vector2i(0, 110))
	_run(s, 60)
	_check(near.lured and near.goal.distance_to(Vector2(home)) < 20.0,
		"a zombie 30 cells away hears a working family and heads there")
	_check(not far.lured and far.target < 0, "a zombie 110 cells away does not")

	# The same distance at night, everyone asleep indoors: nothing to hear.
	s = _manual(_new_game())
	home = _home(s)
	_run(s, 1400)
	_check(s.is_night(), "it is night")
	near = s.spawn_zombie(home + Vector2i(0, 30))
	_run(s, 100)
	_check(not near.lured, "a sleeping household is not heard from 30 cells")

	# A gunshot carries much further than work does.
	s = _manual(_new_game())
	home = _home(s)
	near = s.spawn_zombie(home + Vector2i(0, 55))
	_run(s, 60)
	_check(not near.lured, "idle people are not heard from 55 cells")
	s._shot_noise[s._noise_bucket(Vector2(home))] = Defs.NOISE_SHOT * 10.0  # a short firefight
	_run(s, 60)
	_check(near.lured, "a firefight is")

	# Arrivals at the map edge grow with the days.
	s = GameState.new_game(SEED)
	_manual(s)
	s.stockpile["food"] = 100000
	s.stockpile["water"] = 100000
	_check(s.zombies.size() == Defs.ZOMBIES_AT_START, "the game starts with %d zombies, far away" % Defs.ZOMBIES_AT_START)
	var closest := INF
	for zz: SimZombie in s.zombies.values():
		closest = minf(closest, zz.pos.distance_to(Vector2(_home(s))))
	_check(closest > Defs.ZOMBIE_START_DISTANCE, "none starts within %d cells of the house (closest %.0f)" % [
		Defs.ZOMBIE_START_DISTANCE, closest])
	var count := s.zombies.size()
	s.tick = GameState.DUSK_TICK - 1
	s.step()
	var first_night := s.zombies.size() - count
	s.tick = Defs.DAY_TICKS * 40 + GameState.DUSK_TICK - 1
	count = s.zombies.size()
	s.step()
	var later := s.zombies.size() - count
	_check(first_night >= 1 and later > first_night * 3, "more arrive each dusk as time passes (%d on day 1, %d on day 41)" % [first_night, later])


## The stage 3 criterion: the same attack wipes out an undefended base and is beaten
## off by a fortified one.
func _test_siege() -> void:
	print("-- siege")
	var undefended := _siege_scenario(false)
	_manual(undefended)
	_run(undefended, 4000)
	_check(undefended.is_over(), "an undefended base falls (%d of 4 alive, %d zombies left)" % [
		undefended.people.size(), undefended.zombies.size()])

	var fortified := _siege_scenario(true)
	var house: SimBuilding = fortified.buildings.values()[0]
	var walls := fortified.buildings.size()
	_run(fortified, 4000)
	_check(fortified.people.size() == 4 and fortified.zombies.is_empty(), "a fortified base resists (%d of 4 alive, %d zombies left)" % [
		fortified.people.size(), fortified.zombies.size()])
	_check(fortified.buildings.has(house.id), "the house is still standing")
	print("      fortified: ammo left %d, wall pieces lost %d, medicine left %d" % [
		fortified.stockpile["ammo"], walls - fortified.buildings.size(), fortified.stockpile["medicine"]])

	# For balance only: the default family, no walls, 20 rounds.
	var plain := _siege_scenario(false)
	_run(plain, 4000)
	print("      default family, no walls: %d of 4 alive, %d zombies left" % [plain.people.size(), plain.zombies.size()])


## A family with full stores and 12 zombies closing in from all sides. Fortified adds a
## palisade ring with a gate, a watchtower and plenty of ammunition.
func _siege_scenario(fortified: bool) -> GameState:
	var s := _new_game()
	var home := _home(s)
	for kind: String in ["food", "water", "wood", "scrap"]:
		s.stockpile[kind] = 5000
	s.stockpile["medicine"] = 20
	if fortified:
		s.stockpile["ammo"] = 300
		for y in range(-7, 8):
			for x in range(-7, 8):
				if maxi(absi(x), absi(y)) == 7:
					_built(s, "gate" if x == 0 and y == 7 else "palisade", home + Vector2i(x, y))
		_built(s, "tower", home + Vector2i(3, -3))
		s.stockpile["wood"] = 5000
	for i in 12:
		var angle := TAU * i / 12.0
		var cell := home + Vector2i(roundi(cos(angle) * 9.5), roundi(sin(angle) * 9.5))
		for spot in s._spread(cell, 1):
			s.spawn_zombie(spot)
	return s


func _test_save_load() -> void:
	print("-- save / load")
	var s := _new_game()
	var home := _home(s)
	var everyone := _ids(_by_age(s, false) + _by_age(s, true))
	s.stockpile["wood"] = 100
	s.place_building("garden", home + Vector2i(-3, 3))
	s.zombies_enabled = true
	s.stockpile["ammo"] = 3  # the fight below runs out of ammunition half way
	_built(s, "fence", home + Vector2i(2, 5))
	_built(s, "trap", home + Vector2i(3, 5))
	s.spawn_zombie(home + Vector2i(0, 12))
	s.spawn_zombie(home + Vector2i(2, 9))
	s.spawn_zombie(home + Vector2i(-30, 4))
	# No water and nobody allowed to fetch it: people die a while after the save,
	# so the comparison below also covers deaths and the memorial.
	s.stockpile["water"] = 0
	s.set_job(everyone, "water", false)
	_run(s, 1300)  # automatic work going on, some people already in bed
	var saved := var_to_bytes(s.to_dict())
	var loaded := GameState.from_dict(bytes_to_var(saved))
	_check(var_to_bytes(loaded.to_dict()) == saved, "save/load round trip is lossless")
	_check((loaded.buildings.values()[0] as SimBuilding).occupants == (s.buildings.values()[0] as SimBuilding).occupants,
		"bed occupancy is rebuilt on load")
	_run(s, Defs.DAY_TICKS * 2)
	_run(loaded, Defs.DAY_TICKS * 2)
	_check(not s.memorial.is_empty(), "the scenario includes deaths (%d)" % s.memorial.size())
	_check(var_to_bytes(loaded.to_dict()) == var_to_bytes(s.to_dict()),
		"loaded game stays in sync for 2 more days")


## A new game with no zombies on the map and none arriving.
func _new_game() -> GameState:
	var s := GameState.new_game(SEED)
	s.zombies_enabled = false
	s.clear_zombies()
	return s


## Places a building and finishes it on the spot. Null if it cannot go there.
func _built(s: GameState, def_id: String, cell: Vector2i) -> SimBuilding:
	var id := s.place_building(def_id, cell)
	if id < 0:
		return null
	var b: SimBuilding = s.buildings[id]
	b.progress = b.get_def().build_ticks
	return b


## Switches off automatic work for everyone, for tests that drive people by hand.
func _manual(s: GameState) -> GameState:
	for p: SimPerson in s.people.values():
		for work in Defs.WORK_TYPES:
			p.jobs[work] = false
	return s


func _home(s: GameState) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(s.width / 2, s.height / 2)


func _by_age(s: GameState, children: bool) -> Array[SimPerson]:
	var out: Array[SimPerson] = []
	for p: SimPerson in s.people.values():
		if p.is_child(s.day()) == children:
			out.append(p)
	return out


func _ids(list: Array[SimPerson]) -> Array[int]:
	var out: Array[int] = []
	for p in list:
		out.append(p.id)
	return out


func _run(s: GameState, ticks: int) -> void:
	for i in ticks:
		s.step()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", label])
