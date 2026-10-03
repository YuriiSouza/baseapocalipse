class_name PlayerController
extends Node2D
## Turns mouse and keyboard input into a selection and into orders for the simulation.

signal notice(text: String)

const CLICK_SLOP := 6.0
const PICK_RADIUS := 14.0

var state: GameState
var selected_people: Array[int] = []
var selected_building := -1
var selected_poi := -1
## Id of the building type being placed, or "" when not placing.
var placing := ""
var hover_cell := Vector2i.ZERO
var dragging := false
var drag_start := Vector2.ZERO

var _drag_placing := false
var _last_dragged := Vector2i(-1, -1)


func clear_selection() -> void:
	selected_people.clear()
	selected_building = -1
	selected_poi = -1
	placing = ""
	dragging = false


## Selection made from the list of people rather than on the map.
func select_people(ids: Array[int]) -> void:
	selected_people = ids
	selected_building = -1
	selected_poi = -1


func begin_placement(def_id: String) -> void:
	placing = def_id


## Applies to everyone selected.
func set_job(work: String, allowed: bool) -> void:
	state.set_job(selected_people, work, allowed)


func _process(_delta: float) -> void:
	if state == null:
		return
	hover_cell = Iso.cell_at(get_global_mouse_position())
	# People can die while selected.
	for i in range(selected_people.size() - 1, -1, -1):
		if not state.people.has(selected_people[i]):
			selected_people.remove_at(i)
	# Fences and walls are laid by dragging: one piece per cell the mouse passes over.
	if placing != "" and Defs.building(placing).drag_place and hover_cell != _last_dragged \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _drag_placing:
		_last_dragged = hover_cell
		var id := state.place_building(placing, hover_cell)
		if id >= 0:
			state.order_build(selected_people, id)
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag_placing = false
	# The release can be swallowed by the HUD, so do not rely on the event alone.
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_selection(get_global_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if state == null or state.is_over():
		return
	if event is InputEventMouseButton:
		var world := get_global_mouse_position()
		var cell := Iso.cell_at(world)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				if dragging:
					_finish_selection(world)
			elif placing != "":
				_place(cell, event.shift_pressed)
			else:
				dragging = true
				drag_start = world
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if placing != "":
				placing = ""
			else:
				_issue_order(cell)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				placing = ""
			KEY_B:
				begin_placement("house")


func _place(cell: Vector2i, keep_placing: bool) -> void:
	var id := state.place_building(placing, cell)
	if id < 0:
		var def := Defs.building(placing)
		if not state.can_build(placing):
			notice.emit("Falta conhecimento: requer %s" % Knowledge.requirement_text(def.requires))
		else:
			notice.emit("Não é possível construir aqui" if state.can_afford(def.cost) else "Recursos insuficientes")
		return
	state.order_build(selected_people, id)
	if Defs.building(placing).drag_place:
		# Stays in placing mode; holding the button keeps laying pieces.
		_drag_placing = true
		_last_dragged = cell
	elif not keep_placing:
		placing = ""


func _finish_selection(world: Vector2) -> void:
	dragging = false
	selected_people.clear()
	selected_building = -1
	selected_poi = -1
	if drag_start.distance_to(world) < CLICK_SLOP:
		var best_dist := PICK_RADIUS
		for p: SimPerson in state.people.values():
			var dist := (Iso.to_world(p.pos) + Vector2(0, -8)).distance_to(world)
			if p.inside < 0 and dist < best_dist:
				best_dist = dist
				selected_people.assign([p.id])
		if selected_people.is_empty():
			var b := state.building_at(Iso.cell_at(world))
			var poi := state.poi_at(Iso.cell_at(world))
			if b != null:
				selected_building = b.id
			elif poi != null and poi.discovered:
				selected_poi = poi.id
	else:
		var box := Rect2(drag_start, world - drag_start).abs()
		for p: SimPerson in state.people.values():
			if p.inside < 0 and box.has_point(Iso.to_world(p.pos)):
				selected_people.append(p.id)


func _issue_order(cell: Vector2i) -> void:
	if selected_people.is_empty():
		return
	var b := state.building_at(cell)
	var poi := state.poi_at(cell)
	if poi != null and poi.discovered:
		state.order_expedition(selected_people, poi.id)
	elif state.source_yield(cell) != "":
		state.order_gather(selected_people, cell)
	elif b != null and state.building_needs_work(b):
		state.order_build(selected_people, b.id)
	else:
		state.order_move(selected_people, cell)
	for id in selected_people:
		if (state.people[id] as SimPerson).energy <= Defs.EXHAUSTED:
			notice.emit("Alguém está exausto demais para obedecer")
			break
