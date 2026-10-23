class_name StructureService
extends Node
## Estruturas modulares apoiadas no terreno (P2): monta a torre, decide quais peças
## perderam apoio e as solta em etapas.
##
## Fluxo (pesquisa §2.3): TerrainChanged{aabb} perto dos pés → (a) âncoras lidas no SDF
## (dados, imediatos): pé inválido se < 3 dos 5 pontos sob ele são sólidos → (b) espera o
## COLLIDER confirmar o buraco sob o pé (o evento chega antes do collider, e blocos
## vizinhos atualizam em quadros diferentes; ver B5 no p1_results.md) → (c) ponto fixo do
## SupportGraph → peças sem apoio entram numa fila, de baixo para cima, soltas no máximo
## max_releases_per_frame por quadro de física.

signal piece_released(piece: StructurePiece)

@export var terrain_service_path: NodePath = ^"../TerrainService"
@export var structures_root_path: NodePath = ^"../Structures"
@export var tower_origin := Vector3(19, 0, 14)
@export var max_releases_per_frame := 6
@export var collider_confirm_timeout_s := 1.0
@export var min_solid_anchor_points := 3

var terrain_service: TerrainService

var _root: Node3D
var _tower_node: Node3D
var _pieces: Array[StructurePiece] = []
var _anchor_region := AABB()
var _dirty := false
var _pending := {}  # piece_index → {from, to, bottom, since_ms}
var _queue: Array[StructurePiece] = []
var _suspended: Array[StructurePiece] = []
var _builds := 0
var _stats := {"checks": 0, "invalid_feet": 0, "confirm_timeouts": 0, "released": 0,
	"max_released_in_frame": 0, "last_confirm_ms": 0.0, "last_check": ""}


func _ready() -> void:
	terrain_service = get_node(terrain_service_path) as TerrainService
	_root = get_node(structures_root_path) as Node3D
	terrain_service.terrain_changed.connect(_on_terrain_changed)
	build()


# --- Montagem e ciclo de vida ---------------------------------------------------------

## Monta a torre intacta (libera a anterior, se houver). Chamado no início, no reset e na carga.
func build() -> void:
	_queue.clear()
	_pending.clear()
	_suspended.clear()
	_dirty = false
	if is_instance_valid(_tower_node):
		_root.remove_child(_tower_node)
		_tower_node.free()
	_pieces = TowerFactory.build(_root, tower_origin)
	_tower_node = _root.get_child(_root.get_child_count() - 1) as Node3D
	_builds += 1
	_anchor_region = AABB()
	var first := true
	for p in _pieces:
		if p.is_foot:
			var b := p.home_box()
			var region := AABB(b.position - Vector3(0, 1.0, 0), Vector3(b.size.x, 1.2, b.size.z))
			_anchor_region = region if first else _anchor_region.merge(region)
			first = false


## Reavalia todas as âncoras (depois de carregar um slot: o terreno salvo pode ter o apoio escavado).
func check_all() -> void:
	_dirty = true


## Congela as peças já soltas (o terreno some por alguns quadros ao salvar) e lembra quais.
func suspend() -> void:
	_suspended.clear()
	for p in _pieces:
		if p.released and not p.freeze:
			p.freeze = true
			_suspended.append(p)


func resume() -> void:
	for p in _suspended:
		if is_instance_valid(p):
			p.freeze = false
	_suspended.clear()


func get_pieces() -> Array[StructurePiece]:
	return _pieces


func get_anchor_region() -> AABB:
	return _anchor_region


func released_count() -> int:
	var n := 0
	for p in _pieces:
		n += int(p.released)
	return n


func is_busy() -> bool:
	return _dirty or not _pending.is_empty() or not _queue.is_empty()


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["pieces"] = _pieces.size()
	d["released_now"] = released_count()
	d["queued"] = _queue.size()
	d["pending_confirm"] = _pending.size()
	d["builds"] = _builds
	return d


# --- Apoio -------------------------------------------------------------------------------

func _on_terrain_changed(aabb: AABB, _revision: int) -> void:
	if aabb.grow(1.0).intersects(_anchor_region):
		_dirty = true


func _physics_process(_delta: float) -> void:
	if _dirty and terrain_service.is_ready() and terrain_service.can_edit_area(_anchor_region):
		_dirty = false
		_check_anchors()
	if not _pending.is_empty():
		_confirm_colliders()
	_release_some()


func _check_anchors() -> void:
	_stats.checks += 1
	var newly := []
	for p in _pieces:
		if not p.is_foot or p.released or not p.anchor_valid:
			continue
		var solid := 0
		for q in p.anchor_points():
			if terrain_service.sample_sdf(q) < 0.0:
				solid += 1
		if solid < min_solid_anchor_points:
			p.anchor_valid = false
			newly.append(p.name)
			_stats.invalid_feet += 1
			var b := p.home_box()
			var c := Vector3(b.get_center().x, b.position.y, b.get_center().z)
			_pending[p.piece_index] = {"from": c + Vector3.UP * 0.3, "to": c + Vector3.DOWN * 1.5,
				"bottom": b.position.y, "since_ms": Time.get_ticks_msec()}
	_stats.last_check = "pés sem apoio: %s" % [newly] if not newly.is_empty() else "âncoras ok"


## Espera o collider mostrar o buraco sob cada pé invalidado (ou o prazo) antes de soltar.
func _confirm_colliders() -> void:
	var now := Time.get_ticks_msec()
	for idx in _pending.keys():
		var e: Dictionary = _pending[idx]
		var hit := terrain_service.raycast_terrain(e.from, e.to)
		var hole: bool = hit.is_empty() or hit.position.y < e.bottom - 0.3
		var late: bool = now - e.since_ms > collider_confirm_timeout_s * 1000.0
		if hole or late:
			if late and not hole:
				_stats.confirm_timeouts += 1
			_stats.last_confirm_ms = float(now - e.since_ms)
			_pending.erase(idx)
	if _pending.is_empty():
		_enqueue_unsupported()


func _enqueue_unsupported() -> void:
	var sup := SupportGraph.supported(_pieces)
	for p in _pieces:
		if sup[p.piece_index] == 0 and not p.released and not _queue.has(p):
			_queue.append(p)
	# De baixo para cima: a cascata sai em etapas e nenhuma peça cai "por cima" de outra ainda presa.
	_queue.sort_custom(func(a: StructurePiece, b: StructurePiece): return a.home_box().position.y < b.home_box().position.y)


func _release_some() -> void:
	var n := 0
	while not _queue.is_empty() and n < max_releases_per_frame:
		var p: StructurePiece = _queue.pop_front()
		if not is_instance_valid(p) or p.released:
			continue
		p.released = true
		p.freeze = false
		p.sleeping = false
		n += 1
		piece_released.emit(p)
	_stats.released += n
	_stats.max_released_in_frame = maxi(_stats.max_released_in_frame, n)
