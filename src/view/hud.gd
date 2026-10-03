class_name Hud
extends CanvasLayer
## Resource bar, speed controls, selection details, work toggles, survivors asking to
## join, the list of people, the log of events and the game-over screen.
## Built in code; emits signals only.

signal speed_selected(speed: float)
signal build_requested(def_id: String)
signal job_toggled(work: String, allowed: bool)
signal offer_answered(offer_id: int, accepted: bool)
signal people_picked(ids: Array[int])
signal focus_requested(person_id: int)
signal save_requested
signal load_requested
signal new_game_requested

const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 5.0]
const LOG_SIZE := 14
const LIST_REFRESH := 0.5  # seconds

var state: GameState
var controller: PlayerController
var speed := 1.0

var _resources: Label
var _status: Label
var _info: Label
var _jobs: HBoxContainer
var _job_buttons := {}  # work type -> Button
var _build_buttons := {}  # building id -> Button
var _offers: VBoxContainer
var _offers_shown: Array[int] = []
var _people_panel: PanelContainer
var _people_list: ItemList
var _people_filter := ""
var _people_ids: Array[int] = []
var _list_wait := 0.0
var _log_panel: PanelContainer
var _log_text: Label
var _log: Array[String] = []
var _toast: Label
var _toast_left := 0.0
var _over: Control
var _over_text: Label


func _ready() -> void:
	var top := PanelContainer.new()
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# Two rows: stock and buttons above, people, mood and date below.
	var rows := VBoxContainer.new()
	top.add_child(rows)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	rows.add_child(bar)
	_status = Label.new()
	rows.add_child(_status)
	_resources = Label.new()
	_resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_resources)
	for s in SPEEDS:
		var label := "Pausa" if s == 0.0 else "%dx" % int(s)
		bar.add_child(_button(label, func() -> void: speed_selected.emit(s)))
	bar.add_child(_button("Pessoas [P]", _toggle_people))
	bar.add_child(_button("Registro [L]", func() -> void: _log_panel.visible = not _log_panel.visible))
	bar.add_child(_button("Salvar [F5]", func() -> void: save_requested.emit()))
	bar.add_child(_button("Carregar [F9]", func() -> void: load_requested.emit()))

	var bottom := PanelContainer.new()
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	var box := VBoxContainer.new()
	bottom.add_child(box)
	_info = Label.new()
	box.add_child(_info)

	# Work the selected people are allowed to do on their own.
	_jobs = HBoxContainer.new()
	box.add_child(_jobs)
	var jobs_label := Label.new()
	jobs_label.text = "Trabalhos:"
	_jobs.add_child(jobs_label)
	for work in Defs.WORK_TYPES:
		var toggle := Button.new()
		toggle.text = Defs.WORK_NAMES[work]
		toggle.toggle_mode = true
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.toggled.connect(func(on: bool) -> void: job_toggled.emit(work, on))
		_jobs.add_child(toggle)
		_job_buttons[work] = toggle

	var actions := HFlowContainer.new()
	actions.custom_minimum_size.x = 620.0
	box.add_child(actions)
	for id: String in Defs.BUILDINGS:
		var def := Defs.building(id)
		if def.buildable:
			var button := _button(_build_label(def, false), func() -> void: build_requested.emit(id))
			actions.add_child(button)
			_build_buttons[id] = button

	var offers_panel := PanelContainer.new()
	offers_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(offers_panel)
	offers_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offers_panel.offset_top = 72.0
	_offers = VBoxContainer.new()
	offers_panel.add_child(_offers)
	offers_panel.visible = false

	# Everyone in the community, for when there are too many to pick on the map.
	_people_panel = PanelContainer.new()
	add_child(_people_panel)
	_people_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_people_panel.offset_top = 72.0
	_people_panel.visible = false
	var people_box := VBoxContainer.new()
	_people_panel.add_child(people_box)
	var filters := HBoxContainer.new()
	people_box.add_child(filters)
	for filter: Array in [["Todos", ""], ["Adultos", "adults"], ["Crianças", "children"], ["Sem tarefa", "idle"], ["Feridos", "hurt"]]:
		filters.add_child(_button(filter[0], func() -> void:
			_people_filter = filter[1]
			_refresh_people()))
	filters.add_child(_button("Selecionar a lista", func() -> void: people_picked.emit(_people_ids.duplicate())))
	_people_list = ItemList.new()
	_people_list.select_mode = ItemList.SELECT_MULTI
	_people_list.focus_mode = Control.FOCUS_NONE
	_people_list.custom_minimum_size = Vector2(640.0, 300.0)
	_people_list.multi_selected.connect(func(_index: int, _on: bool) -> void: _emit_picked())
	_people_list.item_activated.connect(func(index: int) -> void: focus_requested.emit(_people_ids[index]))
	people_box.add_child(_people_list)

	_log_panel = PanelContainer.new()
	_log_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_log_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_log_panel)
	_log_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_log_panel.visible = false
	_log_text = Label.new()
	_log_panel.add_child(_log_text)

	_toast = Label.new()
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 72.0
	_toast.modulate.a = 0.0

	_over = CenterContainer.new()
	add_child(_over)
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var over_panel := PanelContainer.new()
	_over.add_child(over_panel)
	var over_box := VBoxContainer.new()
	over_panel.add_child(over_box)
	_over_text = Label.new()
	_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_box.add_child(_over_text)
	over_box.add_child(_button("Novo jogo", func() -> void: new_game_requested.emit()))
	_over.visible = false


func show_message(text: String) -> void:
	_toast.text = text
	_toast_left = 3.5
	_log.append("Dia %d: %s" % [state.day(), text] if state != null else text)
	if _log.size() > LOG_SIZE:
		_log.remove_at(0)
	_log_text.text = "\n".join(_log)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P:
				_toggle_people()
			KEY_L:
				_log_panel.visible = not _log_panel.visible


func _toggle_people() -> void:
	_people_panel.visible = not _people_panel.visible
	_refresh_people()


## Rebuilds the list of people: one row each, sorted by name, with whoever is selected
## on the map selected here too.
func _refresh_people() -> void:
	if state == null or not _people_panel.visible:
		return
	var today := state.day()
	var rows: Array[SimPerson] = []
	for p: SimPerson in state.people.values():
		var child := p.is_child(today)
		match _people_filter:
			"adults":
				if child:
					continue
			"children":
				if not child:
					continue
			"idle":
				if p.state != SimPerson.State.IDLE:
					continue
			"hurt":
				if not p.wounded and p.health >= 0.6:
					continue
		rows.append(p)
	rows.sort_custom(func(a: SimPerson, b: SimPerson) -> bool: return a.full_name() < b.full_name())
	_people_list.clear()
	_people_ids.clear()
	for p in rows:
		var best := ""
		for skill: String in p.skills:
			if p.skills[skill] >= 1.0 and (best == "" or p.skills[skill] > p.skills[best]):
				best = skill
		_people_list.add_item("%s, %d  |  %s  |  saúde %d%%%s%s" % [
			p.full_name(), int(p.age(today)), _activity(p), roundi(p.health * 100.0),
			" FERIDO" if p.wounded else "",
			"  |  %s %d" % [Defs.SKILL_NAMES[best], int(p.skills[best])] if best != "" else ""])
		_people_ids.append(p.id)
		if controller.selected_people.has(p.id):
			_people_list.select(_people_ids.size() - 1, false)


func _emit_picked() -> void:
	var ids: Array[int] = []
	for index in _people_list.get_selected_items():
		ids.append(_people_ids[index])
	people_picked.emit(ids)


func _process(delta: float) -> void:
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = minf(1.0, _toast_left)
	if state == null or controller == null:
		return

	var parts := PackedStringArray()
	for kind in Defs.RESOURCE_KINDS:
		parts.append("%s %d" % [Defs.RESOURCE_NAMES[kind], state.stockpile[kind]])
	_resources.text = "  " + "   |   ".join(parts)
	parts.clear()
	parts.append("Pessoas %d (%d camas)" % [state.people.size(), state.total_beds()])
	parts.append("Moral %d%%" % roundi(state.morale * 100.0))
	if state.threat_count() > 0:
		parts.append("ZUMBIS ATACANDO: %d" % state.threat_count())
	var hour := state.hour()
	parts.append("%s do ano %d, dia %d, %02d:%02d" % [
		Defs.SEASON_NAMES[state.season()], state.year(), state.day(), int(hour), int(fmod(hour, 1.0) * 60.0)])
	parts.append("Pausado" if speed == 0.0 else "%dx" % int(speed))
	_status.text = "  " + "   |   ".join(parts)
	_info.text = _describe_selection()
	_list_wait -= delta
	if _list_wait <= 0.0:
		_list_wait = LIST_REFRESH
		_refresh_people()

	# Buildings the community does not know how to make are greyed out, saying what is missing.
	for id: String in _build_buttons:
		var button: Button = _build_buttons[id]
		var locked := not state.can_build(id)
		if button.disabled != locked:
			button.disabled = locked
			button.text = _build_label(Defs.building(id), locked)
	_refresh_offers()

	# The toggles mirror the first selected person; a click applies to the whole selection.
	var first: SimPerson = null
	if not controller.selected_people.is_empty():
		first = state.people.get(controller.selected_people[0])
	_jobs.visible = first != null
	if first != null:
		for work: String in _job_buttons:
			(_job_buttons[work] as Button).set_pressed_no_signal(first.jobs.get(work, false))

	if state.is_over() and not _over.visible:
		var lines := PackedStringArray(["A comunidade não sobreviveu.", "Dia %d" % state.day(), ""])
		for entry: Dictionary in state.memorial:
			lines.append("%s, %d anos: %s (dia %d)" % [entry["name"], entry["age"], entry["cause"], entry["day"]])
		_over_text.text = "\n".join(lines)
	_over.visible = state.is_over()


## Rebuilds the list of groups asking to join, only when it changed.
func _refresh_offers() -> void:
	var ids: Array[int] = []
	for offer: Dictionary in state.offers:
		ids.append(int(offer["id"]))
	if ids == _offers_shown:
		return
	_offers_shown = ids
	for child in _offers.get_children():
		child.queue_free()
	(_offers.get_parent() as Control).visible = not ids.is_empty()
	for offer: Dictionary in state.offers:
		var id := int(offer["id"])
		var poi: SimPoi = state.pois.get(offer["poi"])
		var lines := PackedStringArray([
			"Encontrados em %s:" % poi.display_name() if poi != null else "Pedem abrigo:"])
		for row: Dictionary in offer["people"]:
			var skills := PackedStringArray()
			for skill: String in row["skills"]:
				skills.append("%s %d" % [Defs.SKILL_NAMES[skill], int(row["skills"][skill])])
			lines.append("  %s %s, %d anos%s" % [row["first_name"], row["surname"], int(row["age"]),
				" (%s)" % ", ".join(skills) if not skills.is_empty() else ""])
		var text := Label.new()
		text.text = "\n".join(lines)
		_offers.add_child(text)
		var buttons := HBoxContainer.new()
		_offers.add_child(buttons)
		buttons.add_child(_button("Aceitar", func() -> void: offer_answered.emit(id, true)))
		buttons.add_child(_button("Recusar", func() -> void: offer_answered.emit(id, false)))


func _describe_selection() -> String:
	if controller.placing != "":
		return "Clique para posicionar (Shift mantém). Botão direito ou Esc cancela."
	if controller.selected_people.size() == 1:
		var p: SimPerson = state.people.get(controller.selected_people[0])
		if p != null:
			return _describe_person(p)
	if not controller.selected_people.is_empty():
		return "%d pessoas. Botão direito: mover, coletar, construir ou enviar a um local." % controller.selected_people.size()
	var building: SimBuilding = state.buildings.get(controller.selected_building)
	if building != null:
		return _describe_building(building)
	var poi: SimPoi = state.pois.get(controller.selected_poi)
	if poi != null:
		return _describe_poi(poi)
	return "Arraste para selecionar pessoas. WASD move a câmera, scroll dá zoom, B constrói casa.\n" \
			+ _describe_knowledge()


func _build_label(def: BuildingDef, locked: bool) -> String:
	var label := "%s (%s)" % [def.display_name, Defs.format_cost(def.cost)]
	if locked:
		label += " requer %s" % Knowledge.requirement_text(def.requires)
	return label


## What the community knows, the books it has and the improvements that follow.
func _describe_knowledge() -> String:
	var known := PackedStringArray()
	var books := PackedStringArray()
	for skill in Defs.SKILLS:
		if state.knowledge(skill) > 0:
			known.append("%s %d" % [Defs.SKILL_NAMES[skill], state.knowledge(skill)])
		if state.library.has(skill):
			books.append("%s %d" % [Defs.SKILL_NAMES[skill], int(state.library[skill])])
	var lines := PackedStringArray(["Conhecimento: %s" % (", ".join(known) if not known.is_empty() else "nenhum")])
	if not books.is_empty():
		lines.append("Livros: %s" % ", ".join(books))
	var gains := PackedStringArray()
	for def: ImprovementDef in Defs.IMPROVEMENTS.values():
		if Knowledge.knows(state, def.requires):
			gains.append(def.display_name)
	if not gains.is_empty():
		lines.append("Melhorias: %s" % ", ".join(gains))
	return "\n".join(lines)


func _describe_workshop(b: SimBuilding) -> String:
	var lines := PackedStringArray([b.get_def().display_name + ":"])
	for def: RecipeDef in Defs.RECIPES.values():
		var status := "requer %s" % Knowledge.requirement_text(def.requires)
		if Knowledge.unlocked(state, def.requires):
			var product: String = def.outputs.keys()[0]
			status = "estoque cheio" if state.stockpile[product] >= def.target else "disponível"
		lines.append("  %s (%s → %s): %s" % [
			def.display_name, Defs.format_cost(def.inputs), Defs.format_cost(def.outputs), status])
	return "\n".join(lines)


func _describe_poi(poi: SimPoi) -> String:
	var how := "Selecione pessoas e clique aqui com o botão direito para enviar uma expedição."
	if not poi.visited:
		return "%s: ninguém esteve aqui ainda.\n%s" % [poi.display_name(), how]
	if poi.loot_left() == 0:
		return "%s: não sobrou nada." % poi.display_name()
	return "%s: resta %s.\n%s" % [poi.display_name(), Defs.format_cost(poi.loot), how]


func _describe_building(b: SimBuilding) -> String:
	var def := b.get_def()
	if not b.is_complete():
		@warning_ignore("integer_division")
		return "%s (em construção: %d%%)" % [def.display_name, 100 * b.progress / def.build_ticks]
	var condition := "   Estrutura %d/%d" % [b.hp, def.max_hp] if b.is_damaged() else ""
	if def.is_workshop:
		return _describe_workshop(b) + condition
	if def.beds > 0:
		return "%s: %d de %d camas ocupadas, %d abrigados%s" % [
			def.display_name, b.occupants, def.beds, b.sheltered, condition]
	if def.guard_slots > 0:
		return "%s: %d de %d guardas%s" % [def.display_name, b.sheltered, def.guard_slots, condition]
	if def.crop_yield > 0:
		if b.stock > 0:
			return "%s: pronta para colher (%d de comida)" % [def.display_name, b.stock]
		if b.ripe_tick > 0:
			var days := float(b.ripe_tick - state.tick) / Defs.DAY_TICKS
			return "%s: crescendo, colheita em %.1f dias" % [def.display_name, days]
		return "%s: esperando plantio" % def.display_name
	return def.display_name + condition


func _describe_person(p: SimPerson) -> String:
	var skills := PackedStringArray()
	for skill: String in p.skills:
		if p.skills[skill] >= 1.0:
			skills.append("%s %d" % [Defs.SKILL_NAMES[skill], int(p.skills[skill])])
	return "%s, %d anos: %s%s\nSaciedade %d%%   Água %d%%   Energia %d%%   Saúde %d%%%s\nHabilidades: %s" % [
		p.full_name(), int(p.age(state.day())), _activity(p), " (ordem direta)" if p.ordered else "",
		roundi(p.satiety * 100.0), roundi(p.hydration * 100.0),
		roundi(p.energy * 100.0), roundi(p.health * 100.0),
		"   FERIDO, precisa de remédio" if p.wounded else "",
		", ".join(skills) if not skills.is_empty() else "nenhuma",
	]


func _activity(p: SimPerson) -> String:
	var what := String(Defs.RESOURCE_NAMES.get(p.gather_kind, "")).to_lower()
	match p.state:
		SimPerson.State.MOVING:
			return "andando"
		SimPerson.State.TO_RESOURCE, SimPerson.State.GATHERING:
			return "coletando %s" % what
		SimPerson.State.TO_DROPOFF:
			if p.expedition >= 0:
				return "voltando da expedição" + (" com %s" % what if p.carry_amount > 0 else "")
			return "levando %s para o estoque" % what
		SimPerson.State.TO_STUDY, SimPerson.State.STUDYING:
			var subject: String = Defs.SKILL_NAMES.get(p.study_skill, "")
			return "escrevendo um livro de %s" % subject if p.writing else "estudando %s" % subject
		SimPerson.State.TO_CRAFT, SimPerson.State.CRAFTING:
			var recipe: RecipeDef = Defs.RECIPES.get(p.recipe)
			return "na oficina: %s" % (recipe.display_name.to_lower() if recipe != null else "")
		SimPerson.State.TO_POI:
			return "em expedição para %s" % (state.pois[p.expedition] as SimPoi).display_name()
		SimPerson.State.LOOTING:
			return "saqueando %s" % what
		SimPerson.State.TO_BUILD, SimPerson.State.BUILDING:
			var site: SimBuilding = state.buildings.get(p.target_building)
			if site != null and site.is_complete():
				return "consertando" if site.is_damaged() else "plantando"
			return "construindo"
		SimPerson.State.TO_SHELTER:
			return "fugindo para o abrigo"
		SimPerson.State.SHELTERED:
			return "escondido"
		SimPerson.State.DEFENDING:
			if p.inside >= 0:
				return "atirando da torre"
			return "defendendo" if state.stockpile["ammo"] > 0 else "lutando corpo a corpo"
		SimPerson.State.TO_HUNT, SimPerson.State.HUNTING:
			return "caçando"
		SimPerson.State.TO_BED:
			return "indo dormir"
		SimPerson.State.SLEEPING:
			if p.expedition >= 0:
				return "acampado no caminho"
			return "dormindo" if p.inside >= 0 else "dormindo no chão"
	return "sem tarefa"


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep Space and hotkeys for the game
	b.pressed.connect(on_pressed)
	return b
