class_name ThirdPersonCamera
extends Node3D
## Rig de câmera orbital: este nó gira em yaw, o filho Pitch gira em pitch e o
## SpringArm3D aproxima a câmera ao encontrar terreno (máscara = Layers.TERRAIN).
## Esc alterna captura do mouse; clicar na janela recaptura.

@export var mouse_sensitivity := 0.0025
@export var min_pitch_deg := -75.0
@export var max_pitch_deg := 55.0

var _yaw := 0.0
var _pitch := deg_to_rad(-12.0)

@onready var _pitch_node: Node3D = $Pitch
@onready var _spring: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	_spring.collision_mask = Layers.TERRAIN
	_apply()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch -= motion.relative.y * mouse_sensitivity
		_apply()
	elif event.is_action_pressed(&"toggle_mouse_capture"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


## Orientação explícita (spawn, reset, capturas de teste).
func set_view(yaw_rad: float, pitch_rad: float) -> void:
	_yaw = yaw_rad
	_pitch = pitch_rad
	_apply()


## Raio de mira saindo do centro da tela. Retorna [origem, direção].
func get_aim_ray() -> Array:
	var center := camera.get_viewport().get_visible_rect().size * 0.5
	return [camera.project_ray_origin(center), camera.project_ray_normal(center)]


func _apply() -> void:
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)
