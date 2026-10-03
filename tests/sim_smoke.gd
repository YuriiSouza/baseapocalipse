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
	_test_exploration()
	_test_expeditions()
	_test_survivors()
	_test_growth()
	_test_skills()
	_test_knowledge()
	_test_teaching()
	_test_seasons()
	_test_morale()
	_test_generations()
	_test_hordes()
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
	_check(s.events.filter(func(e: String) -> bool: return e.contains("morreu")).size() == 4, "each death raises an event")
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

	# Once every target is met, nobody works: at most they sit down to study.
	for kind: String in ["food", "water", "wood", "scrap"]:
		s.stockpile[kind] = 500
	for p: SimPerson in s.people.values():
		p.energy = 1.0
	_run(s, 400)
	var resting := 0
	for p: SimPerson in s.people.values():
		if (p.state == State.IDLE and p.work == "") or p.work == "study":
			resting += 1
	_check(resting == 4, "with every target met, everyone rests or studies (%d of 4)" % resting)

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
	# The mother knows farming well enough for crop rotation, which gives half as much again.
	_check(garden.stock == garden.get_def().crop_yield * 3 / 2, "the crop ripens after %d days (%d of food)" % [
		Defs.GROW_TICKS / Defs.DAY_TICKS, garden.stock])
	# Back to the plain yield: more than that and the food target is met before the plot is empty.
	garden.stock = garden.get_def().crop_yield
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


func _test_exploration() -> void:
	print("-- fog and points of interest")
	var s := _manual(_new_game())
	var home := _home(s)
	_check(s.is_explored(home) and s.is_explored(home + Vector2i(12, 0)) and not s.is_explored(home + Vector2i(40, 0)),
		"only the surroundings of the home start explored")
	var known: Array[SimPoi] = []
	var kinds := {}
	var formula_ok := true
	var reachable := true
	var closest := INF
	for poi: SimPoi in s.pois.values():
		kinds[poi.kind] = true
		var dist := Vector2(poi.cell - home).length()
		closest = minf(closest, dist)
		if poi.discovered:
			known.append(poi)
		var base: int = Defs.POI_KINDS[poi.kind]["lurkers"]
		if poi.kind != "camp" and poi.lurkers != base + int(dist / Defs.POI_CELLS_PER_LURKER):
			formula_ok = false
		if s._ring(poi.cell, SimPoi.SIZE).is_empty() or not s._maybe_connected(home + Vector2i(1, 1), s._ring(poi.cell, SimPoi.SIZE)[0]):
			reachable = false
	_check(s.pois.size() >= 20 and kinds.size() == Defs.POI_KINDS.size(), "the map has %d places of %d kinds" % [s.pois.size(), kinds.size()])
	_check(closest >= Defs.POI_MIN_DISTANCE, "none closer than %d cells to the home (%.0f)" % [Defs.POI_MIN_DISTANCE, closest])
	_check(reachable, "every place can be walked to from the home")
	_check(formula_ok, "the further a place, the more zombies inside")
	_check(known.size() == 1 and absf(Vector2(known[0].cell - home).length() - Defs.FIRST_POI_DISTANCE) < 2.0,
		"the family starts knowing one place, a short trip away")
	_check(not s.can_place("house", known[0].cell) and s.poi_at(known[0].cell + Vector2i.ONE) == known[0],
		"a place takes up its cells")

	# Walking into the fog lifts it and finds what is there.
	var hidden: SimPoi = null
	for poi: SimPoi in s.pois.values():
		if not poi.discovered and (hidden == null or (poi.cell - home).length() < (hidden.cell - home).length()):
			hidden = poi
	var scout := _by_age(s, false)[0]
	_check(not s.is_explored(hidden.cell), "the nearest unknown place is in the fog")
	s.order_expedition(_ids([scout]), hidden.id)
	_check(scout.expedition < 0 and scout.state == State.IDLE, "an expedition cannot be sent to a place nobody has seen")
	s.order_move(_ids([scout]), s._ring(hidden.cell, SimPoi.SIZE)[0])
	for i in 600:
		s.step()
		if hidden.discovered:
			break
	_check(hidden.discovered and s.is_explored(hidden.cell), "a scout walking there finds it")
	_check(s.events.has("Encontrado: %s" % hidden.display_name()), "and the find is announced")
	_check(not s.revealed.is_empty(), "newly explored blocks are reported to the view")


func _test_expeditions() -> void:
	print("-- expeditions")
	var s := _manual(_new_game())
	var adults := _by_age(s, false)
	var place := _known_place(s)
	place.lurkers = 0
	place.survivors = 0
	place.loot = {"scrap": 100}
	s.order_expedition(_ids(adults), place.id)
	_check(adults[0].state == State.TO_POI and adults[0].expedition == place.id and adults[0].ordered, "the group sets off")
	_check(_expedition(s, adults, 1500), "and comes back")
	_check(place.visited and place.loot_left() == 100 - 2 * Defs.LOOT_CAPACITY and s.stockpile["scrap"] == 2 * Defs.LOOT_CAPACITY,
		"each brings a full bag home (%d left there, %d in stock)" % [place.loot_left(), s.stockpile["scrap"]])
	_check(adults[0].state == State.IDLE and not adults[0].ordered, "the order ends when they are back")

	# The loot is finite.
	place.loot = {"scrap": 5}
	s.events.clear()
	s.order_expedition(_ids(adults), place.id)
	_expedition(s, adults, 1500)
	_check(place.loot_left() == 0 and s.stockpile["scrap"] == 2 * Defs.LOOT_CAPACITY + 5, "a place can be stripped bare")
	adults[1].energy = 1.0
	s.order_expedition(_ids([adults[1]]), place.id)
	_expedition(s, adults, 1500)
	_check(s.events.any(func(e: String) -> bool: return e.ends_with("de mãos vazias")), "whoever goes there again comes back empty-handed")

	# Medicine and ammunition are taken before food and scrap.
	place.loot = {"scrap": 50, "food": 50, "medicine": 3}
	adults[0].energy = 1.0
	s.order_expedition(_ids([adults[0]]), place.id)
	_expedition(s, adults, 1500)
	_check(place.loot["medicine"] == 0 and place.loot["food"] == 50 and s.stockpile["medicine"] == 8,
		"medicine is taken first")

	# Too tired half way: camp on the spot, then carry on.
	s.stockpile["food"] = 500
	s.stockpile["water"] = 500
	adults[0].energy = Defs.TIRED + 0.04
	place.loot = {"scrap": 50}
	s.order_expedition(_ids([adults[0]]), place.id)
	_run(s, 120)
	_check(adults[0].state == State.SLEEPING and adults[0].inside < 0 and adults[0].expedition == place.id,
		"a tired expedition camps on the way")
	adults[0].energy = 1.0
	s.step()
	_check(adults[0].state == State.TO_POI, "and goes on after sleeping")
	_check(_expedition(s, adults, 1500) and place.loot_left() == 50 - Defs.LOOT_CAPACITY, "the trip is completed")

	# Zombies inside come out when the group gets close; armed guards deal with them.
	s = _new_game()
	adults = _by_age(s, false)
	place = _known_place(s)
	place.lurkers = 2
	place.survivors = 0
	for kind: String in ["food", "water", "wood", "scrap"]:
		s.stockpile[kind] = 500
	s.order_expedition(_ids(adults), place.id)
	var came_out := 0
	for i in 400:
		s.step()
		came_out = maxi(came_out, s.zombies.size())
	_check(came_out == 2 and place.lurkers == 0 and s.events.has("Zumbis saem de %s!" % place.display_name()),
		"the zombies inside come out (%d)" % came_out)
	_check(_expedition(s, adults, 2500) and s.zombies.is_empty() and s.people.size() == 4,
		"the guards shoot them and the trip goes on (%d zombies left)" % s.zombies.size())
	_check(s.stockpile["ammo"] < 20 and place.visited, "at the cost of ammunition (%d left)" % s.stockpile["ammo"])


func _test_survivors() -> void:
	print("-- survivors")
	var s := _manual(_new_game())
	var home := _home(s)
	var adults := _by_age(s, false)
	var place := _known_place(s)
	place.lurkers = 0
	place.survivors = 2
	s.stockpile["food"] = 500
	s.stockpile["water"] = 500
	s.order_expedition(_ids([adults[0]]), place.id)
	_expedition(s, adults, 1500)
	_check(s.offers.size() == 1 and s.offers[0]["poi"] == place.id and (s.offers[0]["people"] as Array).size() == 2,
		"people hiding at a place ask to join when it is reached")
	var offer_id: int = s.offers[0]["id"]
	var first_name: String = s.offers[0]["people"][0]["first_name"]
	_check(not s.accept_offer(offer_id) and s.people.size() == 4 and s.offers.size() == 1, "without free beds they cannot be taken in")
	s.stockpile["wood"] = 200
	s.stockpile["scrap"] = 50
	_built(s, "house", home + Vector2i(-4, 3))
	_check(s.total_beds() == 8 and s.accept_offer(offer_id), "with a second house they can")
	_check(s.people.size() == 6 and s.offers.is_empty(), "the community grows to 6")
	var newcomer: SimPerson = null
	for p: SimPerson in s.people.values():
		if p.first_name == first_name and p.pos.distance_to(place.center()) < 5.0:
			newcomer = p
	_check(newcomer != null and newcomer.jobs["guard"] and not newcomer.skills.is_empty(), "they start at the place where they were found")
	_run(s, 400)
	_check(newcomer.pos.distance_to(Vector2(home)) < 8.0, "and walk to the base on their own (%.0f cells away)" % newcomer.pos.distance_to(Vector2(home)))

	# Refusing and letting an offer lapse.
	Exploration.make_offer(s, 3, -1, 100)
	s.refuse_offer(s.offers[0]["id"])
	_check(s.offers.is_empty() and s.people.size() == 6, "a refused group goes away")
	Exploration.make_offer(s, 1, -1, 100)
	_run(s, 151)
	_check(s.offers.is_empty() and s.events.has("Os sobreviventes foram embora"), "an unanswered group leaves after a while")

	# People turning up at the base: none in the first days, then now and then.
	s = _manual(_new_game())
	s.arrivals_enabled = true
	var groups := 0
	var first_day := 0
	var one_at_a_time := true
	for d in range(1, 61):
		s.tick = Defs.DAY_TICKS * d - 1
		s.step()
		if not s.offers.is_empty():
			groups += 1
			if first_day == 0:
				first_day = s.day()
			if s.offers.size() != 1 or s.offers[0]["poi"] != -1:
				one_at_a_time = false
			s.refuse_offer(s.offers[0]["id"])
	_check(one_at_a_time, "one group at the door at a time")
	_check(first_day >= Defs.ARRIVAL_FIRST_DAY and groups >= 6 and groups <= 25,
		"survivors reach the base now and then (%d groups in 60 days, first on day %d)" % [groups, first_day])
	Exploration.make_offer(s, 2, -1, 100)
	s.stockpile["wood"] = 200
	s.stockpile["scrap"] = 50
	_check(_built(s, "house", _home(s) + Vector2i(-4, 3)) != null and s.accept_offer(s.offers[0]["id"]), "they are taken in")
	var at_base := 0
	for p: SimPerson in s.people.values():
		if p.pos.distance_to(Vector2(_home(s))) < 6.0:
			at_base += 1
	_check(at_base == 6, "and appear at the base (%d there)" % at_base)


## The stage 4 criterion: by exploring and taking people in, the family of 4 becomes a
## community of about 20. Played by a simple script standing in for the player, in a
## normal game with zombies.
func _test_growth() -> void:
	print("-- growth by exploration")
	var s := GameState.new_game(SEED)
	var home := _home(s)
	var days := 0
	var found := 0
	var arrived := 0
	while s.people.size() < 20 and not s.is_over() and days < 5 * Defs.DAYS_PER_YEAR:
		for i in Defs.DAY_TICKS / 100:
			_run(s, 100)
			for offer: Dictionary in s.offers.duplicate():
				var group: int = (offer["people"] as Array).size()
				if s.accept_offer(offer["id"]):
					if offer["poi"] >= 0:
						found += group
					else:
						arrived += group
			_player_builds(s, home)
			_player_explores(s, home)
		days += 1
	_check(s.people.size() >= 20, "the family of 4 grows to %d in %d days (%d found, %d arrived, %d died)" % [
		s.people.size(), days, found, arrived, s.memorial.size()])
	_check(found >= 8, "most of them found by expeditions")
	var visited := 0
	var explored := 0
	for poi: SimPoi in s.pois.values():
		if poi.visited:
			visited += 1
	for block in s.explored:
		explored += block
	print("      places visited %d of %d, map explored %d%%, zombies %d, stock %s" % [
		visited, s.pois.size(), 100 * explored / s.explored.size(), s.zombies.size(), s.stockpile])


## Keeps a few beds free for newcomers, and water and food production in step with the
## number of people.
func _player_builds(s: GameState, home: Vector2i) -> void:
	var counts := {}
	for b: SimBuilding in s.buildings.values():
		counts[b.def_id] = int(counts.get(b.def_id, 0)) + 1
	var wanted := ""
	if int(counts.get("well", 0)) == 0:
		wanted = "well"
	elif int(counts.get("house", 0)) * 4 < s.people.size() + 4:
		wanted = "house"
	elif int(counts.get("garden", 0)) * 3 < s.people.size():
		wanted = "garden"
	if wanted == "" or not s.can_afford(Defs.building(wanted).cost):
		return
	for r in range(3, 16, 3):
		for y in range(-r, r + 1, 3):
			for x in range(-r, r + 1, 3):
				if maxi(absi(x), absi(y)) == r and s.place_building(wanted, home + Vector2i(x, y)) >= 0:
					return


## Each morning sends half of the rested adults to the nearest known place worth a trip.
## With none known, one adult scouts towards the nearest undiscovered place, which stands
## in for a player combing the fog.
func _player_explores(s: GameState, home: Vector2i) -> void:
	if s.hour() > 9.0:
		return
	var team: Array[int] = []
	for p: SimPerson in s.people.values():
		if p.expedition >= 0 or p.ordered:
			return  # someone is still out
		if not p.is_child(s.day()) and p.energy > 0.8 and not p.wounded:
			team.append(p.id)
	team.resize(mini(team.size(), maxi(2, team.size() / 2)))
	var target: SimPoi = null
	var unknown: SimPoi = null
	for poi: SimPoi in s.pois.values():
		var dist := (poi.cell - home).length()
		if not poi.discovered:
			if unknown == null or dist < (unknown.cell - home).length():
				unknown = poi
		elif (not poi.visited or poi.loot_left() > 0) and (target == null or dist < (target.cell - home).length()):
			target = poi
	if team.is_empty():
		return
	if target != null:
		s.order_expedition(team, target.id)
	elif unknown != null:
		s.order_move([team[0]] as Array[int], s._ring(unknown.cell, SimPoi.SIZE)[0])


## The place the family knows about from the start.
func _known_place(s: GameState) -> SimPoi:
	for poi: SimPoi in s.pois.values():
		if poi.discovered:
			return poi
	return null


## Runs until none of the people is on an expedition any more. False if it takes too long.
func _expedition(s: GameState, members: Array[SimPerson], limit: int) -> bool:
	for i in limit:
		s.step()
		if not members.any(func(p: SimPerson) -> bool: return p.expedition >= 0):
			return true
	return false


func _test_skills() -> void:
	print("-- skills grow with practice")
	var s := _manual(_new_game())
	var home := _home(s)
	var adults := _by_age(s, false)
	s.stockpile["wood"] = 500
	s.stockpile["scrap"] = 100
	s.order_gather(_ids([adults[0]]), home + Vector2i(-4, 0))  # tree
	s.order_build(_ids([adults[1]]), s.place_building("storage", home + Vector2i(3, 6)))
	_run(s, 300)
	_check(adults[0].skills["building"] > 0.0 and adults[0].skills["foraging"] == 0.0, "cutting wood trains building (%.3f)" % adults[0].skills["building"])
	_check(adults[1].skills["building"] > 0.0, "so does putting up a building (%.3f)" % adults[1].skills["building"])

	var novice := SimPerson.new()
	var master := SimPerson.new()
	master.skills["combat"] = 5.0
	Knowledge.practice(novice, "combat", 0.1)
	Knowledge.practice(master, "combat", 0.1)
	_check(novice.skills["combat"] > (master.skills["combat"] - 5.0) * 3.0, "the higher the level, the slower it grows")
	master.skills["combat"] = 9.99
	Knowledge.practice(master, "combat", 5.0)
	_check(master.skills["combat"] == Defs.MAX_SKILL, "skills stop at %d" % Defs.MAX_SKILL)

	var slow := _ticks_to_fill(0.0)
	var fast := _ticks_to_fill(5.0)
	_check(fast < slow, "a skilled person works faster (%d ticks against %d)" % [fast, slow])

	# Shooting and treating wounds are practice too.
	s = _new_game()
	adults = _by_age(s, false)
	var combat: float = adults[0].skills["combat"] + adults[1].skills["combat"]
	var medicine: float = adults[0].skills["medicine"]
	s.stockpile["ammo"] = 0
	s.spawn_zombie(_home(s) + Vector2i(2, 6))
	_run(s, 400)
	_check(adults[0].skills["combat"] + adults[1].skills["combat"] > combat, "fighting trains combat")
	_check(s.stockpile["medicine"] < 5 and adults[0].skills["medicine"] > medicine, "treating wounds trains whoever knows most medicine")


## Ticks an adult with this much foraging takes to fill up with water at the pond.
func _ticks_to_fill(foraging: float) -> int:
	var s := _manual(_new_game())
	var p := _by_age(s, false)[0]
	p.skills["foraging"] = foraging
	s.order_gather(_ids([p]), _home(s) + Vector2i(0, -6))
	for i in 400:
		s.step()
		if p.state == State.TO_DROPOFF:
			return i
	return 400


## The stage 5 criterion: what the community can do follows from what its people know,
## and losing the only one who knew something blocks what was possible before.
func _test_knowledge() -> void:
	print("-- knowledge")
	var s := _locked(_manual(_new_game()))
	var home := _home(s)
	var adults := _by_age(s, false)
	# The test family: the father knows medicine 3 and combat 3, the mother hunting 3 and farming 4.
	_check(s.knowledge("farming") == 4 and s.knowledge("medicine") == 3 and s.knowledge("building") == 0,
		"the community knows what its best member knows")
	_check(s.can_build("house") and s.can_build("fence") and s.can_build("workshop"), "the basics need no knowledge")
	_check(not s.can_build("palisade") and not s.can_build("trap") and not s.can_build("wall"), "fortifications beyond a fence do")
	_check(s.place_building("palisade", home + Vector2i(0, 8)) == -1, "what is not known cannot be built")

	var builder := adults[0]
	builder.skills["building"] = 3.4
	s.step()
	_check(s.knowledge("building") == 3 and s.can_build("palisade") and s.can_build("tower") and not s.can_build("wall"),
		"a builder of level 3 unlocks palisade and tower, not the wall")
	var first := s.place_building("palisade", home + Vector2i(0, 8))
	_check(first >= 0, "and now it can be built")
	s.events.clear()
	s._kill(builder, "zumbis")
	_check(s.knowledge("building") == 0 and not s.can_build("palisade") and s.place_building("palisade", home + Vector2i(1, 8)) == -1,
		"with the only builder dead, it cannot any more")
	_check(s.events.any(func(e: String) -> bool: return e.contains("se foi conhecimento") and e.contains("construção 3 → 0")),
		"the loss is announced")
	_check(s.buildings.has(first), "what was already built stays")

	# Improvements follow knowledge too.
	_check(Knowledge.bonus(s, "crop_yield") == 1.5 and Knowledge.bonus(s, "carcass") == 1.5, "farming 4 and hunting 3 bring improvements")
	s._kill(adults[1], "zumbis")
	_check(Knowledge.bonus(s, "crop_yield") == 1.0, "which are lost with the person")

	# Recipes at the workshop: ammunition out of scrap needs mechanics 3.
	s = _locked(_manual(_new_game()))
	home = _home(s)
	adults = _by_age(s, false)
	for kind: String in ["food", "water", "wood", "scrap"]:
		s.stockpile[kind] = 500
	s.stockpile["ammo"] = 0
	var shop := _built(s, "workshop", home + Vector2i(3, 5))
	s.set_job(_ids(adults), "craft", true)
	_run(s, 400)
	_check(shop != null and s.stockpile["ammo"] == 0 and s.stockpile["medicine"] > 5,
		"without mechanics no ammunition is made, but the father's medicine makes remedies (%d)" % s.stockpile["medicine"])
	adults[1].skills["mechanics"] = 3.0
	_run(s, 600)
	_check(s.stockpile["ammo"] > 0 and s.stockpile["scrap"] < 500, "a mechanic makes ammunition out of scrap (%d)" % s.stockpile["ammo"])
	_check(adults[1].skills["mechanics"] > 3.0, "and gets better at it")
	s._kill(adults[1], "zumbis")
	s.stockpile["ammo"] = 0
	_run(s, 600)
	_check(s.stockpile["ammo"] == 0, "with the mechanic dead, no more ammunition")
	s.stockpile["medicine"] = 10
	_run(s, 50)
	var food: int = s.stockpile["food"]
	_run(s, 400)
	_check(s.stockpile["medicine"] == 10 and adults[0].state != State.CRAFTING, "nothing is made beyond the target stock")
	_check(food - s.stockpile["food"] < 10, "and no food goes into remedies meanwhile")


func _test_teaching() -> void:
	print("-- teaching and books")
	var s := _locked(_manual(_new_game()))
	var adults := _by_age(s, false)
	var kids := _by_age(s, true)
	var master := adults[0]
	var pupil := kids[0]
	for kind: String in ["food", "water", "wood"]:
		s.stockpile[kind] = 5000
	for skill in Defs.SKILLS:
		for p: SimPerson in s.people.values():
			p.skills[skill] = 0.0
	master.skills["building"] = 4.0
	_check(Knowledge.study_plan(s, pupil) == ["building", false], "a pupil can learn what someone else knows")
	_check(Knowledge.study_plan(s, master) == ["building", true], "the one who knows it best can write it down")
	_check(Knowledge.study_plan(s, kids[1]) == ["building", false] and Knowledge.study_plan(s, adults[1]).size() == 2, "and so can everyone else")

	s.set_job(_ids([pupil]), "study", true)
	_run(s, 60)
	_check(pupil.work == "study" and pupil.state in [State.TO_STUDY, State.STUDYING], "with nothing else to do, the pupil studies")
	_run(s, Defs.DAY_TICKS * 3)
	_check(pupil.skills["building"] > 1.0 and pupil.skills["building"] <= 4.0, "and learns from the master (%.2f)" % pupil.skills["building"])
	var learned: float = pupil.skills["building"]

	# No book: when the master dies the pupil is stuck at what was learned so far.
	var lone := GameState.from_dict(bytes_to_var(var_to_bytes(s.to_dict())))
	lone._kill(lone.people[master.id], "zumbis")
	var lone_pupil: SimPerson = lone.people[pupil.id]
	_run(lone, Defs.DAY_TICKS * 4)
	_check(is_equal_approx(lone_pupil.skills["building"], learned), "without the master or a book there is nobody to learn from")

	# The master writes a book; after the master dies, the book still teaches.
	s.set_job(_ids([master]), "study", true)
	for i in Defs.DAY_TICKS * 2:
		s.step()
		if s.library.has("building"):
			break
	_check(s.library.get("building", 0) == 4, "the master writes a book of level 4")
	_check(s.events.any(func(e: String) -> bool: return e.contains("escreveu um livro de construção")), "which is announced")
	_check(Knowledge.study_plan(s, master).is_empty(), "there is nothing more for the master to write")
	s._kill(master, "zumbis")
	pupil.skills["building"] = 1.5
	s.step()
	_check(not s.can_build("palisade"), "with the master dead the palisade is lost")
	for i in Defs.DAY_TICKS * 6:
		s.step()
		if s.can_build("palisade"):
			break
	_check(s.can_build("palisade") and pupil.skills["building"] >= 2.0, "the pupil gets it back from the book (%.2f)" % pupil.skills["building"])
	_run(s, Defs.DAY_TICKS * 30)
	_check(pupil.skills["building"] > 3.0 and pupil.skills["building"] <= 4.0, "but no further than the book goes (%.2f)" % pupil.skills["building"])

	# Books are also found on expeditions.
	s = _manual(_new_game())
	var place := _known_place(s)
	place.lurkers = 0
	place.survivors = 0
	place.book = "mechanics"
	place.book_level = 3
	s.order_expedition(_ids([_by_age(s, false)[0]]), place.id)
	_expedition(s, _by_age(s, false), 1500)
	_check(s.library.get("mechanics", 0) == 3 and place.book == "", "a book found at a place joins the library")
	var with_books := 0
	for poi: SimPoi in s.pois.values():
		if poi.book != "":
			with_books += 1
	_check(with_books >= 3, "some places on the map have books (%d)" % with_books)


func _test_seasons() -> void:
	print("-- seasons and firewood")
	var s := _manual(_new_game())
	var seen := []
	for d in [1, 3, 4, 7, 10, 12, 13]:
		s.tick = Defs.DAY_TICKS * (d - 1)
		seen.append(s.season())
	_check(seen == [0, 0, 1, 2, 3, 3, 0], "a year has four seasons of %d days, starting in spring" % (Defs.DAYS_PER_YEAR / 4))

	s = _manual(_new_game())
	s.stockpile["food"] = 5000
	s.stockpile["water"] = 5000
	s.stockpile["wood"] = 100
	for d in range(2, 6):
		_dawn(s, d)
	_check(s.stockpile["wood"] == 100 - 2 and not s.heating, "little firewood is burned in spring and none in summer (%d left)" % s.stockpile["wood"])
	_dawn(s, 10)
	var before: int = s.stockpile["wood"]
	_dawn(s, 11)
	_check(before - s.stockpile["wood"] == 4 and s.heating and not s.cold, "in winter each person burns a log a day")
	s.stockpile["wood"] = 0
	s.events.clear()
	_dawn(s, 12)
	_check(s.cold and s.events.has("Acabou a lenha: a comunidade passa frio"), "with no firewood in winter the community goes cold")
	_run(s, Defs.DAY_TICKS - 10)
	var worst := 1.0
	for p: SimPerson in s.people.values():
		worst = minf(worst, p.health)
	_check(worst < 0.8 and s.people.size() == 4, "the cold costs health (%.2f)" % worst)
	_dawn(s, 13)
	_check(not s.cold, "spring ends the cold")
	_check(s.need("wood") > 0.9, "the wood target covers a winter of firewood")

	# Nothing is planted in winter.
	s = _new_game()
	for kind: String in ["food", "water", "wood", "scrap"]:
		s.stockpile[kind] = 5000
	var garden := _built(s, "garden", _home(s) + Vector2i(-3, 3))
	s.tick = Defs.DAY_TICKS * 10 - 600  # evening of the last day of autumn
	for p: SimPerson in s.people.values():
		p.energy = Defs.TIRED
	_run(s, Defs.DAY_TICKS + 600)
	_check(s.season() == 3 and garden.is_fallow(), "a plot is left alone through the winter")
	s.tick = Defs.DAY_TICKS * 12
	_run(s, 900)
	_check(s.season() == 0 and garden.ripe_tick > 0, "and planted when spring comes")


func _test_morale() -> void:
	print("-- morale")
	var s := _manual(_new_game())
	_check(is_equal_approx(s.morale, Defs.MORALE_START), "morale starts at %.1f" % Defs.MORALE_START)
	var good := Society.morale_target(s)
	s.stockpile["food"] = 0
	var hungry := Society.morale_target(s)
	s.cold = true
	_check(good > 0.8 and hungry < good - 0.25 and Society.morale_target(s) < hungry, "food, beds and warmth set where morale is heading (%.2f, %.2f)" % [good, hungry])
	s.cold = false
	s.stockpile["food"] = 5000
	s.stockpile["water"] = 5000
	s.stockpile["wood"] = 5000
	_dawn(s, 2)
	var day2 := s.morale
	_dawn(s, 8)
	_check(day2 > Defs.MORALE_START and s.morale > day2 and s.morale <= good, "morale moves towards it day by day (%.2f, %.2f)" % [day2, s.morale])
	_check(Society.work_factor(s) > 1.0, "a content community works faster")
	var before := s.morale
	s._kill(_by_age(s, true)[0], "zumbis")
	_check(s.morale < before and Society.morale_target(s) < good, "a death hurts morale, and weighs on it for days")
	before = s.morale
	Exploration.make_offer(s, 2, -1, 100)
	s.refuse_offer(s.offers[0]["id"])
	_check(s.morale < before, "so does turning people away")

	# At rock bottom, people who have nobody here walk away.
	s = _manual(_new_game())
	var home := _home(s)
	s.stockpile["wood"] = 5000
	_built(s, "house", home + Vector2i(-4, 3))
	var loner := s.spawn_person(home + Vector2i(3, 3))
	var other := s.spawn_person(home + Vector2i(4, 3))
	other.sex = loner.sex  # so the two do not pair up
	_manual(s)
	s.stockpile["food"] = 0
	s.stockpile["water"] = 0
	s.morale = 0.0
	s.events.clear()
	_dawn(s, 2)
	_check(s.people.size() == 5 and s.memorial.is_empty(), "with morale at the bottom someone leaves")
	_check(s.events.any(func(e: String) -> bool: return e.contains("foi embora")), "which is announced")
	_dawn(s, 3)
	_dawn(s, 4)
	_check(s.people.size() == 4 and not s.people.has(loner.id) and not s.people.has(other.id), "the family stays to the end")
	_check(Society.work_factor(s) < 0.9, "and a miserable community works slowly")


func _test_generations() -> void:
	print("-- couples, births, growing up")
	var s := _manual(_new_game())
	var home := _home(s)
	for kind: String in ["food", "water", "wood", "scrap"]:
		s.stockpile[kind] = 100000
	_built(s, "house", home + Vector2i(-4, 3))
	_built(s, "house", home + Vector2i(-4, 6))
	var man := s.add_person(home + Vector2i(3, 3), "Paulo", "Lima", "m", 25.0)
	var woman := s.add_person(home + Vector2i(4, 3), "Vera", "Gomes", "f", 24.0)
	_manual(s)
	var day := 2
	while day < 40 and woman.spouse != man.id:
		_dawn(s, day)
		day += 1
	_check(woman.spouse == man.id and man.spouse == woman.id, "two single adults become a couple (day %d)" % day)
	_check(s.events.has("Vera e Paulo agora são um casal"), "which is announced")
	var kids := _by_age(s, true)
	_check(Society._related(kids[0], kids[1]) and Society._related(kids[0], _by_age(s, false)[0]) and not Society._related(man, woman),
		"relatives do not pair up")

	var people := s.people.size()
	while day < 120 and s.people.size() == people:
		_dawn(s, day)
		day += 1
	var baby: SimPerson = null
	for p: SimPerson in s.people.values():
		if p.birth_day > 0:
			baby = p
	_check(baby != null and s.people.has(baby.mother) and s.people.has(baby.father), "a couple has a child (day %d)" % day)
	var mother: SimPerson = s.people[baby.mother]
	_check(baby.surname == (s.people[baby.father] as SimPerson).surname and mother.last_birth == baby.birth_day and mother.pregnant_until == 0,
		"with the father's surname, born on the day due")
	_check(not baby.jobs.values().has(true), "a baby does no work")
	_check(s.events.any(func(e: String) -> bool: return e.begins_with("Nasceu %s" % baby.full_name())), "the birth is announced")

	# No room, no children.
	var s2 := _manual(_new_game())
	for kind: String in ["food", "water", "wood"]:
		s2.stockpile[kind] = 100000
	for d in range(2, 80):
		_dawn(s2, d)
	_check(s2.people.size() == 4, "with every bed taken no children are born")

	# Growing up: chores at 6, adult work at 16, and learning from the parents on the way.
	mother.skills["farming"] = 4.0
	baby.birth_day = s.day() + 1 - roundi(Defs.WORK_AGE * Defs.DAYS_PER_YEAR)
	_dawn(s, s.day() + 1)
	_check(baby.jobs["forage"] and baby.jobs["study"] and not baby.jobs["hunt"], "at %d a child starts helping" % Defs.WORK_AGE)
	var today := s.day()
	var knew: float = baby.skills["farming"]
	for d in range(today + 1, today + 11):
		_dawn(s, d)
	_check(is_equal_approx(baby.skills["farming"] - knew, 10 * Defs.CHILD_LEARN_PER_DAY), "and picks up what the parents know (%.2f)" % baby.skills["farming"])
	baby.birth_day = s.day() + 1 - roundi(Defs.ADULT_AGE * Defs.DAYS_PER_YEAR)
	s.events.clear()
	_dawn(s, s.day() + 1)
	_check(baby.jobs["hunt"] and baby.jobs["guard"] and not baby.is_child(s.day()), "at %d the child takes on adult work" % Defs.ADULT_AGE)
	_check(s.events.any(func(e: String) -> bool: return e.contains("agora é adult")), "which is announced")

	# Old age.
	var elder := s.add_person(home + Vector2i(5, 5), "Teresa", "Lima", "f", 90.0)
	today = s.day()
	for d in range(today + 1, today + 80):
		_dawn(s, d)
	_check(not s.people.has(elder.id) and s.memorial.any(func(m: Dictionary) -> bool: return m["cause"] == "velhice"), "the very old die of old age")


func _test_hordes() -> void:
	print("-- hordes and events")
	var s := _manual(_new_game())
	s.zombies_enabled = true
	s.stockpile["food"] = 100000
	s.stockpile["water"] = 100000
	s.next_horde_day = 3
	_dawn(s, 2)
	_check(s.events.any(func(e: String) -> bool: return e.begins_with("Uma horda foi avistada")), "a horde is announced a day ahead")
	s.clear_zombies()
	s.tick = Defs.DAY_TICKS * 2 + GameState.DUSK_TICK - 1
	s.step()
	var marching := 0
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	for z: SimZombie in s.zombies.values():
		if z.goal != SimZombie.NO_GOAL:
			marching += 1
			from = z.pos
			to = z.goal
	_check(marching == Defs.HORDE_BASE + 1, "the horde comes in at dusk (%d zombies)" % marching)
	_check(from.distance_to(to) > s.width * 0.9, "bound for the other side of the map")
	_check(s.next_horde_day == 3 + Defs.HORDE_INTERVAL, "the next one comes in a year")
	# Family asleep indoors, so nothing draws the horde off its way.
	var walker: SimZombie = null
	for z: SimZombie in s.zombies.values():
		if z.migrating:
			walker = z
	var horde := s.zombies.size()
	s._zombie_index.move(walker.id, walker.pos, walker.goal + Vector2(0.5, 0.5))
	walker.pos = walker.goal + Vector2(0.5, 0.5)
	_run(s, 3)
	_check(not s.zombies.has(walker.id) and s.zombies.size() == horde - 1, "a horde zombie that reaches the far side leaves the map")
	var old := s.spawn_zombie(_home(s) + Vector2i(60, 60))
	var attacker := s.spawn_zombie(_home(s) + Vector2i(62, 60))
	_dawn(s, s.day() + Defs.ZOMBIE_LIFE_DAYS)
	_check(s.zombies.has(old.id), "zombies last %d days" % Defs.ZOMBIE_LIFE_DAYS)
	attacker.siege = (s.buildings.values()[0] as SimBuilding).id  # busy tearing the house down
	_dawn(s, s.day() + 1)
	_check(not s.zombies.has(old.id) and s.zombies.has(attacker.id), "then rot away, unless they are attacking")
	s.clear_zombies()
	for cell in s._spread(_home(s) + Vector2i(0, 80), Defs.ZOMBIE_CAP - 3):
		s.spawn_zombie(cell)
	s.next_horde_day = s.day()
	s.tick = Defs.DAY_TICKS * (s.day() - 1) + GameState.DUSK_TICK - 1
	s.step()
	_check(s.zombies.size() <= Defs.ZOMBIE_CAP, "the map never holds more than %d zombies (%d)" % [Defs.ZOMBIE_CAP, s.zombies.size()])
	s.tick = Defs.DAY_TICKS * (Defs.DAYS_PER_YEAR * 5 + 2) + GameState.DUSK_TICK - 1
	s.next_horde_day = s.day()
	s.clear_zombies()
	s.step()
	_check(s.zombies.size() > marching * 2, "hordes grow with the years (%d in year 6)" % s.zombies.size())

	s = _manual(_new_game())
	s.events_enabled = true
	s.stockpile["medicine"] = 0
	var animals := s.animals.size()
	for d in range(2, 120):
		_dawn(s, d)
	_check(s.events.any(func(e: String) -> bool: return e.contains("adoeceu")), "now and then someone falls ill")
	_check(s.events.has("Uma manada passa perto da base") and s.animals.size() > animals, "or a herd comes by")


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
	# An expedition on its way, a group waiting for an answer and survivors arriving.
	s.arrivals_enabled = true
	s.events_enabled = true
	s.next_horde_day = 2
	_by_age(s, false)[1].pregnant_until = 2
	s.library["farming"] = 5
	_built(s, "workshop", home + Vector2i(4, 6))
	_known_place(s).survivors = 2
	s.order_expedition(_ids([_by_age(s, false)[0]]), _known_place(s).id)
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


## A new game with no zombies on the map, neither zombies nor survivors arriving, and
## everything allowed to be built whatever the family knows.
func _new_game() -> GameState:
	var s := GameState.new_game(SEED)
	s.locks_enabled = false
	s.events_enabled = false
	s.zombies_enabled = false
	s.arrivals_enabled = false
	s.clear_zombies()
	return s


## Switches the knowledge locks back on, for tests about what the community may build.
func _locked(s: GameState) -> GameState:
	s.locks_enabled = true
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


## Jumps to the dawn of the given day and runs the tick on which the daily rules apply.
func _dawn(s: GameState, day: int) -> void:
	s.tick = Defs.DAY_TICKS * (day - 1) - 1
	s.step()


func _run(s: GameState, ticks: int) -> void:
	for i in ticks:
		s.step()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", label])
