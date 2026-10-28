class_name TerrainBrushQueue
extends Node
## Porta de entrada das edições de GAMEPLAY no terreno (P1).
##
## - Traço contínuo (segurar G/H/N): begin_stroke / update_stroke / end_stroke. Um carimbo
##   sai quando passou o intervalo temporal (escalado pela dureza do material no REMOVE)
##   E a mira andou pelo menos stroke_spacing_factor × raio. Se a mira andou mais que
##   stroke_gap_factor × raio desde o último carimbo, o carimbo vira um tubo (PATH) do
##   último ponto até a mira, para a vala não ficar com buracos. SMOOTH só exige o intervalo.
## - Orçamento por quadro de física: no máximo max_ops_per_frame operações e
##   max_aabb_volume_per_frame m³ de AABB somada; PATH cuja AABB passaria de max_aabb_extent
##   é dividido em trechos aplicados em quadros seguintes; carimbos acumulados do mesmo traço
##   são fundidos num único tubo.
## - Material: recusa com material_not_bendable se o material alvo não é dobrável.
## Nada aqui percorre voxels: cada operação é uma chamada nativa do Voxel Tools via TerrainService.

signal brush_applied(request: TerrainBrushRequest, result: TerrainEditResult)

@export var terrain_service_path: NodePath = ^"../TerrainService"

@export_group("Orçamento por quadro de física")
@export var max_ops_per_frame := 2
## Soma dos volumes das AABBs aplicadas num quadro. O 1º pedido do quadro sempre passa
## (ele já é limitado por max_aabb_extent).
@export var max_aabb_volume_per_frame := 3000.0
## Maior extensão, em qualquer eixo, da AABB de UMA operação. PATH maior é dividido.
@export var max_aabb_extent := 14.0
@export var max_pending := 64

@export_group("Traço contínuo")
## Intervalo mínimo entre carimbos de um traço; no REMOVE é multiplicado pela dureza.
@export var stroke_base_interval := 0.15
## Movimento mínimo da mira (× raio) para um novo carimbo REMOVE/ADD.
@export var stroke_spacing_factor := 0.35
## Acima disso (× raio) entre carimbos, o carimbo vira tubo do último ponto até a mira.
@export var stroke_gap_factor := 1.0
## Ao soltar a tecla, cava/adiciona do último carimbo até o último ponto mirado (P3.6; ver
## end_stroke). false = comportamento do P1–P3.5 (o fim do traço podia ficar até um intervalo curto).
@export var close_stroke_on_end := true

var terrain_service: TerrainService

var _pending: Array[TerrainBrushRequest] = []
var _strokes := {}
var _next_stroke_id := 1
var _world_epoch := 0
var _stats := {
	"enqueued": 0, "applied": 0, "rejected": 0, "dropped": 0, "cleared": 0,
	"stamps": 0, "stamps_skipped": 0, "merged": 0, "splits": 0, "strokes_closed": 0,
	"max_ops_in_frame": 0, "max_volume_in_frame": 0.0, "ops_last_frame": 0,
}
var _reject_reasons := {}
var _last_request: TerrainBrushRequest
var _last_result: TerrainEditResult
var _last_queue_delay_ms := 0.0
var _last_stroke_material: TerrainMaterial


class Stroke:
	var id := 0
	var op: TerrainBrushRequest.Op
	var radius := 1.0
	var material_id: StringName = &""
	var source := ""
	var has_stamp := false
	var last_point := Vector3.ZERO
	var last_stamp_s := 0.0
	## Último ponto mirado (com alvo), mesmo sem carimbo: end_stroke fecha o traço nele.
	var last_aim := Vector3.ZERO
	var has_aim := false
	var segment_id := 0
	## Último material sólido lido sob a mira. Mantido quando a amostra cai no ar
	## (dentro do buraco recém-escavado, antes de o collider atualizar).
	var material: TerrainMaterial


func _ready() -> void:
	# Roda depois dos controladores no mesmo quadro de física: o carimbo pedido neste
	# quadro já é aplicado neste quadro.
	process_physics_priority = 100
	terrain_service = get_node_or_null(terrain_service_path) as TerrainService
	if terrain_service != null:
		terrain_service.world_reset_started.connect(func(): clear("reset"))
		terrain_service.world_save_started.connect(func(_slot): clear("salvar"))
		terrain_service.world_load_started.connect(func(_slot): clear("carregar"))


# --- Pedidos avulsos ------------------------------------------------------------

## false se a fila está cheia (o pedido é descartado e contado).
func enqueue(request: TerrainBrushRequest) -> bool:
	if terrain_service != null and not terrain_service.is_ready():
		return false
	if request.world_epoch >= 0 and request.world_epoch != _world_epoch:
		_stats.dropped += 1
		return false
	if _pending.size() >= max_pending:
		_stats.dropped += 1
		_reject_reasons["queue_full"] = _reject_reasons.get("queue_full", 0) + 1
		return false
	request.enqueued_usec = Time.get_ticks_usec()
	request.world_epoch = _world_epoch
	_pending.append(request)
	_stats.enqueued += 1
	return true


## Cancela um pedido avulso ainda pendente, sem descartar edições de outras ferramentas.
func cancel_request(request: TerrainBrushRequest) -> void:
	_pending.erase(request)


## Pedidos de habilidade que dependem da identidade/cancelamento precisam caber inteiros.
func can_apply_unsplit(request: TerrainBrushRequest) -> bool:
	return not request.is_path() or (request.length() <= _segment_limit(request.max_radius())
		and request.points.size() <= _max_path_points())


## Esvazia a fila e encerra os traços (reset, salvar, carregar). Retorna quantos pedidos caíram.
func clear(reason := "") -> int:
	_world_epoch += 1
	var n := _pending.size()
	_pending.clear()
	_strokes.clear()
	_stats.cleared += n
	if n > 0:
		print("[TerrainBrushQueue] %d pedido(s) descartado(s): %s" % [n, reason])
	return n


# --- Traços contínuos -----------------------------------------------------------

func begin_stroke(op: TerrainBrushRequest.Op, radius: float, material_id: StringName = &"", source := "") -> int:
	assert(op != TerrainBrushRequest.Op.PATH, "traço contínuo usa REMOVE, ADD ou SMOOTH")
	var s := Stroke.new()
	s.id = _next_stroke_id
	_next_stroke_id += 1
	s.op = op
	s.radius = radius
	s.material_id = material_id
	s.source = source
	_strokes[s.id] = s
	return s.id


## Chamar a cada quadro de física enquanto o traço dura. `point` é o centro do carimbo;
## `normal` é a normal da superfície mirada (para ler o material logo abaixo dela).
func update_stroke(stroke_id: int, point: Vector3, normal: Vector3, has_target := true) -> void:
	var s: Stroke = _strokes.get(stroke_id)
	if s == null:
		return
	if not has_target:
		_close_segment(s)
		s.has_stamp = false
		s.has_aim = false
		s.segment_id += 1
		return
	s.last_aim = point
	s.has_aim = true
	var now := Time.get_ticks_usec() / 1000000.0
	if s.op == TerrainBrushRequest.Op.REMOVE:
		var sampled := sample_stroke_material(point, normal)
		if sampled != null:
			s.material = sampled
			_last_stroke_material = sampled
	if not s.has_stamp:
		_stamp(s, point, now)
		return
	if now - s.last_stamp_s < stroke_interval(s.op, s.material):
		return
	var moved := s.last_point.distance_to(point)
	if s.op != TerrainBrushRequest.Op.SMOOTH and moved < s.radius * stroke_spacing_factor:
		_stats.stamps_skipped += 1
		return
	if s.op != TerrainBrushRequest.Op.SMOOTH and moved > s.radius * stroke_gap_factor:
		var req := TerrainBrushRequest.path(PackedVector3Array([s.last_point, point]),
			PackedFloat32Array([s.radius, s.radius]), s.op == TerrainBrushRequest.Op.ADD, s.material_id)
		_enqueue_stamp(s, req, point, now)
	else:
		_stamp(s, point, now)


## Encerra o traço FECHANDO-O no último ponto mirado: o trecho andado depois do último carimbo
## (até um intervalo inteiro, ~1,5 m a 10 m/s) não era cavado ao soltar a tecla, e como os
## carimbos seguem o relógio, a sobra variava a cada rodada (T8 intermitente: fim da vala raso;
## spike P3.6 R5: 1 de 6 réplicas). SMOOTH não fecha (é por tempo, não por caminho).
func end_stroke(stroke_id: int) -> void:
	var s: Stroke = _strokes.get(stroke_id)
	_strokes.erase(stroke_id)
	_close_segment(s)


## Cancelamento descarta o resto, sem gerar o segmento final (reset e ferramenta desativada).
func cancel_stroke(stroke_id: int) -> void:
	_strokes.erase(stroke_id)


func _close_segment(s: Stroke) -> void:
	if not close_stroke_on_end or s == null or not s.has_stamp or not s.has_aim or s.op == TerrainBrushRequest.Op.SMOOTH:
		return
	var moved := s.last_point.distance_to(s.last_aim)
	if moved < 0.001:
		return
	var now := Time.get_ticks_usec() / 1000000.0
	if moved > s.radius * stroke_gap_factor:
		var req := TerrainBrushRequest.path(PackedVector3Array([s.last_point, s.last_aim]),
			PackedFloat32Array([s.radius, s.radius]), s.op == TerrainBrushRequest.Op.ADD, s.material_id)
		_enqueue_stamp(s, req, s.last_aim, now)
	else:
		_stamp(s, s.last_aim, now)
	_stats.strokes_closed += 1


func is_stroke_active(stroke_id: int) -> bool:
	return _strokes.has(stroke_id)


## Intervalo do próximo carimbo. No REMOVE, base × dureza do material (1 se desconhecido).
func stroke_interval(op: TerrainBrushRequest.Op, material: TerrainMaterial) -> float:
	if op != TerrainBrushRequest.Op.REMOVE or material == null:
		return stroke_base_interval
	return stroke_base_interval * material.hardness


## Material sólido logo abaixo da superfície mirada (dados voxel), ou null se for ar.
func sample_stroke_material(point: Vector3, normal: Vector3) -> TerrainMaterial:
	if terrain_service == null:
		return null
	var mat := terrain_service.get_material_at(point - normal.normalized() * 0.5)
	return mat if mat != null else terrain_service.get_material_at(point)


## Regra de material isolada (testável sem pintar um material não dobrável no mundo).
static func material_policy(op: TerrainBrushRequest.Op, target: TerrainMaterial) -> String:
	if target != null and not target.bendable:
		return "material_not_bendable"
	return ""


# --- Estado -----------------------------------------------------------------------

func pending_count() -> int:
	return _pending.size()


func active_stroke_count() -> int:
	return _strokes.size()


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["pending"] = _pending.size()
	d["active_strokes"] = _strokes.size()
	d["reject_reasons"] = _reject_reasons.duplicate()
	d["last_request"] = str(_last_request) if _last_request != null else ""
	d["last_result"] = str(_last_result) if _last_result != null else ""
	d["last_queue_delay_ms"] = _last_queue_delay_ms
	return d


func get_last_request() -> TerrainBrushRequest:
	return _last_request


func get_last_result() -> TerrainEditResult:
	return _last_result


func reset_frame_peaks() -> void:
	_stats.max_ops_in_frame = 0
	_stats.max_volume_in_frame = 0.0


# --- Processamento ----------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	var ops := 0
	var volume := 0.0
	while not _pending.is_empty() and ops < max_ops_per_frame:
		_merge_backlog()
		var parts := _split_head(_pending[0])
		var head: TerrainBrushRequest = parts[0]
		var vol := head.world_aabb().get_volume()
		if ops > 0 and volume + vol > max_aabb_volume_per_frame:
			break
		_pending.pop_front()
		if parts[1] != null:
			_pending.push_front(parts[1])
			_stats.splits += 1
		var result := _apply(head)
		if not result.ok and result.reason == "frame_budget_exceeded":
			# Outro sistema gastou o orçamento do TerrainService neste quadro: tenta no próximo.
			_pending.push_front(head)
			break
		ops += 1
		volume += vol
	_stats.ops_last_frame = ops
	_stats.max_ops_in_frame = maxi(_stats.max_ops_in_frame, ops)
	_stats.max_volume_in_frame = maxf(_stats.max_volume_in_frame, volume)


func _apply(req: TerrainBrushRequest) -> TerrainEditResult:
	if req.world_epoch != _world_epoch:
		return TerrainEditResult.failure(req.op_name(), "stale_world_epoch")
	var result: TerrainEditResult
	var reason := _check_policy(req)
	if terrain_service == null:
		result = TerrainEditResult.failure(req.op_name(), "no_terrain_service")
	elif reason != "":
		result = TerrainEditResult.failure(req.op_name(), reason, req.world_aabb())
	else:
		var p := req.points[0]
		var r := req.radii[0]
		if req.op == TerrainBrushRequest.Op.REMOVE:
			result = terrain_service.dig_sphere(p, r)
		elif req.op == TerrainBrushRequest.Op.ADD:
			result = terrain_service.add_sphere(p, r, req.material_id)
		elif req.op == TerrainBrushRequest.Op.SMOOTH:
			result = terrain_service.smooth_area(p, r)
		elif req.additive:
			result = terrain_service.add_path(req.points, req.radii, req.material_id)
		else:
			result = terrain_service.dig_path(req.points, req.radii)
	if not result.ok and result.reason == "frame_budget_exceeded":
		return result
	req.applied_usec = Time.get_ticks_usec()
	_last_queue_delay_ms = (req.applied_usec - req.enqueued_usec) / 1000.0
	_last_request = req
	_last_result = result
	if result.ok:
		_stats.applied += 1
	else:
		_note_reject(req, result)
	brush_applied.emit(req, result)
	return result


func _check_policy(req: TerrainBrushRequest) -> String:
	if terrain_service == null:
		return ""
	var target: TerrainMaterial
	var adds := req.op == TerrainBrushRequest.Op.ADD or (req.is_path() and req.additive)
	if adds and req.material_id != &"":
		target = TerrainMaterialLibrary.get_by_id(req.material_id)
	else:
		target = terrain_service.get_material_at(req.points[0])
	return material_policy(req.op, target)


## Funde carimbos REMOVE/ADD consecutivos do MESMO traço (fila acumulada) num tubo.
func _merge_backlog() -> void:
	var head := _pending[0]
	if head.stroke_id < 0 or head.is_path() or head.op == TerrainBrushRequest.Op.SMOOTH:
		return
	var limit := _segment_limit(head.radii[0])
	var pts := PackedVector3Array([head.points[0]])
	var length := 0.0
	var i := 1
	while i < _pending.size():
		var nxt := _pending[i]
		if nxt.stroke_id != head.stroke_id or nxt.segment_id != head.segment_id or nxt.world_epoch != head.world_epoch or nxt.op != head.op or nxt.is_path() \
				or nxt.material_id != head.material_id or not is_equal_approx(nxt.radii[0], head.radii[0]):
			break
		var step := pts[-1].distance_to(nxt.points[0])
		if length + step > limit or pts.size() >= _max_path_points():
			break
		length += step
		pts.append(nxt.points[0])
		i += 1
	if pts.size() < 2:
		return
	var radii := PackedFloat32Array()
	radii.resize(pts.size())
	radii.fill(head.radii[0])
	var merged := TerrainBrushRequest.path(pts, radii, head.op == TerrainBrushRequest.Op.ADD, head.material_id)
	merged.stroke_id = head.stroke_id
	merged.segment_id = head.segment_id
	merged.world_epoch = head.world_epoch
	merged.source = head.source
	merged.enqueued_usec = head.enqueued_usec
	merged.merged_count = pts.size()
	for k in i:
		_pending.pop_front()
	_pending.push_front(merged)
	_stats.merged += pts.size() - 1


## [cabeça, resto]: resto != null quando o PATH foi cortado no comprimento máximo do trecho.
func _split_head(req: TerrainBrushRequest) -> Array:
	if not req.is_path():
		return [req, null]
	var limit := _segment_limit(req.max_radius())
	var max_pts := _max_path_points()
	if can_apply_unsplit(req):
		return [req, null]
	var head_pts := PackedVector3Array([req.points[0]])
	var head_radii := PackedFloat32Array([req.radii[0]])
	var acc := 0.0
	var i := 1
	var cut_point := Vector3.ZERO
	var cut_radius := 0.0
	var cut := false
	while i < req.points.size():
		var a := req.points[i - 1]
		var b := req.points[i]
		var seg := a.distance_to(b)
		if acc + seg > limit or head_pts.size() >= max_pts:
			var t := clampf((limit - acc) / maxf(seg, 1e-4), 0.0, 1.0) if acc + seg > limit else 0.0
			cut_point = a.lerp(b, t)
			cut_radius = lerpf(req.radii[i - 1], req.radii[i], t)
			cut = true
			break
		acc += seg
		head_pts.append(b)
		head_radii.append(req.radii[i])
		i += 1
	if not cut:
		return [req, null]
	if cut_point.distance_to(head_pts[-1]) > 1e-3:
		head_pts.append(cut_point)
		head_radii.append(cut_radius)
	var tail_pts := PackedVector3Array([head_pts[-1]])
	var tail_radii := PackedFloat32Array([head_radii[-1]])
	for k in range(i, req.points.size()):
		tail_pts.append(req.points[k])
		tail_radii.append(req.radii[k])
	var head := _derive(req, head_pts, head_radii)
	var tail := _derive(req, tail_pts, tail_radii) if tail_pts.size() >= 2 else null
	return [head, tail]


func _derive(src: TerrainBrushRequest, pts: PackedVector3Array, radii: PackedFloat32Array) -> TerrainBrushRequest:
	var r := TerrainBrushRequest.path(pts, radii, src.additive, src.material_id)
	r.stroke_id = src.stroke_id
	r.segment_id = src.segment_id
	r.world_epoch = src.world_epoch
	r.source = src.source
	r.enqueued_usec = src.enqueued_usec
	r.merged_count = src.merged_count
	return r


func _max_path_points() -> int:
	return terrain_service.max_path_points if terrain_service != null else 32


## Comprimento máximo de um trecho de tubo para a AABB caber em max_aabb_extent.
func _segment_limit(radius: float) -> float:
	return maxf(1.0, max_aabb_extent - 2.0 * radius)


func _stamp(s: Stroke, point: Vector3, now: float) -> void:
	_enqueue_stamp(s, TerrainBrushRequest.sphere(s.op, point, s.radius, s.material_id), point, now)


func _enqueue_stamp(s: Stroke, req: TerrainBrushRequest, point: Vector3, now: float) -> void:
	req.stroke_id = s.id
	req.segment_id = s.segment_id
	req.source = s.source
	if enqueue(req):
		_stats.stamps += 1
	s.has_stamp = true
	s.last_point = point
	s.last_stamp_s = now


func _note_reject(req: TerrainBrushRequest, result: TerrainEditResult) -> void:
	_stats.rejected += 1
	_reject_reasons[result.reason] = _reject_reasons.get(result.reason, 0) + 1
	_last_request = req
	_last_result = result


func get_last_stroke_material() -> TerrainMaterial:
	return _last_stroke_material
