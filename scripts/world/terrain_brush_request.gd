class_name TerrainBrushRequest
extends RefCounted
## Um pedido de edição para a TerrainBrushQueue, em coordenadas do MUNDO.
## REMOVE/ADD/SMOOTH usam um ponto e um raio; PATH usa 2+ pontos (tubo) e `additive`
## escolhe escavar (túnel) ou acrescentar (rampa).

enum Op { REMOVE, ADD, PATH, SMOOTH }

const OP_NAMES := ["REMOVE", "ADD", "PATH", "SMOOTH"]

var op: Op = Op.REMOVE
var points := PackedVector3Array()
var radii := PackedFloat32Array()
## PATH: true acrescenta matéria, false escava.
var additive := false
## ADD/PATH aditivo: material da matéria nova; vazio = o que o gerador previa ali.
var material_id: StringName = &""
## -1 = pedido avulso; >= 0 = carimbo de um traço contínuo.
var stroke_id := -1
var source := ""
var enqueued_usec := 0
var applied_usec := 0
## Quantos carimbos foram fundidos neste pedido (1 = nenhum).
var merged_count := 1
## Epoch da fila: reset/save/load invalidam pedidos capturados antes da transição.
var world_epoch := -1
## Segmentos separados por perda da mira nunca podem ser fundidos em um PATH.
var segment_id := 0


static func sphere(p_op: Op, center: Vector3, radius: float, p_material: StringName = &"") -> TerrainBrushRequest:
	var r := TerrainBrushRequest.new()
	r.op = p_op
	r.points = PackedVector3Array([center])
	r.radii = PackedFloat32Array([radius])
	r.material_id = p_material
	return r


static func path(p_points: PackedVector3Array, p_radii: PackedFloat32Array, p_additive: bool,
		p_material: StringName = &"") -> TerrainBrushRequest:
	var r := TerrainBrushRequest.new()
	r.op = Op.PATH
	r.points = p_points
	r.radii = p_radii
	r.additive = p_additive
	r.material_id = p_material
	return r


func is_path() -> bool:
	return op == Op.PATH


func length() -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


func max_radius() -> float:
	var m := 0.0
	for r in radii:
		m = maxf(m, r)
	return m


## AABB nominal (sem as folgas internas do TerrainService).
func world_aabb() -> AABB:
	var box := AABB()
	for i in points.size():
		var e := Vector3.ONE * radii[i]
		var b := AABB(points[i] - e, e * 2.0)
		box = b if i == 0 else box.merge(b)
	return box


func op_name() -> String:
	if op == Op.PATH:
		return "PATH+" if additive else "PATH-"
	return OP_NAMES[op]


func _to_string() -> String:
	return "%s r=%.2f pts=%d%s" % [op_name(), max_radius(), points.size(),
		(" mat=%s" % material_id) if material_id != &"" else ""]
