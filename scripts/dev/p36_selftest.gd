extends "res://scripts/dev/p35_selftest.gd"
## P3.6: regressões P0–P3.5 e cenários novos. --only=T46,T47,T48 limita a Água;
## T1 e baseline continuam obrigatórios. Capturas não equivalem a playtest humano.


func _ready() -> void:
	super._ready()
	if OS.get_cmdline_user_args().has("--p36-screenshots") and DisplayServer.get_name() != "headless":
		_screens = true


func _report_prefix() -> String:
	return super._report_prefix() if _persist_phase != "" else "p36_selftest"


func _evidence_dir() -> String:
	return "res://docs/evidence/p36/%s/" % _evidence_stage() if OS.has_feature("editor") else "user://"


func _screens_dir() -> String:
	var stage := _evidence_stage()
	return "res://docs/evidence/p36/%s/screens/" % stage if OS.has_feature("editor") else "user://screens_p36_%s/" % stage


## Consultado também por super._ready(): não depende de campos inicializados depois.
func _evidence_stage() -> String:
	var stage := "final"
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--evidence-stage="):
			continue
		var value := arg.trim_prefix("--evidence-stage=")
		if value not in ["m1", "m2", "m3", "final"]:
			push_error("[P36TEST] evidence-stage inválido: %s" % value)
			return "final"
		stage = value
	return stage


func _log(msg: String) -> void:
	print("[P36TEST] ", msg)


func _run_tests() -> bool:
	var ok: bool = await super._run_tests()
	if not ok or _persist_phase != "":
		return ok
	_log("--- testes P3.6 M1 (Água) ---")
	if _should_run("T46"): await _t46_water_transport()
	if _should_run("T47"): await _t47_water_cancel_and_tuning()
	if _should_run("T48"): await _t48_water_splash_and_mass()
	return true


## Relógio de física para o contrato de transporte. O gate de frame time continua
## usando tempo real nos benchmarks herdados, sem misturar as duas grandezas.
func _water_distance(ab: AbilityController, target: RigidBody3D) -> float:
	var start := ab.hand_position()
	var toward := ab.aim_point(24.0)
	var hit := ab.cast_segment(start, start + (toward - start).normalized() * 14.0)
	return start.distance_to(hit.position) if not hit.is_empty() and hit.collider == target else -1.0


func _water_touch(jet: WaterJet, state: MaterialState, distance: float, start_frame: int,
		check_pressure := true) -> Dictionary:
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var earliest := maxf(0.0, distance / jet.tuning.stream_speed - 2.0 * dt)
	var deadline := distance / jet.tuning.stream_speed + jet.tuning.emission_interval_s + 3.0 * dt
	var first_s := -1.0
	var pressure_s := -1.0
	var peak := jet.packets.size()
	var early_ok := true
	while float(Engine.get_physics_frames() - start_frame) * dt <= deadline + dt:
		var elapsed := float(Engine.get_physics_frames() - start_frame) * dt
		peak = maxi(peak, jet.packets.size())
		if pressure_s < 0.0 and jet.pressure >= 0.999:
			pressure_s = elapsed
		if state.wetness > 0.00001:
			first_s = elapsed
			early_ok = first_s >= earliest - 0.000001
			break
		await get_tree().physics_frame
	return {"distance_m": distance, "first_contact_s": first_s, "earliest_s": earliest,
		"deadline_s": deadline, "no_early_contact": early_ok, "arrived_on_time": first_s >= 0.0 and first_s <= deadline + 0.000001,
		"pressure_ready_s": pressure_s, "pressure_on_time": not check_pressure or (pressure_s >= 0.0 and pressure_s <= jet.tuning.pressure_rise_s + dt + 0.000001),
		"peak_packets": peak, "max_packets": jet.tuning.max_packets}


func _t46_water_transport() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var first := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -6))
	first.freeze = true
	var second := DebugProps.spawn_crate(props, base + Vector3(6, 0.8, 0))
	second.freeze = true
	await _aim_settle(MaterialResponseSystem.body_center(first))
	var distance := _water_distance(ab, first)
	var frame := Engine.get_physics_frames()
	var pressed := ab.use_pressed()
	var forward := await _water_touch(jet, materials.state_of(first), distance, frame)
	await _snap("p36_water_contact")
	# O jato já está cheio: uma implementação que apenas gira um raio de 14 m
	# molharia a segunda caixa imediatamente. Pacotes antigos devem seguir -Z.
	# A câmera orbita atrás do jogador: resolver a orientação iterativamente no
	# mesmo tick evita os 4 ticks de emissão que _aim_settle acrescentaria à virada.
	for i in 8:
		_aim_at(MaterialResponseSystem.body_center(second))
	var second_distance := _water_distance(ab, second)
	var turn_frame := Engine.get_physics_frames()
	var turn := await _water_touch(jet, materials.state_of(second), second_distance, turn_frame, false)
	await _snap("p36_water_after_turn")
	ab.use_released()
	# Captura independente das medições de chegada, sem introduzir espera de render
	# dentro da janela temporal observada acima.
	if _screens:
		ab.use_pressed()
		await _frames(2)
		await _snap("p36_water_start")
		ab.use_released()
	player.input_enabled = false
	var ok: bool = pressed and distance > 0.0 and second_distance > 0.0 \
		and forward.no_early_contact and forward.arrived_on_time and forward.pressure_on_time \
		and turn.no_early_contact and turn.arrived_on_time \
		and forward.peak_packets <= jet.tuning.max_packets and turn.peak_packets <= jet.tuning.max_packets
	_record("T46", "Água transporta pacotes e pressão; virar 90° não acerta alvo distante instantaneamente", ok,
		{"forward": forward, "turn_90_deg": turn, "method": "physics ticks; distances to actual collider contact", "pressed": pressed})


func _water_shutdown(ab: AbilityController, jet: WaterJet, kind: String) -> Dictionary:
	ab.use_pressed()
	await _frames(3)
	var live_before := jet.packets.size()
	if kind == "release": ab.use_released()
	elif kind == "cancel": jet.cancel()
	else: jet.clear()
	var clean_now := not jet.active and jet.packets.is_empty()
	var contacts: int = jet.get_stats().body_ticks + jet.get_stats().terrain_ticks
	await _frames(2)
	var after: int = jet.get_stats().body_ticks + jet.get_stats().terrain_ticks
	ab.use_released()
	return {"kind": kind, "live_before": live_before, "clean_in_command": clean_now,
		"contacts_before": contacts, "contacts_after_2_ticks": after,
		"ok": live_before > 0 and clean_now and contacts == after and jet.packets.is_empty()}


func _t47_water_cancel_and_tuning() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var original: WaterTuning = jet.tuning
	var variant: WaterTuning = original.duplicate(true)
	variant.stream_speed = 12.0
	variant.pressure_rise_s = 0.24
	variant.emission_interval_s = 1.0 / 60.0
	variant.max_packets = 2
	variant.force = 0.0
	jet.tuning = variant
	var body := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -6))
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.collision_mask = 0
	await _aim_settle(MaterialResponseSystem.body_center(body))
	var distance := _water_distance(ab, body)
	var impulse_before: float = jet.get_stats().impulse_ns
	var frame := Engine.get_physics_frames()
	ab.use_pressed()
	await _frames(7)
	var mid_pressure := jet.pressure
	var arrival := await _water_touch(jet, materials.state_of(body), distance, frame)
	var no_force := body.linear_velocity.length() < 0.0001 and is_zero_approx(float(jet.get_stats().impulse_ns) - impulse_before)
	ab.use_released()
	var stops: Array[Dictionary] = []
	for kind in ["release", "cancel", "clear"]:
		stops.append(await _water_shutdown(ab, jet, kind))
	jet.tuning = original
	player.input_enabled = false
	var ok: bool = distance > 0.0 and mid_pressure > 0.1 and mid_pressure < 0.9 \
		and arrival.no_early_contact and arrival.arrived_on_time and arrival.pressure_on_time \
		and arrival.peak_packets <= variant.max_packets and no_force and stops.all(func(s): return s.ok)
	_record("T47", "Água usa Resource variante, limita pacotes e descarta simulação ao soltar/cancelar/limpar", ok,
		{"variant": {"speed_mps": variant.stream_speed, "rise_s": variant.pressure_rise_s, "max_packets": variant.max_packets, "force_N": variant.force},
		"pressure_at_7_ticks": mid_pressure, "arrival": arrival, "zero_force_observed": no_force, "stops": stops})


func _p36_thin_wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "P36ThinWall"
	wall.collision_layer = Layers.PROPS
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	wall.add_child(cs)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	wall.add_child(mesh)
	props.add_child(wall)
	wall.global_position = at
	return wall


func _water_mass_case(ab: AbilityController, jet: WaterJet, base: Vector3, mass: float) -> Dictionary:
	var body := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -6))
	body.mass = mass
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.collision_mask = 0
	await _aim_settle(MaterialResponseSystem.body_center(body))
	var impulse_before: float = jet.get_stats().impulse_ns
	var held := await _hold_on(body, 0.8)
	await _frames(1)
	var impulse: float = jet.get_stats().impulse_ns - impulse_before
	var speed := body.linear_velocity.length()
	var expected := impulse / mass
	var ok := held and impulse > 0.0 and expected > 0.0 and absf(speed - expected) <= expected * 0.12
	body.queue_free()
	await _frames(2)
	return {"mass_kg": mass, "impulse_Ns": impulse, "speed_mps": speed,
		"expected_delta_v": expected, "relative_tolerance": 0.12, "ok": ok}


## A mão avança 0,6 m além dos pés e pode nascer dentro de um prop estreito
## mesmo com a cápsula do jogador fora. O raio da câmera deve continuar vendo
## o alvo atrás; caso contrário, o cenário não exercitaria o bypass do segmento.
func _water_inside_obstacle(ab: AbilityController, jet: WaterJet, base: Vector3) -> Dictionary:
	var target := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -4))
	target.freeze = true
	await _aim_settle(MaterialResponseSystem.body_center(target))
	var hand := ab.hand_position()
	var size := Vector3(0.3, 0.3, 0.3)
	var wall := _p36_thin_wall(hand, size)
	await _frames(2)
	var aim := ab.aim_any(24.0)
	var sees_target: bool = not aim.is_empty() and aim.collider == target
	var inside := AABB(wall.global_position - size * 0.5, size).has_point(ab.hand_position())
	var state := materials.state_of(target)
	var before := jet.get_stats()
	var pressed := ab.use_pressed()
	await _seconds(0.5)
	var after := jet.get_stats()
	var wetness := state.wetness
	var normal := jet.contact_normal
	var origin_contact := jet.contact_point
	await _snap("p36_water_origin_inside_prop")
	ab.use_released()
	return {"hand": str(hand), "origin_inside_convex_prop": inside, "camera_sees_target_behind": sees_target,
		"blocked_wetness": wetness, "wall_contacts": after.terrain_ticks - before.terrain_ticks,
		"body_contacts": after.body_ticks - before.body_ticks, "contact_point": str(origin_contact),
		"contact_normal": str(normal), "ok": pressed and inside and sees_target and wetness < 0.001 \
			and after.terrain_ticks > before.terrain_ticks and after.body_ticks == before.body_ticks}


func _t48_water_splash_and_mass() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var wall := _p36_thin_wall(base + Vector3(0, 0.8, -4), Vector3(3, 3, 0.001))
	var exposed := DebugProps.spawn_crate(props, base + Vector3(0.8, 0.8, -3.4))
	var blocked := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -4.6))
	exposed.freeze = true
	blocked.freeze = true
	await _aim_settle(wall.global_position)
	_apply_direct(ElementalEvent.Kind.HEAT, exposed, 80.0)
	_apply_direct(ElementalEvent.Kind.HEAT, blocked, 80.0)
	var exposed_state := materials.state_of(exposed)
	var blocked_state := materials.state_of(blocked)
	var start := jet.get_stats()
	var pressed := ab.use_pressed()
	await _seconds(1.4)
	var origin := jet.contact_point + jet.contact_normal * 0.02
	var los_exposed := materials.line_of_sight(origin, exposed)
	var los_blocked := materials.line_of_sight(origin, blocked)
	var splash := {"pressed": pressed, "wall_thickness_m": 0.001,
		"physical_wall_contacts": jet.get_stats().terrain_ticks - start.terrain_ticks,
		"impact_origin": str(origin), "impact_normal": str(jet.contact_normal),
		"exposed_wetness": exposed_state.wetness, "blocked_wetness": blocked_state.wetness,
		"exposed_temperature": exposed_state.temperature, "blocked_temperature": blocked_state.temperature,
		"los_exposed": los_exposed, "los_blocked": los_blocked}
	var splash_ok: bool = pressed and splash.physical_wall_contacts > 0 and jet.contact_normal.z > 0.9 \
		and los_exposed and not los_blocked and exposed_state.wetness > 0.01 and blocked_state.wetness < 0.001 \
		and exposed_state.temperature < blocked_state.temperature - 1.0
	await _snap("p36_water_thin_wall_splash")
	ab.use_released()
	base = await _p3_lab(1)
	var inside := await _water_inside_obstacle(ab, jet, base)
	base = await _p3_lab(1)
	var light := await _water_mass_case(ab, jet, base, 20.0)
	var heavy := await _water_mass_case(ab, jet, base, 2000.0)
	player.input_enabled = false
	var mass_ok: bool = light.ok and heavy.ok and light.speed_mps > heavy.speed_mps * 10.0
	_record("T48", "Água respeita parede fina e origem dentro de prop; respingo resfria e impulso depende da massa", splash_ok and inside.ok and mass_ok,
		{"splash": splash, "origin_inside_prop": inside, "light": light, "heavy": heavy, "legacy_extinction": "T33 conserva o limite de 3 s"})
