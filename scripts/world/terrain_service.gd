class_name TerrainService
extends Node
## Único ponto do jogo que conhece o Voxel Tools.
##
## API pública em coordenadas do MUNDO; a conversão para o espaço local do
## terreno é interna. Cada operação valida entrada, limites e área carregada
## (VoxelTool.is_area_editable) antes de tocar nos dados. Edição altera os
## dados imediatamente; malha e colisão são reconstruídas assincronamente pelo
## motor voxel. Use raycast_terrain() (física) para saber o que o jogador
## realmente colide.
##
## Persistência (P1): o terreno vivo usa um VoxelStreamSQLite num arquivo de SESSÃO
## novo a cada recriação (TerrainSaveFiles). Salvar = save_modified_blocks → esperar o
## tracker → liberar o nó → fechar o stream → copiar a sessão para o slot → reabrir a
## mesma sessão. Carregar = copiar o slot para uma sessão nova e recriar o nó. Reset =
## sessão nova e vazia (só o gerador). O slot fica intacto no reset.

signal terrain_ready
## Evento TerrainChanged {aabb, revision}: emitido quando os DADOS mudaram. Malha e
## collider da região ainda NÃO refletem a edição neste momento (atualizam em quadros seguintes).
signal terrain_changed(world_aabb: AABB, revision: int)
signal edit_rejected(op: String, reason: String, world_aabb: AABB)
signal world_reset_started
signal world_reset_finished(world_generation: int, duration_ms: float)
signal world_save_started(slot: String)
signal world_saved(slot: String, ok: bool, duration_ms: float)
signal world_load_started(slot: String)
signal world_loaded(slot: String, ok: bool, duration_ms: float)

## Nó onde o VoxelLodTerrain é instanciado (e recriado no reset).
@export var terrain_parent_path: NodePath = ^"../TerrainRoot"
## Corpo que não pode ficar preso dentro de matéria adicionada.
@export var protected_body_path: NodePath
## Centro da região que precisa estar pronta (malha + colisão) após carga/reset.
@export var ready_probe_point := Vector3(0, 0, 28)
@export var ready_timeout_s := 30.0

@export_group("Limites de edição")
@export var min_radius := 0.5
@export var max_radius := 6.0
@export var max_path_length := 60.0
@export var max_path_points := 32
## smooth_sphere desfoca uma caixa inteira; raio menor que o de ADD/REMOVE limita o custo.
@export var max_smooth_radius := 4.0
## Extração de rocha (P2): com r = 1 o casco convexo sai grosseiro (10 pontos no spike; r = 1,5
## deu 34). O máximo mantém a caixa de separate_floating_chunks bem abaixo de ~30 voxels.
@export var min_extract_radius := 1.0
@export var max_extract_radius := 2.0
## Folga entre o núcleo e a parede da cavidade.
@export var extract_gap := 0.9
## Orçamento de operações por quadro de física, para evitar rajadas de edição.
@export var max_edits_per_physics_frame := 4
## Folga somada ao raio de REMOÇÃO. Sem ela, remover exatamente a mesma esfera
## que foi adicionada deixa voxels com SDF == 0 na fronteira coincidente
## (max(atual, -esfera) = 0), que o Transvoxel transforma numa película sólida de
## espessura zero, com colisão. Diagnóstico em docs/voxel_spike_results.md.
@export var remove_radius_padding := 0.05
## O ADD com material pinta o canal INDICES num raio um pouco maior que o da matéria,
## para a superfície nova ler 100% o material (o mesher mistura os voxels de cada célula,
## inclusive os de ar logo fora da esfera). Matéria existente nessa faixa troca de material.
@export var material_paint_margin := 0.5
@export var verbose := true

@export_group("Persistência")
## false = sem stream: edições só em memória (comportamento do P0).
@export var persistence_enabled := true
@export var world_dir := "user://world"
@export var saves_dir := "user://saves"
@export var save_timeout_s := 15.0

var _terrain: VoxelLodTerrain
var _tool: VoxelTool
var _stream: VoxelStreamSQLite
## Tracker de um save abortado que ainda grava em segundo plano (ver _flush_modified_blocks).
var _inflight_tracker: VoxelSaveCompletionTracker
var _session_index := 0
var _session_path := ""
var _stale_sessions := PackedStringArray()
var _busy_op := ""
var _last_save := {}
var _last_load := {}
var _ready_flag := false
var _resetting := false
var _revision := 0
var _world_generation := 0
var _edit_count := 0
var _reject_count := 0
var _budget_frame := -1
var _budget_used := 0
var _last_ready_ms := 0.0


func _ready() -> void:
	if persistence_enabled:
		# Sessões de execuções anteriores (fechadas) são lixo; as de outro processo aberto
		# continuam travadas pelo Windows e a remoção só falha.
		for path in TerrainSaveFiles.list_sessions(world_dir):
			TerrainSaveFiles.remove(path)
	_spawn_terrain()
	_world_generation = 1
	var t0 := Time.get_ticks_msec()
	var ok := await _wait_until_ready()
	_last_ready_ms = Time.get_ticks_msec() - t0
	_log("terreno inicial pronto=%s em %d ms" % [ok, _last_ready_ms])
	if ok:
		terrain_ready.emit()


# --- Estado -------------------------------------------------------------------

func is_ready() -> bool:
	return _ready_flag and not _resetting and is_instance_valid(_terrain)


## true enquanto o terreno está sendo recriado (reset, salvar ou carregar).
func is_resetting() -> bool:
	return _resetting


## "reset", "save", "load" ou "" (livre).
func get_busy_op() -> String:
	return _busy_op


func has_saved_world(slot: String) -> bool:
	return TerrainSaveFiles.is_valid_slot(slot) and TerrainSaveFiles.exists(TerrainSaveFiles.slot_path(saves_dir, slot))


func get_slot_path(slot: String) -> String:
	return TerrainSaveFiles.slot_path(saves_dir, slot)


func get_session_path() -> String:
	return _session_path


func count_session_files() -> int:
	return TerrainSaveFiles.list_sessions(world_dir).size()


func get_revision() -> int:
	return _revision


func get_world_generation() -> int:
	return _world_generation


func get_last_ready_ms() -> float:
	return _last_ready_ms


## Só para depuração/testes. Gameplay deve usar a API deste serviço.
func get_terrain_node() -> VoxelLodTerrain:
	return _terrain


func get_debug_stats() -> Dictionary:
	return {
		"ready": is_ready(),
		"resetting": _resetting,
		"busy_op": _busy_op,
		"revision": _revision,
		"world_generation": _world_generation,
		"edits": _edit_count,
		"rejects": _reject_count,
		"persistence": persistence_enabled,
		"session_file": _session_path.get_file(),
		"session_files": count_session_files() if persistence_enabled else 0,
		"last_save": _last_save,
		"last_load": _last_load,
	}


# --- Consultas ----------------------------------------------------------------

func can_edit_area(world_aabb: AABB) -> bool:
	return _validate_area(world_aabb) == ""


## Raycast contra os colliders do terreno (o que a física enxerga agora).
## Retorna o dicionário de intersect_ray ou {} se não acertou.
func raycast_terrain(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_viewport().get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.TERRAIN)
	query.collide_with_areas = false
	query.hit_back_faces = false
	return PhysicsRayHelper.intersect(world.direct_space_state, query)


## Valor SDF dos DADOS (negativo = sólido). Não reflete a colisão.
func sample_sdf(world_point: Vector3) -> float:
	if not is_ready():
		return NAN
	var local := _terrain.to_local(world_point)
	return _tool.get_voxel_f(Vector3i(local.round()))


## Material do voxel mais próximo, lido dos DADOS (canal INDICES). null se o voxel é ar
## ou o terreno não está pronto. Para um ponto de raycast na superfície, passe um ponto
## um pouco para dentro (ponto − normal × 0,5).
func get_material_at(world_point: Vector3) -> TerrainMaterial:
	if not is_ready() or not _is_finite_vec(world_point):
		return null
	var local := _terrain.to_local(world_point)
	var voxel := Vector3i(local.round())
	if not _terrain.voxel_bounds.has_point(Vector3(voxel)) or not _tool.is_area_editable(AABB(Vector3(voxel), Vector3.ONE)):
		return null
	if _tool.get_voxel_f(voxel) > 0.0:
		return null
	return TerrainMaterialLibrary.get_by_index(_material_index_local(local))


## Índice cru do canal INDICES (inclui voxels de ar). Só para depuração e testes.
func sample_material_index(world_point: Vector3) -> int:
	if not is_ready():
		return -1
	return _material_index_local(_terrain.to_local(world_point))


# --- Edição -------------------------------------------------------------------

func dig_sphere(world_point: Vector3, radius: float) -> TerrainEditResult:
	return _sphere_op("dig_sphere", VoxelTool.MODE_REMOVE, world_point, radius)


## `material_id` vazio = a matéria nova fica com o material que o gerador previa ali.
func add_sphere(world_point: Vector3, radius: float, material_id: StringName = &"") -> TerrainEditResult:
	return _sphere_op("add_sphere", VoxelTool.MODE_ADD, world_point, radius, material_id)


## Escava um tubo passando pelos pontos (ligação linear), raio por ponto.
func dig_path(world_points: PackedVector3Array, radii: PackedFloat32Array) -> TerrainEditResult:
	return _path_op("dig_path", VoxelTool.MODE_REMOVE, world_points, radii)


## Acrescenta um tubo de matéria pelos pontos (rampa, ponte). `material_id` vazio = material
## que o gerador previa ali. Recusa se o tubo prender o corpo protegido.
func add_path(world_points: PackedVector3Array, radii: PackedFloat32Array,
		material_id: StringName = &"") -> TerrainEditResult:
	return _path_op("add_path", VoxelTool.MODE_ADD, world_points, radii, material_id)


## Suaviza o SDF numa esfera (VoxelTool.smooth_sphere, desfoque de `blur_voxels`).
## Não cria nem pinta material; arredonda quinas e degraus.
func smooth_area(world_point: Vector3, radius: float, blur_voxels := 2) -> TerrainEditResult:
	const OP := "smooth_area"
	var t0 := Time.get_ticks_usec()
	if not _is_finite_vec(world_point) or not is_finite(radius):
		return _reject(OP, "invalid_input")
	if radius < min_radius or radius > max_smooth_radius or blur_voxels < 1 or blur_voxels > 4:
		return _reject(OP, "radius_out_of_range")
	# O desfoque lê vizinhos até blur_voxels fora da esfera.
	var extent := radius + blur_voxels
	var aabb := AABB(world_point - Vector3.ONE * extent, Vector3.ONE * extent * 2.0)
	var reason := _validate_area(aabb)
	if reason != "":
		return _reject(OP, reason, aabb)
	if not _consume_budget():
		return _reject(OP, "frame_budget_exceeded", aabb)
	var local := _terrain.to_local(world_point)
	var mat := TerrainMaterialLibrary.get_by_index(_material_index_local(local))
	_tool.channel = VoxelBuffer.CHANNEL_SDF
	_tool.smooth_sphere(local, radius, blur_voxels)
	var result := _commit(OP, aabb, t0, "c=%s r=%.2f blur=%d" % [_fmt(world_point), radius, blur_voxels])
	# Suavizar só redistribui matéria: sem massa estimada.
	_set_estimate(result, mat, 0.0)
	return result


## Extrai uma rocha do terreno (P2, laboratório): o núcleo de raio `core_radius` logo
## abaixo de `world_point` (encostado na superfície, ao longo de −normal) vira um
## RigidBody3D convexo de verdade, filho de `parent`. Como: cavidade em volta do núcleo
## (REMOVE), núcleo recriado com o material que estava ali (ADD + INDICES) e
## VoxelToolLodTerrain.separate_floating_chunks numa caixa ≤ 30 voxels (spike P2, F1/F3).
## O Voxel Tools cria o corpo na camada/máscara 1 (as do terreno), com massa 1 kg e malha
## sem material: aqui ele vai para PROPS, recebe massa = volume da malha × densidade e a cor
## do material.
## A cavidade esférica em volta do núcleo tem boca mais estreita que ela (r = 1,5: boca de
## ~1,9 m de raio para uma rocha de ~1,3 m de meia-largura), então a rocha ficaria presa no
## fundo (medido no T24). Com `place_dir` horizontal, a rocha é posicionada UMA vez, ainda
## cinemática, sobre o chão ao lado do buraco nessa direção; com Vector3.ZERO fica no buraco.
## Com `hold_kinematic`, o Timer que o Voxel Tools cria para descongelar o corpo em 0,2 s é
## parado: o corpo fica congelado até quem chamou descongelar (P3.5, Terra: desprendimento;
## spike P3.5 E1).
## Retorna {"result": TerrainEditResult, "bodies": Array[RigidBody3D]}.
func extract_rock(world_point: Vector3, normal: Vector3, core_radius: float, parent: Node,
		place_dir := Vector3.ZERO, hold_kinematic := false) -> Dictionary:
	const OP := "extract_rock"
	var t0 := Time.get_ticks_usec()
	var out := {"result": null, "bodies": []}
	if parent == null:
		out.result = _reject(OP, "invalid_input")
		return out
	var check := _check_extract(world_point, normal, core_radius)
	var aabb: AABB = check.aabb
	if check.reason != "":
		out.result = _reject(OP, check.reason, aabb)
		return out
	var center: Vector3 = check.center
	var cavity: float = check.cavity
	var local: Vector3 = check.local
	var mat: TerrainMaterial = check.mat
	if not _consume_budget():
		out.result = _reject(OP, "frame_budget_exceeded", aabb)
		return out
	_tool.mode = VoxelTool.MODE_REMOVE
	_tool.do_sphere(local, cavity)
	_tool.mode = VoxelTool.MODE_ADD
	_tool.do_sphere(local, core_radius)
	if mat != null:
		_paint_sphere(local, core_radius + material_paint_margin, mat.index)
	var half := Vector3.ONE * (cavity + 1.0)
	var lod_tool := _tool as VoxelToolLodTerrain
	var bodies: Array = lod_tool.separate_floating_chunks(AABB(local - half, half * 2.0), parent)
	var total_volume := 0.0
	for b in bodies:
		var rb := b as RigidBody3D
		if rb == null:
			continue
		rb.name = "Rock"
		rb.collision_layer = Layers.PROPS
		rb.collision_mask = Layers.TERRAIN | Layers.PLAYER | Layers.PROPS
		var volume := 0.0
		for ch in rb.get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
				volume = _mesh_volume((ch as MeshInstance3D).mesh)
				if mat != null:
					var m := StandardMaterial3D.new()
					m.albedo_color = mat.surface_color
					m.roughness = 0.95
					(ch as MeshInstance3D).material_override = m
		rb.mass = maxf(volume * (mat.density if mat != null else 1500.0), 1.0)
		rb.set_meta("material_id", mat.id if mat != null else &"")
		rb.set_meta("volume_m3", volume)
		rb.add_to_group(DebrisBudget.GROUP)
		total_volume += volume
		out.bodies.append(rb)
		if hold_kinematic:
			for ch in rb.get_children():
				if ch is Timer:
					(ch as Timer).stop()
		var flat := Vector3(place_dir.x, 0.0, place_dir.z)
		if flat.length() > 0.01:
			_place_beside_hole(rb, world_point, flat.normalized(), cavity)
	var result := _commit(OP, aabb, t0, "c=%s r=%.2f corpos=%d" % [_fmt(center), core_radius, bodies.size()])
	_set_estimate(result, mat, total_volume)
	out.result = result
	return out


## As mesmas checagens do extract_rock, sem editar nada: "" se a extração seria aceita agora,
## senão o motivo (a Terra valida o alvo no clique, antes da antecipação; P3.5).
func can_extract_rock(world_point: Vector3, normal: Vector3, core_radius: float) -> String:
	return _check_extract(world_point, normal, core_radius).reason


## O collider já mostra a cavidade aberta em `world_point` (boca do buraco)? Raio vertical no
## centro chega mais de `depth` abaixo da boca. O collider do terreno é uma casca: uma consulta
## de forma não detecta uma rocha dentro do sólido (spike P3.5 E1/E2).
func cavity_confirmed(world_point: Vector3, depth := 1.0) -> bool:
	var hit := raycast_terrain(world_point + Vector3.UP * 1.0, world_point + Vector3.DOWN * (depth + 6.0))
	return not hit.is_empty() and hit.position.y < world_point.y - depth


func _check_extract(world_point: Vector3, normal: Vector3, core_radius: float) -> Dictionary:
	var out := {"reason": "", "aabb": AABB(), "center": Vector3.ZERO, "cavity": 0.0, "local": Vector3.ZERO, "mat": null}
	if not _is_finite_vec(world_point) or not _is_finite_vec(normal) or normal.length() < 0.5:
		out.reason = "invalid_input"
		return out
	if core_radius < min_extract_radius or core_radius > max_extract_radius:
		out.reason = "radius_out_of_range"
		return out
	var center := world_point - normal.normalized() * core_radius
	# Centro no MEIO do voxel: a folga (0,9 m) é menor que um voxel, e com o centro em certas
	# posições sub-voxel a cavidade deixava uma ponte e o núcleo não se separava (cavidade aberta,
	# 0 corpos: 4 de 36 posições no spike P3.5 E5). Alinhado, a rasterização é sempre a mesma.
	if _terrain != null:
		center = _terrain.to_global(_terrain.to_local(center).floor() + Vector3.ONE * 0.5)
	var cavity := core_radius + extract_gap + remove_radius_padding
	out.center = center
	out.cavity = cavity
	out.aabb = AABB(center - Vector3.ONE * (cavity + material_paint_margin), Vector3.ONE * (cavity + material_paint_margin) * 2.0)
	out.reason = _validate_area(out.aabb)
	if out.reason != "":
		return out
	var local := _terrain.to_local(center)
	out.local = local
	if _tool.get_voxel_f(Vector3i(local.round())) > 0.0:
		out.reason = "no_solid_core"
		return out
	var mat := TerrainMaterialLibrary.get_by_index(_material_index_local(local))
	out.mat = mat
	var policy := TerrainBrushQueue.material_policy(TerrainBrushRequest.Op.REMOVE, mat)
	if policy != "":
		out.reason = policy
		return out
	if _overlaps_protected_body(center, cavity):
		out.reason = "overlaps_player"
	return out


## Move a rocha recém-criada (ainda cinemática) para cima do chão, ao lado da boca do buraco.
func _place_beside_hole(rb: RigidBody3D, hole: Vector3, dir: Vector3, cavity: float) -> void:
	var box := AABB()
	for ch in rb.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			box = mi.global_transform * mi.mesh.get_aabb()
	if not box.has_volume():
		return
	var half := maxf(box.size.x, box.size.z) * 0.5
	var target := hole + dir * (cavity + half + 0.5)
	var hit := raycast_terrain(Vector3(target.x, target.y + 20.0, target.z), Vector3(target.x, target.y - 20.0, target.z))
	if hit.is_empty():
		return
	var center := box.get_center()
	var delta := Vector3(target.x - center.x, hit.position.y + 0.2 - box.position.y, target.z - center.z)
	rb.global_position += delta


## Volume de uma malha fechada (soma de tetraedros com a origem), em m³.
static func _mesh_volume(mesh: Mesh) -> float:
	var total := 0.0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := idx.size() if not idx.is_empty() else v.size()
		for i in range(0, n - 2, 3):
			var a := v[idx[i]] if not idx.is_empty() else v[i]
			var b := v[idx[i + 1]] if not idx.is_empty() else v[i + 1]
			var c := v[idx[i + 2]] if not idx.is_empty() else v[i + 2]
			total += a.dot(b.cross(c)) / 6.0
	return absf(total)


## Recria o terreno a partir do gerador, descartando TODAS as edições:
## dados voxel, malhas e colliders do nó antigo são liberados com ele.
## Aguarda a região de ready_probe_point ter malha e colisão de novo.
## Com persistência, o terreno novo usa uma sessão nova e vazia; a sessão descartada
## é apagada (o slot salvo não é tocado).
func reset_world() -> bool:
	if _resetting:
		return false
	_begin_busy("reset")
	world_reset_started.emit()
	var t0 := Time.get_ticks_msec()
	_log("reset: liberando VoxelLodTerrain (geração %d, rev %d)" % [_world_generation, _revision])
	var old_session := _session_path
	await _release_terrain()
	_discard_session(old_session)
	_spawn_terrain()
	_world_generation += 1
	var ok := await _wait_until_ready()
	_last_ready_ms = Time.get_ticks_msec() - t0
	_end_busy()
	_log("reset: geração %d pronta=%s em %d ms" % [_world_generation, ok, _last_ready_ms])
	world_reset_finished.emit(_world_generation, _last_ready_ms)
	return ok


## Grava todas as edições no slot. O terreno é liberado e recriado a partir da mesma
## sessão (o mundo volta do disco), então o jogador deve ficar congelado durante a chamada.
func save_world(slot: String) -> bool:
	if _resetting or not persistence_enabled or not TerrainSaveFiles.is_valid_slot(slot):
		_last_save = {"slot": slot, "ok": false, "reason": "busy" if _resetting else "unavailable"}
		world_saved.emit(slot, false, 0.0)
		return false
	_begin_busy("save")
	world_save_started.emit(slot)
	var t0 := Time.get_ticks_msec()
	var session := _session_path
	var dst := TerrainSaveFiles.slot_path(saves_dir, slot)
	var flushed: Dictionary = await _flush_modified_blocks()
	if not flushed.saved:
		# Sem a gravação completa, liberar o nó perderia as edições: aborta e mantém o terreno.
		_last_save = {"slot": slot, "ok": false, "reason": "flush_incomplete", "flush_ms": flushed.ms,
			"blocks_tasks": flushed.tasks}
		_ready_flag = true
		_end_busy()
		_log("save %s ABORTADO: %s" % [slot, _last_save])
		world_saved.emit(slot, false, float(Time.get_ticks_msec() - t0))
		return false
	await _release_terrain()
	TerrainSaveFiles.ensure_dir(saves_dir)
	var copy_err := TerrainSaveFiles.copy(session, dst)
	_spawn_terrain(session)
	var ready := await _wait_until_ready()
	var ms := float(Time.get_ticks_msec() - t0)
	var ok: bool = copy_err == OK and ready
	_last_save = {"slot": slot, "ok": ok, "ms": ms, "flush_ms": flushed.ms, "blocks_tasks": flushed.tasks,
		"save_anterior_em_voo": flushed.inflight, "copy": error_string(copy_err),
		"bytes": TerrainSaveFiles.file_size(dst), "path": dst}
	_last_ready_ms = ms
	_end_busy()
	_log("save %s: ok=%s %s" % [slot, ok, _last_save])
	world_saved.emit(slot, ok, ms)
	return ok


## Substitui o mundo atual pelo slot salvo (sessão nova copiada do slot).
func load_world(slot: String) -> bool:
	if _resetting or not persistence_enabled or not has_saved_world(slot):
		_last_load = {"slot": slot, "ok": false,
			"reason": "busy" if _resetting else ("slot_not_found" if persistence_enabled else "unavailable")}
		world_loaded.emit(slot, false, 0.0)
		return false
	_begin_busy("load")
	world_load_started.emit(slot)
	var t0 := Time.get_ticks_msec()
	var old_session := _session_path
	await _release_terrain()
	_discard_session(old_session)
	var session := _new_session_path()
	var src := TerrainSaveFiles.slot_path(saves_dir, slot)
	var copy_err := TerrainSaveFiles.copy(src, session)
	_spawn_terrain(session)
	_world_generation += 1
	var ready := await _wait_until_ready()
	var ms := float(Time.get_ticks_msec() - t0)
	var ok := copy_err == OK and ready
	_last_load = {"slot": slot, "ok": ok, "ms": ms, "copy": error_string(copy_err),
		"bytes": TerrainSaveFiles.file_size(src)}
	_last_ready_ms = ms
	_end_busy()
	_log("load %s: ok=%s %s" % [slot, ok, _last_load])
	world_loaded.emit(slot, ok, ms)
	return ok


# --- Internos -----------------------------------------------------------------

## `session_path` vazio = sessão nova. Sem persistência, terreno sem stream.
func _spawn_terrain(session_path := "") -> void:
	var parent := get_node(terrain_parent_path) as Node3D
	assert(parent != null, "TerrainService: terrain_parent_path inválido")
	_stream = null
	if persistence_enabled:
		TerrainSaveFiles.ensure_dir(world_dir)
		_session_path = session_path if session_path != "" else _new_session_path()
		_stream = VoxelStreamSQLite.new()
		# Cache das chaves existentes no banco: blocos nunca salvos vão direto ao gerador sem
		# consulta SQL. Medido: reset médio 581 → ~260 ms (docs/p1_results.md).
		_stream.set_key_cache_enabled(true)
		_stream.database_path = _session_path
	_terrain = LabTerrainFactory.create_terrain(_stream)
	parent.add_child(_terrain)
	# API pública em coordenadas do mundo assume escala 1 (1 voxel = 1 unidade).
	assert(_terrain.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE))
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_SDF


func _new_session_path() -> String:
	_session_index += 1
	return TerrainSaveFiles.session_path(world_dir, _session_index)


## Grava os blocos modificados no stream e espera o VoxelSaveCompletionTracker.
## Liberar o nó SEM isto não grava as edições (conferido no spike, I1).
func _flush_modified_blocks() -> Dictionary:
	var info := {"saved": false, "tasks": 0, "ms": 0.0, "inflight": "nenhum"}
	if not is_instance_valid(_terrain) or _stream == null:
		return info
	var t0 := Time.get_ticks_msec()
	var deadline := t0 + int(save_timeout_s * 1000.0)
	# Um save abortado continua gravando em segundo plano, e os blocos dele já não contam
	# como modificados: sem esperar por ele, este save veria "nada a gravar", fecharia o
	# stream e as gravações em voo falhariam.
	if _inflight_tracker != null:
		info.inflight = "já concluído" if _inflight_tracker.is_complete() else "esperado"
		while not _inflight_tracker.is_complete() and Time.get_ticks_msec() < deadline:
			await get_tree().physics_frame
		info["inflight_wait_ms"] = float(Time.get_ticks_msec() - t0)
		if not _inflight_tracker.is_complete():
			info.ms = float(Time.get_ticks_msec() - t0)
			_log("save anterior ainda gravando após %.1f s" % save_timeout_s)
			return info
		_inflight_tracker = null
	var tracker: VoxelSaveCompletionTracker = _terrain.save_modified_blocks()
	while not tracker.is_complete() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	info.saved = tracker.is_complete() and not tracker.is_aborted()
	info.tasks = tracker.get_total_tasks()
	info.ms = float(Time.get_ticks_msec() - t0)
	if not tracker.is_complete():
		_inflight_tracker = tracker
	if not info.saved:
		# Relatado por world_saved(ok=false) e no overlay; o save é abortado sem perda de dados.
		_log("save_modified_blocks não concluiu em %.1f s: restantes=%d abortado=%s" % [
			save_timeout_s, tracker.get_remaining_tasks(), tracker.is_aborted()])
	return info


## Libera o nó do terreno (descartando edições não gravadas) e fecha o stream.
func _release_terrain() -> void:
	if is_instance_valid(_terrain):
		_terrain.get_parent().remove_child(_terrain)
		_terrain.free()
	_terrain = null
	_tool = null
	await get_tree().physics_frame
	if _stream != null:
		# database_path vazio fecha o SQLite (doc do Voxel Tools, "streams").
		_stream.database_path = ""
		_stream = null
	_session_path = ""
	# Gravações pendentes de um save abortado iam para a sessão que acabou de ser fechada.
	_inflight_tracker = null


## Apaga uma sessão já fechada; se o Windows ainda a travar, tenta de novo depois.
func _discard_session(path: String) -> void:
	if path != "":
		_stale_sessions.append(path)
	var keep := PackedStringArray()
	for p in _stale_sessions:
		if p != _session_path and TerrainSaveFiles.remove(p) != OK:
			keep.append(p)
	_stale_sessions = keep


func _begin_busy(op: String) -> void:
	_resetting = true
	_ready_flag = false
	_busy_op = op


func _end_busy() -> void:
	_resetting = false
	_busy_op = ""


func _wait_until_ready() -> bool:
	_ready_flag = false
	var deadline := Time.get_ticks_msec() + int(ready_timeout_s * 1000.0)
	var center := ready_probe_point
	var area := AABB(_terrain.to_local(center) - Vector3(8, 8, 8), Vector3(16, 16, 16))
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if not is_instance_valid(_terrain):
			return false
		if not _terrain.is_area_meshed(area, 0):
			continue
		var hit := raycast_terrain(center + Vector3.UP * 20.0, center + Vector3.DOWN * 20.0)
		if not hit.is_empty():
			_ready_flag = true
			return true
	push_error("[TerrainService] timeout esperando terreno pronto em %s" % center)
	return false


func _sphere_op(op: String, mode: int, world_point: Vector3, radius: float,
		material_id: StringName = &"") -> TerrainEditResult:
	var t0 := Time.get_ticks_usec()
	if not _is_finite_vec(world_point) or not is_finite(radius):
		return _reject(op, "invalid_input")
	if radius < min_radius or radius > max_radius:
		return _reject(op, "radius_out_of_range")
	var paint: TerrainMaterial = null
	if material_id != &"":
		paint = TerrainMaterialLibrary.get_by_id(material_id)
		if paint == null:
			return _reject(op, "unknown_material")
	var effective_radius := radius + (remove_radius_padding if mode == VoxelTool.MODE_REMOVE else 0.0)
	# A AABB validada e anunciada cobre tudo o que muda, inclusive a margem de pintura.
	var extent := effective_radius + (material_paint_margin if paint != null else 0.0)
	var aabb := AABB(world_point - Vector3.ONE * extent, Vector3.ONE * extent * 2.0)
	var reason := _validate_area(aabb)
	if reason != "":
		return _reject(op, reason, aabb)
	if mode == VoxelTool.MODE_ADD and _overlaps_protected_body(world_point, radius):
		return _reject(op, "overlaps_player", aabb)
	if not _consume_budget():
		return _reject(op, "frame_budget_exceeded", aabb)
	var local := _terrain.to_local(world_point)
	# Material de referência lido ANTES da edição (o que sai no REMOVE, o que o gerador previa no ADD).
	var mat := paint if paint != null else TerrainMaterialLibrary.get_by_index(_material_index_local(local))
	_tool.mode = mode
	_tool.do_sphere(local, effective_radius)
	if paint != null:
		_paint_sphere(local, effective_radius + material_paint_margin, paint.index)
	var result := _commit(op, aabb, t0, "c=%s r=%.2f%s" % [_fmt(world_point), radius,
		(" mat=%s" % paint.id) if paint != null else ""])
	_set_estimate(result, mat, 4.0 / 3.0 * PI * pow(radius, 3.0))
	return result


func _path_op(op: String, mode: int, world_points: PackedVector3Array, radii: PackedFloat32Array,
		material_id: StringName = &"") -> TerrainEditResult:
	var t0 := Time.get_ticks_usec()
	var n := world_points.size()
	if n < 2 or n != radii.size() or n > max_path_points:
		return _reject(op, "invalid_path_points")
	var paint: TerrainMaterial = null
	if material_id != &"":
		paint = TerrainMaterialLibrary.get_by_id(material_id)
		if paint == null:
			return _reject(op, "unknown_material")
	var pad := remove_radius_padding if mode == VoxelTool.MODE_REMOVE else 0.0
	var margin := pad + (material_paint_margin if paint != null else 0.0)
	var length := 0.0
	var aabb := AABB()
	for i in n:
		var p := world_points[i]
		var r := radii[i]
		if not _is_finite_vec(p) or not is_finite(r):
			return _reject(op, "invalid_input")
		if r < min_radius or r > max_radius:
			return _reject(op, "radius_out_of_range")
		var e := r + margin
		var sphere_box := AABB(p - Vector3.ONE * e, Vector3.ONE * e * 2.0)
		aabb = sphere_box if i == 0 else aabb.merge(sphere_box)
		if i > 0:
			length += p.distance_to(world_points[i - 1])
	if length > max_path_length:
		return _reject(op, "path_too_long", aabb)
	var reason := _validate_area(aabb)
	if reason != "":
		return _reject(op, reason, aabb)
	if mode == VoxelTool.MODE_ADD and _path_overlaps_protected_body(world_points, radii):
		return _reject(op, "overlaps_player", aabb)
	if not _consume_budget():
		return _reject(op, "frame_budget_exceeded", aabb)

	var local_points := PackedVector3Array()
	local_points.resize(n)
	var padded_radii := PackedFloat32Array()
	padded_radii.resize(n)
	for i in n:
		local_points[i] = _terrain.to_local(world_points[i])
		padded_radii[i] = radii[i] + pad
	var mat := paint if paint != null else TerrainMaterialLibrary.get_by_index(_material_index_local(local_points[0]))
	_tool.mode = mode
	_tool.do_path(local_points, padded_radii)
	if paint != null:
		var paint_radii := PackedFloat32Array()
		paint_radii.resize(n)
		for i in n:
			paint_radii[i] = padded_radii[i] + material_paint_margin
		# Mesmo princípio do _paint_sphere; do_path em MODE_SET conferido no spike (S4b).
		_tool.channel = VoxelBuffer.CHANNEL_INDICES
		_tool.mode = VoxelTool.MODE_SET
		_tool.value = paint.index
		_tool.do_path(local_points, paint_radii)
		_tool.channel = VoxelBuffer.CHANNEL_SDF
	var result := _commit(op, aabb, t0, "pontos=%d comp=%.1fm%s" % [n, length,
		(" mat=%s" % paint.id) if paint != null else ""])
	_set_estimate(result, mat, _path_volume(world_points, radii))
	return result


func _validate_area(world_aabb: AABB) -> String:
	if not is_ready():
		return "terrain_not_ready"
	var local_aabb := AABB(_terrain.to_local(world_aabb.position), world_aabb.size)
	if not _terrain.voxel_bounds.encloses(local_aabb):
		return "outside_bounds"
	if not _tool.is_area_editable(local_aabb):
		return "area_not_loaded"
	return ""


func _overlaps_protected_body(center: Vector3, radius: float) -> bool:
	if protected_body_path.is_empty():
		return false
	var body := get_node_or_null(protected_body_path) as Node3D
	if body == null:
		return false
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs == null or not (cs.shape is CapsuleShape3D):
			continue
		var capsule := cs.shape as CapsuleShape3D
		var half := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		var axis := cs.global_transform.basis.y.normalized()
		var a := cs.global_position - axis * half
		var b := cs.global_position + axis * half
		var closest := Geometry3D.get_closest_point_to_segment(center, a, b)
		if closest.distance_to(center) < radius + capsule.radius + 0.1:
			return true
	return false


## Amostra cada trecho do tubo a cada 0,5 m contra a cápsula do corpo protegido.
func _path_overlaps_protected_body(points: PackedVector3Array, radii: PackedFloat32Array) -> bool:
	for i in range(1, points.size()):
		var steps := maxi(1, ceili(points[i].distance_to(points[i - 1]) / 0.5))
		for s in steps + 1:
			var t := float(s) / steps
			if _overlaps_protected_body(points[i - 1].lerp(points[i], t), lerpf(radii[i - 1], radii[i], t)):
				return true
	return false


func _material_index_local(local: Vector3) -> int:
	_tool.channel = VoxelBuffer.CHANNEL_INDICES
	var v := _tool.get_voxel(Vector3i(local.round()))
	_tool.channel = VoxelBuffer.CHANNEL_SDF
	return v


## Modo Single: MODE_SET + CHANNEL_INDICES + value (doc do Voxel Tools; conferido no spike S3).
func _paint_sphere(local_center: Vector3, radius: float, index: int) -> void:
	_tool.channel = VoxelBuffer.CHANNEL_INDICES
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = index
	_tool.do_sphere(local_center, radius)
	_tool.channel = VoxelBuffer.CHANNEL_SDF


## Volume nominal de um tubo: troncos de cone entre pontos + meia esfera em cada ponta.
## Ignora sobreposição em curvas (estimativa).
static func _path_volume(points: PackedVector3Array, radii: PackedFloat32Array) -> float:
	var v := 2.0 / 3.0 * PI * (pow(radii[0], 3.0) + pow(radii[-1], 3.0))
	for i in range(1, points.size()):
		var r0 := radii[i - 1]
		var r1 := radii[i]
		v += PI / 3.0 * points[i].distance_to(points[i - 1]) * (r0 * r0 + r0 * r1 + r1 * r1)
	return v


static func _set_estimate(result: TerrainEditResult, mat: TerrainMaterial, volume_m3: float) -> void:
	result.est_volume_m3 = volume_m3
	if mat != null:
		result.material_id = mat.id
		result.est_mass_kg = volume_m3 * mat.density


func _consume_budget() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_used = 0
	if _budget_used >= max_edits_per_physics_frame:
		return false
	_budget_used += 1
	return true


func _commit(op: String, aabb: AABB, t0_usec: int, detail: String) -> TerrainEditResult:
	_revision += 1
	_edit_count += 1
	var usec := Time.get_ticks_usec() - t0_usec
	_log("%s OK %s rev=%d %.3fms" % [op, detail, _revision, usec / 1000.0])
	terrain_changed.emit(aabb, _revision)
	return TerrainEditResult.success(op, aabb, _revision, usec)


func _reject(op: String, reason: String, aabb: AABB = AABB()) -> TerrainEditResult:
	_reject_count += 1
	_log("%s RECUSADO: %s %s" % [op, reason, _fmt(aabb.get_center()) if aabb.has_volume() else ""])
	edit_rejected.emit(op, reason, aabb)
	return TerrainEditResult.failure(op, reason, aabb)


func _log(msg: String) -> void:
	if verbose:
		print("[TerrainService] ", msg)


static func _is_finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _fmt(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
