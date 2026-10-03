class_name PlayerController
extends Node2D
## Turns mouse and keyboard input into a selection and into orders for the simulation.

signal notice(text: String)

const CLICK_SLOP := 6.0
const PICK_RADIUS := 14.0

var state: GameState
var selected_units: Array[int] = []
var selected_building := -1
## Id of the building type being placed, or "" when not placing.
var placing := ""
var hover_cell := Vector2i.ZERO
var dragging := false
var drag_start := Vector2.ZERO


func clear_selection() -> void:
	selected_units.clear()
	selected_building = -1
	placing = ""
	dragging = false


func begin_placement(def_id: String) -> void:
	placing = def_id


func train_villager() -> void:
	if selected_building < 0:
		return
	if not state.queue_villager(selected_building):
		notice.emit("Recursos insuficientes")
	elif state.units.size() >= state.pop_cap():
		notice.emit("Limite de população: construa mais casas")


func _process(_delta: float) -> void:
	hover_cell = Iso.cell_at(get_global_mouse_position())
	# The release can be swallowed by the HUD, so do not rely on the event alone.
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_selection(get_global_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
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
			KEY_Q:
				train_villager()


func _place(cell: Vector2i, keep_placing: bool) -> void:
	var id := state.place_building(placing, cell)
	if id < 0:
		var affordable := state.can_afford(Defs.building(placing).cost)
		notice.emit("Não é possível construir aqui" if affordable else "Recursos insuficientes")
		return
	state.order_build(selected_units, id)
	if not keep_placing:
		placing = ""


func _finish_selection(world: Vector2) -> void:
	dragging = false
	selected_units.clear()
	selected_building = -1
	if drag_start.distance_to(world) < CLICK_SLOP:
		var best_dist := PICK_RADIUS
		for u: SimUnit in state.units.values():
			var dist := (Iso.to_world(u.pos) + Vector2(0, -8)).distance_to(world)
			if dist < best_dist:
				best_dist = dist
				selected_units.assign([u.id])
		if selected_units.is_empty():
			var b := state.building_at(Iso.cell_at(world))
			if b != null:
				selected_building = b.id
	else:
		var box := Rect2(drag_start, world - drag_start).abs()
		for u: SimUnit in state.units.values():
			if box.has_point(Iso.to_world(u.pos)):
				selected_units.append(u.id)


func _issue_order(cell: Vector2i) -> void:
	if selected_units.is_empty():
		return
	var b := state.building_at(cell)
	if state.nodes.has(cell):
		state.order_gather(selected_units, cell)
	elif b != null and not b.is_complete():
		state.order_build(selected_units, b.id)
	else:
		state.order_move(selected_units, cell)
