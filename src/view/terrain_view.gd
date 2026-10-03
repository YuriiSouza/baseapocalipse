class_name TerrainView
extends Node2D
## Draws the ground once per game; the canvas item caches it between frames.

const GRASS_A := Color(0.36, 0.56, 0.3)
const GRASS_B := Color(0.38, 0.59, 0.32)
const WATER := Color(0.2, 0.4, 0.62)

var state: GameState:
	set(value):
		state = value
		queue_redraw()


func _draw() -> void:
	if state == null:
		return
	for y in state.height:
		for x in state.width:
			var c := Vector2i(x, y)
			var color := GRASS_A if (x + y) % 2 == 0 else GRASS_B
			if state.terrain_at(c) == GameState.Terrain.WATER:
				color = WATER
			draw_colored_polygon(Iso.diamond(Vector2(c)), color)
