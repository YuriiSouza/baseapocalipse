class_name Hud
extends CanvasLayer
## Resource bar, speed controls and context actions. Built in code; emits signals only.

signal speed_selected(speed: float)
signal build_requested(def_id: String)
signal train_requested
signal save_requested
signal load_requested

const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 5.0]

var state: GameState
var controller: PlayerController
var speed := 1.0

var _resources: Label
var _info: Label
var _train_button: Button
var _toast: Label
var _toast_left := 0.0


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
	var actions := HBoxContainer.new()
	box.add_child(actions)
	for id: String in Defs.BUILDINGS:
		var def := Defs.building(id)
		if def.buildable:
			var label := "%s (%s)" % [def.display_name, Defs.format_cost(def.cost)]
			actions.add_child(_button(label, func() -> void: build_requested.emit(id)))
	_train_button = _button(
		"Aldeão (%s) [Q]" % Defs.format_cost(Defs.VILLAGER_COST),
		func() -> void: train_requested.emit())
	actions.add_child(_train_button)

	_toast = Label.new()
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 48.0
	_toast.modulate.a = 0.0


func show_message(text: String) -> void:
	_toast.text = text
	_toast_left = 2.5


func _process(delta: float) -> void:
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = minf(1.0, _toast_left)
	if state == null or controller == null:
		return

	var parts := PackedStringArray()
	for kind in Defs.RESOURCE_KINDS:
		parts.append("%s %d" % [Defs.RESOURCE_NAMES[kind], state.stockpile[kind]])
	parts.append("Pop %d/%d" % [state.units.size(), state.pop_cap()])
	parts.append("Ano %d" % state.year())
	parts.append("Pausado" if speed == 0.0 else "%dx" % int(speed))
	_resources.text = "  " + "   |   ".join(parts)

	var building: SimBuilding = state.buildings.get(controller.selected_building)
	_train_button.visible = building != null and building.is_complete() and building.get_def().trains_villagers
	_info.text = _describe_selection(building)


func _describe_selection(building: SimBuilding) -> String:
	if controller.placing != "":
		return "Clique para posicionar (Shift mantém). Botão direito ou Esc cancela."
	if not controller.selected_units.is_empty():
		return "%d aldeão(ões). Botão direito: mover, coletar ou construir." % controller.selected_units.size()
	if building != null:
		var def := building.get_def()
		if not building.is_complete():
			return "%s (em construção: %d%%)" % [def.display_name, 100 * building.progress / def.build_ticks]
		if building.train_queue > 0:
			return "%s (fila de treino: %d)" % [def.display_name, building.train_queue]
		return def.display_name
	return "Arraste para selecionar aldeões. WASD move a câmera, scroll dá zoom, B constrói casa."


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep Space and hotkeys for the game
	b.pressed.connect(on_pressed)
	return b
