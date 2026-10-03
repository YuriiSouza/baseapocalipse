class_name EntityView
extends Node2D
## Draws everything that sits on the ground, back to front, with placeholder shapes.

const HALF := Vector2(0.5, 0.5)
const TRUNK := Color(0.4, 0.27, 0.15)
const LEAVES := Color(0.13, 0.36, 0.17)
const BUSH := Color(0.2, 0.45, 0.2)
const WRECK := Color(0.5, 0.33, 0.25)
const CLOTHES_M := Color(0.2, 0.4, 0.85)
const CLOTHES_F := Color(0.75, 0.3, 0.55)
const SKIN := Color(0.93, 0.78, 0.62)
const SCAFFOLD := Color(0.85, 0.8, 0.65)
const ZOMBIE_BODY := Color(0.35, 0.3, 0.28)
const ZOMBIE_SKIN := Color(0.55, 0.7, 0.5)
const ANIMAL := Color(0.6, 0.45, 0.3)
const CROP_GROWING := Color(0.45, 0.65, 0.3)
const CROP_RIPE := Color(0.8, 0.72, 0.25)
const KIND_COLORS := {
	"food": Color(0.85, 0.2, 0.25),
	"water": Color(0.3, 0.6, 0.95),
	"wood": Color(0.55, 0.36, 0.2),
	"scrap": Color(0.6, 0.6, 0.62),
	"medicine": Color(0.9, 0.95, 0.9),
	"ammo": Color(0.95, 0.8, 0.2),
}
const POI_COLORS := {
	"farmhouse": Color(0.62, 0.48, 0.35),
	"store": Color(0.8, 0.62, 0.3),
	"gas": Color(0.72, 0.3, 0.28),
	"clinic": Color(0.85, 0.88, 0.9),
	"police": Color(0.3, 0.38, 0.6),
	"camp": Color(0.45, 0.55, 0.35),
}
const NAME_SIZE := 11

var state: GameState
var controller: PlayerController
## Fraction of the current tick already elapsed, for smooth movement.
var alpha := 1.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if state == null or controller == null:
		return
	var inv := get_canvas_transform().affine_inverse()
	var visible_rect := Rect2(inv.origin, get_viewport_rect().size * inv.get_scale()).grow(96.0)

	# [depth, type, payload]; deeper (larger x + y) is drawn later.
	var items := []

	# Walk only the cells on screen. In iso space a screen row is x + y = const and a
	# screen column is x - y = const, so iterate those two instead of x and y.
	var row_min := floori(visible_rect.position.y / Iso.HALF_H)
	var row_max := ceili(visible_rect.end.y / Iso.HALF_H)
	var col_min := floori(visible_rect.position.x / Iso.HALF_W)
	var col_max := ceili(visible_rect.end.x / Iso.HALF_W)
	for row in range(row_min, row_max + 1):
		for col in range(col_min + ((row + col_min) & 1), col_max + 1, 2):
			var cell := Vector2i((row + col) >> 1, (row - col) >> 1)
			if state.nodes.has(cell) and state.is_explored(cell):
				items.append([row + 1.0, 0, cell])

	for b: SimBuilding in state.buildings.values():
		var size := b.get_def().size
		if visible_rect.has_point(Iso.to_world(Vector2(b.cell) + Vector2(size) * 0.5)):
			items.append([b.cell.x + b.cell.y + (size.x + size.y) * 0.5, 1, b])
	for p: SimPerson in state.people.values():
		var at := p.prev_pos.lerp(p.pos, alpha)
		if p.inside < 0 and visible_rect.has_point(Iso.to_world(at)):
			items.append([at.x + at.y, 2, p])
	for z: SimZombie in state.zombies.values():
		var at := z.prev_pos.lerp(z.pos, alpha)
		if visible_rect.has_point(Iso.to_world(at)) and state.is_explored(z.cell()):
			items.append([at.x + at.y, 3, z])
	for a: SimAnimal in state.animals.values():
		var at := a.prev_pos.lerp(a.pos, alpha)
		if visible_rect.has_point(Iso.to_world(at)) and state.is_explored(a.cell()):
			items.append([at.x + at.y, 4, a])
	for poi: SimPoi in state.pois.values():
		if poi.discovered and visible_rect.has_point(Iso.to_world(poi.center())):
			items.append([poi.cell.x + poi.cell.y + (SimPoi.SIZE.x + SimPoi.SIZE.y) * 0.5, 5, poi])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	for item: Array in items:
		match item[1]:
			0: _draw_node(item[2])
			1: _draw_building(item[2])
			2: _draw_person(item[2])
			3: _draw_zombie(item[2])
			4: _draw_animal(item[2])
			5: _draw_poi(item[2])

	for shot: Array in state.shots:
		var from: Vector2 = Iso.to_world(shot[0]) + Vector2(0, -12)
		var to: Vector2 = Iso.to_world(shot[1]) + Vector2(0, -10)
		draw_line(from, to, Color(1.0, 0.95, 0.6), 1.5)

	if controller.placing != "":
		var def := Defs.building(controller.placing)
		var ok := state.can_place(controller.placing, controller.hover_cell) and state.can_afford(def.cost)
		var ghost := Color(0.4, 1.0, 0.4, 0.5) if ok else Color(1.0, 0.3, 0.3, 0.5)
		_draw_box(Vector2(controller.hover_cell), Vector2(def.size), def.height_px, ghost)

	if controller.dragging:
		var box := Rect2(controller.drag_start, get_global_mouse_position() - controller.drag_start).abs()
		draw_rect(box, Color(1, 1, 1, 0.9), false, 1.0)


func _draw_node(cell: Vector2i) -> void:
	var kind: String = state.nodes[cell]["kind"]
	var center := Iso.to_world(Vector2(cell) + HALF)
	match kind:
		"tree":
			draw_rect(Rect2(center + Vector2(-2, -10), Vector2(4, 10)), TRUNK)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-12, -8), center + Vector2(12, -8), center + Vector2(0, -42),
			]), LEAVES)
		"berries":
			draw_circle(center + Vector2(0, -6), 10.0, BUSH)
			for offset: Vector2 in [Vector2(-4, -8), Vector2(3, -10), Vector2(1, -3)]:
				draw_circle(center + offset, 2.0, KIND_COLORS["food"])
		"carcass":
			draw_rect(Rect2(center + Vector2(-8, -5), Vector2(16, 6)), ANIMAL.darkened(0.3))
			draw_circle(center + Vector2(4, -3), 2.0, KIND_COLORS["food"])
		_:
			_draw_box(Vector2(cell) + Vector2(0.15, 0.15), Vector2(0.7, 0.7), 12.0, WRECK)


func _draw_building(b: SimBuilding) -> void:
	var def := b.get_def()
	var ratio := clampf(float(b.progress) / maxi(1, def.build_ticks), 0.0, 1.0)
	var color := def.color if ratio >= 1.0 else def.color.lerp(SCAFFOLD, 0.6)
	if b.stock > 0:
		color = CROP_RIPE
	elif b.ripe_tick > 0:
		var growth := 1.0 - float(b.ripe_tick - state.tick) / Defs.GROW_TICKS
		color = def.color.lerp(CROP_GROWING, clampf(growth, 0.2, 1.0))
	var inset := Vector2(0.08, 0.08)
	_draw_box(Vector2(b.cell) + inset, Vector2(def.size) - inset * 2.0, lerpf(4.0, def.height_px, ratio), color)
	if controller.selected_building == b.id:
		_draw_outline(Iso.diamond(Vector2(b.cell), Vector2(def.size)))
	var bar_pos := Iso.to_world(Vector2(b.cell) + Vector2(def.size) * 0.5) + Vector2(0, -def.height_px - 16.0)
	if ratio < 1.0:
		_draw_bar(bar_pos, ratio, Color.ORANGE)
	elif b.is_damaged():
		_draw_bar(bar_pos, float(b.hp) / def.max_hp, Color.RED)


func _draw_person(p: SimPerson) -> void:
	var cell_pos := p.prev_pos.lerp(p.pos, alpha)
	var at := Iso.to_world(cell_pos)
	var selected := controller.selected_people.has(p.id)
	if selected:
		_draw_outline(Iso.diamond(cell_pos - Vector2(0.3, 0.3), Vector2(0.6, 0.6)))
	var s := 0.7 if p.is_child(state.day()) else 1.0
	var clothes := CLOTHES_F if p.sex == "f" else CLOTHES_M
	if p.state == SimPerson.State.SLEEPING:
		# Lying on the ground.
		draw_rect(Rect2(at + Vector2(-7, -5) * s, Vector2(11, 5) * s), clothes)
		draw_circle(at + Vector2(7, -3) * s, 3.5 * s, SKIN)
	else:
		draw_rect(Rect2(at + Vector2(-3, -12) * s, Vector2(6, 11) * s), clothes)
		draw_circle(at + Vector2(0, -15) * s, 4.0 * s, SKIN)
		if p.carry_amount > 0:
			draw_circle(at + Vector2(6, -8) * s, 3.0, KIND_COLORS[p.carry_kind])
	if p.wounded or p.health < 0.6:
		draw_circle(at + Vector2(0, -24) * s, 2.5, Color.RED)
	if selected:
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(p.first_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
		draw_string(font, at + Vector2(-width * 0.5, -28.0 * s), p.first_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE)


func _draw_zombie(z: SimZombie) -> void:
	var at := Iso.to_world(z.prev_pos.lerp(z.pos, alpha))
	draw_rect(Rect2(at + Vector2(-3, -12), Vector2(6, 11)), ZOMBIE_BODY)
	draw_circle(at + Vector2(0, -15), 4.0, ZOMBIE_SKIN if z.health > 0.5 else ZOMBIE_SKIN.darkened(0.4))


func _draw_animal(a: SimAnimal) -> void:
	var at := Iso.to_world(a.prev_pos.lerp(a.pos, alpha))
	draw_rect(Rect2(at + Vector2(-6, -9), Vector2(12, 6)), ANIMAL)
	draw_circle(at + Vector2(7, -10), 3.0, ANIMAL)


func _draw_poi(poi: SimPoi) -> void:
	# Greyed out once there is nothing left to take.
	var color: Color = POI_COLORS[poi.kind]
	if poi.visited and poi.loot_left() == 0:
		color = color.lerp(Color(0.35, 0.35, 0.35), 0.7)
	var inset := Vector2(0.1, 0.1)
	_draw_box(Vector2(poi.cell) + inset, Vector2(SimPoi.SIZE) - inset * 2.0, 26.0, color)
	var top := Iso.to_world(poi.center()) + Vector2(0, -26.0)
	if not poi.visited:
		draw_string(ThemeDB.fallback_font, top + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if controller.selected_poi == poi.id:
		_draw_outline(Iso.diamond(Vector2(poi.cell), Vector2(SimPoi.SIZE)))
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(poi.display_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
		draw_string(font, top + Vector2(-width * 0.5, -22.0), poi.display_name(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE)


## Isometric box standing on a footprint. `height` must be > 0.
func _draw_box(cell: Vector2, size: Vector2, height: float, color: Color) -> void:
	var base := Iso.diamond(cell, size)
	var top := Iso.diamond(cell, size, height)
	draw_colored_polygon(PackedVector2Array([base[3], base[2], top[2], top[3]]), color.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([base[2], base[1], top[1], top[2]]), color.darkened(0.45))
	draw_colored_polygon(top, color)


func _draw_outline(points: PackedVector2Array) -> void:
	points.append(points[0])
	draw_polyline(points, Color.WHITE, 1.5)


func _draw_bar(center: Vector2, ratio: float, color: Color) -> void:
	var origin := center - Vector2(16, 2)
	draw_rect(Rect2(origin, Vector2(32, 4)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(origin, Vector2(32.0 * clampf(ratio, 0.0, 1.0), 4)), color)
