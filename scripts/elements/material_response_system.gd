class_name MaterialResponseSystem
extends Node
## Reações elementais dos corpos (P3). Recebe ElementalEvent e atualiza MaterialState ANTES
## de qualquer VFX (pesquisa §3.5: AbilityCommand → ElementalEvent → WorldReaction → VFX).
## Não é solver de combustão nem de fluidos: são transições de estado de jogo.
##
## Regras:
##   HEAT     umidade evapora primeiro (DRY_HEAT = 400 unidades secam tudo); o resto sobe a temperatura,
##            dividido pela resistência térmica. Inflamável, quase seco e acima da ignição: acende.
##   WET      soma umidade, resfria (200 °C por unidade) e enfraquece o fogo; apaga se o fogo
##            acaba ou o corpo passa de 30% de umidade.
##   AIRFLOW  fogo fraco (intensidade < 0,35) sob vento forte (> 0,5) apaga; senão o vento aviva
##            (+0,3 × vento). Também seca um pouco. O empurrão físico é do próprio poder.
##   KINETIC  peça de estrutura presa: impulso / massa ≥ break_delta_v do material → solta.
## Tick a cada 0,2 s: queima consome combustível e integridade, aquece os vizinhos (propagação),
## esfria e seca. Combustível ou integridade em 0 → consumido (peça some do jogo; caixa idem).

signal ignited(body: Node3D)
signal extinguished(body: Node3D, cause: String)
signal burned_out(body: Node3D)
signal kinetic_break(body: Node3D, impulse: float)

const TICK_S := 0.2
const SPREAD_RADIUS := 2.2
const SPREAD_HEAT_PER_S := 200.0
## Calor gasto para secar umidade 1,0 antes de esquentar: madeira encharcada resiste a uma rajada.
const DRY_HEAT := 400.0
const FIRE_GROWTH_PER_S := 0.25
const MAX_BURNING := 48

@export var structure_service_path: NodePath = ^"../StructureService"
@export var terrain_service_path: NodePath = ^"../TerrainService"

var structures: StructureService
var _states := {}  # instance_id → {"body": WeakRef, "state": MaterialState}
var _accum := 0.0
var _stats := {"events": 0, "ignitions": 0, "ignitions_skipped": 0, "extinguished": 0, "burned_out": 0,
	"kinetic_breaks": 0}


func _ready() -> void:
	structures = get_node_or_null(structure_service_path) as StructureService
	var svc := get_node_or_null(terrain_service_path) as TerrainService
	if svc != null:
		svc.world_reset_started.connect(clear)
		svc.world_load_started.connect(func(_slot): clear())


# --- Consulta -----------------------------------------------------------------------------

## Estado do corpo (criado na primeira consulta). null se o corpo não tem material elemental.
func state_of(body: Node3D) -> MaterialState:
	if body == null or not is_instance_valid(body):
		return null
	var id := body.get_instance_id()
	if _states.has(id):
		return _states[id].state
	var mat := BodyMaterialLibrary.of_body(body)
	if mat == null:
		return null
	var s := MaterialState.create(mat)
	_states[id] = {"body": weakref(body), "state": s}
	return s


func burning_count() -> int:
	var n := 0
	for e in _states.values():
		n += int(e.state.burning and not e.state.consumed)
	return n


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["tracked"] = _states.size()
	d["burning"] = burning_count()
	return d


## Zera tudo (reset/carregar): os corpos antigos somem ou são remontados intactos.
func clear() -> void:
	_states.clear()


# --- Eventos -------------------------------------------------------------------------------

## Aplica o evento aos corpos atingidos e devolve quais foram. Com `target`, o alvo recebe a
## magnitude inteira; com `radius` > 0, os outros corpos da esfera recebem a queda linear
## (alvo + raio = golpe direto com respingo).
func apply(event: ElementalEvent) -> Array[Node3D]:
	_stats.events += 1
	var hit: Array[Node3D] = []
	if event.target != null:
		_apply_to(event, event.target, 1.0)
		hit.append(event.target)
		if event.radius <= 0.0:
			return hit
	for body in bodies_in_sphere(event.origin, event.radius):
		if body == event.target:
			continue
		var falloff := 1.0 - clampf(body_center(body).distance_to(event.origin) / maxf(event.radius, 0.01), 0.0, 1.0)
		if falloff <= 0.0:
			continue
		if event.kind in [ElementalEvent.Kind.WET, ElementalEvent.Kind.HEAT] and not line_of_sight(event.origin, body):
			continue
		_apply_to(event, body, falloff)
		hit.append(body)
	return hit


func bodies_in_sphere(center: Vector3, radius: float, max_results := 64) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var world := get_viewport().get_world_3d()
	if world == null or radius <= 0.0:
		return out
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = Layers.PROPS
	for h in world.direct_space_state.intersect_shape(q, max_results):
		var b := h.collider as Node3D
		if b != null and not out.has(b):
			out.append(b)
	return out


## Consulta do lado livre de um impacto. Só fontes físicas explícitas são excluídas;
## um corpo atingido não dá permissão para molhar/aquecer através dele.
func line_of_sight(from: Vector3, body: Node3D, source: Node3D = null) -> bool:
	if not is_instance_valid(body):
		return false
	return line_of_sight_to(from, body_center(body), body, source)


func line_of_sight_to(from: Vector3, to: Vector3, target: Node3D, source: Node3D = null) -> bool:
	var world := get_viewport().get_world_3d()
	if world == null:
		return false
	if from.distance_to(to) < 0.001:
		return true
	var exclude: Array[RID] = []
	if is_instance_valid(target) and target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	if is_instance_valid(source) and source is CollisionObject3D:
		exclude.append((source as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.TERRAIN | Layers.PROPS, exclude)
	q.hit_from_inside = true
	q.hit_back_faces = true
	return PhysicsRayHelper.intersect(world.direct_space_state, q).is_empty()


## Centro da malha no mundo. Rochas de separate_floating_chunks têm a origem no canto da caixa
## do pedaço (~3 m do centro): distâncias e mira pela origem erram (medido no T29).
static func body_center(body: Node3D) -> Vector3:
	for ch in body.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			return mi.global_transform * mi.mesh.get_aabb().get_center()
	return body.global_position


func _apply_to(event: ElementalEvent, body: Node3D, falloff: float) -> void:
	var s := state_of(body)
	if s == null or s.consumed:
		return
	var m := event.magnitude * falloff
	match event.kind:
		ElementalEvent.Kind.HEAT:
			_heat(body, s, m)
		ElementalEvent.Kind.WET:
			s.wetness = clampf(s.wetness + m, 0.0, 1.0)
			s.temperature = maxf(MaterialState.AMBIENT, s.temperature - m * 200.0)
			if s.burning:
				s.intensity -= m * 2.0
				if s.intensity <= 0.0 or s.wetness > 0.3:
					_extinguish(body, s, "água")
		ElementalEvent.Kind.AIRFLOW:
			s.wetness = maxf(0.0, s.wetness - m * 0.05)
			if s.burning:
				if s.intensity < 0.35 and m > 0.5:
					_extinguish(body, s, "vento")
				else:
					s.intensity = minf(1.0, s.intensity + 0.3 * m)
		ElementalEvent.Kind.KINETIC:
			var piece := body as StructurePiece
			if piece != null and not piece.released and structures != null:
				var dv := m / maxf(piece.mass, 1.0)
				if dv >= s.material.break_delta_v:
					_stats.kinetic_breaks += 1
					structures.break_piece(piece, event.direction.normalized() * m * 0.5, "impacto")
					kinetic_break.emit(piece, m)


func _heat(body: Node3D, s: MaterialState, units: float) -> void:
	var effective := units / s.material.heat_resistance
	var to_dry := minf(effective, s.wetness * DRY_HEAT)
	s.wetness = maxf(0.0, s.wetness - to_dry / DRY_HEAT)
	s.temperature += effective - to_dry
	if s.burning:
		s.intensity = minf(1.0, s.intensity + effective / 400.0)
	elif s.material.flammable and s.fuel > 0.0 and s.wetness < 0.05 and s.temperature >= s.material.ignition_temperature:
		if burning_count() >= MAX_BURNING:
			_stats.ignitions_skipped += 1
			return
		s.burning = true
		s.intensity = 0.4
		_stats.ignitions += 1
		ignited.emit(body)


func _extinguish(body: Node3D, s: MaterialState, cause: String) -> void:
	s.burning = false
	s.intensity = 0.0
	s.temperature = minf(s.temperature, s.material.ignition_temperature * 0.5)
	_stats.extinguished += 1
	extinguished.emit(body, cause)


# --- Tick ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < TICK_S:
		return
	var dt := _accum
	_accum = 0.0
	var dead := []
	var spread := []
	for id in _states:
		var e: Dictionary = _states[id]
		var body := e.body.get_ref() as Node3D
		var s: MaterialState = e.state
		if body == null or not body.is_inside_tree():
			dead.append(id)
			continue
		if s.consumed:
			continue
		if s.burning:
			s.wetness = 0.0
			s.intensity = minf(1.0, s.intensity + FIRE_GROWTH_PER_S * dt)
			s.temperature = maxf(s.temperature, s.material.ignition_temperature + 300.0 * s.intensity)
			s.fuel -= dt * s.intensity
			s.integrity -= dt * s.material.burn_damage_per_second * s.intensity
			if s.integrity < 0.5:
				s.charred = true
			spread.append([body, s.intensity])
			if s.fuel <= 0.0 or s.integrity <= 0.0:
				_burn_out(body, s)
		else:
			s.temperature = maxf(MaterialState.AMBIENT, s.temperature - s.material.cooling_per_second * dt)
			s.wetness = maxf(0.0, s.wetness - s.material.drying_per_second * dt)
	for id in dead:
		_states.erase(id)
	# Propagação: cada corpo em chamas aquece os vizinhos (não a si mesmo).
	for item in spread:
		var src: Node3D = item[0]
		if not is_instance_valid(src):
			continue
		var c := body_center(src)
		for other in bodies_in_sphere(c, SPREAD_RADIUS):
			if other == src:
				continue
			var falloff := 1.0 - clampf(body_center(other).distance_to(c) / SPREAD_RADIUS, 0.0, 1.0)
			var os := state_of(other)
			if os != null and not os.consumed and falloff > 0.0:
				_heat(other, os, SPREAD_HEAT_PER_S * item[1] * falloff * dt)


## Combustível ou integridade acabou: o corpo é consumido. Peça de estrutura sai do jogo
## pelo StructureService (o grafo de apoio derruba o que dependia dela); outros corpos somem.
func _burn_out(body: Node3D, s: MaterialState) -> void:
	s.burning = false
	s.intensity = 0.0
	s.charred = true
	s.consumed = true
	s.integrity = 0.0
	_stats.burned_out += 1
	burned_out.emit(body)
	var piece := body as StructurePiece
	if piece != null and structures != null:
		structures.consume_piece(piece, "queimada")
	else:
		body.queue_free()
