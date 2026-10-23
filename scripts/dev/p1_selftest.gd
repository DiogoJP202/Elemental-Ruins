extends "res://scripts/dev/p0_selftest.gd"
## Roteiro automatizado do P1: roda os 12 testes do P0 (regressão) e depois os do P1,
## na mesma cena real, com a mesma física e o mesmo jogador.
##
##   godot --headless --path . res://scenes/main.tscn -- --p1-selftest
##   godot --path . res://scenes/main.tscn -- --p1-selftest --p1-screenshots
##   opcional: --report=<caminho.json>, --only=T8,T11 (T1 e baseline sempre rodam)
##
## Colisão é verificada por raycast físico ou movimento do corpo, como no P0.
## Código de saída: 0 = todos PASS, 1 = algum FAIL, 2 = watchdog.

const P1_WATCHDOG_S := 900.0

var queue: TerrainBrushQueue
var controller: TerrainEditController
var _brush_log: Array[Dictionary] = []


func _ready() -> void:
	queue = get_parent().brush_queue
	controller = get_parent().edit_controller
	queue.brush_applied.connect(_on_brush_applied)
	super._ready()


func _report_prefix() -> String:
	return "p1_selftest"


func _watchdog_seconds() -> float:
	return P1_WATCHDOG_S


func _evidence_dir() -> String:
	return "res://docs/evidence/p1/" if OS.has_feature("editor") else "user://"


func _screens_dir() -> String:
	return "res://docs/evidence/p1/screens/" if OS.has_feature("editor") else "user://screens_p1/"


func _log(msg: String) -> void:
	print("[P1TEST] ", msg)


func _run_tests() -> bool:
	var ok: bool = await super._run_tests()
	if not ok:
		return false
	_log("--- testes P1 ---")
	if _should_run("T8"): await _t8_stroke_trench()
	if _should_run("T8b"): await _t8b_input_stroke()
	if _should_run("T9"): await _t9_split_and_merge()
	if _should_run("T10"): await _t10_smooth()
	if _should_run("T11"): await _t11_materials()
	if _should_run("T12"): await _t12_terrain_changed()
	if _should_run("T13"): await _t13_ramp()
	return true


# --- T8: traço contínuo simulado -------------------------------------------------

func _t8_stroke_trench() -> void:
	const X := -30.0
	const Z0 := 10.0
	const Z1 := -10.0
	const R := 1.2
	var area := AABB(Vector3(X - 3, -4, Z1 - 3), Vector3(6, 8, Z0 - Z1 + 6))
	var ready := await _prepare_area(Vector3(X - 6, 0.5, 16), area)
	queue.reset_frame_peaks()
	var s0 := queue.get_stats()
	var log0 := _brush_log.size()
	var id := queue.begin_stroke(TerrainBrushRequest.Op.REMOVE, R, &"", "selftest:T8")
	var samples := 120
	for i in samples:
		await get_tree().physics_frame
		queue.update_stroke(id, Vector3(X, 0, lerpf(Z0, Z1, float(i) / (samples - 1))), Vector3.UP)
	queue.end_stroke(id)
	await _drain_queue()
	var s1 := queue.get_stats()
	var applied := _brush_log.slice(log0)
	var paths := applied.filter(func(e): return e.op == "PATH-").size()
	var all_ok := applied.all(func(e): return e.ok)
	var dug := await _wait_line(X, Z0, Z1, -0.4, 5.0)
	var stamps: int = s1.stamps - s0.stamps
	# 2 s de traço com intervalo de 0,15 s (solo, dureza 1): no máximo ~14 carimbos.
	var max_stamps := int(ceil(2.0 / queue.stroke_base_interval)) + 2
	var ok: bool = ready and all_ok and dug.missing.is_empty() and stamps >= 5 and stamps <= max_stamps \
		and paths > 0 and s1.max_ops_in_frame <= queue.max_ops_per_frame
	_record("T8", "Traço contínuo (120 amostras em 2 s) vira vala contínua com carimbos limitados", ok, {
		"amostras_de_mira": samples, "carimbos": stamps, "limite_carimbos": max_stamps,
		"carimbos_pulados_por_espaco": s1.stamps_skipped - s0.stamps_skipped,
		"ops_aplicadas": applied.size(), "ops_tubo_por_salto": paths, "todas_ok": all_ok,
		"max_ops_num_quadro": s1.max_ops_in_frame, "pontos_sem_vala": dug.missing,
		"vala_no_collider_ms": dug.ms})
	await _shot("t8_vala_traco", Vector3(X - 7, 0.5, 0), -PI / 2.0, -28.0)


# --- T8b: G segurado pelo caminho real de input --------------------------------

func _t8b_input_stroke() -> void:
	var pos := Vector3(-40, 0.5, 26)
	var ready := await _prepare_area(pos, AABB(Vector3(-46, -10, 10), Vector3(12, 14, 18)))
	player.camera_rig.set_view(0.0, deg_to_rad(-25.0))
	await _seconds(0.5)
	var old_radius := controller.radius
	controller.radius = 1.5
	player.input_enabled = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	var aim: Dictionary = controller.get_aim()
	var target: Vector3 = aim.point
	var from := target + Vector3.UP * 30.0
	var to := target + Vector3.DOWN * 30.0
	var y0 := _hit_y(svc.raycast_terrain(from, to))
	var s0 := queue.get_stats()
	Input.action_press(&"terrain_dig")
	await _seconds(1.0)
	Input.action_release(&"terrain_dig")
	await get_tree().physics_frame
	player.input_enabled = false
	controller.radius = old_radius
	await _drain_queue()
	var s1 := queue.get_stats()
	var w := await _wait_ray(from, to, func(h): return not h.is_empty() and h.position.y < y0 - 1.0, 5.0)
	var stamps: int = s1.stamps - s0.stamps
	var ok: bool = ready and aim.hit and stamps >= 2 and s1.applied - s0.applied >= 2 and w.ok \
		and queue.active_stroke_count() == 0
	_record("T8b", "G segurado 1 s (Input → controlador → fila) abre cratera no collider", ok, {
		"mira": str(target), "material_mirado": str(aim.material), "chao_antes_y": y0,
		"chao_depois_y": _hit_y(w.hit), "carimbos": stamps, "aplicadas": s1.applied - s0.applied,
		"tracos_ativos_depois": queue.active_stroke_count(), "collider_ms": w.ms})


# --- T9: limite de AABB (divisão) e fusão de carimbos acumulados ------------------

func _t9_split_and_merge() -> void:
	var ready := await _prepare_area(Vector3(40, 0.5, 26), AABB(Vector3(32, -4, -10), Vector3(14, 8, 34)))
	queue.reset_frame_peaks()
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 14:
		pts.append(Vector3(36, -1, 20.0 - i * 2.0))
		radii.append(1.5)
	var log0 := _brush_log.size()
	var s0 := queue.get_stats()
	var long_path := TerrainBrushRequest.path(pts, radii, false)
	long_path.source = "selftest:T9"
	queue.enqueue(long_path)
	await _drain_queue()
	var parts := _brush_log.slice(log0)
	var max_extent := 0.0
	for e: Dictionary in parts:
		var size: Vector3 = e.aabb.size
		max_extent = maxf(max_extent, maxf(size.x, maxf(size.y, size.z)))
	var s1 := queue.get_stats()
	var dug := await _wait_line(36.0, 20.0, -6.0, -1.5, 5.0)
	var split_ok: bool = parts.size() >= 3 and parts.all(func(e): return e.ok) \
		and max_extent <= queue.max_aabb_extent + 0.2 and dug.missing.is_empty()

	# Rajada: 20 carimbos do mesmo traço enfileirados no MESMO quadro.
	var id := queue.begin_stroke(TerrainBrushRequest.Op.REMOVE, 1.0, &"", "selftest:T9-rajada")
	var log1 := _brush_log.size()
	var s2 := queue.get_stats()
	for i in 20:
		var req := TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE, Vector3(42, 0, i * 0.5), 1.0)
		req.stroke_id = id
		queue.enqueue(req)
	queue.end_stroke(id)
	await _drain_queue()
	var burst := _brush_log.slice(log1)
	var s3 := queue.get_stats()
	var burst_dug := await _wait_line(42.0, 0.0, 9.5, -0.5, 5.0)
	var merge_ok: bool = burst.size() <= 2 and burst.all(func(e): return e.ok) \
		and s3.merged - s2.merged >= 15 and burst_dug.missing.is_empty()
	var ok: bool = ready and split_ok and merge_ok and s3.max_ops_in_frame <= queue.max_ops_per_frame
	_record("T9", "PATH de 26 m dividido por AABB; rajada de 20 carimbos fundida; orçamento por quadro", ok, {
		"tubo_trechos": parts.size(), "divisoes": s1.splits - s0.splits,
		"maior_extensao_aabb_m": snappedf(max_extent, 0.01), "limite_extensao_m": queue.max_aabb_extent,
		"tubo_pontos_sem_vala": dug.missing,
		"rajada_pedidos": 20, "rajada_ops_aplicadas": burst.size(), "rajada_fundidos": s3.merged - s2.merged,
		"rajada_pontos_sem_vala": burst_dug.missing,
		"max_ops_num_quadro": s3.max_ops_in_frame, "max_volume_aabb_num_quadro_m3": snappedf(s3.max_volume_in_frame, 0.1),
		"orcamento_volume_m3": queue.max_aabb_volume_per_frame})


# --- T10: SMOOTH --------------------------------------------------------------------

func _t10_smooth() -> void:
	var c := Vector3(-26, 0, 48)
	var ready := await _prepare_area(c + Vector3(0, 0.5, 10), AABB(c - Vector3(7, 4, 7), Vector3(14, 10, 14)))
	var top_from := c + Vector3.UP * 30.0
	var top_to := c + Vector3.DOWN * 10.0
	var add := svc.add_sphere(c + Vector3.UP, 2.0)
	var wt := await _wait_ray(top_from, top_to, func(h): return not h.is_empty() and h.position.y > 2.5, 5.0)
	await _seconds(0.3)
	var before := _height_profile(c)
	var sdf_before := svc.sample_sdf(c + Vector3(0, 2.5, 0))
	var log0 := _brush_log.size()
	for i in 2:
		var req := TerrainBrushRequest.sphere(TerrainBrushRequest.Op.SMOOTH, c + Vector3.UP, 3.5)
		req.source = "selftest:T10"
		queue.enqueue(req)
	await _drain_queue()
	var smooth_events := _brush_log.slice(log0)
	var sdf_after := svc.sample_sdf(c + Vector3(0, 2.5, 0))
	var wl := await _wait_ray(top_from, top_to, func(h): return not h.is_empty() and h.position.y < before.heights[0] - 0.3, 5.0)
	await _seconds(0.3)
	var after := _height_profile(c)
	var ok: bool = ready and add.ok and wt.ok and smooth_events.size() == 2 and smooth_events.all(func(e): return e.ok) \
		and wl.ok and after.heights[0] < before.heights[0] - 0.3 and after.max_slope < before.max_slope * 0.75 \
		and sdf_after > sdf_before
	_record("T10", "SMOOTH arredonda saliência: topo desce e a maior inclinação cai (collider e dados)", ok, {
		"saliencia": str(add), "suavizacoes": smooth_events.map(func(e): return e.text),
		"distancias_m": before.dist, "alturas_antes": before.heights, "alturas_depois": after.heights,
		"inclinacao_max_antes": before.max_slope, "inclinacao_max_depois": after.max_slope,
		"sdf_topo_antes": sdf_before, "sdf_topo_depois": sdf_after, "collider_ms": wl.ms})
	await _shot("t10_saliencia_suavizada", c + Vector3(0, 0.5, 8), 0.0, -18.0)


# --- T11: materiais -------------------------------------------------------------------

func _t11_materials() -> void:
	var details := {}
	var ok := true

	# a) O que o gerador escreveu bate com o layout documentado.
	await _prepare_area(SPAWN, AABB(Vector3(-4, -10, -14), Vector3(38, 26, 46)))
	var layout := [Vector3(0, -1, 28), Vector3(30, -1, 28), Vector3(0, -8, 28), Vector3(0, 4, -10),
		Vector3(0, 10.5, -10), Vector3(5, -3, 40), Vector3(5, -7, 40)]
	var layout_rows := []
	for p: Vector3 in layout:
		var m := svc.get_material_at(p)
		var expected := LabTerrainFactory.generator_material_index(p)
		var row_ok := m != null and m.index == expected
		ok = ok and row_ok
		layout_rows.append({"p": str(p), "lido": str(m), "esperado": TerrainMaterialLibrary.get_by_index(expected).id, "ok": row_ok})
	details["layout_gerador"] = layout_rows

	# b) ADD com material areia: dado lido de volta; fora da pintura continua solo; massa por densidade.
	var c := Vector3(-36, 0.5, 60)
	await _prepare_area(c + Vector3(6, 0, 4), AABB(c - Vector3(4, 4, 4), Vector3(8, 8, 8)))
	var log0 := _brush_log.size()
	var req := TerrainBrushRequest.sphere(TerrainBrushRequest.Op.ADD, c, 1.5, TerrainMaterialLibrary.SAND)
	queue.enqueue(req)
	await _drain_queue()
	var ev: Dictionary = _brush_log[log0] if _brush_log.size() > log0 else {}
	var inside := svc.get_material_at(c)
	var outside := svc.get_material_at(c + Vector3(3, -1.5, 0))
	var expected_mass := 4.0 / 3.0 * PI * pow(1.5, 3.0) * TerrainMaterialLibrary.get_by_id(TerrainMaterialLibrary.SAND).density
	var add_ok: bool = not ev.is_empty() and ev.ok and inside != null and inside.id == TerrainMaterialLibrary.SAND \
		and outside != null and outside.id == TerrainMaterialLibrary.SOIL and absf(ev.mass - expected_mass) < 1.0
	ok = ok and add_ok
	details["add_areia"] = {"resultado": ev.get("text", ""), "dentro": str(inside), "fora_3m": str(outside),
		"massa_kg": ev.get("mass", 0.0), "massa_esperada_kg": expected_mass, "ok": add_ok}
	await _shot("t11_coluna_areia", c + Vector3(0, 0, 7), 0.0, -12.0)

	# c) Dureza: o mesmo traço (6 m/s por 1,5 s) gera menos carimbos em pedra que em solo,
	#    e mais em areia.
	var sweeps := {
		"areia": {"start": Vector3(30, 0, 0), "player": Vector3(26, 0.5, 4)},
		"solo": {"start": Vector3(-44, 0, 44), "player": Vector3(-38, 0.5, 48)},
		"pedra": {"start": Vector3(-44, -8, 30), "player": Vector3(-38, 0.5, 34)},
	}
	var counts := {}
	for name: String in sweeps:
		var sw: Dictionary = sweeps[name]
		var start: Vector3 = sw.start
		await _prepare_area(sw.player, AABB(start + Vector3(-3, -3, -12), Vector3(6, 6, 15)))
		var s0 := queue.get_stats()
		var id := queue.begin_stroke(TerrainBrushRequest.Op.REMOVE, 1.0, &"", "selftest:T11-%s" % name)
		var frames := 90
		for i in frames:
			await get_tree().physics_frame
			queue.update_stroke(id, start + Vector3(0, 0, -9.0 * i / (frames - 1)), Vector3.UP)
		var mat := queue.get_last_stroke_material()
		queue.end_stroke(id)
		await _drain_queue()
		counts[name] = {"carimbos": queue.get_stats().stamps - s0.stamps, "material": str(mat)}
	var n_sand: int = counts.areia.carimbos
	var n_soil: int = counts.solo.carimbos
	var n_stone: int = counts.pedra.carimbos
	var hard_ok := n_sand > n_soil and n_soil > n_stone and float(n_soil) / maxf(n_stone, 1) >= 2.0 \
		and float(n_sand) / maxf(n_soil, 1) >= 1.4 and str(counts.pedra.material).begins_with("stone") \
		and str(counts.areia.material).begins_with("sand") and str(counts.solo.material).begins_with("soil")
	ok = ok and hard_ok
	details["dureza_tracos"] = counts
	details["dureza_ok"] = hard_ok

	# d) Política bendable=false (isolada: nenhum dos 3 materiais do P1 é não dobrável).
	var rigid := TerrainMaterial.create(&"test_rigid", 200, "teste", 9.0, 7800.0, false, Color.GRAY)
	var pol_rigid := TerrainBrushQueue.material_policy(TerrainBrushRequest.Op.REMOVE, rigid)
	var pol_soil := TerrainBrushQueue.material_policy(TerrainBrushRequest.Op.REMOVE,
		TerrainMaterialLibrary.get_by_id(TerrainMaterialLibrary.SOIL))
	var pol_ok := pol_rigid == "material_not_bendable" and pol_soil == ""
	ok = ok and pol_ok
	details["politica_bendable"] = {"nao_dobravel": pol_rigid, "solo": pol_soil, "ok": pol_ok}
	_record("T11", "Materiais: layout do gerador, ADD de areia lido nos dados, dureza no ritmo, massa por densidade", ok, details)


# --- T12: evento TerrainChanged -----------------------------------------------------

func _t12_terrain_changed() -> void:
	var ready := await _prepare_area(Vector3(20, 0.5, 70), AABB(Vector3(7, -4, 58), Vector3(28, 8, 8)))
	var events: Array[Dictionary] = []
	# Centro em coordenadas inteiras; y = -0,6 arredonda para o voxel y = -1, a 1 m do centro
	# (dentro da esfera de 1,05 m): sólido antes da edição, ar depois.
	var cb := func(aabb: AABB, revision: int):
		var c := aabb.get_center()
		var hit := svc.raycast_terrain(Vector3(c.x, 30, c.z), Vector3(c.x, -30, c.z))
		events.append({"aabb": aabb, "rev": revision, "frame": Engine.get_physics_frames(),
			"collider_y_no_evento": _hit_y(hit), "sdf_centro_no_evento": svc.sample_sdf(Vector3(c.x, -0.6, c.z))})
	svc.terrain_changed.connect(cb)
	var rev0 := svc.get_revision()
	var log0 := _brush_log.size()
	var reqs: Array[TerrainBrushRequest] = []
	for i in 8:
		reqs.append(TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE, Vector3(10 + i * 3, 0, 62), 1.0))
	reqs.insert(3, TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE, Vector3(5000, 0, 5000), 1.0))
	reqs.insert(6, TerrainBrushRequest.sphere(TerrainBrushRequest.Op.ADD, Vector3(15, 3, 62), 1.0, &"lava"))
	for r in reqs:
		queue.enqueue(r)
	await _drain_queue()
	svc.terrain_changed.disconnect(cb)
	var applied := _brush_log.slice(log0)
	var ok_results := applied.filter(func(e): return e.ok)
	var rejected := applied.filter(func(e): return not e.ok)
	var consecutive := true
	var encloses := true
	var stale := 0
	var data_first := true
	for i in events.size():
		var e: Dictionary = events[i]
		consecutive = consecutive and e.rev == rev0 + i + 1
		if i < ok_results.size():
			var nominal: AABB = ok_results[i].request_aabb
			encloses = encloses and e.aabb.grow(0.001).encloses(nominal)
		if absf(e.collider_y_no_evento) < 0.05:
			stale += 1
		data_first = data_first and e.sdf_centro_no_evento > 0.0
	# Latência até o collider refletir a última escavação.
	var last: Vector3 = reqs[-1].points[0]
	var w := await _wait_ray(last + Vector3.UP * 30.0, last + Vector3.DOWN * 30.0,
		func(h): return not h.is_empty() and h.position.y < -0.5, 5.0)
	var ok: bool = ready and events.size() == 8 and ok_results.size() == 8 and rejected.size() == 2 \
		and consecutive and encloses and data_first and w.ok
	_record("T12", "TerrainChanged {aabb, revision}: 1 evento por edição aplicada, nenhum por recusa", ok, {
		"eventos": events.size(), "edicoes_ok": ok_results.size(),
		"recusas": rejected.map(func(e): return e.text), "revisoes_consecutivas": consecutive,
		"aabb_do_evento_contem_brush": encloses, "dados_ja_mudados_no_evento": data_first,
		"collider_ainda_velho_no_evento": "%d/%d" % [stale, events.size()],
		"collider_ultimo_ms": w.ms})


# --- T13: rampa (PATH aditivo) e travessia a pé -------------------------------------

func _t13_ramp() -> void:
	var start := Vector3(-14, 0, 58)
	var forward := Vector3(-1, 0, 0)
	var ready := await _prepare_area(start + Vector3(6, 0.5, 0), AABB(Vector3(-25, -4, 54), Vector3(14, 10, 8)))
	var old_radius := controller.radius
	var old_mat := controller._add_material_index
	controller.radius = 2.0
	controller._add_material_index = TerrainMaterialLibrary.INDEX_SAND
	var req := controller.make_ramp_request(start, forward)
	controller.radius = old_radius
	controller._add_material_index = old_mat
	var log0 := _brush_log.size()
	queue.enqueue(req)
	await _drain_queue()
	var ev: Dictionary = _brush_log[log0] if _brush_log.size() > log0 else {}
	var end := start + forward * controller.ramp_length
	var top_expected := controller.ramp_rise + 0.1
	var w := await _wait_ray(end + Vector3(0.8, 30, 0), end + Vector3(0.8, -10, 0),
		func(h): return not h.is_empty() and h.position.y > top_expected - 0.6, 5.0)
	var mid := start + forward * controller.ramp_length * 0.75
	var mid_top := _hit_y(svc.raycast_terrain(mid + Vector3.UP * 30.0, mid + Vector3.DOWN * 10.0))
	var mat := svc.get_material_at(Vector3(mid.x, mid_top - 0.5, mid.z))

	player.teleport_to(start - forward * 3.0 + Vector3.UP * 0.3)
	player.camera_rig.set_view(PI / 2.0, deg_to_rad(-10.0))
	await _seconds(0.6)
	var max_y := -INF
	var t0 := Time.get_ticks_msec()
	player.set_scripted_move(forward)
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().physics_frame
		max_y = maxf(max_y, player.global_position.y)
		if player.global_position.x < end.x + 1.0:
			break
	player.clear_scripted_move()
	var final_y := player.global_position.y
	await _shot("t13_rampa_areia", player.global_position, -PI / 2.0, -20.0, false)
	var ok: bool = ready and not ev.is_empty() and ev.ok and w.ok and max_y > controller.ramp_rise - 0.6 \
		and mat != null and mat.id == TerrainMaterialLibrary.SAND
	_record("T13", "Rampa (PATH aditivo de areia): jogador sobe a pé até o topo", ok, {
		"edicao": ev.get("text", ""), "topo_esperado_y": top_expected, "topo_no_fim_y": _hit_y(w.hit),
		"material_no_meio": str(mat), "jogador_y_max": max_y, "jogador_y_final": final_y,
		"jogador_x_final": player.global_position.x, "on_floor": player.is_on_floor()})
	player.teleport_to(SPAWN)
	await _seconds(0.3)


# --- Utilidades P1 --------------------------------------------------------------------

func _on_brush_applied(req: TerrainBrushRequest, result: TerrainEditResult) -> void:
	_brush_log.append({"op": req.op_name(), "ok": result.ok, "reason": result.reason, "text": str(result),
		"aabb": result.world_aabb, "request_aabb": req.world_aabb(), "rev": result.revision,
		"mass": result.est_mass_kg, "merged": req.merged_count,
		"queue_ms": (req.applied_usec - req.enqueued_usec) / 1000.0, "applied_usec": req.applied_usec})


## Leva o jogador para perto da área e espera o LOD0 carregar nela (edição possível).
func _prepare_area(player_pos: Vector3, area: AABB, timeout_s := 10.0) -> bool:
	player.teleport_to(player_pos)
	var ok := await _wait_until(func(): return svc.can_edit_area(area), timeout_s)
	await get_tree().physics_frame
	return ok


## Alturas do collider a 0–4,5 m do centro (passo 0,75 m, eixo +x) e a maior
## inclinação entre amostras vizinhas (Δaltura / Δdistância).
func _height_profile(c: Vector3) -> Dictionary:
	var dist := []
	var heights := []
	var max_slope := 0.0
	for i in 7:
		var d := i * 0.75
		var p := c + Vector3(d, 0, 0)
		var h := snappedf(_hit_y(svc.raycast_terrain(p + Vector3.UP * 30.0, p + Vector3.DOWN * 10.0)), 0.001)
		if i > 0:
			max_slope = maxf(max_slope, absf(h - heights[-1]) / 0.75)
		dist.append(d)
		heights.append(h)
	return {"dist": dist, "heights": heights, "max_slope": snappedf(max_slope, 0.001)}


func _drain_queue(timeout_s := 10.0) -> void:
	await _wait_until(func(): return queue.pending_count() == 0, timeout_s)
	await get_tree().physics_frame


## Espera o collider mostrar vala (hit abaixo de y_max) em toda a linha x = const, z0→z1,
## a cada 0,5 m. Retorna {missing: [z sem vala], ms}.
func _wait_line(x: float, z0: float, z1: float, y_max: float, timeout_s: float) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var missing := []
	while true:
		await get_tree().physics_frame
		missing = []
		var n := int(absf(z1 - z0) / 0.5)
		for i in n + 1:
			var z := lerpf(z0, z1, float(i) / n)
			var hit := svc.raycast_terrain(Vector3(x, 30, z), Vector3(x, -30, z))
			if hit.is_empty() or hit.position.y > y_max:
				missing.append(snappedf(z, 0.1))
		if missing.is_empty() or Time.get_ticks_msec() - t0 > timeout_s * 1000.0:
			break
	return {"missing": missing, "ms": Time.get_ticks_msec() - t0}
