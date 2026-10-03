class_name TerrainView
extends Node2D
## Draws the ground as chunks. Each chunk is its own canvas item, drawn once and cached,
## so the engine skips the ones that are off screen. A chunk is drawn again only when
## some of its fog lifts.

const CHUNK := 16
const GRASS_A := Color(0.36, 0.56, 0.3)
const GRASS_B := Color(0.38, 0.59, 0.32)
const WATER := Color(0.2, 0.4, 0.62)
const FOG := Color(0.05, 0.06, 0.08)

var _chunks := {}  # chunk coordinate -> Chunk

var state: GameState:
	set(value):
		state = value
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_chunks.clear()
	if state == null:
		return
	for cy in range(0, state.height, CHUNK):
		for cx in range(0, state.width, CHUNK):
			var chunk := Chunk.new()
			chunk.state = state
			chunk.region = Rect2i(cx, cy, mini(CHUNK, state.width - cx), mini(CHUNK, state.height - cy))
			add_child(chunk)
			@warning_ignore("integer_division")
			_chunks[Vector2i(cx / CHUNK, cy / CHUNK)] = chunk


func _process(_delta: float) -> void:
	if state == null or state.revealed.is_empty():
		return
	for block in state.revealed:
		@warning_ignore("integer_division")
		var chunk: Chunk = _chunks.get(block * Defs.FOG_BLOCK / CHUNK)
		if chunk != null:
			chunk.queue_redraw()
	state.revealed.clear()


class Chunk extends Node2D:
	var state: GameState
	var region: Rect2i

	func _draw() -> void:
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var c := Vector2i(x, y)
				var color := GRASS_A if (x + y) % 2 == 0 else GRASS_B
				if not state.is_explored(c):
					color = FOG
				elif state.terrain_at(c) == GameState.Terrain.WATER:
					color = WATER
				draw_colored_polygon(Iso.diamond(Vector2(c)), color)
