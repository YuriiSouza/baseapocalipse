extends Node2D
## Owns the simulation and advances it at a fixed tick rate, independent of the frame rate.
## Game speed only changes how many ticks run per second; camera and UI are unaffected.

const SAVE_PATH := "user://savegame.sav"
const MAX_STEPS_PER_FRAME := 20
const NIGHT_TINT := Color(0.32, 0.38, 0.6)
const TWILIGHT_HOURS := 2.0

var state: GameState
var speed := 1.0
var _last_speed := 1.0
var _accum := 0.0

@onready var _terrain: TerrainView = $TerrainView
@onready var _entities: EntityView = $EntityView
@onready var _controller: PlayerController = $PlayerController
@onready var _camera := $Camera
@onready var _day_night: CanvasModulate = $DayNight
@onready var _hud: Hud = $Hud


func _ready() -> void:
	_entities.controller = _controller
	_hud.controller = _controller
	_controller.notice.connect(_hud.show_message)
	_hud.speed_selected.connect(set_speed)
	_hud.build_requested.connect(_controller.begin_placement)
	_hud.job_toggled.connect(_controller.set_job)
	_hud.save_requested.connect(save_game)
	_hud.load_requested.connect(load_game)
	_hud.new_game_requested.connect(new_game)
	new_game()


func _process(delta: float) -> void:
	if not state.is_over():
		_accum += delta * speed * GameState.TICKS_PER_SECOND
		var steps := mini(floori(_accum), MAX_STEPS_PER_FRAME)
		_accum -= floorf(_accum)
		for i in steps:
			state.step()
	for message in state.events:
		_hud.show_message(message)
	state.events.clear()
	_entities.alpha = _accum
	_hud.speed = speed
	_day_night.color = NIGHT_TINT.lerp(Color.WHITE, _daylight(state.hour()))


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


func new_game() -> void:
	_start(GameState.new_game(randi()))


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_hud.show_message("Falha ao salvar")
		return
	# Godot's binary format rather than JSON: JSON does not bring floats back exactly.
	file.store_var(state.to_dict())
	_hud.show_message("Jogo salvo")


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_hud.show_message("Nenhum jogo salvo")
		return
	var data: Variant = FileAccess.open(SAVE_PATH, FileAccess.READ).get_var()
	if not data is Dictionary or int(data.get("version", 0)) != GameState.SAVE_VERSION:
		_hud.show_message("Save incompatível com esta versão")
		return
	_start(GameState.from_dict(data))
	_hud.show_message("Jogo carregado")


## 0 at night, 1 during the day, with a ramp at dawn and dusk.
func _daylight(hour: float) -> float:
	var dawn := smoothstep(Defs.NIGHT_END, Defs.NIGHT_END + TWILIGHT_HOURS, hour)
	var dusk := smoothstep(Defs.NIGHT_START, Defs.NIGHT_START - TWILIGHT_HOURS, hour)
	return minf(dawn, dusk)


func _start(new_state: GameState) -> void:
	state = new_state
	_accum = 0.0
	_controller.clear_selection()
	_controller.state = state
	_terrain.state = state
	_entities.state = state
	_hud.state = state
	var focus := Vector2(state.width, state.height) * 0.5
	if not state.people.is_empty():
		focus = (state.people.values()[0] as SimPerson).pos
	# The map is a diamond in world space; this is its bounding box.
	_camera.bounds = Rect2(
		-state.height * Iso.HALF_W, 0.0,
		(state.width + state.height) * Iso.HALF_W, (state.width + state.height) * Iso.HALF_H)
	_camera.position = Iso.to_world(focus)
