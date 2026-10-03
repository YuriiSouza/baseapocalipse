class_name Hud
extends CanvasLayer
## Resource bar, speed controls, selection details, work toggles and the game-over screen.
## Built in code; emits signals only.

signal speed_selected(speed: float)
signal build_requested(def_id: String)
signal job_toggled(work: String, allowed: bool)
signal save_requested
signal load_requested
signal new_game_requested

const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 5.0]

var state: GameState
var controller: PlayerController
var speed := 1.0

var _resources: Label
var _info: Label
var _jobs: HBoxContainer
var _job_buttons := {}  # work type -> Button
var _toast: Label
var _toast_left := 0.0
var _over: Control
var _over_text: Label


func _ready() -> void:
	var top := PanelContainer.new()
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)
	_resources = Label.new()
	_resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_resources)
	for s in SPEEDS:
		var label := "Pausa" if s == 0.0 else "%dx" % int(s)
		bar.add_child(_button(label, func() -> void: speed_selected.emit(s)))
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
			var label := "%s (%s)" % [def.display_name, Defs.format_cost(def.cost)]
			actions.add_child(_button(label, func() -> void: build_requested.emit(id)))

	_toast = Label.new()
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 48.0
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


func _process(delta: float) -> void:
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = minf(1.0, _toast_left)
	if state == null or controller == null:
		return

	var parts := PackedStringArray()
	for kind in Defs.RESOURCE_KINDS:
		parts.append("%s %d" % [Defs.RESOURCE_NAMES[kind], state.stockpile[kind]])
	parts.append("Pessoas %d" % state.people.size())
	if state.threat_count() > 0:
		parts.append("ZUMBIS ATACANDO: %d" % state.threat_count())
	var hour := state.hour()
	parts.append("Dia %d, %02d:%02d" % [state.day(), int(hour), int(fmod(hour, 1.0) * 60.0)])
	parts.append("Pausado" if speed == 0.0 else "%dx" % int(speed))
	_resources.text = "  " + "   |   ".join(parts)
	_info.text = _describe_selection()

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


func _describe_selection() -> String:
	if controller.placing != "":
		return "Clique para posicionar (Shift mantém). Botão direito ou Esc cancela."
	if controller.selected_people.size() == 1:
		var p: SimPerson = state.people.get(controller.selected_people[0])
		if p != null:
			return _describe_person(p)
	if not controller.selected_people.is_empty():
		return "%d pessoas. Botão direito: mover, coletar ou construir." % controller.selected_people.size()
	var building: SimBuilding = state.buildings.get(controller.selected_building)
	if building != null:
		return _describe_building(building)
	return "Arraste para selecionar pessoas. WASD move a câmera, scroll dá zoom, B constrói casa."


func _describe_building(b: SimBuilding) -> String:
	var def := b.get_def()
	if not b.is_complete():
		@warning_ignore("integer_division")
		return "%s (em construção: %d%%)" % [def.display_name, 100 * b.progress / def.build_ticks]
	var condition := "   Estrutura %d/%d" % [b.hp, def.max_hp] if b.is_damaged() else ""
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
		if p.skills[skill] > 0.0:
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
			return "levando %s para o estoque" % what
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
			return "dormindo" if p.inside >= 0 else "dormindo no chão"
	return "sem tarefa"


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep Space and hotkeys for the game
	b.pressed.connect(on_pressed)
	return b
