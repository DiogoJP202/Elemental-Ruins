extends SceneTree
## Edge cases do save P3.6.1, na cena e na física reais (sem doubles/mocks).
## Uso: Godot --headless --path . --script res://tools/spike_t26_save.gd -- --report=<json>
## NÃO é um selftest de gameplay nem relaxa o T26. Cada processo usa slots/sessões isolados.
## O gêmeo de controle do E2 fica fora de Props: segue a física normal enquanto o corpo
## observado passa pela orquestração real do Main. Assim, zerar/congelar velocidades falha.
## E5 usa save_timeout_s=0 com blocos realmente sujos e exige flush_incomplete observado;
## E6 usa um ARQUIVO próprio como diretório de destino para provocar uma falha real de I/O.
## E7 usa mundo limpo e prazo de 1 ms: flush real completo, drenagem de I/O expira antes
## dos dois ticks quietos. Exige io_timeout real, integridade e retry, sem injetar resultados.

const LAB := Vector3(-34.17, 0.0, 60.23)
const SLOT := "edge_save"
const MAX_TIMEOUT_ATTEMPTS := 5

var main: Node
var svc: TerrainService
var props: Node3D
var controls: Node3D
var _results: Array[Dictionary] = []
var _failed := 0
var _ended := false
var _user_base := ""
var _report := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_user_base = "user://t26_save_edge_%d" % OS.get_process_id()
	_report = "res://docs/evidence/p361/edge_save_%s.json" % DisplayServer.get_name()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			_report = arg.trim_prefix("--report=")
	print("[T26EDGE] Godot %s | %s | isolated=%s" % [Engine.get_version_info().string,
		DisplayServer.get_name(), _user_base])
	main = load("res://scenes/main.tscn").instantiate()
	svc = main.get_node("World/TerrainService") as TerrainService
	svc.world_dir = _user_base.path_join("world")
	svc.saves_dir = _user_base.path_join("saves")
	root.add_child(main)
	await process_frame
	props = main.props_root
	controls = Node3D.new()
	controls.name = "NormalPhysicsControls"
	main.add_child(controls)
	if not await _until(func(): return svc.is_ready(), 40.0):
		_record("E0", false, {"reason": "terrain_ready timeout"})
		_finish()
		return
	main.player.input_enabled = false
	main.player.teleport_to(LAB + Vector3(0, 1, 14))
	var area := AABB(LAB - Vector3(15, 6, 15), Vector3(30, 14, 30))
	if not await _until(func(): return svc.can_edit_area(area) and not _ground(LAB).is_empty(), 20.0):
		_record("E0", false, {"reason": "lab data/collider timeout", "area": str(area)})
		_finish()
		return
	await _frames(20)
	await _sleeping_stack()
	await _active_momentum()
	await _parked_and_wake()
	await _invalid_slot()
	await _flush_timeout_and_retry()
	await _copy_failure()
	await _io_drain_timeout()
	_finish()


func _sleeping_stack() -> void:
	var ground := _ground(LAB)
	if ground.is_empty():
		_record("E1", false, {"reason": "missing floor"})
		return
	var stack: Array[RigidBody3D] = []
	for i in 3:
		var b := DebugProps.spawn_crate(props, ground.position + Vector3.UP * (0.51 + i * 1.01))
		b.set_meta("body_material", BodyMaterialLibrary.STONE)
		stack.append(b)
	var settled := await _until(func(): return stack.all(func(b): return b.sleeping and not b.freeze), 12.0)
	var before := stack.map(func(b): return _state(b))
	var positions := stack.map(func(b): return b.global_position)
	var modes := stack.map(func(b): return b.freeze_mode)
	var terrain_id := svc.get_terrain_node().get_instance_id()
	var saved: bool = await main.request_world_save(SLOT)
	var immediate := stack.map(func(b): return _state(b))
	var preserved := true
	for i in stack.size():
		preserved = preserved and stack[i].sleeping and not stack[i].freeze and stack[i].freeze_mode == modes[i]
	await _frames(30)
	var shift := 0.0
	for i in stack.size():
		shift = maxf(shift, stack[i].global_position.distance_to(positions[i]))
	# Um corpo que foi permanentemente congelado/estacionado para esconder a falha não responde.
	var top := stack[2]
	var top_before := top.global_position
	top.apply_central_impulse(Vector3.RIGHT * top.mass * 4.0)
	await _frames(18)
	var impulse_shift := top.global_position.x - top_before.x
	var base_y := stack[0].global_position.y
	var edit: TerrainEditResult = svc.dig_sphere(ground.position - Vector3.UP * 0.15, 2.4)
	var fell := await _until(func(): return stack[0].global_position.y < base_y - 0.4, 3.0)
	_record("E1", settled and saved and preserved and shift < 0.03 and impulse_shift > 0.3
		and edit.ok and fell and terrain_id == svc.get_terrain_node().get_instance_id(),
		{"settled_naturally": settled, "saved": saved, "before": before, "immediate": immediate,
		"modes_preserved": preserved, "max_shift_after_30_frames_m": shift,
		"top_impulse_shift_x_m": impulse_shift, "dig_ok": edit.ok, "base_fell_after_dig": fell,
		"terrain_instance_preserved": terrain_id == svc.get_terrain_node().get_instance_id()})
	for b in stack:
		b.queue_free()
	await _frames(2)


func _active_momentum() -> void:
	var body := _flying_body(props, LAB + Vector3(0, 12, 0))
	var twin := _flying_body(controls, LAB + Vector3(0, 12, 8))
	await _frames(2)
	_seed_motion(body)
	_seed_motion(twin)
	var offset := body.global_position - twin.global_position
	var frames_before := Engine.get_physics_frames()
	var saved: bool = await main.request_world_save(SLOT)
	var save_frames := Engine.get_physics_frames() - frames_before
	# Inclui avanço real após a chamada, mesmo se o save não precisar esperar nenhum quadro.
	await _frames(20)
	var position_error := (body.global_position - twin.global_position - offset).length()
	var linear_error := (body.linear_velocity - twin.linear_velocity).length()
	var angular_error := (body.angular_velocity - twin.angular_velocity).length()
	var rotation_error := body.quaternion.angle_to(twin.quaternion)
	var moving := body.linear_velocity.length() > 2.0 and body.angular_velocity.length() > 0.5
	_record("E2", saved and not body.freeze and moving and position_error < 0.03 and linear_error < 0.01
		and angular_error < 0.01 and rotation_error < 0.03,
		{"saved": saved, "save_physics_frames": save_frames, "body": _state(body), "normal_twin": _state(twin),
		"position_error_vs_normal_m": position_error, "linear_error_m_s": linear_error,
		"angular_error_rad_s": angular_error, "rotation_error_rad": rotation_error})
	body.queue_free()
	twin.queue_free()
	await _frames(2)


func _parked_and_wake() -> void:
	var ground := _ground(LAB + Vector3(8, 0, 0))
	if ground.is_empty():
		_record("E3", false, {"reason": "missing floor"})
		return
	var body := DebugProps.spawn_crate(props, ground.position + Vector3.UP * 0.51)
	await _frames(2)
	# Mesmo caminho usado pelo orçamento, sem reproduzir a implementação de _park.
	main.debris.call("_park", body, "budget")
	var before := _state(body)
	var position := body.global_position
	var saved: bool = await main.request_world_save(SLOT)
	await _frames(6)
	var preserved: bool = body.freeze and body.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC \
		and body.get_meta(DebrisBudget.PARKED_META, "") == "budget" and body.global_position.distance_to(position) < 0.001
	var after := _state(body)
	var edit: TerrainEditResult = svc.dig_sphere(ground.position - Vector3.UP * 0.15, 2.4)
	var fell := await _until(func(): return not body.freeze and not body.has_meta(DebrisBudget.PARKED_META) \
		and body.global_position.y < position.y - 0.4, 3.0)
	_record("E3", saved and preserved and edit.ok and fell,
		{"saved": saved, "before": before, "after_save": after, "park_preserved": preserved,
		"dig_ok": edit.ok, "unparked_and_fell": fell, "after_dig": _state(body)})
	body.queue_free()
	await _frames(2)


func _invalid_slot() -> void:
	var body := _flying_body(props, LAB + Vector3(0, 12, 0))
	await _frames(2)
	_seed_motion(body)
	var terrain_id := svc.get_terrain_node().get_instance_id()
	var generation := svc.get_world_generation()
	var result: bool = await main.request_world_save("../invalid_edge_slot")
	await _frames(2)
	_record("E4", not result and svc.is_ready() and not svc.is_resetting() and not main.player.is_frozen()
		and not body.freeze and body.linear_velocity.length() > 2.0
		and terrain_id == svc.get_terrain_node().get_instance_id() and generation == svc.get_world_generation(),
		{"saved": result, "ready": svc.is_ready(), "player_frozen": main.player.is_frozen(),
		"body": _state(body), "last_save": svc.get_debug_stats().last_save,
		"terrain_instance_preserved": terrain_id == svc.get_terrain_node().get_instance_id()})
	body.queue_free()
	await _frames(2)


func _flush_timeout_and_retry() -> void:
	# O tracker é o REAL do Voxel Tools. Não substitui método, classe ou relógio.
	var initial_saved: bool = await main.request_world_save(SLOT)
	var timeout_before := svc.save_timeout_s
	var attempts: Array[Dictionary] = []
	var failed_as_expected := false
	var intact := false
	var mark := LAB
	var terrain_id := svc.get_terrain_node().get_instance_id()
	var generation := svc.get_world_generation()
	for attempt in MAX_TIMEOUT_ATTEMPTS:
		# Espalha matéria nova por vários blocos carregados, deixando tarefas reais para o tracker.
		for i in 9:
			mark = LAB + Vector3(-8.0 + (i % 3) * 8.0, -0.4 - attempt * 0.15, -8.0 + floorf(i / 3.0) * 8.0)
			var edit: TerrainEditResult = svc.dig_sphere(mark, 1.5 + attempt * 0.1)
			if not edit.ok:
				attempts.append({"edit_rejected": edit.reason, "at": str(mark)})
			if i % 3 == 2:
				await _frames(1)
		var hash_before := FileAccess.get_sha256(svc.get_slot_path(SLOT))
		var sdf_before := svc.sample_sdf(mark)
		svc.save_timeout_s = 0.0
		var saved: bool = await main.request_world_save(SLOT)
		var diagnostic: Dictionary = svc.get_debug_stats().last_save.duplicate(true)
		attempts.append({"attempt": attempt, "saved": saved, "last_save": diagnostic})
		if not saved and diagnostic.get("reason", "") == "flush_incomplete":
			failed_as_expected = true
			intact = svc.is_ready() and not svc.is_resetting() and not main.player.is_frozen() \
				and terrain_id == svc.get_terrain_node().get_instance_id() and generation == svc.get_world_generation() \
				and is_equal_approx(sdf_before, svc.sample_sdf(mark)) \
				and hash_before == FileAccess.get_sha256(svc.get_slot_path(SLOT))
			break
	svc.save_timeout_s = timeout_before
	var retry: bool = await main.request_world_save(SLOT)
	var retry_diagnostic: Dictionary = svc.get_debug_stats().last_save.duplicate(true)
	var sdf_saved := svc.sample_sdf(mark)
	# Confirma que o retry esperou as gravações anteriores e realmente preservou a edição no slot.
	var reset: bool = await main.request_world_reset()
	var loaded: bool = await main.request_world_load(SLOT)
	main.player.teleport_to(LAB + Vector3(0, 1, 14))
	var data_area := AABB(mark - Vector3.ONE * 2.0, Vector3.ONE * 4.0)
	var loaded_area := await _until(func(): return svc.can_edit_area(data_area), 10.0)
	var sdf_loaded := svc.sample_sdf(mark)
	_record("E5", initial_saved and failed_as_expected and intact and retry and reset and loaded and loaded_area
		and sdf_saved > 0.0 and is_equal_approx(sdf_saved, sdf_loaded),
		{"initial_saved": initial_saved, "real_timeout_observed": failed_as_expected, "attempts": attempts,
		"world_and_old_slot_intact_on_failure": intact, "retry_saved": retry, "retry_last_save": retry_diagnostic,
		"reset": reset, "loaded": loaded, "mark": str(mark), "sdf_saved": sdf_saved, "sdf_loaded": sdf_loaded})
	# Load volta ao spawn; traz o viewer para o laboratório antes do próximo caso.
	main.player.teleport_to(LAB + Vector3(0, 1, 14))
	await _until(func(): return svc.can_edit_area(AABB(LAB - Vector3(12, 5, 12), Vector3(24, 10, 24))), 15.0)


func _copy_failure() -> void:
	var original_dir := svc.saves_dir
	var old_slot := svc.get_slot_path(SLOT)
	var hash_before := FileAccess.get_sha256(old_slot)
	var fake_dir := _user_base.path_join("destination_is_a_file")
	var file := FileAccess.open(fake_dir, FileAccess.WRITE)
	if file == null:
		_record("E6", false, {"reason": "could not create isolated file fixture", "error": FileAccess.get_open_error()})
		return
	file.store_string("t26-edge-owned-fixture")
	file.close()
	var terrain_id := svc.get_terrain_node().get_instance_id()
	var generation := svc.get_world_generation()
	var session := svc.get_session_path()
	var body := _flying_body(props, LAB + Vector3(0, 12, 0))
	await _frames(2)
	_seed_motion(body)
	svc.saves_dir = fake_dir
	var result: bool = await main.request_world_save(SLOT)
	var failure: Dictionary = svc.get_debug_stats().last_save.duplicate(true)
	svc.saves_dir = original_dir
	await _frames(2)
	var intact := FileAccess.get_sha256(old_slot) == hash_before and not hash_before.is_empty() \
		and terrain_id == svc.get_terrain_node().get_instance_id() and generation == svc.get_world_generation() \
		and session == svc.get_session_path() and not body.freeze and body.linear_velocity.length() > 2.0
	var ready_after_failure: bool = svc.is_ready() and not svc.is_resetting() and not main.player.is_frozen()
	var retry: bool = await main.request_world_save(SLOT)
	_record("E6", not result and intact and ready_after_failure and retry,
		{"saved_to_invalid_destination": result, "failure": failure, "world_and_previous_slot_intact": intact,
		"ready_after_failure": ready_after_failure, "body": _state(body), "retry_saved": retry})
	body.queue_free()
	await _frames(2)


func _io_drain_timeout() -> void:
	# Cena sem edições novas: o tracker real pode completar sem tarefas, mas a barreira
	# de I/O exige dois ticks quietos e não cabe no prazo de 1 ms. Se o flush não terminar
	# a tempo, o caso registra essa tentativa e tenta novamente depois de um save normal.
	var point := LAB + Vector3(4.3, 0, 4.3)
	var ground := _ground(point)
	if ground.is_empty():
		_record("E7", false, {"reason": "missing floor for sleeping fixture"})
		return
	var sleeper := DebugProps.spawn_crate(props, ground.position + Vector3.UP * 0.51)
	sleeper.set_meta("body_material", BodyMaterialLibrary.STONE)
	var settled := await _until(func(): return sleeper.sleeping and not sleeper.freeze, 12.0)
	var body := _flying_body(props, LAB + Vector3(0, 12, 0))
	var twin := _flying_body(controls, LAB + Vector3(0, 12, 8))
	await _frames(2)
	_seed_motion(body)
	_seed_motion(twin)
	var offset := body.global_position - twin.global_position
	var initial_saved: bool = await main.request_world_save(SLOT)
	var timeout_before := svc.save_timeout_s
	var terrain_id := svc.get_terrain_node().get_instance_id()
	var generation := svc.get_world_generation()
	var session := svc.get_session_path()
	var process_mode_before := svc.get_terrain_node().process_mode
	var sleep_mode_before := sleeper.freeze_mode
	var sleep_position := sleeper.global_position
	var collider_before := _ground(point)
	var sdf_point: Vector3 = ground.position - Vector3.UP * 0.5
	var sdf_before := svc.sample_sdf(sdf_point)
	var attempts: Array[Dictionary] = []
	var timeout_observed := false
	var intact := false
	var retries_ok := true
	for attempt in MAX_TIMEOUT_ATTEMPTS:
		var hash_before := FileAccess.get_sha256(svc.get_slot_path(SLOT))
		svc.save_timeout_s = 0.001
		var saved: bool = await main.request_world_save(SLOT)
		svc.save_timeout_s = timeout_before
		var diagnostic: Dictionary = svc.get_debug_stats().last_save.duplicate(true)
		var collider_after := _ground(point)
		var linear_error := (body.linear_velocity - twin.linear_velocity).length()
		var angular_error := (body.angular_velocity - twin.angular_velocity).length()
		var position_error := (body.global_position - twin.global_position - offset).length()
		var flags_ok: bool = svc.is_ready() and not svc.is_resetting() and svc.get_busy_op() == "" \
			and not main.player.is_frozen() and svc.get_terrain_node().process_mode == process_mode_before
		var body_states_ok := sleeper.sleeping and not sleeper.freeze and sleeper.freeze_mode == sleep_mode_before \
			and sleeper.global_position.distance_to(sleep_position) < 0.01 and not body.freeze \
			and body.linear_velocity.length() > 2.0 and body.angular_velocity.length() > 0.5 \
			and linear_error < 0.01 and angular_error < 0.01 and position_error < 0.03
		var same_colliders: bool = not collider_before.is_empty() and not collider_after.is_empty() \
			and collider_before.get("rid") == collider_after.get("rid") \
			and (collider_before.position as Vector3).distance_to(collider_after.position) < 0.001
		var same_world := terrain_id == svc.get_terrain_node().get_instance_id() \
			and generation == svc.get_world_generation() and session == svc.get_session_path() \
			and is_equal_approx(sdf_before, svc.sample_sdf(sdf_point))
		var same_slot := not hash_before.is_empty() and hash_before == FileAccess.get_sha256(svc.get_slot_path(SLOT))
		var case_info := {"attempt": attempt, "saved": saved, "last_save": diagnostic,
			"flags_restored": flags_ok, "body_states_preserved": body_states_ok,
			"same_colliders": same_colliders, "same_world": same_world, "same_old_slot": same_slot,
			"position_error_vs_normal_m": position_error, "linear_error_m_s": linear_error,
			"angular_error_rad_s": angular_error, "sleeper": _state(sleeper)}
		if not saved and diagnostic.get("reason", "") == "io_timeout":
			timeout_observed = true
			intact = flags_ok and body_states_ok and same_colliders and same_world and same_slot
		var retry: bool = await main.request_world_save(SLOT)
		retries_ok = retries_ok and retry
		case_info["retry_saved"] = retry
		case_info["retry_last_save"] = svc.get_debug_stats().last_save.duplicate(true)
		attempts.append(case_info)
		if timeout_observed:
			break
	svc.save_timeout_s = timeout_before
	_record("E7", initial_saved and settled and timeout_observed and intact and retries_ok,
		{"initial_saved": initial_saved, "settled_naturally": settled, "real_io_timeout_observed": timeout_observed,
		"world_colliders_slot_flags_and_body_states_intact": intact, "all_retries_saved": retries_ok,
		"attempts": attempts, "body": _state(body), "normal_twin": _state(twin)})
	sleeper.queue_free()
	body.queue_free()
	twin.queue_free()
	await _frames(2)


func _flying_body(parent: Node3D, at: Vector3) -> RigidBody3D:
	var body := DebugProps.spawn_crate(parent, at)
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.can_sleep = false
	body.collision_layer = 0
	body.collision_mask = 0
	return body


func _seed_motion(body: RigidBody3D) -> void:
	body.apply_central_impulse(Vector3(3.0, 0.5, -1.0) * body.mass)
	body.angular_velocity = Vector3(0.3, 1.1, 0.2)


func _ground(at: Vector3) -> Dictionary:
	return svc.raycast_terrain(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0)


func _state(body: RigidBody3D) -> Dictionary:
	return {"position": str(body.global_position), "linear_velocity": str(body.linear_velocity),
		"angular_velocity": str(body.angular_velocity), "sleeping": body.sleeping,
		"freeze": body.freeze, "freeze_mode": body.freeze_mode,
		"parked_meta": body.get_meta(DebrisBudget.PARKED_META, "")}


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _until(predicate: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await physics_frame
	return predicate.call()


func _record(id: String, ok: bool, details: Dictionary) -> void:
	_results.append({"id": id, "passed": ok, "details": details})
	if not ok:
		_failed += 1
	print("[T26EDGE] %s %s %s" % [id, "PASS" if ok else "FAIL", JSON.stringify(details)])


func _finish() -> void:
	if _ended:
		return
	_ended = true
	var report := {"suite": "t26_save_edges", "godot": Engine.get_version_info().string,
		"display": DisplayServer.get_name(), "isolated_user_dir": _user_base, "tests": _results,
		"total": _results.size(), "failed": _failed, "passed": _failed == 0}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_report).get_base_dir())
	var file := FileAccess.open(_report, FileAccess.WRITE)
	if file == null:
		print("[T26EDGE] REPORT_WRITE_FAILED %s" % error_string(FileAccess.get_open_error()))
		_failed += 1
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[T26EDGE] RESULTADO GERAL: %s (%d/%d) report=%s" % [
		"PASS" if _failed == 0 else "FAIL", _results.size() - _failed, _results.size(), _report])
	quit(0 if _failed == 0 else 1)
