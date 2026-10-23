class_name TerrainEditController
extends Node
## Traduz os atalhos de engenharia (provisórios, P0/P1) em pedidos para a TerrainBrushQueue.
## G escava, H adiciona e N suavizam enquanto seguradas (traço contínuo); J abre túnel,
## K ergue rampa, M troca o material do H, R extrai uma rocha, T dá um impulso de teste no
## corpo mirado, Z reset, F5/F9 salvar/carregar o slot, roda/[ ] muda o raio, B solta caixa.
## R e T são ferramentas de laboratório do P2, não as habilidades de terra do P3.
## A mira é um raycast FÍSICO do centro da tela contra os colliders do terreno.

signal edit_performed(result: TerrainEditResult)
signal reset_requested
signal save_requested
signal load_requested
signal aim_changed(has_hit: bool, point: Vector3, editable: bool)

const STROKE_ACTIONS := {
	&"terrain_dig": TerrainBrushRequest.Op.REMOVE,
	&"terrain_add": TerrainBrushRequest.Op.ADD,
	&"terrain_smooth": TerrainBrushRequest.Op.SMOOTH,
}
const ADD_MATERIALS: Array[StringName] = [TerrainMaterialLibrary.SOIL, TerrainMaterialLibrary.SAND, TerrainMaterialLibrary.STONE]

@export var max_aim_distance := 40.0
@export var radius := 2.0
@export var radius_step := 0.25
@export var tunnel_length := 10.0
@export var tunnel_segments := 5
@export var ramp_length := 8.0
@export var ramp_rise := 3.0
@export var ramp_segments := 8
@export var max_crates := 10

var terrain_service: TerrainService
var brush_queue: TerrainBrushQueue
var player: PlayerController
var props_root: Node3D

var _aim_hit := false
var _aim_point := Vector3.ZERO
var _aim_normal := Vector3.UP
var _aim_editable := false
var _aim_material: TerrainMaterial
var _add_material_index := 0
## ação → id do traço ativo
var _strokes := {}
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D


func setup(p_service: TerrainService, p_queue: TerrainBrushQueue, p_player: PlayerController, p_props_root: Node3D) -> void:
	terrain_service = p_service
	brush_queue = p_queue
	player = p_player
	props_root = p_props_root
	radius = clampf(radius, terrain_service.min_radius, terrain_service.max_radius)
	brush_queue.brush_applied.connect(func(_req, result): edit_performed.emit(result))


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


func get_add_material() -> StringName:
	return ADD_MATERIALS[_add_material_index]


func get_aim() -> Dictionary:
	return {"hit": _aim_hit, "point": _aim_point, "normal": _aim_normal, "editable": _aim_editable,
		"material": _aim_material}


func _unhandled_input(event: InputEvent) -> void:
	if terrain_service == null or player == null or not player.input_enabled:
		return
	for action: StringName in STROKE_ACTIONS:
		if event.is_action_pressed(action):
			# O traço abre no EVENTO e já carimba: um toque rápido (tecla desce e sobe no
			# mesmo quadro) não pode se perder (bug B3 do P0).
			_begin_stroke(action)
			return
		if event.is_action_released(action):
			_end_stroke(action)
			return
	if event.is_action_pressed(&"brush_radius_up"):
		_change_radius(radius_step)
	elif event.is_action_pressed(&"brush_radius_down"):
		_change_radius(-radius_step)
	elif event.is_action_pressed(&"world_reset"):
		reset_requested.emit()
	elif event.is_action_pressed(&"world_save"):
		save_requested.emit()
	elif event.is_action_pressed(&"world_load"):
		load_requested.emit()
	elif event.is_action_pressed(&"terrain_tunnel"):
		_do_tunnel()
	elif event.is_action_pressed(&"terrain_ramp"):
		_do_ramp()
	elif event.is_action_pressed(&"brush_cycle_material"):
		_add_material_index = (_add_material_index + 1) % ADD_MATERIALS.size()
	elif event.is_action_pressed(&"terrain_extract"):
		_do_extract()
	elif event.is_action_pressed(&"debug_push"):
		_do_push()
	elif event.is_action_pressed(&"debug_spawn_crate"):
		_spawn_crate()


func _physics_process(_delta: float) -> void:
	if terrain_service == null or player == null or not player.input_enabled:
		_marker.visible = false
		_aim_hit = false
		_aim_material = null
		_end_all_strokes()
		return
	_update_aim()
	for action: StringName in STROKE_ACTIONS:
		var held := Input.is_action_pressed(action)
		if held and not _strokes.has(action):
			# Sem evento (ex.: Input.action_press em teste, foco recuperado): abre aqui.
			_begin_stroke(action)
		elif _strokes.has(action):
			if not held:
				_end_stroke(action)
			else:
				_feed_stroke(action)


func _begin_stroke(action: StringName) -> void:
	_end_stroke(action)
	var op: TerrainBrushRequest.Op = STROKE_ACTIONS[action]
	var mat := get_add_material() if op == TerrainBrushRequest.Op.ADD else &""
	var r := minf(radius, terrain_service.max_smooth_radius) if op == TerrainBrushRequest.Op.SMOOTH else radius
	_strokes[action] = brush_queue.begin_stroke(op, r, mat, "input:%s" % action)
	_feed_stroke(action)
	if not _aim_hit:
		edit_performed.emit(TerrainEditResult.failure(TerrainBrushRequest.OP_NAMES[op], "no_aim_target"))


func _feed_stroke(action: StringName) -> void:
	var op: TerrainBrushRequest.Op = STROKE_ACTIONS[action]
	var center := _aim_point
	if op == TerrainBrushRequest.Op.ADD:
		# Centro levemente para fora da superfície: o volume cresce em direção ao jogador.
		center = _aim_point + _aim_normal * radius * 0.5
	brush_queue.update_stroke(_strokes[action], center, _aim_normal, _aim_hit)


func _end_stroke(action: StringName) -> void:
	if _strokes.has(action):
		brush_queue.end_stroke(_strokes[action])
		_strokes.erase(action)


func _end_all_strokes() -> void:
	for action in _strokes.keys():
		_end_stroke(action)


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
		_aim_material = terrain_service.get_material_at(_aim_point - _aim_normal * 0.5)
		_marker.global_position = _aim_point
		_marker.scale = Vector3.ONE * radius
		_marker_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.22) if _aim_editable else Color(1.0, 0.25, 0.2, 0.3)
	else:
		_aim_editable = false
		_aim_material = null
	_marker.visible = _aim_hit
	aim_changed.emit(_aim_hit, _aim_point, _aim_editable)


## Túnel horizontal: começa um pouco antes do ponto mirado e segue a direção
## horizontal da câmera por tunnel_length, na altura do ponto mirado.
func _do_tunnel() -> void:
	if not _aim_hit:
		edit_performed.emit(TerrainEditResult.failure("PATH-", "no_aim_target"))
		return
	var forward := _camera_forward_flat()
	var start := _aim_point - forward * radius * 0.5
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in tunnel_segments + 1:
		points.append(start + forward * (tunnel_length * float(i) / float(tunnel_segments)))
		radii.append(radius)
	var req := TerrainBrushRequest.path(points, radii, false)
	req.source = "input:terrain_tunnel"
	brush_queue.enqueue(req)


func _do_ramp() -> void:
	if not _aim_hit:
		edit_performed.emit(TerrainEditResult.failure("PATH+", "no_aim_target"))
		return
	brush_queue.enqueue(make_ramp_request(_aim_point, _camera_forward_flat()))


## Rampa: tubo de matéria que nasce em `start` e sobe ramp_rise ao longo de ramp_length
## na direção `forward`, com o material atual do H. O eixo começa raio − 0,1 m abaixo do
## chão, então o topo do tubo nasce rente ao solo (sem degrau) e termina ramp_rise acima.
func make_ramp_request(start: Vector3, forward: Vector3) -> TerrainBrushRequest:
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in ramp_segments + 1:
		var t := float(i) / float(ramp_segments)
		points.append(start + forward * ramp_length * t + Vector3.UP * (ramp_rise * t - radius + 0.1))
		radii.append(radius)
	var req := TerrainBrushRequest.path(points, radii, true, get_add_material())
	req.source = "input:terrain_ramp"
	return req


## Extrai uma rocha logo abaixo do ponto mirado (raio do pincel limitado a 1–2 m).
func _do_extract() -> void:
	if not _aim_hit:
		edit_performed.emit(TerrainEditResult.failure("extract_rock", "no_aim_target"))
		return
	var r := clampf(radius, terrain_service.min_extract_radius, terrain_service.max_extract_radius)
	# A rocha sai do buraco para o lado oposto ao jogador (não cai em cima dele).
	var away := _aim_point - player.global_position
	var out: Dictionary = terrain_service.extract_rock(_aim_point, _aim_normal, r, props_root, away)
	edit_performed.emit(out.result)


## Impulso de teste no corpo físico sob a mira (camada PROPS), na direção da câmera.
func _do_push() -> void:
	var ray: Array = player.camera_rig.get_aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_aim_distance, Layers.PROPS)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var body := hit.get("collider") as RigidBody3D
	if body == null or not apply_test_impulse(body, dir):
		edit_performed.emit(TerrainEditResult.failure("impulso", "no_body_target"))


## Impulso de laboratório: lançamento a 45° (direção horizontal dada + a mesma componente
## para cima) com velocidade `speed` (m/s). Só horizontal não serve: uma rocha recém-extraída
## está no fundo da cavidade e seria empurrada contra a parede (medido no T24).
## Peça de estrutura ainda presa não é empurrada (só o StructureService a solta); corpo
## estacionado pelo DebrisBudget volta a ser dinâmico antes.
func apply_test_impulse(body: RigidBody3D, direction: Vector3, speed := 8.0) -> bool:
	if body is StructurePiece and not (body as StructurePiece).released:
		return false
	if body.get_meta(DebrisBudget.PARKED_META, "") != "":
		DebrisBudget.unpark(body)
	if body.freeze:
		return false
	var flat := Vector3(direction.x, 0.0, direction.z)
	var d := (flat.normalized() + Vector3.UP).normalized() if flat.length() > 0.01 else Vector3.UP
	body.sleeping = false
	body.apply_central_impulse(d * body.mass * speed)
	return true


func _camera_forward_flat() -> Vector3:
	var forward := -player.camera_rig.get_yaw_basis().z
	forward.y = 0.0
	return forward.normalized()


func _change_radius(step: float) -> void:
	radius = clampf(radius + step, terrain_service.min_radius, terrain_service.max_radius)


func _spawn_crate() -> void:
	if props_root == null or not _aim_hit:
		return
	var crates := props_root.get_children()
	if crates.size() >= max_crates:
		crates[0].queue_free()
	DebugProps.spawn_crate(props_root, _aim_point + _aim_normal * 1.0 + Vector3.UP * 2.0)
