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
## Material envolvido (o adicionado no ADD; o do centro no REMOVE). Vazio se não se aplica.
var material_id: StringName = &""
## Volume NOMINAL do brush (esfera/tubo), não o volume real de matéria alterada.
var est_volume_m3 := 0.0
## est_volume_m3 × densidade do material. Estimativa por brush (P1), não medição.
var est_mass_kg := 0.0


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
		var mat := (" %s ~%.0f kg" % [material_id, est_mass_kg]) if material_id != &"" else ""
		return "%s OK rev=%d %.2fms%s" % [op, revision, duration_usec / 1000.0, mat]
	return "%s RECUSADO (%s)" % [op, reason]
