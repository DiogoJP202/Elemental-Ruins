extends Node
## Roteiro automatizado de aceite do P0 (ver P0_CHECKLIST.md).
##
## Roda dentro da cena real (scenes/main.tscn), usando o mesmo TerrainService,
## jogador e física do jogo. Prova colisão por raycasts físicos e por
## movimento do CharacterBody3D com input simulado, não por inspeção de dados.
##
##   godot --headless --path . res://scenes/main.tscn -- --p0-selftest
##   godot --path . res://scenes/main.tscn -- --p0-selftest --p0-screenshots
##   opcional: --report=<caminho.json>
##
## Código de saída: 0 = todos PASS, 1 = algum FAIL, 2 = watchdog estourou.

const LOGGER_SCRIPT := preload("res://scripts/dev/error_counter_logger.gd")
const WATCHDOG_S := 420.0
const PROBE_TOLERANCE := 0.05

# Geometria do laboratório (ver LabTerrainFactory).
const SPAWN := Vector3(0, 1, 28)
const CRATER_POINT := Vector3(14, 0, 22)
const CRATER_RADIUS := 3.0
const COLUMN_POINT := Vector3(-14, 0, 22)
const REPEAT_POINT := Vector3(-14, 0, 36)
const TUNNEL_Y := 1.5
const TUNNEL_RADIUS := 1.8
const TUNNEL_Z_START := 16.0
const TUNNEL_Z_MID := -10.0
const TUNNEL_Z_END := -36.0

var main: Node
var svc: TerrainService
var player: PlayerController
var props: Node3D

var _screens := false
var _only: PackedStringArray = []
var _report_path := ""
var _mode := ""
var _results: Array[Dictionary] = []
var _metrics := {}
var _baseline := {}
var _baseline_nodes := 0
var _logger: Logger
var _fps_samples: PackedFloat32Array = []
var _shot_index := 0
var _t_start := 0


func _ready() -> void:
	main = get_parent()
	svc = main.terrain_service
	player = main.player
	props = main.props_root
	var headless := DisplayServer.get_name() == "headless"
	var args := OS.get_cmdline_user_args()
	_screens = args.has("--p0-screenshots") and not headless
	for a: String in args:
		if a.begins_with("--report="):
			_report_path = a.trim_prefix("--report=")
		elif a.begins_with("--only="):
			_only = a.trim_prefix("--only=").split(",", false)
	_mode = "headless" if headless else "window"
	if not OS.has_feature("editor"):
		_mode += "-export"
	if _report_path == "":
		var base := "res://docs/evidence/" if OS.has_feature("editor") else "user://"
		_report_path = base + "p0_selftest_%s.json" % _mode
	player.input_enabled = false
	# Não prende o mouse do usuário enquanto o roteiro roda em janela.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_logger = LOGGER_SCRIPT.new()
	OS.add_logger(_logger)
	get_tree().create_timer(WATCHDOG_S, true).timeout.connect(_on_watchdog)
	if not headless:
		get_tree().create_timer(0.5, true).timeout.connect(_sample_fps)
	_run.call_deferred()


func _run() -> void:
	_t_start = Time.get_ticks_msec()
	_log("início | modo=%s | screenshots=%s | Godot %s" % [_mode, _screens, Engine.get_version_info().string])

	await _t1_ground()
	if _results.back().status != "PASS":
		_finish()
		return
	await _capture_baseline()
	if _should_run("T0"): await _t0_generator_data()
	if _should_run("T1b"): await _t1b_hill_top()
	if _should_run("T2"): await _t2_crater()
	if _should_run("T3"): await _t3_tunnel()
	if _should_run("T4"): await _t4_column()
	if _should_run("T5"): await _t5_repeated_edits()
	if _should_run("T5b"): await _t5b_stress_100()
	if _should_run("T6"): await _t6_invalid_edits()
	if _should_run("T7"): await _t7_reset()
	if _should_run("T7b"): await _t7b_reset_cycles()
	_finish()


## --only=T2,T5 limita os testes (T1 e baseline sempre rodam). Útil para depurar.
func _should_run(id: String) -> bool:
	return _only.is_empty() or _only.has(id)


# --- Testes -------------------------------------------------------------------

func _t1_ground() -> void:
	var ready := await _wait_until(func(): return svc.is_ready() and not player.is_frozen(), 30.0)
	_metrics["initial_terrain_ready_ms"] = svc.get_last_ready_ms()
	if not ready:
		_record("T1", "Terreno pronto e jogador sobre colina/solo", false, {"erro": "terreno não ficou pronto em 30 s"})
		return
	await _seconds(2.0)
	var y1 := player.global_position.y
	var floor1 := player.is_on_floor()
	await _seconds(1.5)
	var y2 := player.global_position.y
	var ok := floor1 and player.is_on_floor() and absf(y1) < 0.3 and absf(y2 - y1) < 0.02
	_record("T1", "Terreno pronto; jogador para no chão voxel e não atravessa", ok,
		{"pronto_ms": svc.get_last_ready_ms(), "y_apos_2s": y1, "y_apos_3_5s": y2, "on_floor": floor1})
	_baseline_nodes = get_tree().get_node_count()
	await _shot("spawn_vista_colina", SPAWN, 0.0, -8.0)


func _capture_baseline() -> void:
	_baseline = await _settled_probes(10.0)
	var missing := []
	for k in _baseline:
		if _baseline[k] == null and not k.begins_with("h_"):
			missing.append(k)
	_metrics["baseline_probes"] = _baseline.size()
	_log("baseline: %d probes, sem chão em %s" % [_baseline.size(), missing])


func _t0_generator_data() -> void:
	var inside_hill := svc.sample_sdf(Vector3(0, 5, -10))
	var above_hill := svc.sample_sdf(Vector3(0, 20, -10))
	var above_ground := svc.sample_sdf(Vector3(20, 1.5, 30))
	var below_ground := svc.sample_sdf(Vector3(20, -1.5, 30))
	var top_hit := svc.raycast_terrain(Vector3(0, 40, -10), Vector3(0, -20, -10))
	var top_y: float = top_hit.position.y if not top_hit.is_empty() else NAN
	var ok := inside_hill < 0.0 and above_hill > 0.0 and above_ground > 0.0 and below_ground < 0.0 \
		and absf(top_y - LabTerrainFactory.HILL_TOP_Y) < 0.6
	_record("T0", "Dados SDF volumétricos coerentes com o gerador (colina sólida, ar acima)", ok, {
		"sdf_dentro_colina": inside_hill, "sdf_acima_colina": above_hill,
		"sdf_acima_solo": above_ground, "sdf_abaixo_solo": below_ground,
		"topo_colina_colisao_y": top_y, "topo_esperado_y": LabTerrainFactory.HILL_TOP_Y})


func _t1b_hill_top() -> void:
	var top := Vector3(0, LabTerrainFactory.HILL_TOP_Y + 1.5, LabTerrainFactory.HILL_CENTER.z)
	player.teleport_to(top)
	await _seconds(2.0)
	var y1 := player.global_position.y
	await _seconds(1.0)
	var y2 := player.global_position.y
	var ok := player.is_on_floor() and absf(y1 - LabTerrainFactory.HILL_TOP_Y) < 0.3 and absf(y2 - y1) < 0.05
	_record("T1b", "Jogador fica sobre o topo da colina voxel sem atravessar", ok, {
		"y_apos_2s": y1, "y_apos_3s": y2, "topo_esperado_y": LabTerrainFactory.HILL_TOP_Y,
		"on_floor": player.is_on_floor()})
	player.teleport_to(SPAWN)
	await _seconds(0.5)


func _t2_crater() -> void:
	var from := CRATER_POINT + Vector3.UP * 30.0
	var to := CRATER_POINT + Vector3.DOWN * 30.0
	var before := _hit_y(svc.raycast_terrain(from, to))
	var r := svc.dig_sphere(CRATER_POINT, CRATER_RADIUS)
	var sdf_now := svc.sample_sdf(CRATER_POINT + Vector3.DOWN * 1.5)
	var w := await _wait_ray(from, to, func(h): return not h.is_empty() and h.position.y < -2.0, 5.0)
	_metrics["crater_collider_latency_ms"] = w.ms
	await _shot("cratera", CRATER_POINT + Vector3(0, 0.2, 9), 0.0, -32.0)
	player.teleport_to(CRATER_POINT + Vector3.UP * 1.0)
	await _seconds(2.0)
	var py := player.global_position.y
	var ok: bool = r.ok and w.ok and sdf_now > 0.0 and py < -1.5 and player.is_on_floor()
	_record("T2", "Escavar remove matéria E colisão; jogador cai na cratera", ok, {
		"edicao": str(r), "chao_antes_y": before, "chao_depois_y": _hit_y(w.hit),
		"sdf_dados_logo_apos_edicao": sdf_now, "latencia_collider_ms": w.ms, "quadros_fisica": w.frames,
		"jogador_y_apos_2s": py, "on_floor": player.is_on_floor()})
	await _shot("jogador_na_cratera", player.global_position, 0.0, -20.0, false)
	player.teleport_to(SPAWN)
	await _seconds(0.5)


func _t3_tunnel() -> void:
	var axis_from := Vector3(0, TUNNEL_Y, 20)
	var axis_to := Vector3(0, TUNNEL_Y, -45)
	var face_before := svc.raycast_terrain(axis_from, axis_to)
	var top_from := Vector3(0, 40, TUNNEL_Z_MID)
	var top_before := _hit_y(svc.raycast_terrain(top_from, Vector3(0, -20, TUNNEL_Z_MID)))

	var r1 := svc.dig_path(_tunnel_points(TUNNEL_Z_START, TUNNEL_Z_MID), _radii(7))
	var r2 := svc.dig_path(_tunnel_points(TUNNEL_Z_MID, TUNNEL_Z_END), _radii(7))
	var w := await _wait_ray(axis_from, axis_to, func(h): return h.is_empty(), 8.0)
	_metrics["tunnel_collider_latency_ms"] = w.ms

	var top_after := _hit_y(svc.raycast_terrain(top_from, Vector3(0, -20, TUNNEL_Z_MID)))
	var inside := Vector3(0, TUNNEL_Y, TUNNEL_Z_MID)
	var ceil_y := _hit_y(svc.raycast_terrain(inside, inside + Vector3.UP * 30.0))
	var floor_y := _hit_y(svc.raycast_terrain(inside, inside + Vector3.DOWN * 10.0))
	var geom_ok: bool = r1.ok and r2.ok and w.ok and not face_before.is_empty() \
		and absf(top_after - top_before) < 0.05 and ceil_y > 2.5 and ceil_y < 4.5 \
		and floor_y > -1.0 and floor_y < 0.5
	_record("T3a", "Túnel escavado: eixo livre, teto e piso sólidos (raycasts físicos)", geom_ok, {
		"edicoes": [str(r1), str(r2)], "face_antes_z": face_before.position.z if not face_before.is_empty() else null,
		"eixo_livre_apos_ms": w.ms, "topo_antes_y": top_before, "topo_depois_y": top_after,
		"teto_interno_y": ceil_y, "piso_interno_y": floor_y})

	# Travessia com input simulado (mesmo move_and_slide do jogo).
	player.teleport_to(Vector3(0, 0.5, 19))
	player.camera_rig.set_view(0.0, deg_to_rad(-6.0))
	await _seconds(0.6)
	await _shot("boca_do_tunel", player.global_position, 0.0, -6.0, false)
	var min_y := INF
	var max_y := -INF
	var ceiling_samples := 0
	var ceiling_hits := 0
	var inside_shot_done := false
	var t0 := Time.get_ticks_msec()
	player.set_scripted_move(Vector3.FORWARD)
	var reached := false
	while Time.get_ticks_msec() - t0 < 20000:
		await get_tree().physics_frame
		var p := player.global_position
		if p.z < 5.0 and p.z > -25.0:
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
			ceiling_samples += 1
			var up := svc.raycast_terrain(p + Vector3.UP * 1.0, p + Vector3.UP * 8.0)
			if not up.is_empty():
				ceiling_hits += 1
		if not inside_shot_done and p.z < TUNNEL_Z_MID and _screens:
			inside_shot_done = true
			player.clear_scripted_move()
			await _shot("dentro_do_tunel", p, 0.0, -2.0, false)
			player.set_scripted_move(Vector3.FORWARD)
		if p.z < TUNNEL_Z_END - 1.0:
			reached = true
			break
	player.clear_scripted_move()
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	var walk_ok := reached and max_y < 1.5 and min_y > -1.5 and ceiling_samples > 0 and ceiling_hits == ceiling_samples
	_record("T3b", "Jogador atravessa o túnel de boca a boca com teto sólido acima", walk_ok, {
		"chegou_na_saida": reached, "tempo_s": elapsed, "z_final": player.global_position.z,
		"y_min_dentro": min_y, "y_max_dentro": max_y,
		"amostras_teto": ceiling_samples, "amostras_com_teto": ceiling_hits})
	await _shot("saida_olhando_para_tras", player.global_position, PI, -6.0, false)
	player.teleport_to(SPAWN)
	await _seconds(0.5)


func _t4_column() -> void:
	var from := COLUMN_POINT + Vector3.UP * 30.0
	var to := COLUMN_POINT + Vector3.DOWN * 10.0
	var rs: Array[String] = []
	var all_ok := true
	for y in [0.5, 2.5, 4.5]:
		var r := svc.add_sphere(COLUMN_POINT + Vector3(0, y, 0), 2.0)
		rs.append(str(r))
		all_ok = all_ok and r.ok
		await get_tree().physics_frame
	var w := await _wait_ray(from, to, func(h): return not h.is_empty() and h.position.y > 5.5, 5.0)
	_metrics["column_collider_latency_ms"] = w.ms
	var crate := DebugProps.spawn_crate(props, COLUMN_POINT + Vector3.UP * 10.0)
	await _seconds(3.0)
	var crate_y := crate.global_position.y
	var crate_v := crate.linear_velocity.length()
	player.teleport_to(COLUMN_POINT + Vector3(0, 9.0, -1.0))
	await _seconds(2.0)
	var py := player.global_position.y
	var ok: bool = all_ok and w.ok and crate_y > 6.0 and crate_v < 0.3 and py > 5.0 and player.is_on_floor()
	_record("T4", "Adicionar matéria forma coluna sólida (caixa e jogador apoiados)", ok, {
		"edicoes": rs, "topo_coluna_y": _hit_y(w.hit), "latencia_collider_ms": w.ms,
		"caixa_y_apos_3s": crate_y, "caixa_vel": crate_v, "jogador_y_no_topo": py,
		"on_floor": player.is_on_floor()})
	player.teleport_to(SPAWN)
	await _seconds(0.3)
	await _shot("coluna_com_caixa", COLUMN_POINT + Vector3(0, 0.2, 10), 0.0, -14.0)


func _t5_repeated_edits() -> void:
	var nodes_before := get_tree().get_node_count()
	var from := REPEAT_POINT + Vector3.UP * 30.0
	var to := REPEAT_POINT + Vector3.DOWN * 30.0
	var lat: PackedFloat32Array = []
	var failures := []
	for i in 20:
		var d := svc.dig_sphere(REPEAT_POINT, 2.0)
		var wd := await _wait_ray(from, to, func(h): return not h.is_empty() and h.position.y < -1.0, 5.0)
		var hit_after_dig := svc.raycast_terrain(from, to)
		var y_after_dig := _hit_y(hit_after_dig)
		var sdf_after_dig := [svc.sample_sdf(REPEAT_POINT + Vector3.UP), svc.sample_sdf(REPEAT_POINT),
			svc.sample_sdf(REPEAT_POINT + Vector3.DOWN), svc.sample_sdf(REPEAT_POINT + Vector3.DOWN * 2.0)]
		var a := svc.add_sphere(REPEAT_POINT, 2.0)
		var wa := await _wait_ray(from, to, func(h): return not h.is_empty() and h.position.y > -0.5, 5.0)
		if not (d.ok and wd.ok and a.ok and wa.ok):
			failures.append({"ciclo": i, "dig": str(d), "dig_col": wd.ok, "add": str(a), "add_col": wa.ok,
				"y_apos_dig": y_after_dig, "sdf_apos_dig_y+1_0_-1_-2": sdf_after_dig,
				"hit_rid": str(hit_after_dig.get("rid", "")), "hit_shape": hit_after_dig.get("shape", -1),
				"blocos_y+2": _debug_blocks(REPEAT_POINT + Vector3.UP * 2.0),
				"blocos_y-2": _debug_blocks(REPEAT_POINT + Vector3.DOWN * 2.0),
				"y_apos_add": _hit_y(svc.raycast_terrain(from, to))})
		lat.append(wd.ms)
		lat.append(wa.ms)
	var nodes_after := get_tree().get_node_count()
	var ok := failures.is_empty() and nodes_after == nodes_before and svc.is_ready()
	_metrics["repeat_latency_ms"] = _stats(lat)
	_record("T5", "20 ciclos escavar+adicionar no mesmo ponto (40 edições)", ok, {
		"falhas": failures, "nos_antes": nodes_before, "nos_depois": nodes_after,
		"latencia_collider_ms": _stats(lat)})


func _t5b_stress_100() -> void:
	var lat: PackedFloat32Array = []
	var call_ms: PackedFloat32Array = []
	var failures := 0
	var timeouts := 0
	var i := 0
	for zi in 10:
		for xi in 10:
			var p := Vector3(-22.5 + xi * 5.0, 0.0, 38.0 + zi * 2.0)
			var from := p + Vector3.UP * 30.0
			var to := p + Vector3.DOWN * 30.0
			var y0 := _hit_y(svc.raycast_terrain(from, to))
			var r := svc.dig_sphere(p, 1.5)
			if not r.ok:
				failures += 1
				continue
			call_ms.append(r.duration_usec / 1000.0)
			var w := await _wait_ray(from, to, func(h): return not h.is_empty() and h.position.y < y0 - 0.4, 5.0)
			if w.ok:
				lat.append(w.ms)
			else:
				timeouts += 1
			i += 1
	_metrics["stress100_collider_latency_ms"] = _stats(lat)
	_metrics["stress100_edit_call_ms"] = _stats(call_ms)
	var ok := failures == 0 and timeouts == 0 and svc.is_ready()
	_record("T5b", "100 escavações em sequência (latência edição→collider)", ok, {
		"executadas": i, "recusadas": failures, "timeouts_collider": timeouts,
		"latencia_collider_ms": _stats(lat), "tempo_chamada_ms": _stats(call_ms)})


func _t6_invalid_edits() -> void:
	var cases := [
		{"desc": "fora dos voxel_bounds", "point": Vector3(5000, 0, 5000), "r": 2.0, "add": false, "expect": "outside_bounds"},
		{"desc": "dentro dos bounds, fora do LOD0 carregado", "point": Vector3(200, 0, 200), "r": 2.0, "add": false, "expect": "area_not_loaded"},
		{"desc": "raio gigante", "point": Vector3(0, 0, 40), "r": 50.0, "add": false, "expect": "radius_out_of_range"},
		{"desc": "adicionar sobre o jogador", "point": player.global_position + Vector3.UP, "r": 1.5, "add": true, "expect": "overlaps_player"},
	]
	var details := []
	var ok := true
	for c: Dictionary in cases:
		var t0 := Time.get_ticks_usec()
		var r := svc.add_sphere(c.point, c.r) if c.add else svc.dig_sphere(c.point, c.r)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var case_ok: bool = not r.ok and r.reason == c.expect and ms < 20.0
		ok = ok and case_ok
		details.append({"caso": c.desc, "resultado": str(r), "esperado": c.expect, "ms": ms, "ok": case_ok})
	_record("T6", "Edições inválidas/fora da área falham rápido e com motivo", ok, {"casos": details})


func _t7_reset() -> void:
	var gen_before := svc.get_world_generation()
	var props_before := props.get_child_count()
	var ok_reset: bool = await main.request_world_reset()
	var probes := await _settled_probes(10.0, _baseline)
	var mismatches := _compare(_baseline, probes)
	await _seconds(0.5)
	var nodes_after := get_tree().get_node_count()
	var ok := ok_reset and mismatches.is_empty() and svc.get_world_generation() == gen_before + 1 \
		and props.get_child_count() == 0 and nodes_after == _baseline_nodes
	_record("T7", "Reset restaura geometria E colisão originais (cratera, túnel e coluna somem)", ok, {
		"reset_ok": ok_reset, "duracao_ms": svc.get_last_ready_ms(), "probes_diferentes": mismatches,
		"props_antes": props_before, "props_depois": props.get_child_count(),
		"nos_baseline": _baseline_nodes, "nos_depois": nodes_after})
	await _shot("pos_reset_colina", SPAWN, 0.0, -8.0)
	await _shot("pos_reset_tunel_fechado", Vector3(0, 0.5, 19), 0.0, -6.0)
	player.teleport_to(SPAWN)
	await _seconds(0.3)


func _t7b_reset_cycles() -> void:
	var durations: PackedFloat32Array = []
	var failures := []
	var from := CRATER_POINT + Vector3.UP * 30.0
	var to := CRATER_POINT + Vector3.DOWN * 30.0
	for i in 10:
		var r := svc.dig_sphere(CRATER_POINT, CRATER_RADIUS)
		var w := await _wait_ray(from, to, func(h): return not h.is_empty() and h.position.y < -2.0, 5.0)
		var ok_reset: bool = await main.request_world_reset()
		durations.append(svc.get_last_ready_ms())
		var probes := await _settled_probes(10.0, _baseline)
		var mism := _compare(_baseline, probes)
		if not (r.ok and w.ok and ok_reset and mism.is_empty()):
			failures.append({"ciclo": i, "dig": str(r), "cratera_colisao": w.ok, "reset": ok_reset, "diferencas": mism})
	await _seconds(0.5)
	var nodes_after := get_tree().get_node_count()
	_metrics["reset_ms"] = _stats(durations)
	var ok := failures.is_empty() and nodes_after == _baseline_nodes
	_record("T7b", "10 ciclos escavar→reset retornam ao baseline", ok, {
		"falhas": failures, "duracao_reset_ms": _stats(durations),
		"nos_baseline": _baseline_nodes, "nos_depois": nodes_after})


# --- Probes -------------------------------------------------------------------

func _probe_defs() -> Dictionary:
	var defs := {}
	for xz: Vector2 in [Vector2(0, 28), Vector2(0, -10), Vector2(10, -10), Vector2(0, 5),
			Vector2(14, 22), Vector2(-14, 22), Vector2(-14, 36), Vector2(-20, -10),
			Vector2(0, -25), Vector2(20, 40), Vector2(-10, 46), Vector2(5, 50)]:
		defs["v(%d,%d)" % [xz.x, xz.y]] = [Vector3(xz.x, 40, xz.y), Vector3(xz.x, -30, xz.y)]
	defs["h_tunel_sul_norte"] = [Vector3(0, TUNNEL_Y, 20), Vector3(0, TUNNEL_Y, -45)]
	defs["h_tunel_norte_sul"] = [Vector3(0, TUNNEL_Y, -45), Vector3(0, TUNNEL_Y, 20)]
	return defs


func _sample_probes() -> Dictionary:
	var out := {}
	var defs := _probe_defs()
	for k: String in defs:
		var hit := svc.raycast_terrain(defs[k][0], defs[k][1])
		out[k] = null if hit.is_empty() else hit.position
	return out


## Amostra até duas leituras seguidas iguais (malhas/colliders assentados).
## Se `target` for dado, também espera coincidir com ele (até o timeout).
func _settled_probes(timeout_s: float, target := {}) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var prev := {}
	var cur := {}
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		await get_tree().physics_frame
		cur = _sample_probes()
		var stable := not prev.is_empty() and _compare(prev, cur).is_empty()
		if stable and (target.is_empty() or _compare(target, cur).is_empty()):
			return cur
		prev = cur
	return cur


func _compare(a: Dictionary, b: Dictionary) -> Array:
	var diffs := []
	for k in a:
		var va = a[k]
		var vb = b.get(k)
		if va == null and vb == null:
			continue
		if va == null or vb == null or va.distance_to(vb) > PROBE_TOLERANCE:
			diffs.append({"probe": k, "esperado": str(va), "obtido": str(vb)})
	return diffs


# --- Utilidades ---------------------------------------------------------------

func _tunnel_points(z0: float, z1: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 7:
		pts.append(Vector3(0, TUNNEL_Y, lerpf(z0, z1, i / 6.0)))
	return pts


func _radii(n: int) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	for i in n:
		r.append(TUNNEL_RADIUS)
	return r


func _wait_ray(from: Vector3, to: Vector3, pred: Callable, timeout_s: float) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var deadline := t0 + int(timeout_s * 1000000.0)
	var frames := 0
	while Time.get_ticks_usec() < deadline:
		await get_tree().physics_frame
		frames += 1
		var hit := svc.raycast_terrain(from, to)
		if pred.call(hit):
			return {"ok": true, "ms": (Time.get_ticks_usec() - t0) / 1000.0, "frames": frames, "hit": hit}
	return {"ok": false, "ms": timeout_s * 1000.0, "frames": frames, "hit": {}}


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


## Estado interno dos blocos de malha que contêm o ponto (diagnóstico de colisão).
func _debug_blocks(world_point: Vector3) -> Dictionary:
	var terrain := svc.get_terrain_node()
	var out := {}
	for lod in 3:
		var bpos := terrain.voxel_to_mesh_block_position(terrain.to_local(world_point), lod)
		var info := terrain.debug_get_mesh_block_info(Vector3(bpos), lod)
		out["lod%d %s" % [lod, bpos]] = "loaded=%s meshed=%s state=%s vis=%s col=%s" % [
			info.get("loaded"), info.get("meshed"), info.get("mesh_state"), info.get("visible"), info.get("collision_active")]
	return out


func _hit_y(hit: Dictionary) -> float:
	return hit.position.y if not hit.is_empty() else NAN


func _stats(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	var p95_index := clampi(int(ceil(sorted.size() * 0.95)) - 1, 0, sorted.size() - 1)
	return {"n": sorted.size(), "min": snappedf(sorted[0], 0.01), "media": snappedf(total / sorted.size(), 0.01),
		"p95": snappedf(sorted[p95_index], 0.01), "max": snappedf(sorted[-1], 0.01)}


## Captura PNG da visão do jogador (só em modo janela com --p0-screenshots).
func _shot(name: String, player_pos: Vector3, yaw: float, pitch_deg: float, move_player := true) -> void:
	if not _screens:
		return
	var restore := player.global_position
	if move_player:
		player.teleport_to(player_pos)
	player.camera_rig.set_view(yaw, deg_to_rad(pitch_deg))
	await _seconds(0.8)
	await RenderingServer.frame_post_draw
	_shot_index += 1
	var dir := "res://docs/evidence/screens/" if OS.has_feature("editor") else "user://screens/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s%02d_%s.png" % [dir, _shot_index, name]
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	_log("captura %s -> %s" % [name, "OK" if err == OK else error_string(err)])
	if move_player:
		player.teleport_to(restore)
	player.camera_rig.set_view(0.0, deg_to_rad(-12.0))


func _sample_fps() -> void:
	_fps_samples.append(Engine.get_frames_per_second())
	get_tree().create_timer(0.5, true).timeout.connect(_sample_fps)


func _record(id: String, title: String, passed: bool, details: Dictionary) -> void:
	var entry := {"id": id, "titulo": title, "status": "PASS" if passed else "FAIL", "detalhes": details}
	_results.append(entry)
	_log("%s %s — %s | %s" % [id, entry.status, title, JSON.stringify(details)])


func _log(msg: String) -> void:
	print("[P0TEST] ", msg)


func _on_watchdog() -> void:
	_record("WATCHDOG", "Selftest excedeu %d s" % WATCHDOG_S, false, {})
	_finish(2)


func _finish(force_code := -1) -> void:
	var passed := 0
	for r in _results:
		if r.status == "PASS":
			passed += 1
	var all_pass := passed == _results.size() and not _results.is_empty()
	var log_snapshot: Dictionary = _logger.snapshot()
	if not _fps_samples.is_empty():
		_metrics["fps_janela"] = _stats(_fps_samples)
	var report := {
		"data": Time.get_datetime_string_from_system(),
		"modo": _mode,
		"godot": Engine.get_version_info().string,
		"godot_hash": Engine.get_version_info().hash,
		"fisica_3d": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(),
		"duracao_s": (Time.get_ticks_msec() - _t_start) / 1000.0,
		"resultado_geral": "PASS" if all_pass else "FAIL",
		"testes_pass": passed,
		"testes_total": _results.size(),
		"erros_motor": log_snapshot.errors,
		"avisos_motor": log_snapshot.warnings,
		"amostras_erros": log_snapshot.samples,
		"metricas": _metrics,
		"resultados": _results,
	}
	var f := FileAccess.open(_report_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		_log("relatório: %s" % ProjectSettings.globalize_path(_report_path))
	else:
		_log("falha ao gravar relatório em %s: %s" % [_report_path, error_string(FileAccess.get_open_error())])
	_log("erros do motor durante o teste: %d | avisos: %d" % [log_snapshot.errors, log_snapshot.warnings])
	_log("RESULTADO GERAL: %s (%d/%d) em %.1f s" % ["PASS" if all_pass else "FAIL", passed, _results.size(), report.duracao_s])
	OS.remove_logger(_logger)
	var code := force_code if force_code >= 0 else (0 if all_pass else 1)
	get_tree().quit(code)
