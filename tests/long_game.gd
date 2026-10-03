extends SceneTree
## Headless long game, the stage 6 criterion: a whole match, from the family of 4 to a
## community of 150, played by a script standing in for the player.
##   godot --headless --path . -s res://tests/long_game.gd
## Takes several minutes. Prints the state of the community once a year and, at the end,
## the cost of a tick at full size. LONG_GAME_SEED and LONG_GAME_YEARS change the run.

const GOAL := 150
const STEP := 100  # ticks between decisions of the scripted player
## Ticks simulated at full size to measure the cost of a tick.
const MEASURE_TICKS := 2 * Defs.DAY_TICKS

var _home := Vector2i.ZERO
var _found := 0
var _arrived := 0
var _born := 0


func _init() -> void:
	var world_seed := int(OS.get_environment("LONG_GAME_SEED")) if OS.has_environment("LONG_GAME_SEED") else 12345
	var max_years := int(OS.get_environment("LONG_GAME_YEARS")) if OS.has_environment("LONG_GAME_YEARS") else 60
	var s := GameState.new_game(world_seed)
	@warning_ignore("integer_division")
	_home = Vector2i(s.width / 2, s.height / 2)
	var peak := 4
	var spent := 0
	var ticks := 0
	while s.people.size() < GOAL and not s.is_over() and s.year() <= max_years:
		var t := Time.get_ticks_usec()
		for i in STEP:
			s.step()
		spent += Time.get_ticks_usec() - t
		ticks += STEP
		_play(s)
		peak = maxi(peak, s.people.size())
		if s.tick % (Defs.DAY_TICKS * Defs.DAYS_PER_YEAR) < STEP:
			_report(s, float(spent) / ticks / 1000.0)
			spent = 0
			ticks = 0
	_report(s, float(spent) / maxi(1, ticks) / 1000.0)
	if s.people.size() < GOAL:
		print("FAILED: reached %d people (peak %d) by day %d" % [s.people.size(), peak, s.day()])
		quit(1)
		return

	print("reached %d people on day %d (year %d): %d found, %d arrived, %d born, %d died" % [
		s.people.size(), s.day(), s.year(), _found, _arrived, _born, s.memorial.size()])
	var samples := PackedFloat32Array()
	for i in MEASURE_TICKS:
		var t := Time.get_ticks_usec()
		s.step()
		samples.append((Time.get_ticks_usec() - t) / 1000.0)
		if i % STEP == 0:
			_play(s)
	samples.sort()
	var total := 0.0
	for v in samples:
		total += v
	@warning_ignore("integer_division")
	print("tick ms at %d people, %d zombies:  avg %.3f  p99 %.3f  max %.3f" % [
		s.people.size(), s.zombies.size(), total / MEASURE_TICKS, samples[MEASURE_TICKS * 99 / 100], samples[MEASURE_TICKS - 1]])
	var share := total / MEASURE_TICKS * 50.0 / 10.0
	print("at 5x (50 ticks/s) the simulation uses %.1f%% of each second" % share)
	print("OK" if share < 50.0 else "FAILED: too slow")
	quit(0 if share < 50.0 else 1)


func _report(s: GameState, tick_ms: float) -> void:
	var children := 0
	for p: SimPerson in s.people.values():
		if p.is_child(s.day()):
			children += 1
	var counts := _building_counts(s)
	print("year %2d day %3d: %3d people (%d children), beds %d, morale %.2f, zombies %3d, dead %d, tick %.2f ms" % [
		s.year(), s.day(), s.people.size(), children, s.total_beds(), s.morale, s.zombies.size(), s.memorial.size(), tick_ms])
	print("      stock %s" % [s.stockpile])
	var causes := {}
	for entry: Dictionary in s.memorial:
		causes[entry["cause"]] = int(causes.get(entry["cause"], 0)) + 1
	print("      buildings %s  knowledge %s  deaths %s" % [counts, Knowledge.levels(s), causes])


# --- The scripted player ---------------------------------------------------

func _play(s: GameState) -> void:
	var before := s.people.size()
	for offer: Dictionary in s.offers.duplicate():
		var group: int = (offer["people"] as Array).size()
		if s.accept_offer(offer["id"]):
			if offer["poi"] >= 0:
				_found += group
			else:
				_arrived += group
	for e in s.events:
		if e.begins_with("Nasceu"):
			_born += 1
	s.events.clear()
	s.revealed.clear()
	if s.people.size() != before or s.tick % 500 < STEP:
		_build(s)
	_explore(s)


func _building_counts(s: GameState) -> Dictionary:
	var counts := {}
	for b: SimBuilding in s.buildings.values():
		counts[b.def_id] = int(counts.get(b.def_id, 0)) + 1
	return counts


## One thing at a time, the most pressing first: water, room for newcomers, food,
## the workshop, then defences.
func _build(s: GameState) -> void:
	var counts := _building_counts(s)
	var people := s.people.size()
	var wanted := ""
	@warning_ignore("integer_division")
	if int(counts.get("well", 0)) < 1 + people / 25:
		wanted = "well"
	elif int(counts.get("house", 0)) * 4 < people + 4 + people / 5:
		wanted = "house"
	elif int(counts.get("garden", 0)) * 3 < people:
		wanted = "garden"
	elif people >= 8 and int(counts.get("workshop", 0)) < 1 + people / 60:
		wanted = "workshop"
	elif people >= 8 and int(counts.get("storage", 0)) < people / 12:
		wanted = "storage"
	elif s.can_build("tower") and int(counts.get("tower", 0)) < people / 6:
		wanted = "tower"
	elif s.can_build("trap") and int(counts.get("trap", 0)) < people / 2:
		wanted = "trap"
	if wanted == "" or not s.can_build(wanted) or not s.can_afford(Defs.building(wanted).cost):
		return
	# Homes and production fill rings outwards from the first house; towers and traps
	# go further out, where the zombies come from.
	var first := 3 if wanted not in ["tower", "trap"] else 9 + 3 * (int(counts.get("house", 0)) / 6)
	for r in range(first, 60, 3):
		for y in range(-r, r + 1, 3):
			for x in range(-r, r + 1, 3):
				if maxi(absi(x), absi(y)) == r and s.place_building(wanted, _home + Vector2i(x, y)) >= 0:
					return


## Each morning sends part of the rested adults to the nearest known place worth a trip.
## With none known, one adult scouts towards the nearest undiscovered place, which stands
## in for a player combing the fog.
func _explore(s: GameState) -> void:
	if s.hour() > 9.0 or s.threat_count() > 0:
		return
	var team: Array[int] = []
	for p: SimPerson in s.people.values():
		if p.expedition >= 0 or p.ordered:
			return  # someone is still out
		if not p.is_child(s.day()) and p.energy > 0.8 and not p.wounded and p.pregnant_until == 0:
			team.append(p.id)
	@warning_ignore("integer_division")
	team.resize(mini(team.size(), clampi(team.size() / 2, 2, 6)))
	var target: SimPoi = null
	var unknown: SimPoi = null
	for poi: SimPoi in s.pois.values():
		var dist := (poi.cell - _home).length()
		if not poi.discovered:
			if unknown == null or dist < (unknown.cell - _home).length():
				unknown = poi
		elif (not poi.visited or poi.loot_left() > 0) and (target == null or dist < (target.cell - _home).length()):
			target = poi
	if team.is_empty():
		return
	if target != null:
		s.order_expedition(team, target.id)
	elif unknown != null:
		s.order_move([team[0]] as Array[int], s._ring(unknown.cell, SimPoi.SIZE)[0])
