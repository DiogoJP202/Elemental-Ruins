extends SceneTree
## Comparação de candidatos no laboratório real. Custos CPU não são custos GPU.
const BASE := Vector3(-34, 0, 60)
var main: Node
var results := {}
var logger: Logger
var proto: MultiMeshInstance3D
var legacy: MeshInstance3D
var visual_mode := 0
var visual_clock := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	logger = load("res://scripts/dev/error_counter_logger.gd").new()
	OS.add_logger(logger)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var deadline := Time.get_ticks_msec() + 30000
	while not main.terrain_service.is_ready() and Time.get_ticks_msec() < deadline:
		await physics_frame
	main.player.input_enabled = false
	main.player.teleport_to(BASE + Vector3(0, 1, 12))
	main.player.camera_rig.set_view(0.0, deg_to_rad(-12.0))
	main.abilities.set_physics_process(false)
	await create_timer(2.0).timeout
	for x in 4:
		for z in 3:
			var b := DebugProps.spawn_crate(main.props_root, BASE + Vector3(-2.25 + x * 1.5, 0.5, -4.0 - z * 1.5))
			b.freeze = true
	await physics_frame
	await physics_frame
	results["query_cpu_us"] = {
		"water_single_ray": _cost(func(): _rays(1), 1000),
		"water_three_rays": _cost(func(): _rays(3), 1000),
		"water_packet_segment_budget_16": _cost(func(): _sweeps(16), 1000),
		"fire_single_sweep": _cost(func(): _sweeps(1), 1000),
		"fire_three_substeps": _cost(func(): _sweeps(3), 1000),
		"air_single_visibility": _cost(func(): _exposure(1), 100),
		"air_three_visibility": _cost(func(): _exposure(3), 100),
		"heat_area_without_visibility": _cost(func(): _heat_area(false), 100),
		"heat_area_with_visibility": _cost(func(): _heat_area(true), 100)}
	await _force_models()
	await _thin_wall_sweeps()
	results["propagation_models"] = _propagation_models()
	if DisplayServer.get_name() != "headless":
		await _visual_models()
	var snap: Dictionary = logger.snapshot()
	results["logger"] = snap
	results["godot"] = Engine.get_version_info()
	results["renderer"] = RenderingServer.get_current_rendering_method()
	results["mode"] = DisplayServer.get_name()
	results["cpu"] = OS.get_processor_name()
	results["resolution"] = str(root.get_visible_rect().size)
	results["methodology"] = "CPU: 7 batches, median microseconds per operation; render: 1.5s warmup + 3s frame intervals per candidate. Isolated effects, not aggregate gate."
	var folder := "res://docs/evidence/p36/m0/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var f := FileAccess.open(folder + ("spike_headless.json" if DisplayServer.get_name() == "headless" else "spike_window.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	OS.remove_logger(logger)
	print("[M0SPIKE] ", JSON.stringify(results))
	quit(0 if snap.errors == 0 and snap.warnings == 0 else 1)

func _cost(cb: Callable, n: int) -> Dictionary:
	var times: Array[float] = []
	for batch in 7:
		var start := Time.get_ticks_usec()
		for i in n: cb.call()
		times.append(float(Time.get_ticks_usec() - start) / n)
	times.sort()
	return {"median_us": times[3], "min_us": times[0], "max_us": times[-1], "batches": 7, "calls_per_batch": n}

func _rays(n: int) -> void:
	var from := BASE + Vector3(0, 1.3, 3)
	var to := BASE + Vector3(0, 0.5, -10)
	for i in n:
		var shift := Vector3(float(i) * 0.1, 0, 0)
		main.abilities.cast_segment(from + shift, to + shift)

func _sweeps(n: int) -> void:
	var from := BASE + Vector3(0, 1.3, 3)
	var to := BASE + Vector3(0, 0.5, -10)
	for i in n:
		main.abilities.cast_segment(from.lerp(to, float(i) / n), from.lerp(to, float(i + 1) / n))

func _thin_wall_sweeps() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.PROPS
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.001, 2, 2)
	cs.shape = shape
	wall.add_child(cs)
	main.add_child(wall)
	wall.global_position = BASE + Vector3(20, 5, 0)
	await physics_frame
	await physics_frame
	results["thin_wall_sweeps"] = {}
	for n in [1, 3]:
		var hits := 0
		for i in 100:
			var from := wall.global_position + Vector3(-2, 0, -0.5 + i * 0.01)
			var to := from + Vector3(4, 0, 0)
			for part in n:
				var h: Dictionary = main.abilities.cast_segment(from.lerp(to, float(part) / n), from.lerp(to, float(part + 1) / n))
				if not h.is_empty() and h.collider == wall:
					hits += 1
					break
		results.thin_wall_sweeps[str(n)] = {"attempts": 100, "hits": hits, "failures": 100 - hits, "thickness_m": 0.001}
	wall.queue_free()

func _exposure(n: int) -> void:
	var from := BASE + Vector3(0, 1.3, 3)
	for b in main.materials.bodies_in_sphere(from, 14, 128):
		var center := MaterialResponseSystem.body_center(b)
		for i in n:
			var q := PhysicsRayQueryParameters3D.create(from, center + Vector3((float(i) - float(n - 1) * 0.5) * 0.3, 0, 0), Layers.TERRAIN | Layers.PROPS, [b.get_rid()])
			main.get_world_3d().direct_space_state.intersect_ray(q)

func _heat_area(visibility: bool) -> void:
	var from := BASE + Vector3(0, 0.5, -5)
	for b in main.materials.bodies_in_sphere(from, 2.2):
		if visibility:
			var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.02, MaterialResponseSystem.body_center(b), Layers.TERRAIN | Layers.PROPS, [b.get_rid()])
			if not main.get_world_3d().direct_space_state.intersect_ray(q).is_empty(): continue
		main.materials.state_of(b)

func _force_models() -> void:
	var data := {}
	for ramped in [false, true]:
		var bodies: Array[RigidBody3D] = []
		for mass in [20.0, 2000.0]:
			var b := DebugProps.spawn_crate(main.props_root, BASE + Vector3(20, 8, 0))
			b.mass = mass
			b.gravity_scale = 0
			b.linear_damp = 0
			b.collision_layer = 0
			b.collision_mask = 0
			bodies.append(b)
		await physics_frame
		for i in 30:
			var pressure := minf(float(i + 1) / 8.0, 1.0) if ramped else 1.0
			for b in bodies: b.apply_central_force(Vector3.RIGHT * 300.0 * pressure)
			await physics_frame
		await physics_frame
		data["pressure_ramp" if ramped else "immediate"] = {"light_mps": bodies[0].linear_velocity.x, "heavy_mps": bodies[1].linear_velocity.x, "mass_ratio": 100.0, "seconds": 0.5}
		for b in bodies: b.queue_free()
	results["force_models"] = data

func _propagation_models() -> Dictionary:
	var data := {}
	for speed in [20.0, 30.0, 60.0]:
		var near := -1.0
		var far := -1.0
		for frame in 120:
			var t := (frame + 1) / 60.0
			if near < 0 and t * speed >= 3.0: near = t
			if far < 0 and t * speed >= 9.0: far = t
		data[str(speed)] = {"near_3m_s": near, "far_9m_s": far, "spatial_solver": "front=min(range,speed*elapsed); once per target"}
	return data

func _make_proto() -> void:
	legacy = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.12
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	cylinder.material = ElementalFx._unshaded(Color(0.45, 0.7, 1.0, 0.6))
	legacy.mesh = cylinder
	legacy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(legacy)
	proto = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	mesh.radial_segments = 6
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.78, 0.95, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	mm.mesh = mesh
	mm.instance_count = 24
	proto.multimesh = mm
	proto.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(proto)

func _process(delta: float) -> bool:
	if main == null or not is_instance_valid(main) or proto == null: return false
	visual_clock += delta
	if visual_mode == 1:
		var origin: Vector3 = main.abilities.hand_position()
		legacy.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD * 12, Vector3.UP), origin + Vector3.FORWARD * 6)
	elif visual_mode == 2:
		var origin: Vector3 = main.abilities.hand_position()
		for i in 24:
			var t := (float(i) + 0.5) / 24
			var p := origin + Vector3(sin(t * 16 - visual_clock * 13) * 0.06 * t, cos(t * 13 - visual_clock * 10) * 0.04 * t, -t * 12)
			proto.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1, 3.1)), p))
	return false

func _visual_models() -> void:
	_make_proto()
	var jet: WaterJet = main.abilities.get_ability(&"water_jet")
	main.fx.set_process(false)
	results["visual_frame_ms"] = {}
	var first_control := true
	for mode in [0, 1, 2, 0]:
		visual_mode = mode
		main.fx.visible = false
		legacy.visible = mode == 1
		proto.visible = mode == 2
		jet.active = mode == 1
		jet.beam_from = main.abilities.hand_position()
		jet.beam_to = jet.beam_from + Vector3.FORWARD * 12
		main.fx._spray.emitting = false
		await create_timer(1.5).timeout
		var frames: Array[float] = []
		var last := Time.get_ticks_usec()
		var start := last
		while Time.get_ticks_usec() - start < 3000000:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
		frames.sort()
		var name: String = ["none", "legacy_cylinder", "multimesh_24"][mode]
		if mode == 0:
			name = "none_initial" if first_control else "none_repeated"
			first_control = false
		results.visual_frame_ms[name] = {"n": frames.size(), "p95": frames[int(ceil(frames.size()*0.95))-1], "p99": frames[int(ceil(frames.size()*0.99))-1], "max": frames[-1]}
		await RenderingServer.frame_post_draw
		var folder := "res://docs/evidence/p36/m0/screens/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		root.get_texture().get_image().save_png(folder + name + ".png")
