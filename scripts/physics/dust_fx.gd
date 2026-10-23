class_name DustFx
extends Node3D
## Poeira decorativa quando uma peça de estrutura se solta (P2). Pool fixo de emissores
## GPUParticles3D de disparo único, sem corpo físico; no máximo max_bursts_per_frame
## disparos por quadro. Não é arte final: só sinaliza "rompeu aqui".

@export var structure_service_path: NodePath = ^"../StructureService"
@export var pool_size := 4
@export var max_bursts_per_frame := 2

var _emitters: Array[GPUParticles3D] = []
var _next := 0
var _burst_frame := -1
var _bursts_this_frame := 0
var _stats := {"bursts": 0, "skipped": 0}


func _ready() -> void:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 3.5
	process.gravity = Vector3(0, -3.0, 0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = 0.25
	process.scale_max = 0.6
	process.color = Color("#C9B79C")
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 0.55)
	quad.material = mat
	for i in pool_size:
		var e := GPUParticles3D.new()
		e.name = "Dust%d" % i
		e.one_shot = true
		e.emitting = false
		e.amount = 24
		e.lifetime = 1.2
		e.explosiveness = 0.9
		e.process_material = process
		e.draw_pass_1 = quad
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
		add_child(e)
		_emitters.append(e)
	var structures := get_node_or_null(structure_service_path) as StructureService
	if structures != null:
		structures.piece_released.connect(func(p: StructurePiece): burst(p.global_position))


func get_stats() -> Dictionary:
	return _stats.duplicate()


func burst(at: Vector3) -> void:
	var frame := Engine.get_physics_frames()
	if frame != _burst_frame:
		_burst_frame = frame
		_bursts_this_frame = 0
	if _bursts_this_frame >= max_bursts_per_frame or _emitters.is_empty():
		_stats.skipped += 1
		return
	_bursts_this_frame += 1
	var e := _emitters[_next]
	_next = (_next + 1) % _emitters.size()
	e.global_position = at
	e.restart()
	e.emitting = true
	_stats.bursts += 1
