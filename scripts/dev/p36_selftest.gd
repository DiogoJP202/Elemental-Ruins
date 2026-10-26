extends "res://scripts/dev/p35_selftest.gd"
## P3.6: regressões P0–P3.5 e cenários novos. --only=T46,T47,T48 limita a Água;
## --only=T49,T50,T51,T57 limita o Fogo e o ciclo de vida (reset/save/load).
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
	_log("--- testes P3.6 M2 (Fogo) ---")
	if _should_run("T49"): await _t49_fire_anticipation_and_tuning()
	if _should_run("T50"): await _t50_fire_sweep_and_dissipation()
	if _should_run("T51"): await _t51_fire_spread_visibility()
	_log("--- testes P3.6 ciclo de vida ---")
	if _should_run("T57"): await _t57_lifecycle_invalidation()
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


# --- M2: Fogo ---------------------------------------------------------------------------------

## Registra os fx_event do fogo com o tick de física do contexto e, em cada evento, a temperatura
## dos corpos observados (no impacto, logo depois do calor: o FX é emitido após o evento térmico).
func _fire_watch(fire: FireBurst, watched: Array) -> Dictionary:
	var watch := {"log": [], "callback": Callable()}
	var log: Array = watch.log
	var cb := func(kind: StringName, data: Dictionary) -> void:
		var temps := []
		for b in watched:
			var s: MaterialState = materials.state_of(b) if is_instance_valid(b) else null
			temps.append(s.temperature if s != null else -1.0)
		log.append({"kind": String(kind), "tick": int(data.get("tick", -1)), "session": int(data.get("session_id", -1)),
			"id": int(data.get("projectile_id", -1)), "data": data.duplicate(), "temps": temps})
	fire.fx_event.connect(cb)
	watch.callback = cb
	return watch


func _fire_unwatch(fire: FireBurst, watch: Dictionary) -> void:
	if fire.fx_event.is_connected(watch.callback):
		fire.fx_event.disconnect(watch.callback)


## Primeiro evento de cada tipo do projétil `pid`.
func _fire_shot(watch: Dictionary, pid: int) -> Dictionary:
	var out := {}
	for e: Dictionary in watch.log:
		if int(e.id) == pid and not out.has(e.kind):
			out[e.kind] = e
	return out


func _fire_kinds_since(watch: Dictionary, index: int) -> Array:
	var kinds := []
	var log: Array = watch.log
	for i in range(index, log.size()):
		kinds.append(log[i].kind)
	return kinds


## O clique acontece no início do tick N, antes da física desse tick; o evento do tick T
## vem depois de integrar os ticks N..T, ou seja, T − N + 1 passos.
func _ticks_s(from_tick: int, to_tick: int) -> float:
	return float(to_tick - from_tick + 1) / float(Engine.physics_ticks_per_second)


## Só para capturas: a câmera orbita o jogador e o capsule fica no centro da tela, escondendo o
## que está na mira. Gira a vista ao lado do ponto, quase horizontal (o marcador do pincel de
## terreno só aparece com chão a até 40 m). Chamada depois do clique: a direção já foi capturada.
func _capture_view(point: Vector3, yaw_offset_deg := 30.0, pitch_deg := 2.0) -> void:
	if not _screens:
		return
	var dir := point - player.global_position
	player.camera_rig.set_view(atan2(-dir.x, -dir.z) + deg_to_rad(yaw_offset_deg), deg_to_rad(pitch_deg))


## Toque único; id do projétil criado ou -1 se o poder recusou (recuperação ou limite).
func _fire_press(ab: AbilityController, fire: FireBurst) -> int:
	var before: int = fire.get_stats().fired
	ab.use_pressed()
	ab.use_released()
	if fire.get_stats().fired == before or fire.projectiles.is_empty():
		return -1
	return int(fire.projectiles[fire.projectiles.size() - 1].id)


func _t49_fire_anticipation_and_tuning() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(2)
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var fx: ElementalFx = main.fx
	var original: FireTuning = fire.tuning
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var target := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -6))
	var decoy := DebugProps.spawn_crate(props, base + Vector3(6, 0.8, -6))
	var tuned := DebugProps.spawn_crate(props, base + Vector3(-3, 0.8, -6))
	for c: RigidBody3D in [target, decoy, tuned]:
		c.freeze = true
	await _frames(2)
	var watch := _fire_watch(fire, [target, decoy, tuned])
	# a) Padrão: slot desde o clique, nenhum calor antes do voo, lançamento em anticipation_s ± 1 tick
	#    e direção do clique mantida mesmo com a câmera girada para outro alvo durante a antecipação.
	await _aim_settle(MaterialResponseSystem.body_center(target))
	var click_dir := (ab.aim_point(original.max_range + 10.0) - ab.hand_position()).normalized()
	var s0 := fire.get_stats()
	var m0: int = materials.get_stats().events
	var pid := _fire_press(ab, fire)
	var slot_at_click: bool = pid > 0 and fire.projectiles.size() == 1 and fire.projectiles[0].phase == "anticipation"
	for i in 8:
		_aim_at(MaterialResponseSystem.body_center(decoy))
	var events_before_launch := 0
	for i in 30:
		if fire.get_stats().launched != s0.launched:
			break
		events_before_launch = maxi(events_before_launch, materials.get_stats().events - m0)
		await get_tree().physics_frame
	events_before_launch = maxi(events_before_launch, materials.get_stats().events - m0)
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	await _frames(3)
	var shot := _fire_shot(watch, pid)
	var antic_s := -1.0
	var launch_dot := 0.0
	var temps_at_impact: Array = []
	if shot.has("fire_anticipation") and shot.has("fire_launch"):
		antic_s = _ticks_s(shot.fire_anticipation.tick, shot.fire_launch.tick)
		launch_dot = (shot.fire_launch.data.direction as Vector3).dot(click_dir)
	if shot.has("fire_impact"):
		temps_at_impact = shot.fire_impact.temps
	var s1 := fire.get_stats()
	var default_case := {"slot_at_click": slot_at_click, "anticipation_s": antic_s, "tuning_s": original.anticipation_s,
		"tolerance_s": dt, "heat_events_before_launch": events_before_launch, "launch_dir_dot_click_dir": launch_dot,
		"launches": s1.launched - s0.launched, "impacts": s1.exploded - s0.exploded,
		"heat_events_total": materials.get_stats().events - m0, "temps_at_impact": temps_at_impact,
		"raw_ticks": {"click": shot.get("fire_anticipation", {}).get("tick", -1), "launch": shot.get("fire_launch", {}).get("tick", -1),
			"impact": shot.get("fire_impact", {}).get("tick", -1)}}
	default_case["ok"] = slot_at_click and absf(antic_s - original.anticipation_s) <= dt + 0.000001 \
		and events_before_launch == 0 and launch_dot >= 0.999 and default_case.launches == 1 and default_case.impacts == 1 \
		and default_case.heat_events_total == 1 and temps_at_impact.size() == 3 \
		and float(temps_at_impact[0]) >= MaterialState.AMBIENT + 400.0 and is_equal_approx(float(temps_at_impact[1]), MaterialState.AMBIENT)
	# b) Trocar de elemento antes do voo cancela: nenhum lançamento, calor ou FX tardio.
	await _seconds(0.25)
	var c0 := fire.get_stats()
	var cm0: int = materials.get_stats().events
	var log_index: int = (watch.log as Array).size()
	var cancel_pid := _fire_press(ab, fire)
	await _frames(2)
	var still_pending: bool = fire.projectiles.size() == 1 and fire.projectiles[0].phase == "anticipation"
	var switched := ab.select(1)
	var removed_now := fire.projectiles.is_empty()
	await _seconds(0.4)
	var c1 := fire.get_stats()
	var cancel_case := {"pending_after_2_ticks": still_pending, "switched": switched, "removed_in_command": removed_now,
		"cancelled": c1.cancelled - c0.cancelled, "launches": c1.launched - c0.launched,
		"heat_events": materials.get_stats().events - cm0, "fx_after_click": _fire_kinds_since(watch, log_index)}
	cancel_case["ok"] = cancel_pid > 0 and still_pending and switched and removed_now and cancel_case.cancelled == 1 \
		and cancel_case.launches == 0 and cancel_case.heat_events == 0 and cancel_case.fx_after_click == ["fire_anticipation"]
	ab.select(2)
	# c) Projétil já lançado não é cancelado pela troca de elemento (compromisso após o voo).
	await _aim_settle(_ground_at(base + Vector3(-1.5, 0, -3.5)))
	await _seconds(0.2)
	var f0 := fire.get_stats()
	var flight_pid := _fire_press(ab, fire)
	await _wait_until(func(): return fire.get_stats().launched != f0.launched, 1.0)
	ab.select(1)
	var kept: bool = fire.projectiles.size() == 1 and fire.projectiles[0].phase == "flight"
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	var f1 := fire.get_stats()
	var flight_case := {"kept_after_switch": kept, "impacts": f1.exploded - f0.exploded, "cancelled": f1.cancelled - f0.cancelled}
	flight_case["ok"] = flight_pid > 0 and kept and flight_case.impacts == 1 and flight_case.cancelled == 0
	ab.select(2)
	# d) Recuperação: segundo clique no mesmo tick é recusado; o próximo aceito chega em cooldown_s ± 1 tick.
	await _seconds(0.3)
	# Timers do SceneTree disparam depois da física do tick; alinhar o clique ao início do tick
	# para contar (A − P) passos integrados entre o clique e o clique aceito.
	await get_tree().physics_frame
	var r0 := fire.get_stats()
	var first := _fire_press(ab, fire)
	var first_tick := Engine.get_physics_frames()
	var immediate := _fire_press(ab, fire)
	var accept_tick := -1
	for i in 40:
		await get_tree().physics_frame
		if _fire_press(ab, fire) > 0:
			accept_tick = Engine.get_physics_frames()
			break
	var recovery_s := float(accept_tick - first_tick) * dt if accept_tick >= 0 else -1.0
	var r1 := fire.get_stats()
	var recovery_case := {"immediate_rejected": immediate < 0, "recovery_s": recovery_s, "cooldown_s": original.cooldown_s,
		"rejected": r1.rejected - r0.rejected, "contract_max_s": 0.3}
	recovery_case["ok"] = first > 0 and immediate < 0 and recovery_s >= 0.0 \
		and absf(recovery_s - original.cooldown_s) <= dt + 0.000001 and recovery_s < 0.3
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	# e) Limite editável (3) e teto do pool (8) mesmo com o recurso pedindo 20; o VFX acompanha por slot.
	var limited: FireTuning = original.duplicate(true)
	limited.cooldown_s = 0.0
	limited.anticipation_s = 0.5
	limited.max_projectiles = 3
	fire.tuning = limited
	var l0 := fire.get_stats()
	for i in 5:
		_fire_press(ab, fire)
	var live_small := fire.projectiles.size()
	var rejected_small: int = fire.get_stats().rejected - l0.rejected
	ab.select(1)
	ab.select(2)
	limited.max_projectiles = 20
	var l1 := fire.get_stats()
	for i in 10:
		_fire_press(ab, fire)
	var live_cap := fire.projectiles.size()
	var rejected_cap: int = fire.get_stats().rejected - l1.rejected
	var missing0: int = fx.get_stats().fire_slots_missing
	await get_tree().process_frame
	await get_tree().process_frame
	var fxs := fx.get_stats()
	ab.select(1)
	ab.select(2)
	await get_tree().process_frame
	var fx_after := fx.get_stats()
	var limit_case := {"limit_3": {"live": live_small, "rejected": rejected_small},
		"limit_20_clamped": {"live": live_cap, "rejected": rejected_cap, "hard_cap": FireBurst.MAX_PROJECTILES},
		"fx_slots_live": fxs.fire_slots_live, "fx_balls_visible": fxs.fire_balls_visible,
		"fx_slots_missing": fxs.fire_slots_missing - missing0, "fx_slots_after_cancel": fx_after.fire_slots_live,
		"cancelled": fire.get_stats().cancelled - l0.cancelled}
	limit_case["ok"] = live_small == 3 and rejected_small == 2 and live_cap == FireBurst.MAX_PROJECTILES and rejected_cap == 2 \
		and fxs.fire_slots_live == FireBurst.MAX_PROJECTILES and fxs.fire_balls_visible == FireBurst.MAX_PROJECTILES \
		and limit_case.fx_slots_missing == 0 and fx_after.fire_slots_live == 0 and limit_case.cancelled == 11
	# f) Recurso variante: antecipação 0,2 s, 20 m/s e calor 120 mudam as medidas.
	var variant: FireTuning = original.duplicate(true)
	variant.anticipation_s = 0.2
	variant.speed = 20.0
	variant.heat = 120.0
	variant.turbulence_mps = 0.0
	fire.tuning = variant
	await _aim_settle(MaterialResponseSystem.body_center(tuned))
	var tuned_state := materials.state_of(tuned)
	var temp_before := tuned_state.temperature
	var vm0: int = materials.get_stats().events
	var vpid := _fire_press(ab, fire)
	await _wait_until(func(): return fire.projectiles.is_empty(), 3.0)
	var vshot := _fire_shot(watch, vpid)
	var v_antic := -1.0
	var flight_err := 999.0
	var temp_delta := -1.0
	var traveled := -1.0
	var straight := -1.0
	if vshot.has("fire_anticipation") and vshot.has("fire_launch") and vshot.has("fire_impact"):
		v_antic = _ticks_s(vshot.fire_anticipation.tick, vshot.fire_launch.tick)
		traveled = float(vshot.fire_impact.data.traveled)
		straight = (vshot.fire_impact.data.start as Vector3).distance_to(vshot.fire_impact.data.position)
		# Resto do tick de lançamento já voa; depois, um passo inteiro por tick até o contato.
		var flight_s := (v_antic - variant.anticipation_s) + float(int(vshot.fire_impact.tick) - int(vshot.fire_launch.tick)) * dt
		flight_err = absf(flight_s - traveled / variant.speed)
		temp_delta = float(vshot.fire_impact.temps[2]) - temp_before
	var tuning_case := {"anticipation_s": v_antic, "tuning_anticipation_s": variant.anticipation_s, "traveled_m": traveled,
		"straight_line_m": straight, "flight_time_error_s": flight_err, "temperature_delta": temp_delta,
		"tuning_heat": variant.heat, "heat_events": materials.get_stats().events - vm0, "burning": tuned_state.burning}
	tuning_case["ok"] = vpid > 0 and absf(v_antic - variant.anticipation_s) <= dt + 0.000001 and flight_err <= dt + 0.000001 \
		and absf(traveled - straight) <= 0.001 and absf(temp_delta - variant.heat) <= 0.01 \
		and tuning_case.heat_events == 1 and not tuned_state.burning
	fire.tuning = original
	# Capturas fora das janelas medidas: antecipação, voo e impacto com o recurso padrão.
	if _screens:
		await _aim_settle(MaterialResponseSystem.body_center(decoy))
		await _seconds(0.2)
		var cap0 := fire.get_stats()
		_fire_press(ab, fire)
		_capture_view(MaterialResponseSystem.body_center(decoy))
		await _snap("p36_fire_anticipation")
		await _wait_until(func(): return fire.get_stats().launched != cap0.launched, 1.0)
		await _snap("p36_fire_flight")
		await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
		await _snap("p36_fire_impact")
	_fire_unwatch(fire, watch)
	player.input_enabled = false
	var ok: bool = default_case.ok and cancel_case.ok and flight_case.ok and recovery_case.ok and limit_case.ok and tuning_case.ok
	_record("T49", "Fogo: antecipação sem calor e com mira do clique, cancelamento antes do voo, recuperação, limites e tuning", ok,
		{"default": default_case, "cancel_before_flight": cancel_case, "flight_survives_switch": flight_case,
		"recovery": recovery_case, "limits": limit_case, "variant": tuning_case,
		"method": "ticks de física pelo contexto do evento; tolerância 1 tick"})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


func _t50_fire_sweep_and_dissipation() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(2)
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	# a) Parede de 1 mm: cada disparo para na face, aquece uma vez e o lado de trás fica frio.
	#    Corpos adjacentes: a caixa encostada atrás do alvo não recebe calor através dele.
	var wall := _p36_thin_wall(base + Vector3(0, 0.8, -4), Vector3(3, 3, 0.001))
	var exposed := DebugProps.spawn_crate(props, base + Vector3(1.2, 0.8, -3.3))
	var behind := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -4.6))
	var front_adj := DebugProps.spawn_crate(props, base + Vector3(-3.2, 0.8, -6.0))
	var back_adj := DebugProps.spawn_crate(props, base + Vector3(-3.2, 0.8, -7.0))
	for c: RigidBody3D in [exposed, behind, front_adj, back_adj]:
		c.freeze = true
	await _frames(2)
	var watch := _fire_watch(fire, [exposed, behind, front_adj, back_adj])
	var face_z := wall.global_position.z + 0.0005
	var offsets: Array[Vector2] = [Vector2(-1.2, 0.5), Vector2(-0.8, -0.4), Vector2(-0.4, 0.2), Vector2(0.0, 0.0),
		Vector2(-0.2, -0.6), Vector2(0.1, 0.6)]
	var shots := []
	var wall_hits := 0
	var last_origin := Vector3.ZERO
	for o: Vector2 in offsets:
		await _aim_settle(wall.global_position + Vector3(o.x, o.y, 0.0))
		await _seconds(0.16)
		var s0 := fire.get_stats()
		var m0: int = materials.get_stats().events
		var pid := _fire_press(ab, fire)
		await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
		await _frames(3)
		var s1 := fire.get_stats()
		var impact: Dictionary = _fire_shot(watch, pid).get("fire_impact", {})
		var pos: Vector3 = impact.data.position if not impact.is_empty() else Vector3.INF
		var normal: Vector3 = impact.data.normal if not impact.is_empty() else Vector3.ZERO
		var on_face := not impact.is_empty() and absf(pos.z - face_z) <= 0.01 and absf(pos.x - wall.global_position.x) <= 1.5
		var entry := {"aim_offset": str(o), "impact": str(pos), "normal": str(normal), "on_wall_face": on_face,
			"impacts": s1.exploded - s0.exploded, "dissipations": s1.dissipated - s0.dissipated,
			"heat_events_after_3_ticks": materials.get_stats().events - m0, "ray_fallback_hits": s1.ray_fallback_hits - s0.ray_fallback_hits,
			"behind_temp_at_impact": impact.temps[1] if not impact.is_empty() else -1.0}
		entry["ok"] = pid > 0 and on_face and normal.z > 0.9 and entry.impacts == 1 and entry.dissipations == 0 \
			and entry.heat_events_after_3_ticks == 1 and is_equal_approx(float(entry.behind_temp_at_impact), MaterialState.AMBIENT)
		wall_hits += int(entry.ok)
		shots.append(entry)
		if not impact.is_empty():
			last_origin = pos + normal * 0.02
		if shots.size() == 1 and _screens:
			# Disparo extra só para a captura, já fora da medição desta amostra.
			await _seconds(0.16)
			_fire_press(ab, fire)
			_capture_view(wall.global_position, -30.0)
			await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
			await _snap("p36_fire_thin_wall")
	await _seconds(0.6)
	var exposed_state := materials.state_of(exposed)
	var behind_state := materials.state_of(behind)
	var wall_case := {"attempts": offsets.size(), "hits": wall_hits, "failures": offsets.size() - wall_hits, "shots": shots,
		"wall_thickness_m": 0.001, "exposed_temperature": exposed_state.temperature, "behind_temperature": behind_state.temperature,
		"los_exposed": materials.line_of_sight(last_origin, exposed), "los_behind": materials.line_of_sight(last_origin, behind)}
	wall_case["ok"] = wall_hits == offsets.size() and exposed_state.temperature > MaterialState.AMBIENT + 50.0 \
		and is_equal_approx(behind_state.temperature, MaterialState.AMBIENT) and wall_case.los_exposed and not wall_case.los_behind
	await _aim_settle(MaterialResponseSystem.body_center(front_adj))
	await _seconds(0.16)
	var a0 := fire.get_stats()
	var adj_pid := _fire_press(ab, fire)
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	var adj_impact: Dictionary = _fire_shot(watch, adj_pid).get("fire_impact", {})
	var adjacent_case := {"impacts": fire.get_stats().exploded - a0.exploded, "body_hits": fire.get_stats().body_hits - a0.body_hits,
		"front_temp_at_impact": adj_impact.temps[2] if not adj_impact.is_empty() else -1.0,
		"back_temp_at_impact": adj_impact.temps[3] if not adj_impact.is_empty() else -1.0}
	adjacent_case["ok"] = adj_pid > 0 and adjacent_case.impacts == 1 and adjacent_case.body_hits == 1 \
		and float(adjacent_case.front_temp_at_impact) >= MaterialState.AMBIENT + 400.0 \
		and is_equal_approx(float(adjacent_case.back_temp_at_impact), MaterialState.AMBIENT)
	_fire_unwatch(fire, watch)
	# b) Alcance: a face além de 30 m (~30,15 m) não é tocada porque o último segmento é recortado;
	#    a dissipação não aquece. Uma caixa com a face a ~29,4 m ainda recebe impacto.
	base = await _p3_lab(2)
	var hand := ab.hand_position()
	var pitch := deg_to_rad(10.0)
	var far_dir := Vector3(0, sin(pitch), -cos(pitch))
	var yaw := deg_to_rad(12.0)
	var near_dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)).normalized()
	var beyond := DebugProps.spawn_crate(props, hand + far_dir * (fire.tuning.max_range + 0.65))
	var within := DebugProps.spawn_crate(props, hand + near_dir * (fire.tuning.max_range - 0.1))
	beyond.freeze = true
	within.freeze = true
	await _frames(2)
	var range_watch := _fire_watch(fire, [beyond, within])
	await _aim_settle(MaterialResponseSystem.body_center(beyond))
	var aim_hit := ab.aim_any(fire.tuning.max_range + 10.0)
	var aims_beyond: bool = not aim_hit.is_empty() and aim_hit.collider == beyond
	var face_distance: float = ab.hand_position().distance_to(aim_hit.position) if aims_beyond else -1.0
	var d0 := fire.get_stats()
	var dm0: int = materials.get_stats().events
	var dpid := _fire_press(ab, fire)
	await _wait_until(func(): return fire.projectiles.is_empty(), 3.0)
	var dshot := _fire_shot(range_watch, dpid)
	if _screens and dshot.has("fire_dissipate"):
		_aim_at(dshot.fire_dissipate.data.position)
		await _snap("p36_fire_dissipate")
	var dissipate: Dictionary = dshot.get("fire_dissipate", {})
	var log_index: int = (range_watch.log as Array).size()
	await _seconds(0.5)
	var d1 := fire.get_stats()
	var beyond_state := materials.state_of(beyond)
	var end_traveled: float = float(dissipate.data.traveled) if not dissipate.is_empty() else -1.0
	var end_straight: float = (dissipate.data.start as Vector3).distance_to(dissipate.data.position) if not dissipate.is_empty() else -1.0
	var step := fire.tuning.speed * dt
	var dissipate_case := {"aims_beyond": aims_beyond, "face_distance_m": face_distance, "range_m": fire.tuning.max_range,
		"traveled_m": end_traveled, "straight_line_m": end_straight, "step_m": step,
		"dissipations": d1.dissipated - d0.dissipated, "impacts": d1.exploded - d0.exploded,
		"heat_events": materials.get_stats().events - dm0, "beyond_temperature": beyond_state.temperature,
		"queries": d1.queries - d0.queries, "max_queries": ceili(fire.tuning.max_range / step) + 1,
		"fx_after_dissipate": _fire_kinds_since(range_watch, log_index)}
	dissipate_case["ok"] = dpid > 0 and aims_beyond and face_distance > fire.tuning.max_range \
		and face_distance < fire.tuning.max_range + step and dissipate_case.dissipations == 1 and dissipate_case.impacts == 0 \
		and dissipate_case.heat_events == 0 and is_equal_approx(beyond_state.temperature, MaterialState.AMBIENT) \
		and absf(end_traveled - fire.tuning.max_range) <= 0.0001 and end_straight >= fire.tuning.max_range - 0.05 \
		and dissipate_case.queries <= dissipate_case.max_queries and (dissipate_case.fx_after_dissipate as Array).is_empty()
	await _aim_settle(MaterialResponseSystem.body_center(within))
	await _seconds(0.16)
	var w0 := fire.get_stats()
	var wpid := _fire_press(ab, fire)
	await _wait_until(func(): return fire.projectiles.is_empty(), 3.0)
	var wimpact: Dictionary = _fire_shot(range_watch, wpid).get("fire_impact", {})
	var w1 := fire.get_stats()
	var within_case := {"impacts": w1.exploded - w0.exploded, "body_hits": w1.body_hits - w0.body_hits,
		"traveled_m": float(wimpact.data.traveled) if not wimpact.is_empty() else -1.0,
		"temp_at_impact": wimpact.temps[1] if not wimpact.is_empty() else -1.0}
	within_case["ok"] = wpid > 0 and within_case.impacts == 1 and within_case.body_hits == 1 \
		and float(within_case.traveled_m) > fire.tuning.max_range - 1.5 and float(within_case.traveled_m) <= fire.tuning.max_range \
		and float(within_case.temp_at_impact) >= MaterialState.AMBIENT + 400.0
	_fire_unwatch(fire, range_watch)
	player.input_enabled = false
	_record("T50", "Fogo: varredura para em parede de 1 mm e corpo adjacente; calor único; alcance recortado dissipa sem calor remoto",
		wall_case.ok and adjacent_case.ok and dissipate_case.ok and within_case.ok,
		{"thin_wall": wall_case, "adjacent_bodies": adjacent_case, "range_dissipation": dissipate_case, "near_range_hit": within_case,
		"raycast_note": "amostra sem falhas não prova correção universal"})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


func _t51_fire_spread_visibility() -> void:
	var base: Vector3 = await _p3_lab(2)
	var fx: ElementalFx = main.fx
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	# a) Fonte em chamas com três vizinhos a 0,5 m de vão: aberto, atrás de parede de 1 mm e molhado;
	#    uma quarta caixa só aquecida (longe) mede o resfriamento.
	var source := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -6))
	var open := DebugProps.spawn_crate(props, base + Vector3(-1.5, 0.8, -6))
	var walled := DebugProps.spawn_crate(props, base + Vector3(1.5, 0.8, -6))
	var wet := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -7.5))
	var cool := DebugProps.spawn_crate(props, base + Vector3(5.5, 0.8, -6))
	_p36_thin_wall(base + Vector3(0.75, 0.8, -6), Vector3(0.001, 2.0, 3.0))
	for c: RigidBody3D in [source, open, walled, wet, cool]:
		c.freeze = true
	await _frames(2)
	var labels := {source.get_instance_id(): "source", open.get_instance_id(): "open",
		walled.get_instance_id(): "walled", wet.get_instance_id(): "wet", cool.get_instance_id(): "cool"}
	var ignitions := {}
	var start_frame := Engine.get_physics_frames()
	var on_ignite := func(body: Node3D) -> void:
		var label: String = labels.get(body.get_instance_id(), "other")
		var st: MaterialState = materials.state_of(body)
		if not ignitions.has(label) and st != null:
			ignitions[label] = {"t_s": float(Engine.get_physics_frames() - start_frame) * dt,
				"wetness": st.wetness, "temperature": st.temperature}
	materials.ignited.connect(on_ignite)
	_apply_direct(ElementalEvent.Kind.WET, wet, 0.6)
	var source_state := materials.state_of(source)
	var walled_state := materials.state_of(walled)
	var wet_state := materials.state_of(wet)
	var cool_state := materials.state_of(cool)
	var st0 := materials.get_stats()
	var fx0 := fx.get_stats()
	_apply_direct(ElementalEvent.Kind.HEAT, source, 400.0)
	_apply_direct(ElementalEvent.Kind.HEAT, cool, 100.0)
	var cool_start := cool_state.temperature
	var fuel0 := source_state.fuel
	var integrity0 := source_state.integrity
	var walled_max := walled_state.temperature
	var wet_dry_while_cold := true
	var cool_after_1s := -1.0
	var shot_spread := false
	for i in int(14.0 / dt):
		await get_tree().physics_frame
		walled_max = maxf(walled_max, walled_state.temperature)
		if not wet_state.burning and wet_state.wetness > 0.05 and wet_state.temperature > MaterialState.AMBIENT + 0.001:
			wet_dry_while_cold = false
		if i == int(1.0 / dt):
			cool_after_1s = cool_state.temperature
		if not shot_spread and ignitions.has("open"):
			shot_spread = true
			_capture_view(MaterialResponseSystem.body_center(source), -30.0)
			await _snap("p36_fire_spread_blocked")
		if source_state.charred and ignitions.has("wet") and ignitions.has("open") and cool_after_1s >= 0.0:
			break
	await _seconds(0.3)
	_capture_view(MaterialResponseSystem.body_center(source), -30.0)
	await _snap("p36_fire_charred")
	materials.ignited.disconnect(on_ignite)
	var st1 := materials.get_stats()
	var fx1 := fx.get_stats()
	var fuel_used := fuel0 - source_state.fuel
	var damage := integrity0 - source_state.integrity
	var ratio := damage / fuel_used if fuel_used > 0.0 else -1.0
	var wall_case := {"ignitions": ignitions, "walled_max_temperature": walled_max, "walled_burning": walled_state.burning,
		"spread_queries": st1.spread_queries - st0.spread_queries, "spread_blocked": st1.spread_blocked - st0.spread_blocked,
		"wet_dried_before_heating": wet_dry_while_cold, "fuel_used_s": fuel_used, "integrity_lost": damage,
		"damage_per_fuel": ratio, "material_burn_damage_per_s": source_state.material.burn_damage_per_second,
		"source_charred": source_state.charred, "fx_charred": fx1.charred - fx0.charred,
		"fx_flames_created": fx1.flames_created - fx0.flames_created,
		"cooling": {"start": cool_start, "after_1s": cool_after_1s, "rate_per_s": cool_state.material.cooling_per_second}}
	var expected_cool := cool_start - cool_state.material.cooling_per_second * 1.0
	var cool_tolerance := cool_state.material.cooling_per_second * maxf(materials.fire_tuning.thermal_tick_s, dt) + 0.001
	wall_case["ok"] = ignitions.has("source") and ignitions.has("open") and ignitions.has("wet") and not ignitions.has("walled") \
		and is_equal_approx(walled_max, MaterialState.AMBIENT) and wall_case.spread_blocked > 0 \
		and float(ignitions.get("wet", {}).get("wetness", 1.0)) < 0.05 \
		and float(ignitions.get("wet", {}).get("t_s", -1.0)) > float(ignitions.get("open", {}).get("t_s", 99.0)) and wet_dry_while_cold \
		and fuel_used > 0.0 and absf(ratio - source_state.material.burn_damage_per_second) <= 0.001 \
		and source_state.charred and wall_case.fx_charred >= 1 and not cool_state.burning \
		and absf(cool_after_1s - expected_cool) <= cool_tolerance
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()
	# b) Terreno também bloqueia; o raio de propagação do FireTuning é de fato usado (4 m alcança 3,2 m).
	base = await _p3_lab(2)
	var original: FireTuning = materials.fire_tuning
	var variant: FireTuning = original.duplicate(true)
	variant.spread_radius = 4.0
	var src := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -6))
	var hidden := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -9.2))
	var open_far := DebugProps.spawn_crate(props, base + Vector3(3.2, 0.8, -6))
	for c: RigidBody3D in [src, hidden, open_far]:
		c.freeze = true
	var mound := svc.add_sphere(base + Vector3(0, 0.8, -7.6), 0.9)
	var src_center := MaterialResponseSystem.body_center(src)
	var hidden_center := MaterialResponseSystem.body_center(hidden)
	var mound_up := await _wait_until(func(): return not svc.raycast_terrain(src_center, hidden_center).is_empty(), 3.0)
	await _frames(2)
	var los_hidden := materials.line_of_sight(src_center, hidden, src)
	var los_open := materials.line_of_sight(src_center, open_far, src)
	materials.fire_tuning = variant
	var hidden_state := materials.state_of(hidden)
	var open_state := materials.state_of(open_far)
	var tb0 := materials.get_stats()
	_apply_direct(ElementalEvent.Kind.HEAT, src, 400.0)
	var hidden_max := hidden_state.temperature
	for i in int(3.0 / dt):
		await get_tree().physics_frame
		hidden_max = maxf(hidden_max, hidden_state.temperature)
	var tb1 := materials.get_stats()
	materials.fire_tuning = original
	var terrain_case := {"mound": str(mound), "mound_collider": mound_up, "los_hidden": los_hidden, "los_open": los_open,
		"hidden_max_temperature": hidden_max, "open_temperature_3_2m": open_state.temperature,
		"spread_radius": variant.spread_radius, "spread_blocked": tb1.spread_blocked - tb0.spread_blocked}
	terrain_case["ok"] = mound.ok and mound_up and not los_hidden and los_open and is_equal_approx(hidden_max, MaterialState.AMBIENT) \
		and open_state.temperature > MaterialState.AMBIENT + 5.0 and terrain_case.spread_blocked > 0
	player.input_enabled = false
	_record("T51", "Propagação térmica respeita parede de 1 mm e terreno; mantém umidade, combustível, carbonização e resfriamento",
		wall_case.ok and terrain_case.ok, {"bodies_and_moisture": wall_case, "terrain_and_tuning": terrain_case})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


# --- Ciclo de vida: reset/save/load -------------------------------------------------------------

const LIFECYCLE_SLOT := "p36_lifecycle"


## Laboratório com um alvo a 12 m (voo de ~0,3 s) e mira nele.
func _lifecycle_lab() -> RigidBody3D:
	var base: Vector3 = await _p3_lab(2)
	var target := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -12))
	target.freeze = true
	await _frames(2)
	await _aim_settle(MaterialResponseSystem.body_center(target))
	return target


## Executa o comando e confere, no próprio sinal de início, que o controlador já descartou tudo.
func _lifecycle_command(kind: String, ab: AbilityController, fire: FireBurst, watch: Dictionary) -> Dictionary:
	var s0 := fire.get_stats()
	var m0: int = materials.get_stats().events
	var session0 := ab.session_id
	var live_before := fire.projectiles.size()
	var phases := []
	for p: Dictionary in fire.projectiles:
		phases.append(p.phase)
	var at_signal := {}
	var probe := func(_slot := "") -> void:
		at_signal["live"] = fire.projectiles.size()
		at_signal["session"] = ab.session_id
	var sig: Signal = svc.world_reset_started
	if kind == "save":
		sig = svc.world_save_started
	elif kind == "load":
		sig = svc.world_load_started
	sig.connect(probe)
	var log_index: int = (watch.log as Array).size()
	var command_ok := false
	if kind == "reset":
		command_ok = await main.request_world_reset()
	elif kind == "save":
		command_ok = await main.request_world_save(LIFECYCLE_SLOT)
	else:
		command_ok = await main.request_world_load(LIFECYCLE_SLOT)
	sig.disconnect(probe)
	await _seconds(0.6)
	var s1 := fire.get_stats()
	var out := {"command": kind, "command_ok": command_ok, "live_before": live_before, "phases_before": phases,
		"live_at_signal": at_signal.get("live", -1), "session_changed": int(at_signal.get("session", session0)) != session0,
		"launches_after": s1.launched - s0.launched, "impacts_after": s1.exploded - s0.exploded,
		"dissipations_after": s1.dissipated - s0.dissipated, "heat_events_after": materials.get_stats().events - m0,
		"fx_after_command": _fire_kinds_since(watch, log_index), "cooldown_left": s1.cooldown_left}
	out["ok"] = command_ok and live_before > 0 and out.live_at_signal == 0 and out.session_changed \
		and out.launches_after == 0 and out.impacts_after == 0 and out.dissipations_after == 0 \
		and out.heat_events_after == 0 and (out.fx_after_command as Array).is_empty() and is_zero_approx(float(out.cooldown_left))
	return out


func _t57_lifecycle_invalidation() -> void:
	var ab: AbilityController = main.abilities
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var watch := _fire_watch(fire, [])
	# Reset durante a antecipação.
	await _lifecycle_lab()
	_fire_press(ab, fire)
	var reset_case := await _lifecycle_command("reset", ab, fire, watch)
	# Save com projétil em voo: as caixas sobrevivem ao save, então um voo antigo as atingiria.
	var target: RigidBody3D = await _lifecycle_lab()
	var f0 := fire.get_stats()
	_fire_press(ab, fire)
	await _wait_until(func(): return fire.get_stats().launched != f0.launched, 1.0)
	var target_state := materials.state_of(target)
	var save_case := await _lifecycle_command("save", ab, fire, watch)
	save_case["target_survived"] = is_instance_valid(target)
	save_case["target_temperature"] = target_state.temperature if target_state != null else -1.0
	save_case.ok = save_case.ok and save_case.target_survived and is_equal_approx(float(save_case.target_temperature), MaterialState.AMBIENT)
	# Load com um voo e uma antecipação ao mesmo tempo.
	await _lifecycle_lab()
	var g0 := fire.get_stats()
	_fire_press(ab, fire)
	await _wait_until(func(): return fire.get_stats().launched != g0.launched, 1.0)
	await _wait_until(func(): return fire.get_stats().cooldown_left <= 0.0, 1.0)
	_fire_press(ab, fire)
	var load_case := await _lifecycle_command("load", ab, fire, watch)
	load_case.ok = load_case.ok and load_case.live_before == 2 and load_case.phases_before == ["flight", "anticipation"]
	_fire_unwatch(fire, watch)
	player.input_enabled = false
	_record("T57", "Reset/save/load descartam antecipações e voos no próprio comando, sem eventos térmicos ou FX tardios",
		reset_case.ok and save_case.ok and load_case.ok, {"reset_during_anticipation": reset_case,
		"save_during_flight": save_case, "load_flight_and_anticipation": load_case, "slot": LIFECYCLE_SLOT})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()
