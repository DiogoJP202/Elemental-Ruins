class_name TerrainContactWaker
extends Node
## Acorda corpos físicos sobre terreno editado (P2).
##
## Medido no spike P2 (I3): um RigidBody3D DORMINDO não acorda quando o collider do
## terreno embaixo dele some (fica flutuando); acordado, cai. Como o collider chega alguns
## quadros depois do TerrainChanged (P1, T12), cada edição gera alguns "pulsos" nos quadros
## seguintes: uma consulta de forma (caixa = AABB da edição + folga) na camada PROPS acorda
## os corpos dormindo e solta os que o DebrisBudget estacionou ali. Peças de estrutura ainda
## presas (congeladas, sem a marca de estacionado) não são tocadas: quem as solta é o
## StructureService.

@export var terrain_service_path: NodePath = ^"../TerrainService"
## Quadros de física depois da edição em que a área é consultada.
@export var pulse_frames := PackedInt32Array([1, 3, 8, 20])
@export var margin := 1.0
@export var max_results := 64

var _pending: Array[Dictionary] = []
var _stats := {"events": 0, "pulses": 0, "woken": 0, "unparked": 0}


func _ready() -> void:
	var svc := get_node(terrain_service_path) as TerrainService
	svc.terrain_changed.connect(_on_terrain_changed)


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["pending"] = _pending.size()
	return d


func _on_terrain_changed(aabb: AABB, _revision: int) -> void:
	_stats.events += 1
	_pending.append({"aabb": aabb.grow(margin), "start": Engine.get_physics_frames(), "next": 0})


func _physics_process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var frame := Engine.get_physics_frames()
	var still: Array[Dictionary] = []
	for e in _pending:
		if frame - e.start >= pulse_frames[e.next]:
			_pulse(e.aabb)
			e.next += 1
		if e.next < pulse_frames.size():
			still.append(e)
	_pending = still


func _pulse(aabb: AABB) -> void:
	_stats.pulses += 1
	var world := get_viewport().get_world_3d()
	if world == null:
		return
	var box := BoxShape3D.new()
	box.size = aabb.size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, aabb.get_center())
	q.collision_mask = Layers.PROPS
	q.collide_with_areas = false
	for hit in world.direct_space_state.intersect_shape(q, max_results):
		var body := hit.collider as RigidBody3D
		if body == null:
			continue
		if body.freeze:
			if body.get_meta(DebrisBudget.PARKED_META, "") != "":
				DebrisBudget.unpark(body)
				_stats.unparked += 1
		elif body.sleeping:
			body.sleeping = false
			_stats.woken += 1
