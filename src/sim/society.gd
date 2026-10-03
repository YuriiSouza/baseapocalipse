class_name Society
extends RefCounted
## The community over the years: morale, couples, births, children growing up, old age
## and people leaving. Runs once a day, at dawn. All the state lives in GameState.


static func daily(s: GameState) -> void:
	_update_morale(s)
	_grow_up(s)
	_form_couples(s)
	_births(s)
	_old_age(s)
	_desertion(s)


## A one-off change of mood: a death, a birth, people turned away.
static func shock(s: GameState, amount: float) -> void:
	s.morale = clampf(s.morale + amount, 0.0, 1.0)


## How fast people work: a miserable community drags its feet.
static func work_factor(s: GameState) -> float:
	return lerpf(Defs.MORALE_WORK_MIN, Defs.MORALE_WORK_MAX, s.morale)


## Where morale is heading, from how the community is living right now.
static func morale_target(s: GameState) -> float:
	var target := 0.5
	var per_day := s.people.size() * Defs.RATIONS_PER_DAY
	if s.total_beds() >= s.people.size():
		target += 0.15
	else:
		target -= 0.1
	for kind: String in ["food", "water"]:
		if s.stockpile[kind] <= 0:
			target -= 0.2
		elif s.stockpile[kind] >= 2 * per_day:
			target += 0.1
	if s.cold:
		target -= 0.15
	if s.day() - s.last_death_day > Defs.MOURNING_DAYS:
		target += 0.1
	return clampf(target, 0.0, 1.0)


static func _update_morale(s: GameState) -> void:
	s.morale += (morale_target(s) - s.morale) * Defs.MORALE_DRIFT


## Children start helping at WORK_AGE and take on adult work at ADULT_AGE. Until then they
## pick up a little, every day, of what their parents know.
static func _grow_up(s: GameState) -> void:
	var today := s.day()
	for p: SimPerson in s.people.values():
		var days := today - p.birth_day
		if days == roundi(Defs.WORK_AGE * Defs.DAYS_PER_YEAR):
			for work in Defs.WORK_TYPES:
				p.jobs[work] = work not in Defs.ADULT_ONLY_WORK
		elif days == roundi(Defs.ADULT_AGE * Defs.DAYS_PER_YEAR):
			for work in Defs.ADULT_ONLY_WORK:
				p.jobs[work] = true
			s.events.append("%s agora é adulto" % p.full_name() if p.sex == "m" else "%s agora é adulta" % p.full_name())
		if days >= Defs.ADULT_AGE * Defs.DAYS_PER_YEAR or days < Defs.LEARN_AGE * Defs.DAYS_PER_YEAR:
			continue
		var best := ""
		var gap := 0.0
		for parent_id: int in [p.mother, p.father]:
			var parent: SimPerson = s.people.get(parent_id)
			if parent == null:
				continue
			for skill in Defs.SKILLS:
				var room := float(parent.skills[skill]) - float(p.skills[skill])
				if room > gap:
					gap = room
					best = skill
		if best != "":
			p.skills[best] = float(p.skills[best]) + minf(gap, Defs.CHILD_LEARN_PER_DAY)


## Single adults pair up, a few at a time.
static func _form_couples(s: GameState) -> void:
	var today := s.day()
	var men: Array[SimPerson] = []
	var women: Array[SimPerson] = []
	for p: SimPerson in s.people.values():
		if p.age(today) < Defs.COUPLE_AGE or s.people.has(p.spouse):
			continue
		if p.sex == "m":
			men.append(p)
		else:
			women.append(p)
	for woman in women:
		for man in men:
			if s.people.has(man.spouse) or _related(woman, man):
				continue
			if absf(woman.age(today) - man.age(today)) > Defs.COUPLE_AGE_GAP:
				continue
			if not _roll(s, woman.id * 31 + man.id, Defs.COUPLE_CHANCE):
				continue
			woman.spouse = man.id
			man.spouse = woman.id
			s.events.append("%s e %s agora são um casal" % [woman.first_name, man.first_name])
			break


static func _related(a: SimPerson, b: SimPerson) -> bool:
	if a.mother == b.id or a.father == b.id or b.mother == a.id or b.father == a.id:
		return true
	return (a.mother >= 0 and a.mother == b.mother) or (a.father >= 0 and a.father == b.father)


## Couples have children while there is room and the mood allows it.
static func _births(s: GameState) -> void:
	var today := s.day()
	for mother: SimPerson in s.people.values():
		if mother.sex != "f":
			continue
		if mother.pregnant_until > 0:
			if today >= mother.pregnant_until:
				_give_birth(s, mother)
			continue
		var father: SimPerson = s.people.get(mother.spouse)
		var age := mother.age(today)
		if father == null or age < Defs.COUPLE_AGE or age > Defs.MAX_MOTHER_AGE:
			continue
		if today - mother.last_birth < Defs.BIRTH_GAP_DAYS or s.morale < Defs.BIRTH_MIN_MORALE:
			continue
		if s.people.size() >= mini(s.total_beds(), Defs.POPULATION_CAP):
			continue
		if _roll(s, mother.id * 17, Defs.BIRTH_CHANCE):
			mother.pregnant_until = today + Defs.PREGNANCY_DAYS
			mother.baby_father = father.id


static func _give_birth(s: GameState, mother: SimPerson) -> void:
	var today := s.day()
	var father: SimPerson = s.people.get(mother.baby_father)
	var r := hash(s.tick * 613 + mother.id)
	var sex := "f" if r % 2 == 0 else "m"
	var names := Defs.FEMALE_NAMES if sex == "f" else Defs.MALE_NAMES
	@warning_ignore("integer_division")
	var first_name := names[(r / 2) % names.size()]
	var cells := s._spread(mother.cell(), 1)
	var baby := s.add_person(cells[0] if not cells.is_empty() else mother.cell(), first_name,
		father.surname if father != null else mother.surname, sex, 0.0)
	baby.mother = mother.id
	baby.father = mother.baby_father
	mother.pregnant_until = 0
	mother.last_birth = today
	shock(s, Defs.MORALE_BIRTH)
	s.events.append("Nasceu %s, %s de %s" % [baby.full_name(), "filha" if sex == "f" else "filho", mother.first_name])


static func _old_age(s: GameState) -> void:
	var today := s.day()
	for p: SimPerson in s.people.values():
		var over := p.age(today) - Defs.OLD_AGE
		if over > 0.0 and _roll(s, p.id * 13, over * Defs.OLD_AGE_DEATH_CHANCE):
			s._kill(p, "velhice")


## With morale at rock bottom, one adult without a family here walks away each day.
static func _desertion(s: GameState) -> void:
	if s.morale >= Defs.DESERTION_MORALE or s.people.size() <= Defs.DESERTION_MIN_PEOPLE:
		return
	var today := s.day()
	for p: SimPerson in s.people.values():
		if p.is_child(today) or s.people.has(p.spouse) or p.expedition >= 0:
			continue
		var known := Knowledge.levels(s)
		s._remove_person(p)
		s.events.append("%s foi embora: não aguentava mais" % p.full_name())
		Knowledge.announce_loss(s, known, p.first_name)
		return


## True with the given chance in percent. Depends only on the tick and the salt.
static func _roll(s: GameState, salt: int, percent: float) -> bool:
	return hash(s.tick * 8191 + salt) % 10000 < percent * 100.0
