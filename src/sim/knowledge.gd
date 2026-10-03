class_name Knowledge
extends RefCounted
## Skills that grow with practice, what the community knows as a whole and what that
## unlocks (buildings, recipes, improvements), plus study, books and the workshop.
## All the state lives in GameState; these functions only act on it.

const State := SimPerson.State


# --- Individual skill ------------------------------------------------------

## Practice raises a skill, more slowly the higher it already is.
static func practice(p: SimPerson, skill: String, amount: float) -> void:
	var level: float = p.skills.get(skill, 0.0)
	p.skills[skill] = minf(Defs.MAX_SKILL, level + amount / (1.0 + level))


## How much faster than an unskilled person this one works.
static func speed(p: SimPerson, skill: String) -> float:
	return 1.0 + Defs.SKILL_SPEED * float(p.skills.get(skill, 0.0))


# --- What the community knows ----------------------------------------------

## The community knows a skill as well as its best member does.
static func level(s: GameState, skill: String) -> int:
	_refresh(s)
	return int(s._top[skill])


## Skill -> level, for every skill.
static func levels(s: GameState) -> Dictionary:
	_refresh(s)
	var out := {}
	for skill in Defs.SKILLS:
		out[skill] = int(s._top[skill])
	return out


## True if the community knows enough for something with these requirements.
static func knows(s: GameState, requires: Dictionary) -> bool:
	for skill: String in requires:
		if level(s, skill) < int(requires[skill]):
			return false
	return true


## Whether something may be built or made: knows(), unless the locks are switched off.
static func unlocked(s: GameState, requires: Dictionary) -> bool:
	return not s.locks_enabled or knows(s, requires)


## "construção 2, mecânica 2"
static func requirement_text(requires: Dictionary) -> String:
	var parts := PackedStringArray()
	for skill: String in requires:
		parts.append("%s %d" % [Defs.SKILL_NAMES[skill], int(requires[skill])])
	return ", ".join(parts)


## Combined multiplier of the improvements the community has for a stat.
static func bonus(s: GameState, stat: String) -> float:
	var factor := 1.0
	for def: ImprovementDef in Defs.IMPROVEMENTS.values():
		if def.stat == stat and knows(s, def.requires):
			factor *= def.value
	return factor


## Call after someone died: announces what the community no longer knows.
static func announce_loss(s: GameState, before: Dictionary, who: String) -> void:
	s._knowledge_dirty = true
	var after := levels(s)
	var lost := PackedStringArray()
	for skill in Defs.SKILLS:
		if after[skill] < before[skill]:
			lost.append("%s %d → %d" % [Defs.SKILL_NAMES[skill], before[skill], after[skill]])
	if not lost.is_empty():
		s.events.append("Com %s se foi conhecimento: %s" % [who, ", ".join(lost)])


static func _refresh(s: GameState) -> void:
	if not s._knowledge_dirty:
		return
	s._knowledge_dirty = false
	for skill in Defs.SKILLS:
		s._top[skill] = 0.0
	for p: SimPerson in s.people.values():
		for skill: String in p.skills:
			if p.skills[skill] > s._top[skill]:
				s._top[skill] = p.skills[skill]


# --- Study and books -------------------------------------------------------

## What the person would do with time to study: [skill, writing], or [] for nothing.
## Whoever knows a skill best writes it down first; the others learn what someone else
## or a book can teach them.
static func study_plan(s: GameState, p: SimPerson) -> Array:
	_refresh(s)
	for skill in Defs.SKILLS:
		var own: float = p.skills[skill]
		if own >= s._top[skill] and int(own) >= maxi(Defs.BOOK_MIN_LEVEL, int(s.library.get(skill, 0)) + 1):
			return [skill, true]
	var best := ""
	var gap := 1.0  # less than a level to gain is not worth sitting down for
	for skill in Defs.SKILLS:
		var room := _study_cap(s, skill) - float(p.skills[skill])
		if room >= gap:
			gap = room
			best = skill
	return [best, false] if best != "" else []


static func tick_study(s: GameState, p: SimPerson) -> void:
	var skill := p.study_skill
	p.work_ticks += 1
	if p.writing:
		if p.work_ticks >= Defs.WRITE_TICKS:
			var written := int(p.skills[skill])
			if written > int(s.library.get(skill, 0)):
				s.library[skill] = written
				s.events.append("%s escreveu um livro de %s (nível %d)" % [p.first_name, Defs.SKILL_NAMES[skill], written])
			p.state = State.IDLE
		return
	var cap := _study_cap(s, skill)
	var own: float = p.skills[skill]
	if own >= cap or p.work_ticks >= Defs.STUDY_TICKS:
		p.state = State.IDLE
		return
	p.skills[skill] = minf(cap, own + Defs.STUDY_PER_TICK / (1.0 + own))


## A found book joins the library if it is better than what is already there.
static func add_book(s: GameState, skill: String, book_level: int) -> void:
	if book_level > int(s.library.get(skill, 0)):
		s.library[skill] = book_level
	s.events.append("Livro encontrado: %s (nível %d)" % [Defs.SKILL_NAMES[skill], book_level])


## As far as study can take someone: what the best person or the best book knows.
static func _study_cap(s: GameState, skill: String) -> float:
	_refresh(s)
	return maxf(s._top[skill], float(s.library.get(skill, 0)))


# --- Workshop --------------------------------------------------------------

## The recipe most worth making now, or null: known, affordable without eating into
## scarce stock, and with its product below target.
static func pick_recipe(s: GameState) -> RecipeDef:
	var best: RecipeDef = null
	var best_want := 0.0
	for def: RecipeDef in Defs.RECIPES.values():
		var want := _recipe_want(s, def)
		if want > best_want:
			best_want = want
			best = def
	return best


## 0 to 1: how much the community wants this recipe made right now.
static func _recipe_want(s: GameState, def: RecipeDef) -> float:
	if not unlocked(s, def.requires) or not s.can_afford(def.inputs):
		return 0.0
	for kind: String in def.inputs:
		if s.need(kind) > 0.5:
			return 0.0
	var product: String = def.outputs.keys()[0]
	return clampf(1.0 - float(s.stockpile[product]) / def.target, 0.0, 1.0)


static func craft_score(s: GameState) -> float:
	var def := pick_recipe(s)
	return 0.6 * _recipe_want(s, def) if def != null else 0.0


## The inputs are only used up when the work is finished, so an interruption wastes nothing.
## Nothing comes out if by then the community no longer knows how.
static func tick_craft(s: GameState, p: SimPerson) -> void:
	var def: RecipeDef = Defs.RECIPES.get(p.recipe)
	if def == null:
		p.state = State.IDLE
		return
	p.work_ticks += 1
	practice(p, def.skill, Defs.PRACTICE_PER_TICK)
	if p.work_ticks >= def.work_ticks / speed(p, def.skill):
		if unlocked(s, def.requires) and s.can_afford(def.inputs):
			s._pay(def.inputs)
			for kind: String in def.outputs:
				s.stockpile[kind] += int(def.outputs[kind])
		p.state = State.IDLE
