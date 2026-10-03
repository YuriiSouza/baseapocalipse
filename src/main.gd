extends Node2D
## Owns the simulation and advances it at a fixed tick rate, independent of the frame rate.
## Game speed only changes how many ticks run per second; camera and UI are unaffected.

const SAVE_PATH := "user://savegame.json"
const MAX_STEPS_PER_FRAME := 20

var state: GameState
var speed := 1.0
var _last_speed := 1.0
var _accum := 0.0

@onready var _terrain: TerrainView = $TerrainView
@onready var _entities: EntityView = $EntityView
@onready var _controller: PlayerController = $PlayerController
@onready var _camera: Camera2D = $Camera
@onready var _hud: Hud = $Hud


func _ready() -> void:
	_entities.controller = _controller
	_hud.controller = _controller
	_controller.notice.connect(_hud.show_message)
	_hud.speed_selected.connect(set_speed)
	_hud.build_requested.connect(_controller.begin_placement)
	_hud.train_requested.connect(_controller.train_villager)
	_hud.save_requested.connect(save_game)
	_hud.load_requested.connect(load_game)
	_start(GameState.new_game(randi()))


func _process(delta: float) -> void:
	_accum += delta * speed * GameState.TICKS_PER_SECOND
	var steps := mini(floori(_accum), MAX_STEPS_PER_FRAME)
	_accum -= floorf(_accum)
	for i in steps:
		state.step()
	_entities.alpha = _accum
	_hud.speed = speed


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_SPACE:
			set_speed(_last_speed if speed == 0.0 else 0.0)
		KEY_1:
			set_speed(1.0)
		KEY_2:
			set_speed(2.0)
		KEY_3:
			set_speed(5.0)
		KEY_F5:
			save_game()
		KEY_F9:
			load_game()


func set_speed(value: float) -> void:
	if value > 0.0:
		_last_speed = value
	speed = value


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_hud.show_message("Falha ao salvar")
		return
	file.store_string(JSON.stringify(state.to_dict()))
	_hud.show_message("Jogo salvo")


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_hud.show_message("Nenhum jogo salvo")
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		_hud.show_message("Save corrompido")
		return
	_start(GameState.from_dict(data))
	_hud.show_message("Jogo carregado")


func _start(new_state: GameState) -> void:
	state = new_state
	_accum = 0.0
	_controller.clear_selection()
	_controller.state = state
	_terrain.state = state
	_entities.state = state
	_hud.state = state
	var focus := Vector2(state.width, state.height) * 0.5
	if not state.units.is_empty():
		focus = (state.units.values()[0] as SimUnit).pos
	_camera.position = Iso.to_world(focus)
