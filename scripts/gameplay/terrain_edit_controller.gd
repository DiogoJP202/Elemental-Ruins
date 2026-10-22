class_name TerrainEditController
extends Node
## Traduz os atalhos de engenharia do P0 em comandos do TerrainService.
## G escava, H adiciona, J abre túnel, Z reset, roda/[ ] muda raio, B solta caixa.
## A mira é um raycast FÍSICO do centro da tela contra os colliders do terreno.

signal edit_performed(result: TerrainEditResult)
signal reset_requested
signal aim_changed(has_hit: bool, point: Vector3, editable: bool)

@export var max_aim_distance := 40.0
@export var radius := 2.0
@export var radius_step := 0.25
## Repetição enquanto G/H estão pressionados (limita taxa de edições).
@export var hold_repeat_interval := 0.15
@export var tunnel_length := 10.0
@export var tunnel_segments := 5
@export var max_crates := 10

var terrain_service: TerrainService
var player: PlayerController
var props_root: Node3D

var _aim_hit := false
var _aim_point := Vector3.ZERO
var _aim_normal := Vector3.UP
var _aim_editable := false
var _repeat_timer := 0.0
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D


func setup(p_service: TerrainService, p_player: PlayerController, p_props_root: Node3D) -> void:
	terrain_service = p_service
	player = p_player
	props_root = p_props_root
	radius = clampf(radius, terrain_service.min_radius, terrain_service.max_radius)


func _ready() -> void:
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_mat.no_depth_test = false
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_marker = MeshInstance3D.new()
	_marker.name = "AimMarker"
	_marker.mesh = sphere
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)


func get_radius() -> float:
	return radius


func get_aim() -> Dictionary:
	return {"hit": _aim_hit, "point": _aim_point, "normal": _aim_normal, "editable": _aim_editable}


func _unhandled_input(event: InputEvent) -> void:
	if terrain_service == null or player == null or not player.input_enabled:
		return
	if event.is_action_pressed(&"brush_radius_up"):
		_change_radius(radius_step)
	elif event.is_action_pressed(&"brush_radius_down"):
		_change_radius(-radius_step)
	elif event.is_action_pressed(&"terrain_dig"):
		# Primeira edição vem do evento: um toque rápido (tecla desce e sobe no
		# mesmo quadro) não pode se perder. A repetição segurando fica no _physics_process.
		_do_sphere(false)
		_repeat_timer = hold_repeat_interval
	elif event.is_action_pressed(&"terrain_add"):
		_do_sphere(true)
		_repeat_timer = hold_repeat_interval
	elif event.is_action_pressed(&"world_reset"):
		reset_requested.emit()
	elif event.is_action_pressed(&"terrain_tunnel"):
		_do_tunnel()
	elif event.is_action_pressed(&"debug_spawn_crate"):
		_spawn_crate()


func _physics_process(delta: float) -> void:
	if terrain_service == null or player == null or not player.input_enabled:
		_marker.visible = false
		return
	_update_aim()
	var dig := Input.is_action_pressed(&"terrain_dig")
	var add := Input.is_action_pressed(&"terrain_add")
	if dig or add:
		_repeat_timer -= delta
		if _repeat_timer <= 0.0:
			_repeat_timer = hold_repeat_interval
			_do_sphere(add and not dig)


func _update_aim() -> void:
	var ray: Array = player.camera_rig.get_aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var hit := terrain_service.raycast_terrain(origin, origin + dir * max_aim_distance)
	_aim_hit = not hit.is_empty()
	if _aim_hit:
		_aim_point = hit.position
		_aim_normal = hit.normal
		var box := AABB(_aim_point - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
		_aim_editable = terrain_service.can_edit_area(box)
		_marker.global_position = _aim_point
		_marker.scale = Vector3.ONE * radius
		_marker_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.22) if _aim_editable else Color(1.0, 0.25, 0.2, 0.3)
	else:
		_aim_editable = false
	_marker.visible = _aim_hit
	aim_changed.emit(_aim_hit, _aim_point, _aim_editable)


func _do_sphere(add: bool) -> void:
	if not _aim_hit:
		edit_performed.emit(TerrainEditResult.failure("add_sphere" if add else "dig_sphere", "no_aim_target"))
		return
	var result: TerrainEditResult
	if add:
		# Centro levemente para fora da superfície: o volume cresce em direção ao jogador.
		result = terrain_service.add_sphere(_aim_point + _aim_normal * radius * 0.5, radius)
	else:
		result = terrain_service.dig_sphere(_aim_point, radius)
	edit_performed.emit(result)


## Túnel horizontal: começa um pouco antes do ponto mirado e segue a direção
## horizontal da câmera por tunnel_length, na altura do ponto mirado.
func _do_tunnel() -> void:
	if not _aim_hit:
		edit_performed.emit(TerrainEditResult.failure("dig_path", "no_aim_target"))
		return
	var forward := -player.camera_rig.get_yaw_basis().z
	forward.y = 0.0
	forward = forward.normalized()
	var start := _aim_point - forward * radius * 0.5
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in tunnel_segments + 1:
		points.append(start + forward * (tunnel_length * float(i) / float(tunnel_segments)))
		radii.append(radius)
	edit_performed.emit(terrain_service.dig_path(points, radii))


func _change_radius(step: float) -> void:
	radius = clampf(radius + step, terrain_service.min_radius, terrain_service.max_radius)


func _spawn_crate() -> void:
	if props_root == null or not _aim_hit:
		return
	var crates := props_root.get_children()
	if crates.size() >= max_crates:
		crates[0].queue_free()
	DebugProps.spawn_crate(props_root, _aim_point + _aim_normal * 1.0 + Vector3.UP * 2.0)
