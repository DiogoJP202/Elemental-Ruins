class_name ThirdPersonCamera
extends Node3D
## Rig de câmera orbital: este nó gira em yaw, o filho Pitch gira em pitch e o
## SpringArm3D aproxima a câmera ao encontrar terreno (máscara = Layers.TERRAIN).
## Esc alterna captura do mouse; clicar na janela recaptura.

@export var mouse_sensitivity := 0.0025
@export var min_pitch_deg := -75.0
@export var max_pitch_deg := 55.0

@export_group("Tremor (P3.5)")
## Tremor de câmera LOCAL por "trauma" (0–1, decai): deslocamento ∝ trauma². Só visual: a mira
## (get_aim_ray) não treme. 0 desliga (acessibilidade).
@export var shake_scale := 1.0
@export var shake_max_offset := 0.22
@export var shake_max_roll_deg := 1.2
@export var shake_decay_per_s := 1.8
@export var shake_frequency := 22.0

var _yaw := 0.0
var _pitch := deg_to_rad(-12.0)
var _trauma := 0.0
var _shake_t := 0.0

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
		# O clique que só recaptura o mouse não chega aos poderes (LMB = usar poder no P3).
		get_viewport().set_input_as_handled()


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


## Orientação explícita (spawn, reset, capturas de teste).
func set_view(yaw_rad: float, pitch_rad: float) -> void:
	_yaw = yaw_rad
	_pitch = pitch_rad
	_apply()


## Raio de mira saindo do centro da tela. Retorna [origem, direção].
## Calculado pelo transform da câmera SEM o tremor: project_ray_* usa get_camera_transform(),
## que inclui h_offset/v_offset (o tremor); a rolagem não muda o raio do centro.
func get_aim_ray() -> Array:
	var t := camera.global_transform
	return [t.origin, -t.basis.z]


## Soma trauma (0–1) ao tremor; quem chama escala pela proximidade do evento.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount * shake_scale, 0.0, 1.0)


func get_trauma() -> float:
	return _trauma


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(0.0, _trauma - shake_decay_per_s * delta)
	_shake_t += delta
	var s := _trauma * _trauma
	var f := shake_frequency * _shake_t
	camera.h_offset = shake_max_offset * s * (sin(f * 1.0) * 0.6 + sin(f * 2.3 + 1.7) * 0.4)
	camera.v_offset = shake_max_offset * s * (sin(f * 1.3 + 0.5) * 0.6 + sin(f * 2.9 + 2.1) * 0.4)
	camera.rotation.z = deg_to_rad(shake_max_roll_deg) * s * sin(f * 0.9 + 0.3)
	if _trauma <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.rotation.z = 0.0


func _apply() -> void:
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)
