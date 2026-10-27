extends "res://scripts/dev/p2_selftest.gd"
## Diagnostic experiment only. One fresh process, one layout, one intervention.
## A: normal physics; B: current freeze/thaw without terrain replacement;
## C: complete production save; D: pause the physics space while saving.
## Does not change the original T26 or powers.

var _scenario := "C"
var _layout := "tower"
var _repeat := 1
var _pause_frames := 15
var _restore_state := false
var _contacts := false
var _trace_enabled := true
var _natural_rest := false
const NATURAL_REST_TICKS := 60
const NATURAL_REST_TIMEOUT_MS := 30000
const NATURAL_REST_VELOCITY_EPS := 0.00001
const NATURAL_CONTROL_MAX_SHIFT_M := 0.005
var _layout_variant := {}
var _bodies: Array[RigidBody3D] = []
var _trace: Array[Dictionary] = []
var _sampling := false
var _phase := "setup"
var _operation_frame := 0
var _measure_peak := false
var _peak_references := {}
var _peak_per_body := {}
var _peak_m := 0.0
var _peak_body := ""
var _peak_tick := 0
var _thaw_frame := 0
var _control_sampling := false
var _control_references := {}
var _control_previous_sleep := {}
var _control_wakes := {}
var _control_peak_per_body := {}
var _control_ticks := 0
var _control_awake_ticks := 0
var _control_last_frame := -1
var _control_max_linear := 0.0
var _control_max_angular := 0.0
var _preflight_natural := true


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-scenario="): _scenario = arg.trim_prefix("--probe-scenario=")
		elif arg.begins_with("--probe-layout="): _layout = arg.trim_prefix("--probe-layout=")
		elif arg.begins_with("--probe-repeat="): _repeat = int(arg.trim_prefix("--probe-repeat="))
		elif arg.begins_with("--probe-pause-frames="): _pause_frames = int(arg.trim_prefix("--probe-pause-frames="))
		elif arg.begins_with("--probe-restore-state="): _restore_state = arg.trim_prefix("--probe-restore-state=") == "true"
		elif arg.begins_with("--probe-contacts="): _contacts = arg.trim_prefix("--probe-contacts=") == "true"
		elif arg.begins_with("--probe-trace="): _trace_enabled = arg.trim_prefix("--probe-trace=") == "true"
		elif arg == "--probe-natural-rest" or arg == "--probe-natural-rest=true": _natural_rest = true
	super._ready()


func _report_prefix() -> String:
	return "t26_probe"


func _evidence_dir() -> String:
	return "res://docs/evidence/p36/t26_stabilization/" if OS.has_feature("editor") else "user://"


func _log(msg: String) -> void:
	print("[T26PROBE] ", msg)


func _physics_process(_delta: float) -> void:
	if _control_sampling:
		_sample_natural_control()
	if _natural_rest and _sampling and _phase == "before":
		_preflight_natural = _preflight_natural and _natural_status().all_natural
	if _measure_peak:
		_update_peak()
	if _sampling and _trace_enabled:
		_trace.append(_snapshot())


func _run_tests() -> bool:
	await _t1_ground()
	if _results.back().status != "PASS": return false
	if _scenario not in ["A", "B", "C", "D"] or _layout not in ["tower", "stack"] or _pause_frames < 1 or (_restore_state and _scenario != "B"):
		_record("PROBE", "Valid diagnostic arguments", false, {"scenario": _scenario, "layout": _layout, "pause_frames": _pause_frames, "restore_state": _restore_state})
		return false
	var prepared := await _prepare_probe_layout()
	if not prepared:
		_record("PROBE", "Prepared independent physical layout", false, {"layout": _layout})
		return false
	# Same settling predicate and pre-save control duration as T26. Angular motion
	# and sleeping are recorded, rather than silently changing that predicate.
	var settled := await _wait_until(func(): return _bodies.all(func(b): return b.freeze or b.linear_velocity.length() < 0.05), 15.0)
	# This stricter protocol is opt-in and prospective. It never changes sleeping,
	# retries a failed layout, or reclassifies an earlier legacy experiment.
	var natural_wait := {"enabled": false}
	if _natural_rest:
		natural_wait = await _wait_natural_rest()
	var control_start := _positions()
	if _natural_rest: _begin_natural_control(control_start)
	await _seconds(2.0)
	var natural_control := {"enabled": false}
	if _natural_rest:
		_sample_natural_control()
		_control_sampling = false
		natural_control = _natural_control_result(control_start)
	var control_shift := _largest_shift(control_start)
	_operation_frame = Engine.get_physics_frames() + 6
	_phase = "before"
	_sampling = true
	await _frames(6)
	_sampling = false
	var before := _snapshot()
	if _natural_rest:
		var fresh_status := _natural_status()
		_preflight_natural = _preflight_natural and fresh_status.all_natural
		var setup_ok: bool = settled and natural_wait.reached and natural_control.stable and _preflight_natural
		if not setup_ok:
			var setup_trace := _write_probe_trace({"run_id": _run_id, "scenario": _scenario, "layout": _layout, "repeat": _repeat,
				"layout_variant": _layout_variant, "setup_status": "SETUP_UNSTABLE", "intervention_executed": false,
				"natural_rest": natural_wait, "natural_control": natural_control, "before": before, "ticks": _trace})
			_record("PROBE", "SETUP_UNSTABLE: prospective natural-rest precondition failed", false,
				{"scenario": _scenario, "layout": _layout, "repeat": _repeat, "layout_variant": _layout_variant,
				"setup_status": "SETUP_UNSTABLE", "intervention_executed": false, "settled": settled,
				"natural_rest": natural_wait, "natural_control": natural_control, "preflight_natural": _preflight_natural,
				"fresh_status": fresh_status, "control_without_save_2s": control_shift,
				"trace_enabled": _trace_enabled, "trace_path": setup_trace.path, "trace_written": setup_trace.written,
				"contacts_enabled": _contacts, "restore_state": _restore_state})
			return false
	var positions_before := _positions()
	var saved_state := _save_body_state()
	_operation_frame = Engine.get_physics_frames()
	_phase = "during"
	_sampling = true
	var operation_ok := true
	var support_ok := true
	var t0 := Time.get_ticks_msec()
	if _scenario == "A":
		await _frames(_pause_frames)
	elif _scenario == "B":
		# Exact production suspension entry/exit, with the terrain left intact.
		player.set_frozen(true)
		var frozen: Array = main._freeze_props()
		structures.suspend()
		if _trace_enabled: _trace.append(_snapshot())
		await _frames(_pause_frames)
		structures.resume()
		for body: RigidBody3D in frozen:
			if is_instance_valid(body): body.freeze = false
		if _restore_state:
			_restore_body_state(saved_state)
		player.set_frozen(false)
	elif _scenario == "C":
		operation_ok = await main.request_world_save("t26_probe_%s_%d" % [_layout, _repeat])
	else:
		# Extra diagnostic: leave all MotionTypes unchanged and pause the solver.
		var world_space := player.get_world_3d().space
		var support := {}
		var nodes: Array[Node3D] = []
		for body: RigidBody3D in _bodies:
			nodes.append(body)
			support[body] = main._support_hits(body)
		player.set_frozen(true)
		PhysicsServer3D.space_set_active(world_space, false)
		operation_ok = await svc.save_world("t26_probe_%s_%d" % [_layout, _repeat])
		support_ok = await main._wait_terrain_under(nodes, support, 3.0)
		_restore_body_state(saved_state)
		PhysicsServer3D.space_set_active(world_space, true)
		player.set_frozen(false)
	var operation_ms := Time.get_ticks_msec() - t0
	var operation_frames := Engine.get_physics_frames() - _operation_frame
	_sampling = false
	var immediate := _snapshot()
	var immediate_shift := _largest_shift(positions_before)
	_peak_references = positions_before
	_thaw_frame = Engine.get_physics_frames()
	_measure_peak = true
	_update_peak()
	_phase = "after_first_ticks"
	_sampling = true
	await _frames(30)
	_sampling = false
	# Measurement endpoint is 90 physics ticks after thaw (1.5 s at 60 Hz).
	await _frames(60)
	_update_peak()
	_measure_peak = false
	_phase = "after_1_5s"
	var final := _snapshot()
	var shift := _largest_shift(positions_before)
	var peak := {"max_m": _peak_m, "worst_body": _peak_body, "tick_after_operation": _peak_tick, "per_body_m": _peak_per_body}
	var trace_result := _write_probe_trace({"run_id": _run_id, "scenario": _scenario, "layout": _layout, "repeat": _repeat,
		"layout_variant": _layout_variant, "restore_state": _restore_state, "contacts_enabled": _contacts, "peak_after_1_5s": peak,
		"natural_rest": natural_wait, "natural_control": natural_control,
		"ticks_per_second": Engine.physics_ticks_per_second, "before": before, "immediate": immediate, "final": final, "ticks": _trace})
	var coverage := _support_coverage(before)
	var coverage_ok: bool = _layout != "stack" or (coverage.body_supported_bodies >= 4 and coverage.terrain_supported_bodies >= 2)
	var still_frozen := _bodies.filter(func(b): return b.freeze and not b.has_meta(DebrisBudget.PARKED_META)).size()
	var details := {"scenario": _scenario, "layout": _layout, "repeat": _repeat, "restore_state": _restore_state, "contacts_enabled": _contacts,
		"setup_status": "NATURAL_REST_CONFIRMED" if _natural_rest else "LEGACY", "intervention_executed": true,
		"natural_rest": natural_wait, "natural_control": natural_control, "preflight_natural": _preflight_natural if _natural_rest else null,
		"layout_variant": _layout_variant, "immediate_state_changes": _state_changes(before, immediate),
		"terrain_identity_before": before.terrain_identity, "terrain_identity_immediate": immediate.terrain_identity, "terrain_identity_after": final.terrain_identity,
		"settled": settled, "body_count": _bodies.size(), "control_without_save_2s": control_shift,
		"operation_ok": operation_ok, "support_ok": support_ok, "operation_ms": operation_ms, "operation_frames": operation_frames,
		"pause_frames_requested": _pause_frames, "immediate_shift": immediate_shift, "after_1_5s": shift, "peak_after_1_5s": peak,
		"box_geometry_before": before.box_geometry, "box_geometry_immediate": immediate.box_geometry, "box_geometry_after": final.box_geometry,
		"max_shift_limit_m": 0.1, "still_frozen": still_frozen, "support_coverage": coverage, "coverage_ok": coverage_ok,
		"last_thaw": main.last_thaw if _scenario in ["C", "D"] else {}, "terrain_save": svc.get_debug_stats().last_save if _scenario in ["C", "D"] else {},
		"trace_enabled": _trace_enabled, "trace_path": trace_result.path, "trace_written": trace_result.written, "trace_ticks": _trace.size(),
		"sampling_note": "contacts disabled by default; five support rays; unsigned collide_shape distances; signed 15-axis OBB SAT gap excludes collision margins; position peak sampled at every tick through tick90"}
	_record("PROBE", "T26 causal intervention and support trace", settled and operation_ok and support_ok and shift.max_m < 0.1 and peak.max_m < 0.1 and still_frozen == 0 and coverage_ok and (not _trace_enabled or trace_result.written), details)
	return true


func _write_probe_trace(data: Dictionary) -> Dictionary:
	if not _trace_enabled: return {"path": "", "written": false}
	var path := _report_path.get_basename() + "_trace.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"path": path, "written": false}
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return {"path": path, "written": true}


func _natural_status() -> Dictionary:
	var sleeping := 0
	var frozen := 0
	var parked := 0
	var missing_state := 0
	var max_linear := 0.0
	var max_angular := 0.0
	var unsettled_bodies: Array[String] = []
	for body: RigidBody3D in _bodies:
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var natural := state != null
		if state == null:
			missing_state += 1
		else:
			sleeping += int(state.sleeping)
			max_linear = maxf(max_linear, state.linear_velocity.length())
			max_angular = maxf(max_angular, state.angular_velocity.length())
			natural = state.sleeping and state.linear_velocity.length() <= NATURAL_REST_VELOCITY_EPS \
				and state.angular_velocity.length() <= NATURAL_REST_VELOCITY_EPS
		frozen += int(body.freeze)
		parked += int(body.has_meta(DebrisBudget.PARKED_META))
		natural = natural and not body.freeze and not body.has_meta(DebrisBudget.PARKED_META)
		if not natural: unsettled_bodies.append(str(body.name))
	return {"all_natural": unsettled_bodies.is_empty() and not _bodies.is_empty(), "sleeping": sleeping,
		"frozen": frozen, "parked": parked, "missing_state": missing_state,
		"max_linear_velocity": max_linear, "max_angular_velocity": max_angular, "unsettled_bodies": unsettled_bodies}


func _wait_natural_rest() -> Dictionary:
	var started_ms := Time.get_ticks_msec()
	var started_frame := Engine.get_physics_frames()
	var consecutive := 0
	var max_consecutive := 0
	var observations: Array[Dictionary] = []
	while Time.get_ticks_msec() - started_ms < NATURAL_REST_TIMEOUT_MS:
		var observation := _natural_status()
		consecutive = consecutive + 1 if observation.all_natural else 0
		max_consecutive = maxi(max_consecutive, consecutive)
		observation["frame"] = Engine.get_physics_frames()
		observation["consecutive_natural_ticks"] = consecutive
		observations.append(observation)
		if consecutive >= NATURAL_REST_TICKS: break
		await get_tree().physics_frame
	return {"enabled": true, "reached": consecutive >= NATURAL_REST_TICKS, "timeout": consecutive < NATURAL_REST_TICKS,
		"required_consecutive_ticks": NATURAL_REST_TICKS, "consecutive_ticks": consecutive, "max_consecutive_ticks": max_consecutive,
		"deadline_ms": NATURAL_REST_TIMEOUT_MS, "observed_ticks": observations.size(),
		"elapsed_physics_frames": Engine.get_physics_frames() - started_frame, "waited_ms": Time.get_ticks_msec() - started_ms,
		"velocity_epsilon": NATURAL_REST_VELOCITY_EPS, "observations": observations, "forced_sleep": false, "retries": 0}


func _begin_natural_control(references: Dictionary) -> void:
	_control_references = references
	for body: RigidBody3D in _bodies:
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		_control_previous_sleep[body.get_instance_id()] = state != null and state.sleeping
	_control_sampling = true
	_sample_natural_control()


func _sample_natural_control() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _control_last_frame: return
	_control_last_frame = frame
	_control_ticks += 1
	var any_active := false
	for body: RigidBody3D in _bodies:
		var key := str(body.name)
		var body_id := body.get_instance_id()
		var shift := body.global_position.distance_to(_control_references[body_id])
		_control_peak_per_body[key] = maxf(float(_control_peak_per_body.get(key, 0.0)), shift)
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var sleeping: bool = state != null and state.sleeping
		if bool(_control_previous_sleep.get(body_id, false)) and not sleeping:
			_control_wakes[key] = int(_control_wakes.get(key, 0)) + 1
		_control_previous_sleep[body_id] = sleeping
		any_active = any_active or not sleeping or body.freeze or body.has_meta(DebrisBudget.PARKED_META)
		if state != null:
			_control_max_linear = maxf(_control_max_linear, state.linear_velocity.length())
			_control_max_angular = maxf(_control_max_angular, state.angular_velocity.length())
			any_active = any_active or state.linear_velocity.length() > NATURAL_REST_VELOCITY_EPS \
				or state.angular_velocity.length() > NATURAL_REST_VELOCITY_EPS
	_control_awake_ticks += int(any_active)


func _natural_control_result(references: Dictionary) -> Dictionary:
	var peak := 0.0
	for value in _control_peak_per_body.values(): peak = maxf(peak, float(value))
	var wakes := 0
	for value in _control_wakes.values(): wakes += int(value)
	var final_status := _natural_status()
	return {"enabled": true, "duration_s": 2.0, "observed_ticks": _control_ticks, "awake_ticks": _control_awake_ticks,
		"wake_events": wakes, "wake_events_per_body": _control_wakes, "peak_shift_m": peak, "peak_per_body_m": _control_peak_per_body,
		"endpoint": _largest_shift(references), "max_linear_velocity": _control_max_linear, "max_angular_velocity": _control_max_angular,
		"max_shift_limit_m": NATURAL_CONTROL_MAX_SHIFT_M, "final_status": final_status,
		"stable": _control_awake_ticks == 0 and wakes == 0 and peak <= NATURAL_CONTROL_MAX_SHIFT_M and final_status.all_natural}


func _prepare_probe_layout() -> bool:
	await main.request_world_reset()
	if not await _go_to_tower(): return false
	if _layout == "tower":
		if _contacts:
			for piece: StructurePiece in structures.get_pieces():
				piece.contact_monitor = true
				piece.max_contacts_reported = 32
		var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		var reverse := int((_repeat - 1) / 4.0) % 2 == 1
		if reverse: corners.reverse()
		var offset := (_repeat - 1) % 4
		var order: Array[Vector2] = []
		for index in 4: order.append(corners[(index + offset) % 4])
		_layout_variant = {"foot_order_offset": offset, "foot_order_reversed": reverse,
			"foot_order": order.map(func(c: Vector2): return [c.x, c.y])}
		for corner: Vector2 in order:
			if not await _dig_under(_foot_at(corner)): return false
		if not await _wait_structures_idle(5.0): return false
		await _seconds(4.0)
		for piece: StructurePiece in structures.get_pieces(): _bodies.append(piece)
		return structures.released_count() == 36
	# Two independent four-crate stacks on unchanged flat voxel ground.
	# Bottom two touch terrain; six upper bodies are supported by other bodies.
	var amplitude := float((_repeat - 1) % 5) * 0.01
	var direction := 1.0 if int((_repeat - 1) / 5.0) % 2 == 0 else -1.0
	_layout_variant = {"alternating_offset_amplitude_m": amplitude, "offset_direction": direction, "offsets": []}
	for column in 2:
		for level in 4:
			var pos := Vector3(10.17 + column * 3.0, 0.62 + level * 1.04, 23.17)
			var sign_offset := direction * (1.0 if (level + column) % 2 == 0 else -1.0)
			var offset := Vector3(sign_offset * amplitude, 0.0, -sign_offset * amplitude) if level > 0 else Vector3.ZERO
			pos += offset
			_layout_variant.offsets.append({"column": column, "level": level, "offset_m": _vec(offset)})
			var crate := DebugProps.spawn_crate(props, pos)
			crate.name = "ProbeStack_%d_%d" % [column, level]
			if _contacts:
				crate.contact_monitor = true
				crate.max_contacts_reported = 32
			_bodies.append(crate)
	await _seconds(5.0)
	return _bodies.size() == 8


func _frames(count: int) -> void:
	for tick in count: await get_tree().physics_frame


func _positions() -> Dictionary:
	var positions := {}
	for body: RigidBody3D in _bodies: positions[body.get_instance_id()] = body.global_position
	return positions


func _save_body_state() -> Dictionary:
	var saved := {}
	for body: RigidBody3D in _bodies:
		saved[body.get_instance_id()] = {"linear_velocity": body.linear_velocity, "angular_velocity": body.angular_velocity, "sleeping": body.sleeping}
	return saved


func _restore_body_state(saved: Dictionary) -> void:
	for body: RigidBody3D in _bodies:
		var prior: Dictionary = saved[body.get_instance_id()]
		body.linear_velocity = prior.linear_velocity
		body.angular_velocity = prior.angular_velocity
		body.sleeping = prior.sleeping


func _largest_shift(prior: Dictionary) -> Dictionary:
	var max_m := 0.0
	var worst := ""
	var each := {}
	for body: RigidBody3D in _bodies:
		var distance := body.global_position.distance_to(prior[body.get_instance_id()])
		each[str(body.name)] = distance
		if distance > max_m:
			max_m = distance
			worst = str(body.name)
	return {"max_m": max_m, "worst_body": worst, "per_body_m": each}


func _update_peak() -> void:
	for body: RigidBody3D in _bodies:
		var distance := body.global_position.distance_to(_peak_references[body.get_instance_id()])
		var key := str(body.name)
		_peak_per_body[key] = maxf(float(_peak_per_body.get(key, 0.0)), distance)
		if distance > _peak_m:
			_peak_m = distance
			_peak_body = key
			_peak_tick = Engine.get_physics_frames() - _thaw_frame


func _snapshot() -> Dictionary:
	var bodies: Array[Dictionary] = []
	for body: RigidBody3D in _bodies: bodies.append(_body_snapshot(body))
	return {"phase": _phase, "physics_frame": Engine.get_physics_frames(), "relative_tick": Engine.get_physics_frames() - _operation_frame,
		"time_ms": Time.get_ticks_msec(), "terrain_busy": svc.is_resetting(), "bodies": bodies,
		"terrain_identity": _terrain_identity(bodies), "box_geometry": _box_geometry()}


func _body_snapshot(body: RigidBody3D) -> Dictionary:
	var row := {"name": str(body.name), "instance_id": body.get_instance_id(), "freeze": body.freeze,
		"freeze_mode": body.freeze_mode, "sleeping": body.sleeping, "can_sleep": body.can_sleep,
		"parked": str(body.get_meta(DebrisBudget.PARKED_META, "")), "mass": body.mass,
		"contact_monitor": body.contact_monitor, "max_contacts_reported": body.max_contacts_reported,
		"position": _vec(body.global_position), "basis": [_vec(body.global_basis.x), _vec(body.global_basis.y), _vec(body.global_basis.z)],
		"linear_velocity": _vec(body.linear_velocity), "angular_velocity": _vec(body.angular_velocity)}
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var contacts: Array[Dictionary] = []
	if state != null:
		row["direct_sleeping"] = state.sleeping
		row["direct_position"] = _vec(state.transform.origin)
		row["direct_linear_velocity"] = _vec(state.linear_velocity)
		row["direct_angular_velocity"] = _vec(state.angular_velocity)
		if _contacts:
			for i in state.get_contact_count():
				contacts.append({"collider": _object_info(state.get_contact_collider_object(i)),
					"local_position_api": _vec(state.get_contact_local_position(i)), "collider_position_api": _vec(state.get_contact_collider_position(i)),
					"local_normal_api": _vec(state.get_contact_local_normal(i)), "impulse": _vec(state.get_contact_impulse(i))})
	row["contacts"] = contacts
	row["contact_count"] = contacts.size()
	row["supports"] = _support_rays(body)
	row["overlaps"] = _overlap_pairs(body)
	return row


func _support_rays(body: RigidBody3D) -> Array[Dictionary]:
	var box := AABB(body.global_position, Vector3.ZERO)
	for child in body.get_children():
		if child is MeshInstance3D and child.mesh != null:
			box = child.global_transform * child.mesh.get_aabb()
			break
	var center := box.get_center()
	var hx := box.size.x * 0.3
	var hz := box.size.z * 0.3
	var rays: Array[Dictionary] = []
	for off: Vector2 in [Vector2.ZERO, Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		var top := Vector3(center.x + off.x, box.position.y + 0.3, center.z + off.y)
		var end := top + Vector3.DOWN * 0.9
		var query := PhysicsRayQueryParameters3D.create(top, end, Layers.TERRAIN | Layers.PROPS, [body.get_rid()])
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		var terrain := svc.raycast_terrain(top, end)
		rays.append({"from": _vec(top), "to": _vec(end), "hit": _hit_info(hit), "terrain": _hit_info(terrain)})
	return rays


func _overlap_pairs(body: RigidBody3D) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.collision_mask = Layers.TERRAIN | Layers.PROPS
		query.exclude = [body.get_rid()]
		query.margin = 0.0
		var points := body.get_world_3d().direct_space_state.collide_shape(query, 16)
		for i in range(0, points.size() - 1, 2):
			pairs.append({"queried_point": _vec(points[i]), "other_point": _vec(points[i + 1]), "unsigned_distance_m": points[i].distance_to(points[i + 1])})
	return pairs


func _hit_info(hit: Dictionary) -> Dictionary:
	if hit.is_empty(): return {}
	return {"collider": _object_info(hit.get("collider")), "position": _vec(hit.position), "normal": _vec(hit.normal),
		"body": hit.get("collider") is RigidBody3D, "shape": hit.get("shape", -1), "rid": hit.get("rid", RID()).get_id()}


func _object_info(object: Object) -> Dictionary:
	if not is_instance_valid(object): return {}
	return {"instance_id": object.get_instance_id(), "class": object.get_class(), "name": str(object.name) if object is Node else ""}


func _terrain_identity(bodies: Array[Dictionary]) -> Dictionary:
	var terrain := svc.get_terrain_node()
	var ids: Array[int] = []
	for body: Dictionary in bodies:
		for ray: Dictionary in body.supports:
			if not ray.terrain.is_empty():
				var rid_id: int = ray.terrain.rid
				if not ids.has(rid_id): ids.append(rid_id)
	ids.sort()
	return {"instance_id": terrain.get_instance_id() if is_instance_valid(terrain) else 0, "support_collider_rids": ids}


func _state_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var changes: Array[Dictionary] = []
	var max_linear_delta := 0.0
	var max_angular_delta := 0.0
	for index in mini(before.bodies.size(), after.bodies.size()):
		var a: Dictionary = before.bodies[index]
		var b: Dictionary = after.bodies[index]
		var linear_delta := _array_vec(a.linear_velocity).distance_to(_array_vec(b.linear_velocity))
		var angular_delta := _array_vec(a.angular_velocity).distance_to(_array_vec(b.angular_velocity))
		max_linear_delta = maxf(max_linear_delta, linear_delta)
		max_angular_delta = maxf(max_angular_delta, angular_delta)
		if a.sleeping != b.sleeping or a.freeze != b.freeze or a.freeze_mode != b.freeze_mode:
			changes.append({"body": a.name, "sleeping_before": a.sleeping, "sleeping_after": b.sleeping,
				"freeze_before": a.freeze, "freeze_after": b.freeze, "mode_before": a.freeze_mode, "mode_after": b.freeze_mode})
	return {"sleeping_or_freeze_changes": changes, "count": changes.size(), "max_linear_velocity_delta": max_linear_delta,
		"max_angular_velocity_delta": max_angular_delta,
		"terrain_node_preserved": before.terrain_identity.instance_id == after.terrain_identity.instance_id,
		"observed_terrain_rids_preserved": before.terrain_identity.support_collider_rids == after.terrain_identity.support_collider_rids}


func _array_vec(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


func _support_coverage(snapshot: Dictionary) -> Dictionary:
	var body_supported := 0
	var terrain_supported := 0
	for body: Dictionary in snapshot.bodies:
		var on_body := false
		var on_terrain := false
		for ray: Dictionary in body.supports:
			on_body = on_body or (not ray.hit.is_empty() and ray.hit.get("body", false))
			on_terrain = on_terrain or not ray.terrain.is_empty()
		body_supported += int(on_body)
		terrain_supported += int(on_terrain)
	return {"body_supported_bodies": body_supported, "terrain_supported_bodies": terrain_supported}


## Pure geometry: exact OBB overlap decision using the 3+3+9 separating axes.
## Positive gap proves separation; negative gap is the minimum translation along
## these normalized axes. It is not Euclidean distance for separated boxes and
## does not include the physics engine's collision/speculative contact margins.
func _box_geometry() -> Dictionary:
	var boxes: Array[Dictionary] = []
	for body: RigidBody3D in _bodies:
		for child in body.get_children():
			if not child is CollisionShape3D or child.disabled or not child.shape is BoxShape3D: continue
			var transform: Transform3D = child.global_transform
			var half: Vector3 = child.shape.size * 0.5
			half *= Vector3(transform.basis.x.length(), transform.basis.y.length(), transform.basis.z.length())
			boxes.append({"body": str(body.name), "center": transform.origin, "half": half,
				"axes": [transform.basis.x.normalized(), transform.basis.y.normalized(), transform.basis.z.normalized()]})
	var pairs: Array[Dictionary] = []
	var max_penetration := 0.0
	var penetrating := 0
	var deeper_than_1mm := 0
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var a: Dictionary = boxes[i]
			var b: Dictionary = boxes[j]
			var delta: Vector3 = b.center - a.center
			var radius: float = a.half.length() + b.half.length() + 0.1
			if delta.length_squared() > radius * radius: continue
			var separation := _sat_gap(a, b)
			if separation.gap_m > 0.1: continue
			pairs.append({"a": a.body, "b": b.body, "sat_signed_gap_m": separation.gap_m, "axis": separation.axis})
			if separation.gap_m < 0.0: penetrating += 1
			if separation.gap_m < -0.001: deeper_than_1mm += 1
			max_penetration = maxf(max_penetration, -float(separation.gap_m))
	return {"boxes": boxes.size(), "near_pairs": pairs, "penetrating_pairs": penetrating,
		"pairs_penetrating_over_1mm": deeper_than_1mm, "max_penetration_m": max_penetration}


func _sat_gap(a: Dictionary, b: Dictionary) -> Dictionary:
	var candidates: Array[Vector3] = []
	for axis: Vector3 in a.axes: candidates.append(axis)
	for axis: Vector3 in b.axes: candidates.append(axis)
	for axis_a: Vector3 in a.axes:
		for axis_b: Vector3 in b.axes:
			var crossed := axis_a.cross(axis_b)
			if crossed.length_squared() > 1e-10: candidates.append(crossed.normalized())
	var delta: Vector3 = b.center - a.center
	var gap := -INF
	var separating_axis := Vector3.ZERO
	for axis: Vector3 in candidates:
		var radius_a := 0.0
		var radius_b := 0.0
		for k in 3:
			radius_a += a.half[k] * absf(a.axes[k].dot(axis))
			radius_b += b.half[k] * absf(b.axes[k].dot(axis))
		var candidate_gap := absf(delta.dot(axis)) - radius_a - radius_b
		if candidate_gap > gap:
			gap = candidate_gap
			separating_axis = axis
	return {"gap_m": gap, "axis": _vec(separating_axis)}


func _vec(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]
