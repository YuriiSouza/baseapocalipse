extends SceneTree
## Headless smoke test of the simulation:
##   godot --headless --path . -s res://tests/sim_smoke.gd

var _failures := 0


func _init() -> void:
	var s := GameState.new_game(12345)
	@warning_ignore("integer_division")
	var home := Vector2i(s.width / 2, s.height / 2)
	var ids: Array[int] = []
	ids.assign(s.units.keys())
	_check(ids.size() == 3, "starts with 3 villagers")
	_check(s.pop_cap() == 5, "town center gives 5 pop")

	# Gather: one villager on wood, one on food.
	var wood_before: int = s.stockpile["wood"]
	var food_before: int = s.stockpile["food"]
	s.order_gather([ids[0]] as Array[int], home + Vector2i(-4, 0))
	s.order_gather([ids[1]] as Array[int], home + Vector2i(4, -1))
	_run(s, 600)
	_check(s.stockpile["wood"] > wood_before, "wood delivered (%d -> %d)" % [wood_before, s.stockpile["wood"]])
	_check(s.stockpile["food"] > food_before, "food delivered (%d -> %d)" % [food_before, s.stockpile["food"]])

	# Build a house with the third villager.
	var site := home + Vector2i(3, 3)
	_check(s.can_place("house", site), "house site is free")
	var house_id := s.place_building("house", site)
	_check(house_id >= 0, "house placed")
	s.order_build([ids[2]] as Array[int], house_id)
	_run(s, 400)
	_check((s.buildings[house_id] as SimBuilding).is_complete(), "house completed")
	_check(s.pop_cap() == 10, "house raises pop cap to 10")
	_check(not s.can_place("house", site), "cannot build on top of a building")

	# Train a villager.
	var tc_id: int = s.buildings.keys()[0]
	_check(s.queue_villager(tc_id), "villager queued")
	_run(s, Defs.VILLAGER_TRAIN_TICKS + 5)
	_check(s.units.size() == 4, "villager trained (units = %d)" % s.units.size())

	# Move order.
	var mover: SimUnit = s.units[ids[2]]
	s.order_move([ids[2]] as Array[int], home + Vector2i(0, 5))
	_run(s, 200)
	_check(mover.cell() == home + Vector2i(0, 5), "move order reaches destination (at %s)" % mover.cell())

	# Save / load round trip through JSON, then both copies must evolve identically.
	var json := JSON.stringify(s.to_dict())
	var loaded := GameState.from_dict(JSON.parse_string(json))
	_check(JSON.stringify(loaded.to_dict()) == json, "save/load round trip is lossless")
	_run(s, 300)
	_run(loaded, 300)
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(s.to_dict()), "loaded game stays in sync after 300 ticks")

	print("FAILED: %d" % _failures if _failures > 0 else "ALL OK")
	quit(1 if _failures > 0 else 0)


func _run(s: GameState, ticks: int) -> void:
	for i in ticks:
		s.step()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", label])
