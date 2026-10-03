class_name EntityView
extends Node2D
## Draws everything that sits on the ground, back to front, with placeholder shapes.

const HALF := Vector2(0.5, 0.5)
const TRUNK := Color(0.4, 0.27, 0.15)
const LEAVES := Color(0.13, 0.36, 0.17)
const BUSH := Color(0.2, 0.45, 0.2)
const VILLAGER := Color(0.2, 0.4, 0.85)
const SKIN := Color(0.93, 0.78, 0.62)
const SCAFFOLD := Color(0.85, 0.8, 0.65)
const KIND_COLORS := {
	"food": Color(0.85, 0.2, 0.25),
	"wood": Color(0.55, 0.36, 0.2),
	"stone": Color(0.6, 0.6, 0.62),
	"gold": Color(0.95, 0.8, 0.2),
}

var state: GameState
var controller: PlayerController
## Fraction of the current tick already elapsed, for smooth unit movement.
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
	for cell: Vector2i in state.nodes:
		if visible_rect.has_point(Iso.to_world(Vector2(cell) + HALF)):
			items.append([cell.x + cell.y + 1.0, 0, cell])
	for b: SimBuilding in state.buildings.values():
		var size := b.get_def().size
		items.append([b.cell.x + b.cell.y + (size.x + size.y) * 0.5, 1, b])
	for u: SimUnit in state.units.values():
		var p := u.prev_pos.lerp(u.pos, alpha)
		items.append([p.x + p.y, 2, u])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	for item: Array in items:
		match item[1]:
			0: _draw_node(item[2])
			1: _draw_building(item[2])
			2: _draw_unit(item[2])

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
		_:
			var yields: String = Defs.NODE_KINDS[kind]["yields"]
			_draw_box(Vector2(cell) + Vector2(0.2, 0.2), Vector2(0.6, 0.6), 10.0, KIND_COLORS[yields])


func _draw_building(b: SimBuilding) -> void:
	var def := b.get_def()
	var ratio := clampf(float(b.progress) / maxi(1, def.build_ticks), 0.0, 1.0)
	var color := def.color if ratio >= 1.0 else def.color.lerp(SCAFFOLD, 0.6)
	var inset := Vector2(0.08, 0.08)
	_draw_box(Vector2(b.cell) + inset, Vector2(def.size) - inset * 2.0, lerpf(4.0, def.height_px, ratio), color)
	if controller.selected_building == b.id:
		_draw_outline(Iso.diamond(Vector2(b.cell), Vector2(def.size)))

	var bar_pos := Iso.to_world(Vector2(b.cell) + Vector2(def.size) * 0.5) + Vector2(0, -def.height_px - 16.0)
	if ratio < 1.0:
		_draw_bar(bar_pos, ratio, Color.ORANGE)
	elif b.train_queue > 0:
		_draw_bar(bar_pos, float(b.train_progress) / Defs.VILLAGER_TRAIN_TICKS, Color.SKY_BLUE)


func _draw_unit(u: SimUnit) -> void:
	var cell_pos := u.prev_pos.lerp(u.pos, alpha)
	var p := Iso.to_world(cell_pos)
	if controller.selected_units.has(u.id):
		_draw_outline(Iso.diamond(cell_pos - Vector2(0.3, 0.3), Vector2(0.6, 0.6)))
	draw_rect(Rect2(p + Vector2(-3, -12), Vector2(6, 11)), VILLAGER)
	draw_circle(p + Vector2(0, -15), 4.0, SKIN)
	if u.carry_amount > 0:
		draw_circle(p + Vector2(6, -8), 3.0, KIND_COLORS[u.carry_kind])


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
