extends SceneTree
## Cenários definidos da preparação; consultas físicas reais e contratos negativos.
var checks: Array[Dictionary] = []
var main: Node
var logger: Logger

class WitnessSpace:
	extends RefCounted
	var calls := 0
	var disagree := false
	var one_sided := false
	func intersect_ray(q: PhysicsRayQueryParameters3D) -> Dictionary:
		calls += 1
		if calls == 1 or (one_sided and calls == 3):
			return {}
		return {"rid": 2 if disagree and calls == 3 else 1, "normal": Vector3.UP,
			"position": q.from + (q.to - q.from) * 0.5}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	logger = load("res://scripts/dev/error_counter_logger.gd").new()
	OS.add_logger(logger)
	_test_queue()
	_test_witnesses()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var deadline := Time.get_ticks_msec() + 30000
	while not main.terrain_service.is_ready() and Time.get_ticks_msec() < deadline:
		await physics_frame
	main.player.input_enabled = false
	main.player.teleport_to(Vector3(-34, 1, 70))
	await create_timer(2.0).timeout
	_test_physical_rays()
	_test_tool_switch()
	await _test_world_transitions()
	var snapshot: Dictionary = logger.snapshot()
	_record("motor_zero", snapshot.errors == 0 and snapshot.warnings == 0, snapshot)
	var passed := checks.all(func(c): return c.passed)
	var path := "res://docs/evidence/p36/preparation/preparation.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"head_context": "P3.6 preparation", "godot": Engine.get_version_info(),
		"passed": passed, "checks": checks, "logger": snapshot}, "  "))
	f.close()
	OS.remove_logger(logger)
	print("[PREP] ", "PASS" if passed else "FAIL", " ", checks.size(), " cenarios")
	quit(0 if passed else 1)

func _record(id: String, ok: bool, details := {}) -> void:
	checks.append({"id": id, "passed": ok, "details": details})
	print("[PREP] ", id, " ", ok, " ", JSON.stringify(details))

func _test_queue() -> void:
	var q := TerrainBrushQueue.new()
	for distance in [0.2, 20.0]:
		q.clear()
		var id := q.begin_stroke(TerrainBrushRequest.Op.REMOVE, 1.0)
		q.update_stroke(id, Vector3.ZERO, Vector3.UP)
		q.update_stroke(id, Vector3(distance, 0, 0), Vector3.UP)
		q.end_stroke(id)
		_record("release_%.1fm" % distance, q._pending.size() == 2 and q._pending[-1].points[-1].is_equal_approx(Vector3(distance, 0, 0)))
	q.clear()
	var id := q.begin_stroke(TerrainBrushRequest.Op.REMOVE, 1.0)
	q.update_stroke(id, Vector3.ZERO, Vector3.UP)
	q.update_stroke(id, Vector3(0.2, 0, 0), Vector3.UP)
	q.update_stroke(id, Vector3.ZERO, Vector3.UP, false)
	q.update_stroke(id, Vector3(20, 0, 0), Vector3.UP)
	q.end_stroke(id)
	q._merge_backlog()
	var safe := true
	for req in q._pending:
		safe = safe and (not req.is_path() or req.length() < 1.0)
	_record("lost_aim_no_bridge", safe and q._pending.size() >= 2)
	q.clear()
	id = q.begin_stroke(TerrainBrushRequest.Op.REMOVE, 1.0)
	q.update_stroke(id, Vector3.ZERO, Vector3.UP)
	q.update_stroke(id, Vector3(20, 0, 0), Vector3.UP)
	q.cancel_stroke(id)
	_record("cancel_no_final_segment", q._pending.size() == 1 and q.active_stroke_count() == 0)
	var stale: TerrainBrushRequest = q._pending[0]
	q.clear("test epoch")
	_record("stale_request_rejected", not q.enqueue(stale) and q.pending_count() == 0)
	q.free()

func _test_witnesses() -> void:
	for mode in ["agreement", "adjacent_colliders", "thin_edge"]:
		var space := WitnessSpace.new()
		space.disagree = mode == "adjacent_colliders"
		space.one_sided = mode == "thin_edge"
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(0, -1, 0), Layers.TERRAIN)
		var hit := PhysicsRayHelper.intersect(space, q)
		_record("fallback_" + mode, (not hit.is_empty()) == (mode == "agreement") and q.from == Vector3(0, 1, 0), {"queries": space.calls})

func _test_physical_rays() -> void:
	var svc: TerrainService = main.terrain_service
	var hits := 0
	var attempts := 0
	var fallback := 0
	for xi in 10:
		for zi in 9:
			var at := Vector3(-40 + xi, 0, 52 + zi)
			var from := at + Vector3(0, 3, 9)
			var hit := svc.raycast_terrain(from, from + (at - from).normalized() * 22.0)
			attempts += 1
			hits += int(not hit.is_empty())
			fallback += int(hit.get("ray_fallback", false))
	_record("terrain_slanted_vertices", hits == attempts, {"attempts": attempts, "hits": hits, "failures": attempts - hits, "fallbacks": fallback})
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.PROPS
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.001, 2, 2)
	cs.shape = shape
	wall.add_child(cs)
	main.add_child(wall)
	wall.global_position = Vector3(-34, 3, 60)
	# Queries precisam de um tick para a inserção no espaço físico.
	_test_thin_wall.call_deferred(wall)

func _test_thin_wall(wall: StaticBody3D) -> void:
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var hits := 0
	for i in 100:
		var z := 59.5 + float(i) * 0.01
		var q := PhysicsRayQueryParameters3D.create(Vector3(-36, 3, z), Vector3(-32, 3, z), Layers.PROPS)
		var h := PhysicsRayHelper.intersect(space, q)
		hits += int(not h.is_empty() and h.collider == wall)
	_record("thin_wall_1mm", hits == 100, {"attempts": 100, "hits": hits, "failures": 100 - hits})
	var excluded := PhysicsRayQueryParameters3D.create(Vector3(-36, 3, 60), Vector3(-32, 3, 60), Layers.PROPS, [wall.get_rid()])
	_record("ray_exclusion_preserved", PhysicsRayHelper.intersect(space, excluded).is_empty())
	var neighbor := StaticBody3D.new()
	neighbor.collision_layer = Layers.PROPS
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.001, 2, 2)
	cs.shape = box
	neighbor.add_child(cs)
	main.add_child(neighbor)
	neighbor.global_position = wall.global_position + Vector3(0, 0, 2)
	await physics_frame
	await physics_frame
	var correct := 0
	for i in 100:
		var z := 60.5 + float(i) * 0.01
		var q := PhysicsRayQueryParameters3D.create(Vector3(-36, 3, z), Vector3(-32, 3, z), Layers.PROPS)
		var h := PhysicsRayHelper.intersect(space, q)
		correct += int(not h.is_empty() and h.collider == (wall if z < 61.0 else neighbor))
	_record("adjacent_native_colliders", correct == 100, {"attempts": 100, "correct_selection": correct, "failures": 100 - correct})
	neighbor.queue_free()
	wall.queue_free()

func _test_world_transitions() -> void:
	var q: TerrainBrushQueue = main.brush_queue
	for op in ["reset", "save", "load"]:
		q.set_physics_process(false)
		var req := TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE, Vector3(12, 0, 28), 1.0)
		q.enqueue(req)
		var id := q.begin_stroke(TerrainBrushRequest.Op.REMOVE, 1.0)
		q.update_stroke(id, Vector3(12, 0, 28), Vector3.UP)
		var ok := false
		if op == "reset": ok = await main.request_world_reset()
		elif op == "save": ok = await main.request_world_save("p36_preparation")
		else: ok = await main.request_world_load("p36_preparation")
		q.end_stroke(id)
		_record("transition_" + op, ok and q.pending_count() == 0 and q.active_stroke_count() == 0 and not q.enqueue(req))
	q.set_physics_process(true)

func _test_tool_switch() -> void:
	var edit: TerrainEditController = main.edit_controller
	var q: TerrainBrushQueue = main.brush_queue
	q.clear("switch test")
	edit._aim_hit = true
	edit._aim_point = Vector3(-34, 0, 60)
	edit._begin_stroke(&"terrain_dig")
	edit._aim_point += Vector3(0.2, 0, 0)
	edit._feed_stroke(&"terrain_dig")
	edit._begin_stroke(&"terrain_add")
	_record("tool_switch_explicit", edit._strokes.size() == 1 and edit._strokes.has(&"terrain_add") and q.active_stroke_count() == 1)
	Input.action_press(&"terrain_add")
	edit._cancel_for_transition()
	_record("held_action_latched_on_transition", edit._strokes.is_empty() and edit._blocked_actions.has(&"terrain_add"))
	Input.action_release(&"terrain_add")
	edit._blocked_actions.clear()
	q.clear("switch test end")
