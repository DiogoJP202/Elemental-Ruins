class_name PlayerController
extends CharacterBody3D
## Locomoção em terceira pessoa: WASD relativo à câmera, Shift corre, Space pula.
## A origem do corpo fica nos pés (a cápsula é deslocada para cima na cena).
##
## Testes automatizados usam set_scripted_move() em vez de Input, exercitando
## o mesmo move_and_slide() do jogo.

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var ground_acceleration := 40.0
@export var air_acceleration := 8.0
@export var jump_velocity := 6.0
@export var turn_speed := 12.0

var input_enabled := true
## Multiplicador de velocidade aplicado pelos poderes (ex.: segurar uma rocha; P3.5). 1 = normal.
var speed_scale := 1.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _frozen := false
var _scripted := false
var _scripted_dir := Vector3.ZERO
var _scripted_sprint := false

@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var _visual: Node3D = $Visual


func _ready() -> void:
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35


func _physics_process(delta: float) -> void:
	if _frozen:
		velocity = Vector3.ZERO
		return

	var move_dir := Vector3.ZERO
	var sprint := false
	var jump := false
	if _scripted:
		move_dir = _scripted_dir
		sprint = _scripted_sprint
	elif input_enabled:
		var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		move_dir = camera_rig.get_yaw_basis() * Vector3(input.x, 0.0, input.y)
		sprint = Input.is_action_pressed(&"sprint")
		jump = Input.is_action_just_pressed(&"jump")
	move_dir.y = 0.0
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif jump:
		velocity.y = jump_velocity

	var target := move_dir * (sprint_speed if sprint else walk_speed) * speed_scale
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	if move_dir.length_squared() > 0.01:
		var target_yaw := atan2(-move_dir.x, -move_dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


## Congela o corpo (sem gravidade nem movimento). Usado enquanto o terreno carrega/reseta.
func set_frozen(frozen: bool) -> void:
	_frozen = frozen
	velocity = Vector3.ZERO


func is_frozen() -> bool:
	return _frozen


## Teletransporte pontual (spawn/reset/testes), nunca por quadro.
func teleport_to(world_position: Vector3) -> void:
	global_position = world_position
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func set_scripted_move(world_dir: Vector3, sprint := false) -> void:
	_scripted = true
	_scripted_dir = world_dir
	_scripted_sprint = sprint


func clear_scripted_move() -> void:
	_scripted = false
	_scripted_dir = Vector3.ZERO
	_scripted_sprint = false
