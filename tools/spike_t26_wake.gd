extends SceneTree
## Prova isolada da pose de P16 na falha B002, sem alterar a cena ou poderes.
## Uso: godot --headless --path . --script res://tools/spike_t26_wake.gd
##   -- --wake-case=all|control|wake|freeze_thaw --report=<arquivo.json>
## Cada intervenção cria um corpo novo, inicialmente dormindo, na pose EXATA do trace.
## O chão é o terreno intacto da cena principal; nenhum save/rebuild é executado aqui.
## Resultado distingue experimento válido de hipótese apoiada pelos deslocamentos.

const TRACE_PATH := "res://docs/evidence/p36/t26_stabilization/causal_v1/headless_tower_B_002_trace.json"
const DEFAULT_REPORT := "res://docs/evidence/p36/t26_stabilization/wake_pose.json"
const SOURCE_BODY := "P16_pilar1"
const OBSERVATION_TICKS := 90
const POSITION_TOLERANCE_M := 0.000001
const T26_LIMIT_M := 0.1
const LOGGER_SCRIPT := preload("res://scripts/dev/error_counter_logger.gd")

var _case := "all"
var _report_path := DEFAULT_REPORT
var _main: Node3D
var _service: TerrainService
var _source := {}
var _source_sha256 := ""
var _source_location := ""
var _results: Array[Dictionary] = []
var _logger: Logger
var _finished := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_logger = LOGGER_SCRIPT.new()
	OS.add_logger(_logger)
	create_timer(90.0).timeout.connect(func(): _finish(false, "watchdog_timeout"))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--wake-case="):
			_case = arg.trim_prefix("--wake-case=")
		elif arg.begins_with("--report="):
			_report_path = arg.trim_prefix("--report=")
	if _case not in ["all", "control", "wake", "freeze_thaw"]:
		_finish(false, "invalid_case")
		return
	if not _read_source():
		_finish(false, "source_trace_invalid")
		return
	# --script normally retains project autoloads; keep this standalone entry point
	# explicit if the custom executable has not populated them.
	if not root.has_node("InputActions"):
		var input_actions: Node = load("res://scripts/core/input_actions.gd").new()
		input_actions.name = "InputActions"
		root.add_child(input_actions)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_main = packed.instantiate() as Node3D
	_service = _main.get_node("World/TerrainService") as TerrainService
	var isolated_dir := "user://t26_wake_%d" % OS.get_process_id()
	_service.world_dir = isolated_dir.path_join("world")
	_service.saves_dir = isolated_dir.path_join("saves")
	root.add_child(_main)
	current_scene = _main
	var player := _main.get_node("Player") as PlayerController
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not await _wait_terrain():
		_finish(false, "terrain_timeout")
		return
	player.set_frozen(true)
	var cases: Array[String] = []
	if _case == "all":
		cases.assign(["control", "wake", "freeze_thaw"])
	else:
		cases.append(_case)
	for intervention: String in cases:
		var result: Dictionary = await _measure(intervention)
		_results.append(result)
		print("[T26WAKE] case=%s valid_initial=%s peak=%.9f m final=%.9f m" % [
			intervention, result.initial_state_ok, result.peak_shift_m, result.final_shift_m])
		if not result.initial_state_ok:
			_finish(false, "initial_pose_or_sleep_not_preserved")
			return
	var valid := true
	for result: Dictionary in _results:
		if result.intervention == "control":
			valid = valid and result.peak_shift_m <= POSITION_TOLERANCE_M
	_finish(valid, "" if valid else "control_moved")


func _read_source() -> bool:
	var bytes := _read_trace_bytes()
	if bytes.is_empty():
		return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	_source_sha256 = digest.finish().hex_encode()
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary or data.get("scenario") != "B" or data.get("layout") != "tower":
		return false
	for body: Dictionary in data.get("before", {}).get("bodies", []):
		if body.get("name") == SOURCE_BODY:
			_source = body
			break
	return not _source.is_empty() and _source.get("direct_sleeping", false) \
		and _source.get("basis", []).size() == 3 and _source.get("position", []).size() == 3 \
		and float(_source.get("mass", 0.0)) > 0.0


func _read_trace_bytes() -> PackedByteArray:
	if FileAccess.file_exists(TRACE_PATH):
		_source_location = TRACE_PATH
		return FileAccess.get_file_as_bytes(TRACE_PATH)
	# The runner stores verified archives by replacing .json with .zip. Accept
	# the appended extension too, for an explicitly archived raw trace.
	for archive_path: String in [TRACE_PATH.get_basename() + ".zip", TRACE_PATH + ".zip"]:
		if not FileAccess.file_exists(archive_path):
			continue
		var archive := ZIPReader.new()
		if archive.open(archive_path) != OK:
			return PackedByteArray()
		var entries := archive.get_files()
		if entries.size() != 1 or entries[0].get_file() != TRACE_PATH.get_file():
			archive.close()
			return PackedByteArray()
		var contents := archive.read_file(entries[0])
		archive.close()
		_source_location = archive_path + "::" + entries[0]
		return contents
	return PackedByteArray()


func _wait_terrain() -> bool:
	var position := _vector(_source.position)
	var area := AABB(position - Vector3.ONE * 3.0, Vector3.ONE * 6.0)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if _service.can_edit_area(area):
			var hit := _service.raycast_terrain(position + Vector3.UP * 2.0, position + Vector3.DOWN * 3.0)
			if not hit.is_empty():
				return true
	return false


func _measure(intervention: String) -> Dictionary:
	var world_space := _main.get_world_3d().space
	var previously_active := PhysicsServer3D.space_is_active(world_space)
	PhysicsServer3D.space_set_active(world_space, false)
	var body := _make_body(intervention)
	# Insertion can queue compound-shape optimization, which wakes the body in
	# Jolt's next pre-step. Let that setup finish while the specimen is STATIC,
	# then set its dynamic sleeping state before any unrestrained integration.
	_body_neighbors(body) # Query also flushes pending bodies into broadphase.
	PhysicsServer3D.space_set_active(world_space, previously_active)
	if previously_active:
		await physics_frame
		await process_frame
	PhysicsServer3D.space_set_active(world_space, false)
	body.freeze = false
	body.linear_velocity = _vector(_source.linear_velocity)
	body.angular_velocity = _vector(_source.angular_velocity)
	_body_neighbors(body)
	body.sleeping = true
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)
	var expected := _vector(_source.position)
	var initial := _snapshot(body)
	var basis_error := 0.0
	for axis in 3:
		basis_error = maxf(basis_error, _vector(initial.basis[axis]).distance_to(_vector(_source.basis[axis])))
	var initial_state_ok: bool = previously_active and initial.direct_sleeping \
		and not initial.freeze and basis_error <= POSITION_TOLERANCE_M \
		and _vector(initial.position).distance_to(expected) <= POSITION_TOLERANCE_M \
		and _vector(initial.linear_velocity).length() <= POSITION_TOLERANCE_M \
		and _vector(initial.angular_velocity).length() <= POSITION_TOLERANCE_M
	var support_before := _terrain_rays(body)
	var body_neighbors_before := _body_neighbors(body)
	initial_state_ok = initial_state_ok and body_neighbors_before.is_empty()
	PhysicsServer3D.space_set_active(world_space, previously_active)
	if not initial_state_ok:
		# Do not run an intervention on an already drifting/awake setup.
		body.free()
		return {"intervention": intervention, "initial_state_ok": false, "initial": initial,
			"initial_basis_error": basis_error, "peak_shift_m": 0.0, "final_shift_m": 0.0,
			"body_neighbors_before": body_neighbors_before, "reason": "preparation_invalid", "trace": []}
	var rows: Array[Dictionary] = []
	if intervention == "wake":
		body.sleeping = false
	elif intervention == "freeze_thaw":
		body.freeze = true
		for tick in 15:
			await physics_frame
		body.freeze = false
	var immediate := _snapshot(body)
	var operation_frame := Engine.get_physics_frames()
	var peak := 0.0
	var peak_tick := 0
	for tick in OBSERVATION_TICKS:
		await physics_frame
		var state := _snapshot(body)
		state["tick"] = tick + 1
		state["frame_since_intervention"] = Engine.get_physics_frames() - operation_frame
		var shift := _vector(state.position).distance_to(expected)
		state["shift_m"] = shift
		rows.append(state)
		if shift > peak:
			peak = shift
			peak_tick = tick + 1
	# physics_frame is emitted before the current scene physics callbacks. Take
	# the endpoint at idle as well, so the 90th integration is included explicitly.
	await process_frame
	var final := _snapshot(body)
	var final_shift := _vector(final.position).distance_to(expected)
	if final_shift > peak:
		peak = final_shift
		peak_tick = OBSERVATION_TICKS
	var result := {"intervention": intervention, "initial_state_ok": initial_state_ok,
		"initial_basis_error": basis_error,
		"preparation": "One static insertion pre-step, then pause space, set dynamic/source velocities/sleeping, validate before resuming; no pose correction.",
		"initial": initial, "immediate": immediate, "final": final,
		"observation_ticks": OBSERVATION_TICKS, "elapsed_physics_frames": Engine.get_physics_frames() - operation_frame,
		"peak_shift_m": peak, "peak_tick": peak_tick, "final_shift_m": final_shift,
		"moved_over_t26_limit": peak > T26_LIMIT_M, "support_before": support_before,
		"support_after": _terrain_rays(body), "body_neighbors_before": body_neighbors_before,
		"physics_material_override_null": body.physics_material_override == null,
		"friction": PhysicsServer3D.body_get_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION),
		"bounce": PhysicsServer3D.body_get_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_BOUNCE), "trace": rows}
	body.queue_free()
	await physics_frame
	await process_frame
	return result


func _make_body(intervention: String) -> StructurePiece:
	# Match TowerFactory._add: same class/box, mass, masks, CCD and default physics
	# material (no override). The specimen is outside StructureService's piece list
	# and the debris group, so neither service changes it during this experiment.
	var body := StructurePiece.new()
	body.name = "WakeSpecimen_" + intervention
	body.material_id = BodyMaterialLibrary.WOOD
	body.size = TowerFactory.PILLAR
	body.mass = float(_source.mass)
	body.collision_layer = Layers.PROPS
	body.collision_mask = Layers.TERRAIN | Layers.PLAYER | Layers.PROPS
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.continuous_cd = true
	body.sleeping = true
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = TowerFactory.PILLAR
	shape_node.shape = shape
	body.add_child(shape_node)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = TowerFactory.PILLAR
	var material := StandardMaterial3D.new()
	material.albedo_color = TowerFactory.WOOD_COLOR
	material.roughness = 0.85
	mesh.material = material
	visual.mesh = mesh
	body.add_child(visual)
	var axes: Array = _source.basis
	body.transform = Transform3D(Basis(_vector(axes[0]), _vector(axes[1]), _vector(axes[2])), _vector(_source.position))
	_main.get_node("World/Props").add_child(body)
	return body


func _snapshot(body: RigidBody3D) -> Dictionary:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	return {"position": _array(state.transform.origin), "basis": [_array(state.transform.basis.x),
		_array(state.transform.basis.y), _array(state.transform.basis.z)],
		"linear_velocity": _array(state.linear_velocity), "angular_velocity": _array(state.angular_velocity),
		"direct_sleeping": state.sleeping, "node_sleeping": body.sleeping, "freeze": body.freeze,
		"freeze_mode": body.freeze_mode}


func _terrain_rays(body: RigidBody3D) -> Array[Dictionary]:
	var box := body.global_transform * AABB(-TowerFactory.PILLAR * 0.5, TowerFactory.PILLAR)
	var center := box.get_center()
	var rows: Array[Dictionary] = []
	for offset: Vector2 in [Vector2.ZERO, Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]:
		var start := Vector3(center.x + offset.x * box.size.x, box.position.y + 0.3, center.z + offset.y * box.size.z)
		var hit := _service.raycast_terrain(start, start + Vector3.DOWN * 0.9)
		rows.append({"from": _array(start), "hit": not hit.is_empty(),
			"position": _array(hit.position) if not hit.is_empty() else [],
			"normal": _array(hit.normal) if not hit.is_empty() else []})
	return rows


func _body_neighbors(body: RigidBody3D) -> Array[String]:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (body.get_child(0) as CollisionShape3D).shape
	query.transform = body.global_transform
	query.margin = 0.1
	query.collision_mask = Layers.PROPS
	query.exclude = [body.get_rid()]
	var names: Array[String] = []
	for hit: Dictionary in body.get_world_3d().direct_space_state.intersect_shape(query, 64):
		names.append(str(hit.collider.name))
	return names


func _finish(valid: bool, reason: String) -> void:
	if _finished:
		return
	_finished = true
	var supported: Variant = null
	if _case == "all" and _results.size() == 3:
		supported = _results[0].peak_shift_m <= POSITION_TOLERANCE_M \
			and _results[1].peak_shift_m > T26_LIMIT_M and _results[2].peak_shift_m > T26_LIMIT_M
	var counters: Dictionary = _logger.snapshot() if _logger != null else {}
	valid = valid and counters.get("errors", 0) == 0 and counters.get("warnings", 0) == 0
	var report := {"experiment_valid": valid, "reason": reason, "hypothesis_supported": supported,
		"case": _case, "source_trace": TRACE_PATH, "source_location": _source_location, "source_sha256": _source_sha256,
		"source_body": SOURCE_BODY, "source_state": _source, "results": _results,
		"engine": Engine.get_version_info(), "physics": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"ticks_per_second": Engine.physics_ticks_per_second, "errors_warnings": counters,
		"limitation": "Isolated traced pose on intact lab terrain; reproduces awakening mechanism, not the complete original collapse or its occurrence rate."}
	var path := ProjectSettings.globalize_path(_report_path)
	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE) if dir_error == OK else null
	if file == null:
		print("[T26WAKE] report_write_failed: ", path)
		valid = false
	else:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("[T26WAKE] experiment_valid=%s hypothesis_supported=%s report=%s" % [valid, supported, path])
	quit(0 if valid else 1)


func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
