extends "res://scripts/dev/p1_selftest.gd"
## Roteiro automatizado do P2: roda P0 + P1 (regressão) e depois os testes de estruturas,
## destroços e extração, na mesma cena real.
##
##   godot --headless --path . res://scenes/main.tscn -- --p2-selftest
##   godot --path . res://scenes/main.tscn -- --p2-selftest --p2-screenshots
##   opcional: --report=<caminho.json>, --only=T19,T21 (T1 e baseline sempre rodam)
##
## Código de saída: 0 = todos PASS, 1 = algum FAIL, 2 = watchdog.

const P2_WATCHDOG_S := 1500.0

var structures: StructureService


func _ready() -> void:
	structures = get_parent().structures
	super._ready()
	if OS.get_cmdline_user_args().has("--p2-screenshots") and DisplayServer.get_name() != "headless":
		_screens = true


func _report_prefix() -> String:
	# Fases de persistência (--p2-selftest --p1-persist=...) mantêm o nome do P1, mas gravam
	# em docs/evidence/p2/, sem tocar nas evidências de referência do P1.
	return super._report_prefix() if _persist_phase != "" else "p2_selftest"


func _watchdog_seconds() -> float:
	return P2_WATCHDOG_S


func _evidence_dir() -> String:
	return "res://docs/evidence/p2/" if OS.has_feature("editor") else "user://"


func _screens_dir() -> String:
	return "res://docs/evidence/p2/screens/" if OS.has_feature("editor") else "user://screens_p2/"


func _log(msg: String) -> void:
	print("[P2TEST] ", msg)


func _run_tests() -> bool:
	var ok: bool = await super._run_tests()
	if not ok or _persist_phase != "":
		return ok
	_log("--- testes P2 ---")
	if _should_run("T18"): await _t18_sleeping_crate()
	if _should_run("T19"): await _t19_tower_intact()
	if _should_run("T20"): await _t20_partial_collapse()
	if _should_run("T21"): await _t21_full_collapse()
	if _should_run("T22"): await _t22_body_budget()
	if _should_run("T23"): await _t23_extract_rock()
	if _should_run("T24"): await _t24_push_rock()
	if _should_run("T25"): await _t25_collapse_reset_cycles()
	if _should_run("T26"): await _t26_save_load_structures()
	if _should_run("T27"): await _t27_collapse_benchmark()
	return true


# --- T27: benchmark do colapso total ---------------------------------------------------------

## Pior caso: os 4 pés escavados no mesmo quadro (36 peças a soltar). Mede por 6 s o intervalo
## entre quadros de processo, o monitor TIME_PHYSICS_PROCESS e os corpos dinâmicos.
## Critério (decisão 8 do plano P2), só em janela: p95 ≤ 20 ms, p99 ≤ 33 ms, máx ≤ 50 ms.
func _t27_collapse_benchmark() -> void:
	await main.request_world_reset()
	await _go_to_tower()
	await _seconds(1.0)
	var budget: DebrisBudget = main.debris
	var frame_ms := PackedFloat32Array()
	var phys_ms := PackedFloat32Array()
	var last := [Time.get_ticks_usec()]
	var on_frame := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last[0]) / 1000.0)
		last[0] = now
	var peak_dynamic := 0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var c := _foot_at(corner).home.origin
		queue.enqueue(TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE, Vector3(c.x, 0, c.z), 2.0))
	get_tree().process_frame.connect(on_frame)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().physics_frame
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var dyn := 0
		for p in structures.get_pieces():
			dyn += int(p.released and not p.freeze)
		peak_dynamic = maxi(peak_dynamic, dyn)
	get_tree().process_frame.disconnect(on_frame)
	if not frame_ms.is_empty():
		frame_ms.remove_at(0)
	var fs := _stats(frame_ms)
	fs["p50"] = _percentile(frame_ms, 0.5)
	fs["p99"] = _percentile(frame_ms, 0.99)
	var ps := _stats(phys_ms)
	ps["p99"] = _percentile(phys_ms, 0.99)
	_metrics["p2_colapso_quadro_ms"] = fs
	_metrics["p2_colapso_fisica_ms"] = ps
	var below := []
	for p in structures.get_pieces():
		var c := p.global_position
		var hit := svc.raycast_terrain(Vector3(c.x, 40, c.z), Vector3(c.x, -40, c.z))
		if hit.is_empty() or c.y < hit.position.y - 0.2:
			below.append(p.name)
	var windowed := not _mode.begins_with("headless")
	var fps_ok: bool = (not windowed) or (fs.get("p95", 999.0) <= 20.0 and fs.get("p99", 999.0) <= 33.0 and fs.get("max", 999.0) <= 50.0)
	var ok: bool = structures.released_count() == 36 and below.is_empty() and fps_ok
	_record("T27", "Benchmark do colapso total (4 pés no mesmo quadro): quadro e física por 6 s; critério de FPS em janela", ok, {
		"modo": _mode, "criterio_fps_aplicado": windowed, "criterio": "p95 ≤ 20 ms, p99 ≤ 33 ms, máx ≤ 50 ms",
		"intervalo_entre_quadros_ms": fs, "time_physics_process_ms": ps, "pico_pecas_dinamicas": peak_dynamic,
		"soltas": structures.released_count(), "abaixo_do_chao": below, "orcamento": budget.get_stats(),
		"poeira": main.dust.get_stats()})
	await _shot("t27_colapso_total_simultaneo", structures.tower_origin + Vector3(0, 0.5, 16), 0.0, -12.0)
	await main.request_world_reset()


# --- T25: 10 ciclos colapso → reset --------------------------------------------------------

func _t25_collapse_reset_cycles() -> void:
	var failures := []
	var durations := PackedFloat32Array()
	var released_per_cycle := []
	for c in 10:
		await main.request_world_reset()
		await _go_to_tower()
		for corner in [Vector2(-1, -1), Vector2(1, -1)]:
			await _dig_under(_foot_at(corner))
		await _wait_structures_idle(5.0)
		await _seconds(1.5)
		released_per_cycle.append(structures.released_count())
		var ok_reset: bool = await main.request_world_reset()
		durations.append(svc.get_last_ready_ms())
		await _seconds(0.5)
		var pieces := structures.get_pieces()
		var off_home := pieces.filter(func(p): return p.global_position.distance_to(p.home.origin) > 0.001 or not p.freeze or p.released)
		var debris_left := get_tree().get_nodes_in_group(DebrisBudget.GROUP).size()
		var nodes := get_tree().get_node_count()
		if not ok_reset or pieces.size() != 36 or not off_home.is_empty() or debris_left != 0 or nodes != _baseline_nodes \
				or released_per_cycle[-1] == 0:
			failures.append({"ciclo": c, "reset": ok_reset, "pecas": pieces.size(), "fora_do_lugar": off_home.size(),
				"destrocos_restantes": debris_left, "nos": nodes, "nos_baseline": _baseline_nodes,
				"soltas_antes_do_reset": released_per_cycle[-1]})
	_metrics["p2_reset10_ms"] = _stats(durations)
	_record("T25", "10 ciclos meia torre caída → reset: torre idêntica (36 peças no lugar, congeladas), sem destroços, nós = baseline",
		failures.is_empty(), {"falhas": failures, "soltas_por_ciclo": released_per_cycle,
		"duracao_reset_ms": _stats(durations), "nos_baseline": _baseline_nodes})


# --- T26: salvar/carregar com estruturas ---------------------------------------------------

func _t26_save_load_structures() -> void:
	const SLOT := "selftest_p2"
	var details := {}
	# A) Torre derrubada; salvar congela as peças soltas durante a recarga do terreno e as devolve.
	await main.request_world_reset()
	await _go_to_tower()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		await _dig_under(_foot_at(corner))
	await _wait_structures_idle(5.0)
	await _seconds(4.0)
	var pieces := structures.get_pieces()
	# Só compara posições com a cena parada: 4 s depois do colapso total ainda havia peça
	# deslizando a 0,56 m/s (medido), e o deslocamento seria do assentamento, não do save.
	var settled := await _wait_until(func(): return pieces.all(func(p): return p.freeze or p.linear_velocity.length() < 0.05), 15.0)
	# Controle: quanto as peças ainda andam sozinhas (sem save) num intervalo de 2 s.
	var ctrl0 := pieces.map(func(p): return p.global_position)
	await _seconds(2.0)
	var ctrl_shift := 0.0
	for i in pieces.size():
		ctrl_shift = maxf(ctrl_shift, pieces[i].global_position.distance_to(ctrl0[i]))
	var before := pieces.map(func(p): return p.global_position)
	var vel_before := pieces.map(func(p): return p.linear_velocity.length())
	var ok_save: bool = await main.request_world_save(SLOT)
	var right_after := pieces.map(func(p): return p.global_position)
	await _seconds(1.5)
	var max_shift := 0.0
	var worst := {}
	for i in pieces.size():
		var s := pieces[i].global_position.distance_to(before[i])
		if s > max_shift:
			max_shift = s
			worst = {"peca": pieces[i].name, "antes": str(before[i]), "logo_apos_save": str(right_after[i]),
				"depois_1_5s": str(pieces[i].global_position), "vel_antes": vel_before[i],
				"mudou_durante_save_m": right_after[i].distance_to(before[i])}
	var still_frozen := pieces.filter(func(p): return p.freeze and p.get_meta(DebrisBudget.PARKED_META, "") == "").size()
	var a_ok: bool = settled and ok_save and max_shift < 0.1 and still_frozen == 0 and structures.released_count() == 36
	details["A_salvar_com_torre_caida"] = {"salvo": ok_save, "cena_parada_antes": settled, "maior_deslocamento_m": max_shift, "pior_peca": worst,
		"controle_sem_save_2s_m": ctrl_shift, "salvar": svc.get_debug_stats().last_save,
		"pecas_ainda_congeladas_pelo_save": still_frozen, "soltas": structures.released_count(), "ok": a_ok}

	# B) Reset (torre de pé) → carregar o slot com o apoio escavado → a torre cai de novo.
	await main.request_world_reset()
	var intact_after_reset := structures.released_count() == 0
	var ok_load: bool = await main.request_world_load(SLOT)
	var t0 := Time.get_ticks_msec()
	await _wait_until(func(): return structures.released_count() == 36, 10.0)
	var collapse_ms := Time.get_ticks_msec() - t0
	await _wait_structures_idle(5.0)
	var b_ok: bool = intact_after_reset and ok_load and structures.released_count() == 36
	details["B_carregar_slot_escavado"] = {"intacta_apos_reset": intact_after_reset, "carregado": ok_load,
		"soltas": structures.released_count(), "ms_ate_36_soltas": collapse_ms, "ok": b_ok}
	await _shot("t26_torre_cai_apos_carregar", structures.tower_origin + Vector3(0, 0.5, 16), 0.0, -12.0)

	# C) Slot sem escavação perto da torre (o do T14 do P1) → nada cai.
	var c_ok := false
	if svc.has_saved_world(PERSIST_SLOT):
		var ok_load_c: bool = await main.request_world_load(PERSIST_SLOT)
		await _seconds(3.0)
		await _wait_structures_idle(5.0)
		c_ok = ok_load_c and structures.released_count() == 0
		details["C_carregar_slot_sem_escavacao"] = {"carregado": ok_load_c, "soltas": structures.released_count(),
			"stats": structures.get_stats(), "ok": c_ok}
	else:
		details["C_carregar_slot_sem_escavacao"] = {"erro": "slot %s ausente (o T14 não rodou)" % PERSIST_SLOT}
	_record("T26", "Salvar/carregar: peças soltas sobrevivem ao save; slot com apoio escavado derruba a torre de novo; slot sem escavação não",
		a_ok and b_ok and c_ok, details)
	await main.request_world_reset()


# --- T23: extração de rocha ----------------------------------------------------------------

var _rock: RigidBody3D
const ROCK_POINT := Vector3(-6, 0, 44)
const ROCK_RADIUS := 1.5


func _t23_extract_rock() -> void:
	var p := ROCK_POINT
	var ready := await _prepare_area(p + Vector3(0, 0, 10), AABB(p - Vector3(5, 5, 5), Vector3(10, 10, 10)))
	var mat_before := svc.get_material_at(p - Vector3(0, ROCK_RADIUS, 0))
	# Jogador em +z: a rocha sai do buraco para −z.
	var out: Dictionary = svc.extract_rock(p, Vector3.UP, ROCK_RADIUS, props, Vector3(0, 0, -1))
	var result: TerrainEditResult = out.result
	var bodies: Array = out.bodies
	var core := p - Vector3(0, ROCK_RADIUS, 0)
	var sdf_core := svc.sample_sdf(core)
	var w := await _wait_ray(p + Vector3.UP * 30.0, p + Vector3.DOWN * 30.0,
		func(h): return not h.is_empty() and h.position.y < -1.5, 5.0)
	await _seconds(4.0)
	_rock = bodies[0] as RigidBody3D if bodies.size() == 1 else null
	var details := {"edicao": str(result), "corpos": bodies.size(), "material_antes": str(mat_before),
		"sdf_no_nucleo_depois": sdf_core, "cavidade_no_collider_y": _hit_y(w.hit)}
	var ok: bool = ready and result != null and result.ok and _rock != null and sdf_core > 0.0 and w.ok
	if _rock != null:
		var volume: float = _rock.get_meta("volume_m3", 0.0)
		var sphere := 4.0 / 3.0 * PI * pow(ROCK_RADIUS, 3.0)
		var density := mat_before.density if mat_before != null else NAN
		var shape_ok := false
		for ch in _rock.get_children():
			shape_ok = shape_ok or (ch is CollisionShape3D and (ch as CollisionShape3D).shape is ConvexPolygonShape3D)
		var box := _mesh_box(_rock)
		var c := box.get_center()
		var floor_hit := svc.raycast_terrain(Vector3(c.x, 30, c.z), Vector3(c.x, -30, c.z))
		var from_hole := Vector2(c.x - p.x, c.z - p.z).length()
		details.merge({"camada": _rock.collision_layer, "mascara": _rock.collision_mask, "forma_convexa": shape_ok,
			"volume_malha_m3": volume, "volume_esfera_nominal_m3": sphere, "massa_kg": _rock.mass,
			"massa_esperada_kg": volume * density, "material": _rock.get_meta("material_id", &""),
			"no_grupo_debris": _rock.is_in_group(DebrisBudget.GROUP), "centro_malha": str(c),
			"fundo_malha_y": _mesh_bottom_y(_rock), "vel": _rock.linear_velocity.length(),
			"chao_sob_a_rocha_y": _hit_y(floor_hit), "distancia_ao_buraco_m": from_hole})
		ok = ok and _rock.collision_layer == Layers.PROPS and shape_ok and volume > 0.5 * sphere and volume < 1.3 * sphere \
			and absf(_rock.mass - volume * density) < 1.0 and mat_before != null \
			and _rock.get_meta("material_id", &"") == mat_before.id and _rock.is_in_group(DebrisBudget.GROUP) \
			and not floor_hit.is_empty() and absf(_mesh_bottom_y(_rock) - _hit_y(floor_hit)) < 0.6 and from_hole > 2.5 \
			and _rock.linear_velocity.length() < 0.3
	_record("T23", "Extração: núcleo do terreno vira corpo convexo (separate_floating_chunks) com massa = volume × densidade", ok, details)
	await _shot("t23_rocha_extraida", p + Vector3(0, 0.5, 6), 0.0, -30.0)


# --- T24: impulso de teste ---------------------------------------------------------------

func _t24_push_rock() -> void:
	if _rock == null or not is_instance_valid(_rock):
		_record("T24", "Impulso de teste desloca a rocha extraída", false, {"erro": "sem rocha do T23"})
		return
	var p0 := _mesh_box(_rock).get_center()
	var dir := Vector3(1, 0, 0)
	var state0 := _body_state(_rock)
	var applied := controller.apply_test_impulse(_rock, dir, 10.0)
	var max_y := p0.y
	var trace := []
	var t0 := Time.get_ticks_msec()
	var f := 0
	while Time.get_ticks_msec() - t0 < 1500:
		await get_tree().physics_frame
		f += 1
		max_y = maxf(max_y, _mesh_box(_rock).get_center().y)
		if f in [1, 2, 5, 10, 30, 60]:
			trace.append({"quadro": f, "estado": _body_state(_rock)})
	await _seconds(3.0)
	var p1 := _mesh_box(_rock).get_center()
	var hit := svc.raycast_terrain(Vector3(p1.x, 30, p1.z), Vector3(p1.x, -30, p1.z))
	var ok: bool = applied and max_y > p0.y + 1.0 and (p1.x - p0.x) > 2.0 and not hit.is_empty() \
		and p1.y > hit.position.y - 0.2
	_record("T24", "Impulso de teste (T) arremessa a rocha para fora da cavidade e ela repousa no terreno", ok, {
		"aplicado": applied, "pos_antes": str(p0), "altura_max": max_y, "pos_depois": str(p1),
		"deslocamento_x": p1.x - p0.x, "chao_y": _hit_y(hit), "vel_final": _rock.linear_velocity.length(),
		"massa_kg": _rock.mass, "estado_antes": state0, "rastro": trace})
	await _shot("t24_rocha_arremessada", p1 + Vector3(0, 0.5, 8), 0.0, -20.0)


# --- T18: corpo dormindo + escavação embaixo ------------------------------------------

func _t18_sleeping_crate() -> void:
	var waker: TerrainContactWaker = main.contact_waker
	var p := Vector3(8, 0.6, 44)
	var ready := await _prepare_area(p + Vector3(0, 0, 10), AABB(p - Vector3(4, 4, 4), Vector3(8, 8, 8)))
	var crate := DebugProps.spawn_crate(props, p)
	var slept := await _wait_until(func(): return crate.sleeping, 8.0)
	var y0 := crate.global_position.y
	var w0: int = waker.get_stats().woken
	var t0 := Time.get_ticks_msec()
	queue.enqueue(TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE, Vector3(p.x, 0, p.z), 2.5))
	var started := await _wait_until(func(): return crate.global_position.y < y0 - 0.3, 3.0)
	var start_ms := Time.get_ticks_msec() - t0
	await _seconds(2.5)
	var y1 := crate.global_position.y
	var floor_y := _hit_y(svc.raycast_terrain(Vector3(p.x, 30, p.z), Vector3(p.x, -30, p.z)))
	var woken: int = waker.get_stats().woken - w0
	var ok: bool = ready and slept and started and y1 < -1.0 and y1 > floor_y - 0.1 and woken >= 1
	_record("T18", "Caixa dormindo sobre o solo cai quando o chão embaixo é escavado (contato atualizado)", ok, {
		"dormiu": slept, "y_antes": y0, "comecou_a_cair": started, "ms_ate_cair_0_3m": start_ms,
		"y_depois": y1, "fundo_cratera_y": floor_y, "acordados_pelo_waker": woken, "stats_waker": waker.get_stats()})
	crate.queue_free()
	await _seconds(0.2)


# --- T19: torre intacta e grafo de apoio ---------------------------------------------

func _t19_tower_intact() -> void:
	await main.request_world_reset()
	await _go_to_tower()
	var pieces := structures.get_pieces()
	var t_start := Time.get_ticks_msec()
	await _seconds(5.0)
	var moved := []
	var unfrozen := []
	for p in pieces:
		if p.global_position.distance_to(p.home.origin) > 0.001:
			moved.append(p.name)
		if not p.freeze or p.released:
			unfrozen.append(p.name)
	# Estrutura do grafo esperada pela montagem (TowerFactory).
	var feet := pieces.filter(func(p): return p.is_foot).size()
	var slabs := pieces.filter(func(p): return p.kind.begins_with("laje"))
	var slabs_ok := slabs.all(func(p): return p.below.size() == 1 and p.lateral.size() == 2)
	var mid_crowns := pieces.filter(func(p): return p.kind == "coroa" and p.below.size() == 2).size()
	var sup := SupportGraph.supported(pieces)
	var all_supported := sup.count(1) == pieces.size()
	var ok := pieces.size() == 36 and moved.is_empty() and unfrozen.is_empty() and feet == 4 and slabs.size() == 8 \
		and slabs_ok and mid_crowns == 4 and all_supported
	_record("T19", "Torre modular intacta: 36 peças congeladas paradas 5 s; grafo de apoio como montado", ok, {
		"pecas": pieces.size(), "pes": feet, "placas": slabs.size(), "placas_1_embaixo_2_laterais": slabs_ok,
		"coroa_apoiada_em_2_placas": mid_crowns, "todas_apoiadas": all_supported, "moveram": moved,
		"soltas": unfrozen, "segundos": (Time.get_ticks_msec() - t_start) / 1000.0})
	await _shot("t19_torre_intacta", structures.tower_origin + Vector3(0, 0.5, 16), 0.0, -8.0)


# --- T20: um pilar sem apoio → colapso parcial -----------------------------------------

func _t20_partial_collapse() -> void:
	var pieces := structures.get_pieces()
	var foot := _foot_at(Vector2(-1, -1))
	var pillar := _pillar_of(foot)
	var r0: int = structures.get_stats().released
	var ok_dig := await _dig_under(foot)
	await _wait_structures_idle(5.0)
	await _seconds(3.0)
	var released := pieces.filter(func(p): return p.released).map(func(p): return p.name)
	var expected := pillar.map(func(p): return p.name)
	released.sort()
	expected.sort()
	var fell := pillar.all(func(p): return p.global_position.y < p.home.origin.y - 1.0)
	var others_home := pieces.filter(func(p): return not p.released).all(
		func(p): return p.global_position.distance_to(p.home.origin) < 0.001)
	var st := structures.get_stats()
	var ok: bool = ok_dig and released == expected and fell and others_home and st.max_released_in_frame <= structures.max_releases_per_frame \
		and st.confirm_timeouts == 0
	_record("T20", "Escavar sob 1 pilar solta só esse pilar (laje fica: 2 placas vizinhas a sustentam)", ok, {
		"pe": foot.name, "soltas": released, "esperadas": expected, "pilar_caiu": fell,
		"demais_no_lugar": others_home, "soltas_no_teste": st.released - r0, "ultima_checagem": st.last_check,
		"confirmacao_collider_ms": st.last_confirm_ms, "timeouts_confirmacao": st.confirm_timeouts})
	await _shot("t20_colapso_parcial", structures.tower_origin + Vector3(0, 0.5, 16), 0.0, -8.0)


# --- T21: os outros pilares → colapso total em etapas -----------------------------------

func _t21_full_collapse() -> void:
	var pieces := structures.get_pieces()
	var rel_frames := []
	var cb := func(p: StructurePiece): rel_frames.append(Engine.get_physics_frames())
	structures.piece_released.connect(cb)
	var t0 := Time.get_ticks_msec()
	var digs := []
	for c in [Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		digs.append(await _dig_under(_foot_at(c)))
	await _wait_structures_idle(5.0)
	await _seconds(6.0)
	structures.piece_released.disconnect(cb)
	var per_frame := {}
	for f in rel_frames:
		per_frame[f] = per_frame.get(f, 0) + 1
	var max_per_frame := 0
	for f in per_frame:
		max_per_frame = maxi(max_per_frame, per_frame[f])
	var below_ground := []
	var far := []
	var moving := 0
	for p in pieces:
		var c := p.global_position
		var hit := svc.raycast_terrain(Vector3(c.x, 40, c.z), Vector3(c.x, -40, c.z))
		if hit.is_empty() or c.y < hit.position.y - 0.2:
			below_ground.append({"peca": p.name, "y": c.y, "chao_y": _hit_y(hit)})
		var horiz := Vector2(c.x - structures.tower_origin.x, c.z - structures.tower_origin.z).length()
		if horiz > 15.0:
			far.append({"peca": p.name, "dist": horiz})
		if p.linear_velocity.length() > 0.2:
			moving += 1
	var all_released := pieces.all(func(p): return p.released)
	var frames_span: int = (rel_frames.max() - rel_frames.min()) if not rel_frames.is_empty() else 0
	var ok: bool = digs.all(func(d): return d) and all_released and below_ground.is_empty() and far.is_empty() \
		and max_per_frame <= structures.max_releases_per_frame and per_frame.size() >= 2 and structures.get_stats().confirm_timeouts == 0
	_record("T21", "Escavar sob os outros 3 pilares: colapso total em etapas, peças sobre o terreno", ok, {
		"soltas": rel_frames.size(), "todas_soltas": all_released, "quadros_com_soltura": per_frame.size(),
		"max_por_quadro": max_per_frame, "quadros_entre_primeira_e_ultima": frames_span,
		"abaixo_do_chao": below_ground, "longe_mais_de_15m": far, "ainda_em_movimento_apos_6s": moving,
		"duracao_s": (Time.get_ticks_msec() - t0) / 1000.0, "stats": structures.get_stats()})
	await _shot("t21_colapso_total", structures.tower_origin + Vector3(0, 0.5, 16), 0.0, -12.0)


# --- T22: teto de corpos ativos ----------------------------------------------------------

## Depois do colapso do T21 (36 peças soltas), solta 150 caixas perto da torre: o orçamento
## deve levar os corpos dinâmicos ao teto, estacionando só corpos já parados.
func _t22_body_budget() -> void:
	var budget: DebrisBudget = main.debris
	var s0 := budget.get_stats()
	var base := structures.tower_origin + Vector3(-14, 4, 6)
	for i in 150:
		var col := i % 15
		var row := (i / 15) % 5
		var layer := i / 75
		DebugProps.spawn_crate(props, base + Vector3(col * 2.0, layer * 1.5, row * 2.0))
	var peak := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await _seconds(0.25)
		peak = maxi(peak, budget.get_stats().active)
	var s1 := budget.get_stats()
	var below := 0
	for c in props.get_children():
		var b := c as Node3D
		var hit := svc.raycast_terrain(Vector3(b.global_position.x, 40, b.global_position.z), Vector3(b.global_position.x, -40, b.global_position.z))
		if hit.is_empty() or b.global_position.y < hit.position.y - 0.2:
			below += 1
	var ok: bool = s1.tracked >= 186 and s1.active <= budget.max_active and s1.parked >= s1.tracked - budget.max_active \
		and s1.max_park_speed < budget.settle_speed and below == 0
	_record("T22", "Orçamento: 150 caixas + 36 peças → corpos ativos ≤ teto; só corpos parados são estacionados", ok, {
		"antes": s0, "depois": s1, "pico_ativos_amostrado": peak, "teto": budget.max_active,
		"caixas_abaixo_do_chao": below})
	await _shot("t22_orcamento_150_caixas", structures.tower_origin + Vector3(0, 0.5, 22), 0.0, -14.0)
	for c in props.get_children():
		c.queue_free()
	await _seconds(0.3)


# --- Utilidades P2 ------------------------------------------------------------------------

## Menor y real da malha (vértices transformados; a AABB transformada de um corpo girado
## envolve a malha e fica abaixo do fundo verdadeiro).
func _mesh_bottom_y(b: RigidBody3D) -> float:
	var low := INF
	for ch in b.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					low = minf(low, (mi.global_transform * v).y)
	return low


## Caixa da malha do corpo no mundo (a origem do corpo criado pelo Voxel Tools não é o centro).
func _mesh_box(b: RigidBody3D) -> AABB:
	for ch in b.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			return mi.global_transform * mi.mesh.get_aabb()
	return AABB(b.global_position, Vector3.ZERO)


func _body_state(b: RigidBody3D) -> String:
	var timer := ""
	for ch in b.get_children():
		if ch is Timer:
			timer = " timer(parado=%s resta=%.2f one_shot=%s)" % [(ch as Timer).is_stopped(), (ch as Timer).time_left, (ch as Timer).one_shot]
	return "pos=%s vel=%s freeze=%s modo=%d sleeping=%s parked=%s%s" % [b.global_position, b.linear_velocity, b.freeze,
		b.freeze_mode, b.sleeping, b.get_meta(DebrisBudget.PARKED_META, ""), timer]

## Jogador a 16 m da torre (fora do alcance da queda), com os pés da torre no LOD0 carregado.
func _go_to_tower() -> bool:
	player.teleport_to(structures.tower_origin + Vector3(0, 0.5, 16))
	var region := structures.get_anchor_region().grow(3.0)
	var ok := await _wait_until(func(): return svc.can_edit_area(region), 10.0)
	await _seconds(0.3)
	return ok


func _foot_at(corner: Vector2) -> StructurePiece:
	for p in structures.get_pieces():
		if p.is_foot:
			var d := p.home.origin - structures.tower_origin
			if signf(d.x) == corner.x and signf(d.z) == corner.y:
				return p
	return null


## Pé + os blocos empilhados acima dele no mesmo pilar do térreo.
func _pillar_of(foot: StructurePiece) -> Array:
	var out := [foot]
	for p in structures.get_pieces():
		if p.kind == foot.kind and p != foot and absf(p.home.origin.x - foot.home.origin.x) < 0.01 \
				and absf(p.home.origin.z - foot.home.origin.z) < 0.01:
			out.append(p)
	return out


## Escava (pela fila) uma esfera de 2 m sob o pé e espera o collider mostrar o buraco.
func _dig_under(foot: StructurePiece) -> bool:
	var c := foot.home.origin
	var p := Vector3(c.x, 0.0, c.z)
	var req := TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE, p, 2.0)
	req.source = "selftest:P2"
	queue.enqueue(req)
	await _drain_queue()
	var w := await _wait_ray(p + Vector3.UP * 30.0, p + Vector3.DOWN * 30.0,
		func(h): return not h.is_empty() and h.position.y < -1.5, 5.0)
	return w.ok


func _wait_structures_idle(timeout_s: float) -> bool:
	await get_tree().physics_frame
	return await _wait_until(func(): return not structures.is_busy(), timeout_s)
