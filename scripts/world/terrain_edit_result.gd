class_name TerrainEditResult
extends RefCounted
## Resultado de uma operação do TerrainService. `ok == true` significa que os
## DADOS voxel foram alterados; malha e colisão são reconstruídas de forma
## assíncrona nos quadros seguintes.

var ok := false
var op := ""
var reason := ""
var world_aabb := AABB()
var revision := 0
var duration_usec := 0


static func success(p_op: String, p_aabb: AABB, p_revision: int, p_usec: int) -> TerrainEditResult:
	var r := TerrainEditResult.new()
	r.ok = true
	r.op = p_op
	r.world_aabb = p_aabb
	r.revision = p_revision
	r.duration_usec = p_usec
	return r


static func failure(p_op: String, p_reason: String, p_aabb: AABB = AABB()) -> TerrainEditResult:
	var r := TerrainEditResult.new()
	r.op = p_op
	r.reason = p_reason
	r.world_aabb = p_aabb
	return r


func _to_string() -> String:
	if ok:
		return "%s OK rev=%d %.2fms" % [op, revision, duration_usec / 1000.0]
	return "%s RECUSADO (%s)" % [op, reason]
