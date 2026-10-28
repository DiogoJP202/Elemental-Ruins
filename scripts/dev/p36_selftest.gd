extends "res://scripts/dev/p35_selftest.gd"
## P3.6: regressões P0–P3.5 e cenários novos. --only=T46,T47,T48 limita a Água;
## --only=T49,T50,T51 limita o Fogo; --only=T52,T53,T54,T56 limita o Ar; T55/T58 integram os
## elementos e limites de VFX; T57 é o ciclo de vida (reset/save/load) de Fogo e Ar.
## P4A: T59 cobre manipulação de uma rocha e T60 input/cancelamentos contextuais.
## P4B: T61 reutiliza a mesma rocha e T62 cobre seleção, orçamento e cancelamentos.
## P4C: T63 cria/persiste um pilar real e T64 cobre recusas e cancelamentos do RMB.
## P4D: T65 escava uma fissura física/persistente e T66 cobre input, limites e cancelamentos.
## P4E: T67 manipula/lança o orbe; T68 verifica contato/material/oclusão; T69 seu ciclo de vida.
## P4F: T70 congela/controla/lança gelo; T71 verifica impacto e limpeza do estado congelado.
## P4G: T72 verifica gelo físico/orçamento; T73 cobre fusão por Fogo e limpeza da sessão.
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
	_log("--- testes P3.6 M3 (Ar) ---")
	if _should_run("T52"): await _t52_air_front_arrival()
	if _should_run("T53"): await _t53_air_mass_response()
	if _should_run("T54"): await _t54_air_occlusion_and_dust()
	if _should_run("T56"): await _t56_air_tuning_and_events()
	_log("--- testes P3.6 M4 (integração) ---")
	if _should_run("T55"): await _t55_cross_elements()
	if _should_run("T58"): await _t58_vfx_limits()
	_log("--- testes P3.6 ciclo de vida ---")
	if _should_run("T57"): await _t57_lifecycle_invalidation()
	_log("--- testes P4A (controle livre de Terra) ---")
	if _should_run("T59"): await _t59_earth_manipulation()
	if _should_run("T60"): await _t60_earth_input_lifecycle()
	_log("--- testes P4B (reutilizar rocha existente) ---")
	if _should_run("T61"): await _t61_earth_reuse()
	if _should_run("T62"): await _t62_earth_reuse_limits()
	_log("--- testes P4C (pilar de Terra) ---")
	if _should_run("T63"): await _t63_earth_pillar()
	if _should_run("T64"): await _t64_earth_pillar_guards()
	_log("--- testes P4D (fissura de Terra) ---")
	if _should_run("T65"): await _t65_earth_fissure()
	if _should_run("T66"): await _t66_earth_fissure_guards()
	_log("--- testes P4E (orbe de Água) ---")
	if _should_run("T67"): await _t67_water_orb_control()
	if _should_run("T68"): await _t68_water_orb_contact()
	if _should_run("T69"): await _t69_water_orb_lifecycle()
	if _should_run("T70"): await _t70_ice_control()
	if _should_run("T71"): await _t71_ice_contact_lifecycle()
	if _should_run("T72"): await _t72_persistent_ice_physics()
	if _should_run("T73"): await _t73_persistent_ice_heat_lifecycle()
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


# --- P4A: uma rocha, pelos mesmos inputs e pela mesma mola -------------------------------------

func _p4a_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _p4a_wheel(up: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	Input.parse_input_event(event)


func _t59_earth_manipulation() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var original: EarthTuning = earth.tuning
	var variant: EarthTuning = original.duplicate(true)
	variant.hold_min_height = 1.8
	variant.hold_max_height = 3.8
	variant.hold_height_speed = 3.0
	variant.min_range = 3.0
	variant.max_range = 6.5
	variant.hold_distance_step = 0.75
	earth.tuning = variant
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -4.5)))
	ab.use_pressed()
	var ready := await _wait_until(func(): return earth.phase == "hold", 2.0)
	if not ready:
		earth.tuning = original
		ab.cancel_all()
		player.input_enabled = false
		_record("T59", "Controle livre de Terra", false, {"reason": "hold_not_reached"})
		return
	var rock := earth.rock
	await _seconds(0.8)
	var start := EarthLiftThrow.center_of(rock)
	var radius0 := controller.radius
	var probe := {"previous": start, "teleport_m": 0.0, "measure": true}
	var dt := 1.0 / Engine.physics_ticks_per_second
	var sample_motion := func():
		var at := EarthLiftThrow.center_of(rock)
		if probe.measure:
			probe.teleport_m = maxf(probe.teleport_m, (at - (probe.previous as Vector3)).distance_to(rock.linear_velocity * dt))
		probe.previous = at
	var frame_ms := PackedFloat32Array()
	var clock := {"last": Time.get_ticks_usec()}
	var sample_frame := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - int(clock.last)) / 1000.0)
		clock.last = now
	get_tree().physics_frame.connect(sample_motion)
	get_tree().process_frame.connect(sample_frame)
	_p4a_key(KEY_E, true)
	await _frames(60)
	_p4a_key(KEY_E, false)
	var high := earth._hold_height
	var raised_m := EarthLiftThrow.center_of(rock).y - start.y
	# A comparação de integração mede o trecho livre; correção de contato com chão/parede é física legítima.
	probe.measure = false
	_p4a_key(KEY_Q, true)
	await _frames(60)
	_p4a_key(KEY_Q, false)
	var low := earth._hold_height
	var lowered_m := start.y + raised_m - EarthLiftThrow.center_of(rock).y
	_p4a_key(KEY_Q, true)
	_p4a_key(KEY_E, true)
	await _frames(12)
	var opposite_keys_neutral := is_equal_approx(earth._hold_height, low)
	_p4a_key(KEY_Q, false)
	await _frames(36)
	_p4a_key(KEY_E, false)
	await _frames(30)
	probe.measure = true
	var distance0 := earth._hold_dist
	_p4a_wheel(true)
	await _frames(2)
	var distance_step := distance0 - earth._hold_dist
	for i in 20: _p4a_wheel(true)
	await _frames(30)
	var near := earth._hold_dist
	for i in 20: _p4a_wheel(false)
	await _frames(45)
	var far := earth._hold_dist
	player.camera_rig.set_view(PI * 0.5, deg_to_rad(-20.0))
	await _frames(60)
	var horizontal_m := Vector2(EarthLiftThrow.center_of(rock).x - start.x, EarthLiftThrow.center_of(rock).z - start.z).length()
	player.camera_rig.set_view(0.0, deg_to_rad(-20.0))
	for i in 20: _p4a_wheel(true)
	await _frames(60)
	probe.measure = false
	var wall_distance := 5.0
	var wall := _p36_thin_wall(player.global_position + Vector3(0, 3, -wall_distance), Vector3(10, 10, 0.5))
	await _frames(2)
	for i in 20: _p4a_wheel(false)
	var farthest := 0.0
	for i in 75:
		await get_tree().physics_frame
		farthest = maxf(farthest, player.global_position.z - EarthLiftThrow.center_of(rock).z)
	var blocked := farthest < wall_distance and is_equal_approx(earth._hold_dist, variant.max_range)
	wall.queue_free()
	get_tree().physics_frame.disconnect(sample_motion)
	get_tree().process_frame.disconnect(sample_frame)
	if not frame_ms.is_empty(): frame_ms.remove_at(0)
	var timings := _stats(frame_ms)
	timings["p99"] = _percentile(frame_ms, 0.99)
	_metrics["p4a_hold_frame_ms"] = timings
	var windowed := not _mode.begins_with("headless")
	var performance_ok: bool = not windowed or (timings.get("p95", 999.0) <= 20.0 and timings.p99 <= 33.0 and timings.get("max", 999.0) <= 50.0)
	await _frames(2)
	var launches := []
	var watch_launch := func(kind, data):
		if kind == &"launch":
			launches.append({"speed": (data.velocity as Vector3).length(), "origin_error_m": (data.point as Vector3).distance_to(EarthLiftThrow.center_of(rock))})
	earth.fx_event.connect(watch_launch)
	var before_release := EarthLiftThrow.center_of(rock)
	ab.use_released()
	var no_release_teleport := before_release.distance_to(EarthLiftThrow.center_of(rock)) < 0.0001
	await _wait_until(func(): return not launches.is_empty(), 1.0)
	earth.fx_event.disconnect(watch_launch)
	var launched: bool = launches.size() == 1 and launches[0].speed >= 18.0 and launches[0].origin_error_m < 0.001
	var ok: bool = is_equal_approx(high, variant.hold_max_height) and is_equal_approx(low, variant.hold_min_height) \
		and raised_m > 0.7 and lowered_m > 0.7 and opposite_keys_neutral and horizontal_m > 2.0 \
		and is_equal_approx(distance_step, variant.hold_distance_step) and is_equal_approx(near, variant.min_range) \
		and is_equal_approx(far, variant.max_range) and is_equal_approx(controller.radius, radius0) \
		and float(probe.teleport_m) < 0.05 and blocked and launched and no_release_teleport and performance_ok
	earth.tuning = original
	ab.cancel_all()
	player.input_enabled = false
	_record("T59", "Q/E e roda reposicionam uma rocha por física, respeitam Resource e obstáculo e mantêm o arremesso", ok,
		{"height_min_max_m": [low, high], "raised_m": raised_m, "lowered_m": lowered_m,
		"opposite_keys_neutral": opposite_keys_neutral, "distance_min_max_m": [near, far], "wheel_step_m": distance_step,
		"horizontal_m": horizontal_m, "teleport_error_m": probe.teleport_m, "wall_distance_m": wall_distance,
		"farthest_rock_m": farthest, "wall_blocked": blocked, "brush_unchanged": is_equal_approx(controller.radius, radius0),
		"launches": launches, "release_without_teleport": no_release_teleport, "frame_ms": timings, "frame_gate_applied": windowed})
	await main.request_world_reset()


func _t60_earth_input_lifecycle() -> void:
	const SLOT := "p4a_lifecycle"
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var radius0 := controller.radius
	var outside := []
	# A roda continua no pincel em Terra ociosa e nos outros três elementos.
	for index in 4:
		_send_key(index)
		await _frames(1)
		var before := controller.radius
		_p4a_wheel(true)
		await _frames(1)
		outside.append(is_equal_approx(controller.radius, before + controller.radius_step))
		_p4a_wheel(false)
		await _frames(1)
	var slot_ready: bool = await main.request_world_save(SLOT)
	var cases := {}
	for kind: String in ["select", "reset", "save", "load"]:
		base = await _p3_lab(0)
		await _aim_settle(_ground_at(base + Vector3(0.17, 0, -4.5)))
		ab.use_pressed()
		var ready := await _wait_until(func(): return earth.phase == "hold", 2.0)
		if not ready:
			cases[kind] = {"ok": false, "reason": "hold_not_reached"}
			continue
		var old_ref: WeakRef = weakref(earth.rock)
		_p4a_key(KEY_E, true)
		_p4a_wheel(true)
		await _frames(8)
		var modified := earth._hold_height > earth.tuning.hold_height
		var at_signal := {}
		var probe := func(_slot := ""):
			at_signal["clean"] = earth.rock == null and earth.phase == "" and not ab.holding
		var sig: Signal = svc.world_reset_started
		if kind == "save": sig = svc.world_save_started
		elif kind == "load": sig = svc.world_load_started
		if kind != "select": sig.connect(probe)
		var thrown0: int = earth.get_stats().thrown
		var command_ok := true
		if kind == "select":
			_send_key(1)
			await _frames(1)
		elif kind == "reset": command_ok = await main.request_world_reset()
		elif kind == "save": command_ok = await main.request_world_save(SLOT)
		else: command_ok = await main.request_world_load(SLOT)
		if sig.is_connected(probe): sig.disconnect(probe)
		var height_after := earth._hold_height
		var distance_after := earth._hold_dist
		await _frames(12)
		var old_rock: RigidBody3D = old_ref.get_ref()
		var clean: bool = earth.rock == null and earth.phase == "" and not ab.holding \
			and earth.get_stats().thrown == thrown0 and is_equal_approx(earth._hold_height, height_after) \
			and is_equal_approx(earth._hold_dist, distance_after) \
			and (old_rock == null or (not old_rock.freeze and is_equal_approx(old_rock.gravity_scale, 1.0)))
		_p4a_key(KEY_E, false)
		# Um ciclo novo, com teclas liberadas, volta aos padrões em vez de herdar os offsets.
		await _prepare_area(base, AABB(LAB_P3 - Vector3(8, 4, 16), Vector3(16, 10, 30)))
		# Outra origem, fora da cavidade do ciclo anterior (salvar/selecionar a preservam).
		await _wait_until(func(): return not svc.raycast_terrain(base + Vector3(-4, 5, -4.5), base + Vector3(-4, -10, -4.5)).is_empty(), 5.0)
		ab.select(0)
		player.input_enabled = true
		await _aim_settle(_ground_at(base + Vector3(-4, 0, -4.5)))
		var expected := earth.validate_target()
		ab.use_pressed()
		var new_hold := await _wait_until(func(): return earth.phase == "hold", 2.0)
		var defaults: bool = new_hold and is_equal_approx(earth._hold_height, earth.tuning.hold_height) \
			and absf(earth._hold_dist - float(expected.get("dist", -1.0))) < 0.001
		cases[kind] = {"command_ok": command_ok, "modified_before": modified, "clean_after": clean,
			"clean_at_signal": at_signal.get("clean", kind == "select"), "new_hold_defaults": defaults,
			"new_target": expected, "new_phase": earth.phase, "new_result": earth.last_result,
			"new_height_m": earth._hold_height, "new_distance_m": earth._hold_dist,
			"ok": command_ok and modified and clean and defaults and bool(at_signal.get("clean", kind == "select"))}
		ab.cancel_all()
	_p4a_key(KEY_Q, false)
	_p4a_key(KEY_E, false)
	controller.radius = radius0
	player.input_enabled = false
	_record("T60", "Roda preserva pincel fora do hold; seleção/reset/save/load limpam manipulação sem comandos residuais",
		slot_ready and outside.all(func(passed): return passed) and cases.values().all(func(c): return c.ok),
		{"wheel_outside_hold_by_element": outside, "cases": cases, "slot": SLOT})
	await main.request_world_reset()


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


# --- M3: Ar ---------------------------------------------------------------------------------

## Registra os fx_event do ar com tick, sessão, id do evento e onda.
func _air_watch(gust: AirGust) -> Dictionary:
	var watch := {"log": [], "callback": Callable()}
	var log: Array = watch.log
	var cb := func(kind: StringName, data: Dictionary) -> void:
		log.append({"kind": String(kind), "tick": int(data.get("tick", -1)), "session": int(data.get("session_id", -1)),
			"event_id": int(data.get("event_id", -1)), "wave": int(data.get("wave_id", -1)), "data": data.duplicate()})
	gust.fx_event.connect(cb)
	watch.callback = cb
	return watch


func _air_unwatch(gust: AirGust, watch: Dictionary) -> void:
	if gust.fx_event.is_connected(watch.callback):
		gust.fx_event.disconnect(watch.callback)


func _air_contacts(watch: Dictionary, wave: int) -> Array:
	var out := []
	for e: Dictionary in watch.log:
		if e.kind == "air_contact" and int(e.wave) == wave:
			out.append(e)
	return out


## Contato da onda `wave` com o corpo (pelo id da instância registrado no evento).
func _air_contact_for(watch: Dictionary, wave: int, body: Node3D) -> Dictionary:
	for e: Dictionary in _air_contacts(watch, wave):
		if int(e.data.get("body_id", -1)) == body.get_instance_id():
			return e
	return {}


## Caixa flutuante sem gravidade, amortecimento ou colisões: a velocidade medida é só a do ar.
func _air_crate(at: Vector3, mass := DebugProps.CRATE_MASS) -> RigidBody3D:
	var body := DebugProps.spawn_crate(props, at)
	body.mass = mass
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	body.collision_mask = 0
	return body


## Toque único; id da onda criada ou -1 se recusada (recuperação ou limite).
func _air_press(ab: AbilityController, gust: AirGust) -> int:
	var before: int = gust.get_stats().gusts
	ab.use_pressed()
	ab.use_released()
	if gust.get_stats().gusts == before or gust.waves.is_empty():
		return -1
	return int(gust.waves[gust.waves.size() - 1].id)


## Mira num ponto e dispara uma onda no início do tick (o clique precede a física desse tick).
func _air_fire_at(ab: AbilityController, gust: AirGust, point: Vector3) -> Dictionary:
	await _aim_settle(point)
	var press_tick := Engine.get_physics_frames()
	var wave := _air_press(ab, gust)
	return {"wave": wave, "press_tick": press_tick}


func _t52_air_front_arrival() -> void:
	var ab: AbilityController = main.abilities
	await _p3_lab(3)
	var gust: AirGust = ab.get_ability(&"air_gust")
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var hand := ab.hand_position()
	var crates: Array[RigidBody3D] = [_air_crate(hand + Vector3(0, 0, -3)), _air_crate(hand + Vector3(2.0, 0, -6)),
		_air_crate(hand + Vector3(-2.6, 0, -9))]
	await _frames(2)
	var watch := _air_watch(gust)
	var shot := await _air_fire_at(ab, gust, hand + Vector3(0, 0, -8))
	var first_motion := [-1, -1, -1]
	for i in 60:
		for k in crates.size():
			if first_motion[k] < 0 and crates[k].linear_velocity.length() > 0.0:
				first_motion[k] = Engine.get_physics_frames()
		if gust.waves.is_empty():
			break
		await get_tree().physics_frame
	await _frames(2)
	var cases := []
	var all_ok: bool = shot.wave > 0
	for k in crates.size():
		var contact := _air_contact_for(watch, shot.wave, crates[k])
		var d: float = float(contact.data.distance) if not contact.is_empty() else -1.0
		var arrival := _ticks_s(shot.press_tick, contact.tick) if not contact.is_empty() else -1.0
		var expected := d / gust.tuning.front_speed
		# A velocidade aparece no início do tick seguinte ao impulso (a física integra depois do callback).
		var motion_s := float(int(first_motion[k]) - int(shot.press_tick)) * dt if int(first_motion[k]) >= 0 else -1.0
		var entry := {"distance_m": d, "arrival_s": arrival, "expected_s": expected, "deadline_s": expected + 2.0 * dt,
			"first_motion_s": motion_s}
		entry["ok"] = not contact.is_empty() and arrival >= expected - 0.000001 and arrival <= expected + 2.0 * dt + 0.000001 \
			and motion_s >= arrival - 0.000001
		all_ok = all_ok and entry.ok
		cases.append(entry)
	var contacts := _air_contacts(watch, shot.wave).size()
	if _screens:
		await _air_fire_at(ab, gust, hand + Vector3(0, 0, -8))
		_capture_view(hand + Vector3(0, 0, -6), 30.0)
		await _frames(4)
		await _snap("p36_air_front_mid")
		await _wait_until(func(): return gust.waves.is_empty(), 1.0)
		await _snap("p36_air_after_front")
	_air_unwatch(gust, watch)
	player.input_enabled = false
	_record("T52", "Ar: frente progressiva; nenhum efeito antes da casca; chegada em d/v + 2 ticks", all_ok and contacts == crates.size(),
		{"front_speed": gust.tuning.front_speed, "crates": cases, "contacts_in_wave": contacts,
		"method": "ticks de física; distância ao centro do corpo"})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


func _t53_air_mass_response() -> void:
	var ab: AbilityController = main.abilities
	await _p3_lab(3)
	var gust: AirGust = ab.get_ability(&"air_gust")
	var hand := ab.hand_position()
	var masses := [20.0, 200.0, 2000.0]
	var crates: Array[RigidBody3D] = []
	for k in masses.size():
		var ang := deg_to_rad(-20.0 + 20.0 * k)
		crates.append(_air_crate(hand + Vector3(sin(ang), 0, -cos(ang)) * 5.0, masses[k]))
	await _frames(2)
	var watch := _air_watch(gust)
	var events0: int = materials.get_stats().events
	var s0 := gust.get_stats()
	var shot := await _air_fire_at(ab, gust, hand + Vector3(0, 0, -8))
	await _wait_until(func(): return gust.waves.is_empty(), 1.0)
	await _frames(2)
	var cases := []
	var all_ok: bool = shot.wave > 0
	for body in crates:
		var contact := _air_contact_for(watch, shot.wave, body)
		var strength: float = float(contact.data.strength) if not contact.is_empty() else 0.0
		var exposure: float = float(contact.data.exposure) if not contact.is_empty() else 0.0
		var expected_dv := minf(gust.tuning.max_delta_v, gust.tuning.impulse_cap / body.mass) * strength * exposure
		var dv := body.linear_velocity.length()
		var entry := {"mass_kg": body.mass, "strength": strength, "exposure": exposure,
			"impulse_Ns": float(contact.data.impulse) if not contact.is_empty() else -1.0,
			"expected_dv": expected_dv, "measured_dv": dv, "cap_dv": gust.tuning.max_delta_v * strength,
			"cap_impulse_Ns": gust.tuning.impulse_cap}
		entry["ok"] = not contact.is_empty() and exposure >= 0.999 and absf(dv - expected_dv) <= expected_dv * 0.02 + 0.0001 \
			and dv <= gust.tuning.max_delta_v * strength + 0.001
		all_ok = all_ok and entry.ok
		cases.append(entry)
	var s1 := gust.get_stats()
	var contacts := _air_contacts(watch, shot.wave).size()
	var once := {"contacts": contacts, "bodies": crates.size(), "airflow_events": materials.get_stats().events - events0,
		"stats_contacts": s1.contacts - s0.contacts}
	once["ok"] = contacts == crates.size() and once.airflow_events == crates.size() and once.stats_contacts == crates.size()
	var light_over_mid: float = float(cases[0].measured_dv) / maxf(float(cases[1].measured_dv), 0.0001)
	var mid_over_heavy: float = float(cases[1].measured_dv) / maxf(float(cases[2].measured_dv), 0.0001)
	if _screens:
		_capture_view(hand + Vector3(0, 0, -5), 30.0)
		await _snap("p36_air_mass_response")
	_air_unwatch(gust, watch)
	player.input_enabled = false
	_record("T53", "Ar: mesma pressão respeita teto de Δv e de impulso; resposta inversa à massa; um contato por corpo por onda",
		all_ok and once.ok and light_over_mid > 1.5 and mid_over_heavy > 9.0,
		{"bodies": cases, "once_per_wave": once, "ratios": {"light_over_mid": light_over_mid, "mid_over_heavy": mid_over_heavy}})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


func _t54_air_occlusion_and_dust() -> void:
	var ab: AbilityController = main.abilities
	var gust: AirGust = ab.get_ability(&"air_gust")
	var fx: ElementalFx = main.fx
	# a) Parede de 1 mm cobrindo a caixa inteira: exposição zero, nenhum impulso nem AIRFLOW.
	await _p3_lab(3)
	var hand := ab.hand_position()
	_p36_thin_wall(hand + Vector3(0, 0, -4.0), Vector3(3, 3, 0.001))
	var hidden := _air_crate(hand + Vector3(0, 0, -4.8))
	await _frames(2)
	var watch := _air_watch(gust)
	var e0: int = materials.get_stats().events
	var b0 := gust.get_stats()
	var fx0 := fx.get_stats()
	var shot_a := await _air_fire_at(ab, gust, hand + Vector3(0, 0, -8))
	await _wait_until(func(): return gust.waves.is_empty(), 1.0)
	await _frames(2)
	var b1 := gust.get_stats()
	var wall_case := {"velocity": hidden.linear_velocity.length(), "blocked": b1.blocked - b0.blocked,
		"airflow_events": materials.get_stats().events - e0, "contacts": _air_contacts(watch, shot_a.wave).size(),
		"exposure_rays": b1.exposure_rays - b0.exposure_rays, "ray_fallback_hits": b1.ray_fallback_hits - b0.ray_fallback_hits,
		"dust_contacts": fx.get_stats().air_dust_contacts - fx0.air_dust_contacts}
	wall_case["ok"] = shot_a.wave > 0 and is_zero_approx(float(wall_case.velocity)) and wall_case.blocked == 1 \
		and wall_case.airflow_events == 0 and wall_case.contacts == 0 and wall_case.dust_contacts == 0
	# b) Exposição parcial: a borda da parede cobre só o ponto esquerdo da silhueta (4/5 livres);
	#    a gêmea simétrica, sem parede, recebe a frente inteira na mesma distância.
	await _p3_lab(3)
	hand = ab.hand_position()
	var partial := _air_crate(hand + Vector3(2.5, 0, -6.0))
	var twin := _air_crate(hand + Vector3(-2.5, 0, -6.0))
	_p36_thin_wall(hand + Vector3(0.43, 0, -5.0), Vector3(3, 3, 0.001))
	await _frames(2)
	var p0 := gust.get_stats()
	var dust0: int = fx.get_stats().air_dust_contacts
	var shot_b := await _air_fire_at(ab, gust, hand + Vector3(0, 0, -8))
	await _wait_until(func(): return gust.waves.is_empty(), 1.0)
	await _frames(2)
	var pc := _air_contact_for(watch, shot_b.wave, partial)
	var tc := _air_contact_for(watch, shot_b.wave, twin)
	var p_dv := partial.linear_velocity.length()
	var t_dv := twin.linear_velocity.length()
	var partial_case := {"partial_exposure": float(pc.data.exposure) if not pc.is_empty() else -1.0,
		"twin_exposure": float(tc.data.exposure) if not tc.is_empty() else -1.0, "partial_dv": p_dv, "twin_dv": t_dv,
		"ratio": p_dv / maxf(t_dv, 0.0001), "stats_partial": gust.get_stats().partial - p0.partial,
		"dust_contacts": fx.get_stats().air_dust_contacts - dust0, "contacts": _air_contacts(watch, shot_b.wave).size()}
	partial_case["ok"] = shot_b.wave > 0 and is_equal_approx(float(partial_case.partial_exposure), 0.8) \
		and is_equal_approx(float(partial_case.twin_exposure), 1.0) and absf(float(partial_case.ratio) - 0.8) <= 0.02 \
		and partial_case.stats_partial == 1 and partial_case.contacts == 2 and partial_case.dust_contacts == partial_case.contacts
	if _screens:
		_capture_view(hand + Vector3(0, 0, -6), -25.0)
		await _snap("p36_air_partial_exposure")
	# c) Terreno: morro entre a mão e a caixa bloqueia todas as amostras.
	await _p3_lab(3)
	hand = ab.hand_position()
	var behind := _air_crate(hand + Vector3(0, -0.3, -7.0))
	var mound := svc.add_sphere(hand + Vector3(0, -0.6, -3.8), 1.4)
	var behind_center := MaterialResponseSystem.body_center(behind)
	var mound_up := await _wait_until(func(): return not svc.raycast_terrain(hand, behind_center).is_empty(), 3.0)
	await _frames(2)
	var t0 := gust.get_stats()
	var te0: int = materials.get_stats().events
	var shot_c := await _air_fire_at(ab, gust, hand + Vector3(0, 0, -8))
	await _wait_until(func(): return gust.waves.is_empty(), 1.0)
	await _frames(2)
	var terrain_case := {"mound": str(mound), "mound_collider": mound_up, "velocity": behind.linear_velocity.length(),
		"blocked": gust.get_stats().blocked - t0.blocked, "airflow_events": materials.get_stats().events - te0}
	terrain_case["ok"] = mound.ok and mound_up and shot_c.wave > 0 and is_zero_approx(float(terrain_case.velocity)) \
		and terrain_case.blocked == 1 and terrain_case.airflow_events == 0
	# d) Poeira de passagem: no máximo uma por espaçamento por onda, e o pool de anéis volta a zero.
	var fx1 := fx.get_stats()
	var max_front_dust := 3 * ceili(gust.tuning.max_range / gust.tuning.dust_spacing_m)
	var dust_case := {"front_dust": fx1.air_dust_front - fx0.air_dust_front, "max_front_dust": max_front_dust,
		"rings_live_after": fx1.air_rings_live, "rings_missing": fx1.air_rings_missing - fx0.air_rings_missing,
		"contact_dust_total": fx1.air_dust_contacts - fx0.air_dust_contacts}
	dust_case["ok"] = dust_case.front_dust > 0 and dust_case.front_dust <= max_front_dust and dust_case.rings_live_after == 0 \
		and dust_case.rings_missing == 0
	_air_unwatch(gust, watch)
	player.input_enabled = false
	_record("T54", "Ar: parede de 1 mm e terreno bloqueiam; exposição parcial reduz o impulso; poeira só de contatos e passagem reais",
		wall_case.ok and partial_case.ok and terrain_case.ok and dust_case.ok,
		{"thin_wall": wall_case, "partial": partial_case, "terrain": terrain_case, "dust": dust_case,
		"raycast_note": "amostra sem falhas não prova correção universal"})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


func _t56_air_tuning_and_events() -> void:
	var ab: AbilityController = main.abilities
	await _p3_lab(3)
	var gust: AirGust = ab.get_ability(&"air_gust")
	var original: AirTuning = gust.tuning
	var variant: AirTuning = original.duplicate(true)
	variant.front_speed = 15.0
	variant.max_range = 6.0
	variant.impulse_cap = 300.0
	variant.max_waves = 2
	variant.cooldown_s = 0.0
	gust.tuning = variant
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var hand := ab.hand_position()
	var near := _air_crate(hand + Vector3(0.6, 0, -4.0), 200.0)
	var far := _air_crate(hand + Vector3(-1.2, 0, -7.0))
	await _frames(2)
	var watch := _air_watch(gust)
	var shot := await _air_fire_at(ab, gust, hand + Vector3(0, 0, -8))
	await _wait_until(func(): return gust.waves.is_empty(), 1.5)
	await _frames(2)
	var contact := _air_contact_for(watch, shot.wave, near)
	var arrival := _ticks_s(shot.press_tick, contact.tick) if not contact.is_empty() else -1.0
	var d: float = float(contact.data.distance) if not contact.is_empty() else -1.0
	var strength: float = float(contact.data.strength) if not contact.is_empty() else 0.0
	var expected_dv := minf(variant.max_delta_v, variant.impulse_cap / near.mass) * strength
	var tuning_case := {"arrival_s": arrival, "expected_s": d / variant.front_speed, "near_dv": near.linear_velocity.length(),
		"expected_dv": expected_dv, "far_velocity_beyond_range": far.linear_velocity.length(), "range_m": variant.max_range}
	tuning_case["ok"] = shot.wave > 0 and not contact.is_empty() and arrival >= d / variant.front_speed - 0.000001 \
		and arrival <= d / variant.front_speed + 2.0 * dt + 0.000001 \
		and absf(float(tuning_case.near_dv) - expected_dv) <= expected_dv * 0.02 + 0.0001 \
		and is_zero_approx(float(tuning_case.far_velocity_beyond_range))
	# Limite de ondas simultâneas e recusa contabilizada.
	await _aim_settle(hand + Vector3(0, 0, -8))
	var r0 := gust.get_stats()
	var accepted := 0
	for i in 3:
		accepted += int(_air_press(ab, gust) > 0)
	var limit_case := {"accepted": accepted, "live": gust.waves.size(), "rejected": gust.get_stats().rejected - r0.rejected,
		"max_waves": variant.max_waves}
	limit_case["ok"] = accepted == 2 and limit_case.live == 2 and limit_case.rejected == 1
	await _wait_until(func(): return gust.waves.is_empty(), 1.5)
	gust.tuning = original
	# Recuperação padrão: segundo toque no mesmo tick é recusado; aceito em cooldown_s ± 1 tick.
	await get_tree().physics_frame
	var first := _air_press(ab, gust)
	var first_tick := Engine.get_physics_frames()
	var immediate := _air_press(ab, gust)
	var accept_tick := -1
	for i in 40:
		await get_tree().physics_frame
		if _air_press(ab, gust) > 0:
			accept_tick = Engine.get_physics_frames()
			break
	var recovery_s := float(accept_tick - first_tick) * dt if accept_tick >= 0 else -1.0
	var recovery_case := {"immediate_rejected": immediate < 0, "recovery_s": recovery_s, "cooldown_s": original.cooldown_s}
	recovery_case["ok"] = first > 0 and immediate < 0 and absf(recovery_s - original.cooldown_s) <= dt + 0.000001
	await _wait_until(func(): return gust.waves.is_empty(), 1.5)
	# Eventos identificáveis: ids únicos e crescentes, sessão atual, onda, tick e habilidade em todos.
	var ids := []
	var kinds := {}
	var fields_ok := true
	for e: Dictionary in watch.log:
		ids.append(e.event_id)
		kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
		fields_ok = fields_ok and e.event_id > 0 and e.session == ab.session_id and e.wave > 0 and e.tick > 0 \
			and e.data.get("ability", &"") == &"air_gust"
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	var unique := {}
	for i in ids:
		unique[i] = true
	var events_case := {"events": ids.size(), "kinds": kinds, "fields_ok": fields_ok,
		"unique": unique.size() == ids.size(), "increasing": sorted_ids == ids}
	events_case["ok"] = ids.size() > 0 and fields_ok and events_case.unique and events_case.increasing
	_air_unwatch(gust, watch)
	player.input_enabled = false
	_record("T56", "Ar: AirTuning muda velocidade, alcance e teto; limite de ondas e recuperação; eventos identificáveis",
		tuning_case.ok and limit_case.ok and recovery_case.ok and events_case.ok,
		{"variant": tuning_case, "wave_limit": limit_case, "recovery": recovery_case, "events": events_case})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


# --- M4: integração ---------------------------------------------------------------------------

func _has_flame(body: Node3D) -> bool:
	for ch in body.get_children():
		if ch is GPUParticles3D:
			return true
	return false


## Interações cruzadas com as mecânicas novas, todas pelo caminho do jogador (seleção + LMB).
func _t55_cross_elements() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(2)
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var gust: AirGust = ab.get_ability(&"air_gust")
	var fx: ElementalFx = main.fx
	var steps := {}
	# Corpos auxiliares fora do cone das rajadas anteriores (ângulo > 35° em relação à caixa principal).
	var crate := DebugProps.spawn_crate(props, base + Vector3(0, 0, -6))
	var hot := DebugProps.spawn_crate(props, base + Vector3(-4.5, 0, -4.5))
	var damp := DebugProps.spawn_crate(props, base + Vector3(4.5, 0, -4.5))
	await _seconds(0.8)
	_apply_direct(ElementalEvent.Kind.WET, crate, 0.6)
	_apply_direct(ElementalEvent.Kind.WET, damp, 0.5)
	var cs := materials.state_of(crate)
	var ds := materials.state_of(damp)
	# 1) Fogo × umidade: a 1ª rajada seca (vapor no impacto) sem acender; a 2ª acende.
	var fx0 := fx.get_stats()
	await _tap_at(MaterialResponseSystem.body_center(crate))
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	var wet_after_1 := cs.wetness
	var lit_1 := cs.burning
	var steam_fire: int = fx.get_stats().fire_steam - fx0.fire_steam
	await _seconds(0.2)
	await _tap_at(MaterialResponseSystem.body_center(crate))
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	steps["1_fogo_seca_e_acende"] = {"umidade_apos_1a": wet_after_1, "acesa_apos_1a": lit_1, "vapor_do_fogo": steam_fire,
		"acesa_apos_2a": cs.burning, "ok": wet_after_1 < 0.6 and not lit_1 and steam_fire >= 1 and cs.burning}
	# 2) Ar × fogo forte: a frente empurra o corpo em chamas, aviva e a chama segue presa ao corpo.
	await _seconds(0.6)
	_send_key(3)
	await get_tree().physics_frame
	var p0 := crate.global_position
	var i0 := cs.intensity
	var hits: Array = []
	await _tap_at(MaterialResponseSystem.body_center(crate))
	hits = gust.last_gust.get("hit", [])
	await _wait_until(func(): return hits.has(crate) or gust.waves.is_empty(), 1.0)
	var i1 := cs.intensity
	await _wait_until(func(): return gust.waves.is_empty(), 1.0)
	await _seconds(0.6)
	steps["2_ar_empurra_e_aviva"] = {"intensidade_antes": i0, "intensidade_no_contato": i1, "deslocada_m": crate.global_position.distance_to(p0),
		"segue_acesa": cs.burning, "chama_no_corpo": _has_flame(crate),
		"ok": hits.has(crate) and i1 >= i0 + 0.05 and crate.global_position.distance_to(p0) > 1.0 and cs.burning and _has_flame(crate)}
	# 3) Água × fogo: o jato apaga (causa água, vapor).
	_send_key(1)
	await get_tree().physics_frame
	var causes := []
	var cb := func(body, cause):
		if body == crate:
			causes.append(cause)
	materials.extinguished.connect(cb)
	var steam0: int = fx.get_stats().steam
	await _hold_on(crate, 4.0, func(): return not cs.burning)
	materials.extinguished.disconnect(cb)
	var wet_after_water := cs.wetness
	steps["3_agua_apaga"] = {"apagada": not cs.burning, "causas": causes, "vapor": fx.get_stats().steam - steam0,
		"umidade": wet_after_water, "ok": not cs.burning and causes == ["água"] and fx.get_stats().steam - steam0 >= 1}
	# 4) Água × calor: corpo quente (sem chama) esfria com o jato.
	_apply_direct(ElementalEvent.Kind.HEAT, hot, 200.0)
	var hs := materials.state_of(hot)
	var t0 := hs.temperature
	await _hold_on(hot, 0.8)
	steps["4_agua_esfria"] = {"temperatura_antes": t0, "temperatura_depois": hs.temperature, "acesa": hs.burning,
		"ok": not hs.burning and hs.temperature < t0 - 20.0}
	# 5) Ar × umidade: a frente seca um pouco o corpo molhado (AIRFLOW).
	await _seconds(0.4)
	_send_key(3)
	await get_tree().physics_frame
	var w0 := ds.wetness
	await _tap_at(MaterialResponseSystem.body_center(damp))
	var hits2: Array = gust.last_gust.get("hit", [])
	await _wait_until(func(): return gust.waves.is_empty(), 1.0)
	steps["5_ar_seca"] = {"umidade_antes": w0, "umidade_depois": ds.wetness, "na_rajada": hits2.has(damp),
		"ok": w0 > 0.0 and hits2.has(damp) and ds.wetness < w0}
	player.input_enabled = false
	_record("T55", "Interações cruzadas: fogo seca e acende, ar empurra e aviva em chamas, água apaga e esfria, ar seca",
		steps.values().all(func(s): return s.ok), steps)
	if _screens:
		await _shot("p36_cross_elements", player.global_position, 0.0, -12.0, false)
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


## Limites de VFX sob estresse e ausência de vazamento de nós no ElementalFx.
func _t58_vfx_limits() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(2)
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var gust: AirGust = ab.get_ability(&"air_gust")
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var fx: ElementalFx = main.fx
	var fx_children := fx.get_child_count()
	# a) 30 corpos em chamas: no máximo 24 emissores; os excedentes queimam sem chama e são contados.
	var crates: Array[RigidBody3D] = []
	for i in 30:
		var c := DebugProps.spawn_crate(props, base + Vector3(-7.5 + (i % 6) * 1.6, 0.8, -12.0 - floorf(i / 6.0) * 1.6))
		c.freeze = true
		crates.append(c)
	await _frames(2)
	var s0 := fx.get_stats()
	for c in crates:
		_apply_direct(ElementalEvent.Kind.HEAT, c, 400.0)
	await get_tree().process_frame
	var s1 := fx.get_stats()
	var flames := {"burning": materials.burning_count(), "flames_active": s1.flames_active,
		"skipped": s1.flames_skipped - s0.flames_skipped, "cap": mini(ElementalFx.MAX_FLAMES, fire.tuning.max_flame_emitters)}
	flames["ok"] = flames.burning >= 30 and flames.flames_active <= flames.cap and flames.skipped >= 30 - flames.cap
	# b) 8 projéteis + 4 frentes + jato no mesmo intervalo; amostra por quadro.
	var fire_original: FireTuning = fire.tuning
	var air_original: AirTuning = gust.tuning
	var fire_variant: FireTuning = fire_original.duplicate(true)
	fire_variant.cooldown_s = 0.0
	fire_variant.anticipation_s = 0.0
	fire.tuning = fire_variant
	var air_variant: AirTuning = air_original.duplicate(true)
	air_variant.cooldown_s = 0.0
	gust.tuning = air_variant
	await _aim_settle(base + Vector3(0, 1.0, -10))
	for i in 10:
		ab.use_pressed()
		ab.use_released()
	# Um tick para emitir: trocar de elemento cancela o que ainda estiver em antecipação.
	await get_tree().physics_frame
	_send_key(3)
	await get_tree().physics_frame
	for i in 6:
		ab.use_pressed()
		ab.use_released()
	_send_key(1)
	await get_tree().physics_frame
	ab.use_pressed()
	var peak := {"fire_balls": 0, "fire_slots": 0, "air_rings": 0, "water_instances": 0, "fire_live": 0, "air_live": 0}
	var frame_ms := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in 30:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		var st := fx.get_stats()
		peak.fire_balls = maxi(peak.fire_balls, st.fire_balls_visible)
		peak.fire_slots = maxi(peak.fire_slots, st.fire_slots_live)
		peak.air_rings = maxi(peak.air_rings, st.air_rings_live)
		peak.water_instances = maxi(peak.water_instances, st.water_instances)
		peak.fire_live = maxi(peak.fire_live, fire.projectiles.size())
		peak.air_live = maxi(peak.air_live, gust.waves.size())
	if _screens:
		await _snap("p36_vfx_stress")
	ab.use_released()
	fire.tuning = fire_original
	gust.tuning = air_original
	await _wait_until(func(): return fire.projectiles.is_empty() and gust.waves.is_empty(), 2.0)
	await get_tree().process_frame
	var s2 := fx.get_stats()
	var stress := {"peak": peak, "caps": {"fire": FireBurst.MAX_PROJECTILES, "air": AirGust.MAX_WAVES, "water": 24},
		"missing_slots": {"fire": s2.fire_slots_missing - s0.fire_slots_missing, "air": s2.air_rings_missing - s0.air_rings_missing},
		"frame_ms": _stats(frame_ms), "note": "amostra informativa; o gate de quadro é o T27/T37"}
	stress["ok"] = peak.fire_live == FireBurst.MAX_PROJECTILES and peak.fire_balls <= FireBurst.MAX_PROJECTILES \
		and peak.air_live == AirGust.MAX_WAVES and peak.air_rings <= AirGust.MAX_WAVES and peak.water_instances <= 24 \
		and peak.water_instances > 0 and stress.missing_slots.fire == 0 and stress.missing_slots.air == 0
	# c) Sem vazamento: o ElementalFx mantém só os pools; depois do reset, nenhuma chama nem slot ativo.
	await main.request_world_reset()
	# Chamas de corpos removidos saem da lista na verificação periódica (CHAR_CHECK_S = 0,25 s).
	await _seconds(0.4)
	var s3 := fx.get_stats()
	var leak := {"fx_children_before": fx_children, "fx_children_after": fx.get_child_count(), "flames_active": s3.flames_active,
		"fire_slots": s3.fire_slots_live, "air_rings": s3.air_rings_live, "burning": materials.burning_count()}
	leak["ok"] = leak.fx_children_after == fx_children and leak.flames_active == 0 and leak.fire_slots == 0 \
		and leak.air_rings == 0 and leak.burning == 0
	player.input_enabled = false
	_record("T58", "VFX limitados sob estresse (24 chamas, 8 projéteis, 4 frentes, 24 volumes de água) e sem vazamento após reset",
		flames.ok and stress.ok and leak.ok, {"flames": flames, "stress": stress, "no_leak": leak})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


# --- Ciclo de vida: reset/save/load -------------------------------------------------------------

const LIFECYCLE_SLOT := "p36_lifecycle"


## Laboratório com o Fogo, um alvo congelado a 12 m (voo de ~0,3 s) e mira nele.
func _lifecycle_lab() -> RigidBody3D:
	var base: Vector3 = await _p3_lab(2)
	var target := DebugProps.spawn_crate(props, base + Vector3(0, 0.8, -12))
	target.freeze = true
	await _frames(2)
	await _aim_settle(MaterialResponseSystem.body_center(target))
	return target


## Executa o comando e confere, no próprio sinal de início, que o controlador já descartou projéteis
## de fogo e frentes de ar, sem eventos de material, contatos ou FX depois.
func _lifecycle_command(kind: String, ab: AbilityController, watch: Dictionary, air_watch: Dictionary) -> Dictionary:
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var gust: AirGust = ab.get_ability(&"air_gust")
	var s0 := fire.get_stats()
	var a0 := gust.get_stats()
	var m0: int = materials.get_stats().events
	var session0 := ab.session_id
	var live_before := fire.projectiles.size() + gust.waves.size()
	var phases := []
	for p: Dictionary in fire.projectiles:
		phases.append(p.phase)
	for w: Dictionary in gust.waves:
		phases.append("air_front")
	var at_signal := {}
	var probe := func(_slot := "") -> void:
		at_signal["live"] = fire.projectiles.size() + gust.waves.size()
		at_signal["session"] = ab.session_id
	var sig: Signal = svc.world_reset_started
	if kind == "save":
		sig = svc.world_save_started
	elif kind == "load":
		sig = svc.world_load_started
	sig.connect(probe)
	var fire_index: int = (watch.log as Array).size()
	var air_index: int = (air_watch.log as Array).size()
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
	var a1 := gust.get_stats()
	var out := {"command": kind, "command_ok": command_ok, "live_before": live_before, "phases_before": phases,
		"live_at_signal": at_signal.get("live", -1), "session_changed": int(at_signal.get("session", session0)) != session0,
		"launches_after": s1.launched - s0.launched, "impacts_after": s1.exploded - s0.exploded,
		"dissipations_after": s1.dissipated - s0.dissipated, "air_contacts_after": a1.contacts - a0.contacts,
		"material_events_after": materials.get_stats().events - m0,
		"fx_after_command": _fire_kinds_since(watch, fire_index) + _fire_kinds_since(air_watch, air_index),
		"cooldown_left": s1.cooldown_left + a1.cooldown_left}
	out["ok"] = command_ok and live_before > 0 and out.live_at_signal == 0 and out.session_changed \
		and out.launches_after == 0 and out.impacts_after == 0 and out.dissipations_after == 0 and out.air_contacts_after == 0 \
		and out.material_events_after == 0 and (out.fx_after_command as Array).is_empty() and is_zero_approx(float(out.cooldown_left))
	return out


func _t57_lifecycle_invalidation() -> void:
	var ab: AbilityController = main.abilities
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var gust: AirGust = ab.get_ability(&"air_gust")
	var watch := _fire_watch(fire, [])
	var air_watch := _air_watch(gust)
	var cases := {}
	# Fogo: reset durante a antecipação.
	await _lifecycle_lab()
	_fire_press(ab, fire)
	cases["fire_reset_during_anticipation"] = await _lifecycle_command("reset", ab, watch, air_watch)
	# Fogo: save com projétil em voo; as caixas sobrevivem ao save, então um voo antigo as atingiria.
	var target: RigidBody3D = await _lifecycle_lab()
	var f0 := fire.get_stats()
	_fire_press(ab, fire)
	await _wait_until(func(): return fire.get_stats().launched != f0.launched, 1.0)
	var target_state := materials.state_of(target)
	var save_case := await _lifecycle_command("save", ab, watch, air_watch)
	save_case["target_survived"] = is_instance_valid(target)
	save_case["target_temperature"] = target_state.temperature if target_state != null else -1.0
	save_case.ok = save_case.ok and save_case.target_survived and is_equal_approx(float(save_case.target_temperature), MaterialState.AMBIENT)
	cases["fire_save_during_flight"] = save_case
	# Fogo: load com um voo e uma antecipação ao mesmo tempo.
	await _lifecycle_lab()
	var g0 := fire.get_stats()
	_fire_press(ab, fire)
	await _wait_until(func(): return fire.get_stats().launched != g0.launched, 1.0)
	await _wait_until(func(): return fire.get_stats().cooldown_left <= 0.0, 1.0)
	_fire_press(ab, fire)
	var load_case := await _lifecycle_command("load", ab, watch, air_watch)
	load_case.ok = load_case.ok and load_case.live_before == 2 and load_case.phases_before == ["flight", "anticipation"]
	cases["fire_load_flight_and_anticipation"] = load_case
	# Ar: o comando chega com a frente ainda antes da caixa a 8 m (que sobrevive ao save).
	for kind: String in ["reset", "save", "load"]:
		var base: Vector3 = await _p3_lab(3)
		var crate := _air_crate(base + Vector3(0, 1.3, -8))
		await _frames(2)
		await _aim_settle(MaterialResponseSystem.body_center(crate))
		var wave := _air_press(ab, gust)
		var air_case := await _lifecycle_command(kind, ab, watch, air_watch)
		air_case["wave"] = wave
		air_case.ok = air_case.ok and wave > 0 and air_case.phases_before == ["air_front"]
		if kind == "save":
			air_case["crate_survived"] = is_instance_valid(crate)
			air_case["crate_velocity"] = crate.linear_velocity.length() if is_instance_valid(crate) else -1.0
			air_case.ok = air_case.ok and air_case.crate_survived and is_zero_approx(float(air_case.crate_velocity))
		cases["air_%s_during_front" % kind] = air_case
	_fire_unwatch(fire, watch)
	_air_unwatch(gust, air_watch)
	player.input_enabled = false
	_record("T57", "Reset/save/load descartam antecipações, voos e frentes de ar no próprio comando, sem eventos ou FX tardios",
		cases.values().all(func(c): return c.ok), {"cases": cases, "slot": LIFECYCLE_SLOT})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


# --- P4B: capturar o mesmo corpo, inclusive durante seu voo ------------------------------------

func _p4b_lmb(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	# Despachar o mouse antes das amostras imediatas, sem avançar um tick de física.
	Input.flush_buffered_events()


## Fixture real: o TerrainService extrai a rocha pelo fluxo já testado; cancelar a deixa solta.
func _p4b_free_rock(base: Vector3) -> RigidBody3D:
	var ab: AbilityController = main.abilities
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -4.5)))
	ab.use_pressed()
	if not await _wait_until(func(): return earth.phase == "hold", 2.0):
		ab.cancel_all()
		return null
	await _frames(30)
	var body := earth.rock
	ab.cancel_all()
	return body


func _t61_earth_reuse() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var original: EarthTuning = earth.tuning
	var variant: EarthTuning = original.duplicate(true)
	# Uma janela de recaptura reproduzível, sem mudar velocidade de arremesso ou mover a rocha.
	variant.recovery_s = 0.0
	earth.tuning = variant
	var body: RigidBody3D = await _p4b_free_rock(base)
	if body == null:
		earth.tuning = original
		player.input_enabled = false
		_record("T61", "Reutilização de rocha", false, {"reason": "fixture_not_extracted"})
		return
	await _aim_settle(EarthLiftThrow.center_of(body))
	var revision := svc.get_revision()
	var bodies := props.get_child_count()
	var mass := body.mass
	var instance := body.get_instance_id()
	var reused0: int = earth.get_stats().reused
	var extracted0: int = earth.get_stats().extracted
	var before := EarthLiftThrow.center_of(body)
	var velocity := body.linear_velocity
	_p4b_lmb(true)
	var captured: bool = earth.rock == body and earth.phase == "hold" and body.get_instance_id() == instance
	var untouched: bool = before.distance_to(EarthLiftThrow.center_of(body)) < 0.0001 \
		and velocity.distance_to(body.linear_velocity) < 0.0001 and is_equal_approx(body.mass, mass)
	var probe := {"previous": EarthLiftThrow.center_of(body), "teleport_m": 0.0}
	var dt := 1.0 / Engine.physics_ticks_per_second
	var motion := func():
		var at := EarthLiftThrow.center_of(body)
		probe.teleport_m = maxf(probe.teleport_m, (at - (probe.previous as Vector3)).distance_to(body.linear_velocity * dt))
		probe.previous = at
	var frame_ms := PackedFloat32Array()
	var clock := {"last": Time.get_ticks_usec()}
	var sample_frame := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - int(clock.last)) / 1000.0)
		clock.last = now
	get_tree().physics_frame.connect(motion)
	get_tree().process_frame.connect(sample_frame)
	var h0 := earth._hold_height
	var d0 := earth._hold_dist
	_p4a_key(KEY_E, true)
	_p4a_wheel(true)
	await _frames(18)
	_p4a_key(KEY_E, false)
	var controls: bool = earth._hold_height > h0 + 0.3 and is_equal_approx(d0 - earth._hold_dist, variant.hold_distance_step)
	await _frames(45)
	var physical_move := EarthLiftThrow.center_of(body).distance_to(before)
	get_tree().physics_frame.disconnect(motion)
	var no_edit: bool = svc.get_revision() == revision and props.get_child_count() == bodies and earth.get_stats().extracted == extracted0
	player.camera_rig.set_view(0.0, deg_to_rad(10.0))
	_p4b_lmb(false)
	var thrown := await _wait_until(func(): return earth.phase == "", 1.0)
	var flight_speed := body.linear_velocity.length()
	var first_connections := body.get_signal_connection_list(&"body_entered").size()
	# Resolver a mira no mesmo tick permite pegar a rocha a 24 m/s antes de ela sair do alcance.
	for i in 8: _aim_at(EarthLiftThrow.center_of(body))
	var flight_point := EarthLiftThrow.center_of(body)
	var flight_velocity := body.linear_velocity
	_p4b_lmb(true)
	var recaptured: bool = thrown and flight_speed > 18.0 and earth.rock == body and earth.phase == "hold" \
		and flight_point.distance_to(EarthLiftThrow.center_of(body)) < 0.0001 \
		and flight_velocity.distance_to(body.linear_velocity) < 0.0001
	var stale_removed: bool = first_connections == 1 and body.get_signal_connection_list(&"body_entered").is_empty() and not body.contact_monitor
	var crate := DebugProps.spawn_crate(props, base + Vector3(0, 0, -14))
	await _frames(30)
	var c0 := crate.global_position
	await _aim_settle(MaterialResponseSystem.body_center(crate))
	var hits0: int = earth.get_stats().hits
	_p4b_lmb(false)
	var hit_observed := await _wait_until(func(): return earth.get_stats().hits > hits0, 2.0)
	await _frames(45)
	var hits_delta: int = earth.get_stats().hits - hits0
	var crate_displacement := crate.global_position.distance_to(c0)
	var hit_once: bool = hits_delta == 1 and crate_displacement > 0.5
	var remaining_callbacks := body.get_signal_connection_list(&"body_entered").size()
	var contact_monitor_after := body.contact_monitor
	var remaining_flights := earth._thrown.size()
	get_tree().process_frame.disconnect(sample_frame)
	if not frame_ms.is_empty(): frame_ms.remove_at(0)
	var timings := _stats(frame_ms)
	timings["p99"] = _percentile(frame_ms, 0.99)
	_metrics["p4b_reuse_frame_ms"] = timings
	var windowed := not _mode.begins_with("headless")
	var perf_ok: bool = not windowed or (timings.get("p95", 999.0) <= 20.0 and timings.p99 <= 33.0 and timings.get("max", 999.0) <= 50.0)
	var reused_twice: bool = earth.get_stats().reused - reused0 == 2 and is_equal_approx(body.mass, mass)
	ab.cancel_all()
	var clean_callbacks := body.get_signal_connection_list(&"body_entered").is_empty()
	earth.tuning = original
	player.input_enabled = false
	_record("T61", "Mesma rocha e massa: captura por LMB, controles físicos, recaptura em voo e novo impacto sem callbacks duplicados",
		captured and untouched and controls and physical_move > 0.1 and float(probe.teleport_m) < 0.05 \
		and no_edit and recaptured and stale_removed and hit_once and reused_twice and clean_callbacks and perf_ok,
		{"same_body": captured, "capture_without_position_velocity_reset": untouched, "mass_kg": mass,
		"controls": controls, "moved_m": physical_move, "teleport_error_m": probe.teleport_m, "no_terrain_edit_or_new_body": no_edit,
		"flight_speed_m_s": flight_speed, "recaptured_in_flight": recaptured, "previous_flight_disconnected": stale_removed,
		"one_new_impact": hit_once, "reused_twice": reused_twice, "callbacks_clean": clean_callbacks,
		"hit_observed_within_timeout": hit_observed, "hits_delta": hits_delta, "crate_displacement_m": crate_displacement,
		"remaining_callbacks": remaining_callbacks, "contact_monitor_after_impact": contact_monitor_after,
		"remaining_flights": remaining_flights,
		"frame_ms": timings, "frame_gate_applied": windowed})
	await main.request_world_reset()


func _t62_earth_reuse_limits() -> void:
	const SLOT := "p4b_lifecycle"
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var body: RigidBody3D = await _p4b_free_rock(base)
	if body == null:
		player.input_enabled = false
		_record("T62", "Limites e ciclo da reutilização", false, {"reason": "fixture_not_extracted"})
		return
	# Uma rocha estacionada pelo orçamento continua capturável, mas não deve ser reestacionada no hold.
	body.freeze = true
	body.set_meta(DebrisBudget.PARKED_META, "budget")
	var cases := {}
	var reject := func(name: String):
		var rev := svc.get_revision()
		var reused: int = earth.get_stats().reused
		var check := earth.validate_target()
		_p4b_lmb(true)
		await _frames(2)
		_p4b_lmb(false)
		cases[name] = {"reason": check.reason, "ok": not check.ok and earth.rock == null and earth.phase == "" \
			and svc.get_revision() == rev and earth.get_stats().reused == reused}
	var wall := _p36_thin_wall(base + Vector3(0, 2, -2), Vector3(6, 5, 0.2))
	await _frames(2)
	await _aim_settle(EarthLiftThrow.center_of(body))
	await reject.call("wall_occlusion")
	wall.queue_free()
	await _frames(2)
	var crate := DebugProps.spawn_crate(props, base + Vector3(0, 1.5, -2))
	crate.freeze = true
	await _aim_settle(MaterialResponseSystem.body_center(crate))
	await reject.call("crate_not_earth")
	crate.queue_free()
	await _frames(2)
	player.teleport_to(base + Vector3(0, 9, 0))
	await _aim_settle(EarthLiftThrow.center_of(body))
	var out_of_range: bool = EarthLiftThrow.center_of(body).distance_to(player.global_position) > earth.tuning.max_range
	await reject.call("distance_3d")
	cases.distance_3d.ok = cases.distance_3d.ok and out_of_range
	player.teleport_to(base + Vector3(0, 0.5, -2.8))
	await _aim_settle(EarthLiftThrow.center_of(body))
	var budget: DebrisBudget = main.debris
	var active0 := budget.max_active
	budget.max_active = 0
	_p4b_lmb(true)
	var awakened: bool = earth.rock == body and not body.freeze and not body.has_meta(DebrisBudget.PARKED_META)
	var minimum: bool = is_equal_approx(earth._hold_dist, earth.tuning.min_range)
	await _frames(120)
	var protected: bool = not body.freeze and body.has_meta(DebrisBudget.EARTH_HELD_META)
	budget.max_active = active0
	ab.cancel_all()
	cases["near_parked_rock"] = {"awakened": awakened, "minimum_distance": minimum, "budget_protected": protected,
		"ok": awakened and minimum and protected and not body.has_meta(DebrisBudget.EARTH_HELD_META) and is_equal_approx(body.gravity_scale, 1.0)}
	await _go_to_tower()
	var foot: StructurePiece = _foot_at(Vector2(-1, 1))
	player.teleport_to(foot.global_position + Vector3(0, 0.5, 5))
	await _aim_settle(MaterialResponseSystem.body_center(foot))
	await reject.call("tower_not_earth")
	base = await _p3_lab(0)
	var slot_ready: bool = await main.request_world_save(SLOT)
	for kind: String in ["select", "reset", "save", "load"]:
		base = await _p3_lab(0)
		body = await _p4b_free_rock(base)
		if body == null:
			cases[kind] = {"ok": false, "reason": "fixture_not_extracted"}
			continue
		await _aim_settle(EarthLiftThrow.center_of(body))
		_p4b_lmb(true)
		var owned: bool = earth.rock == body and body.has_meta(DebrisBudget.EARTH_HELD_META)
		var old_ref: WeakRef = weakref(body)
		_p4a_key(KEY_E, true)
		_p4a_wheel(true)
		await _frames(6)
		var thrown0: int = earth.get_stats().thrown
		var command_ok := true
		if kind == "select": _send_key(1)
		elif kind == "reset": command_ok = await main.request_world_reset()
		elif kind == "save": command_ok = await main.request_world_save(SLOT)
		else: command_ok = await main.request_world_load(SLOT)
		_p4b_lmb(false)
		var h := earth._hold_height
		var d := earth._hold_dist
		await _frames(12)
		var old: RigidBody3D = old_ref.get_ref()
		var released: bool = old == null or (not old.has_meta(DebrisBudget.EARTH_HELD_META) \
			and not old.freeze and is_equal_approx(old.gravity_scale, 1.0) and old.get_signal_connection_list(&"body_entered").is_empty())
		cases[kind] = {"owned_before": owned, "released_after": released,
			"ok": owned and command_ok and released and earth.rock == null and earth.phase == "" and not ab.holding \
			and earth.get_stats().thrown == thrown0 and is_equal_approx(h, earth._hold_height) and is_equal_approx(d, earth._hold_dist)}
		_p4a_key(KEY_E, false)
		ab.cancel_all()
	player.input_enabled = false
	_record("T62", "Reutilização respeita oclusão/tipo/alcance; acorda rocha estacionada e limpa propriedade em seleção/reset/save/load",
		slot_ready and cases.values().all(func(c): return c.ok), cases)
	await main.request_world_reset()


# --- P4C: PATH real pelo RMB, sem uma segunda implementação de terreno ---------------------

func _p4c_rmb(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _t63_earth_pillar() -> void:
	const SLOT := "p4c_pillar"
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var point := _ground_at(base + Vector3(0.17, 0, -5.0))
	await _aim_settle(point)
	var check := earth.validate_pillar_target()
	if not check.ok:
		player.input_enabled = false
		_record("T63", "Pilar de Terra por RMB", false, {"reason": check.reason})
		return
	point = check.point
	var edits: Array[Dictionary] = []
	var cb := func(req: TerrainBrushRequest, result: TerrainEditResult):
		if req.source == "ability:earth_pillar":
			edits.append({"request": req, "ok": result.ok, "reason": result.reason})
	queue.brush_applied.connect(cb)
	var revision := svc.get_revision()
	var extracted: int = earth.get_stats().extracted
	var frame_ms := PackedFloat32Array()
	var clock := {"last": Time.get_ticks_usec()}
	var sample_frame := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - int(clock.last)) / 1000.0)
		clock.last = now
	get_tree().process_frame.connect(sample_frame)
	_p4c_rmb(true)
	await _frames(12)
	_p4b_lmb(true)
	_p4b_lmb(false)
	var preview: bool = earth.pillar_aiming and svc.get_revision() == revision and edits.is_empty() \
		and queue.pending_count() == 0 and earth.get_stats().extracted == extracted and earth.rock == null
	_p4c_rmb(false)
	var confirmed: bool = await _wait_until(func(): return edits.size() == 1, 5.0)
	var req: TerrainBrushRequest = edits[0].request if confirmed else null
	var radius := earth.tuning.pillar_radius
	var height := earth.tuning.pillar_height
	var geometry: bool = req != null and req.op == TerrainBrushRequest.Op.PATH and req.additive \
		and req.points.size() == 2 and req.radii.size() == 2 \
		and req.points[0].distance_to(point - Vector3.UP * radius) < 0.01 \
		and req.points[1].distance_to(point + Vector3.UP * (height - radius)) < 0.01 \
		and is_equal_approx(req.radii[0], radius) and is_equal_approx(req.radii[1], radius)
	var top := await _wait_ray(point + Vector3.UP * (height + 5.0), point + Vector3.DOWN * 3.0,
		func(h): return not h.is_empty() and absf(h.position.y - point.y - height) < 0.5, 5.0)
	if not confirmed or not geometry or not top.ok:
		queue.brush_applied.disconnect(cb)
		get_tree().process_frame.disconnect(sample_frame)
		player.input_enabled = false
		_record("T63", "Pilar de Terra por RMB", false,
			{"confirmed": confirmed, "geometry": geometry, "collider": top.ok, "preview": preview})
		await main.request_world_reset()
		return
	var top_y := _hit_y(top.hit)
	var crate := DebugProps.spawn_crate(props, Vector3(point.x, top_y + 3.0, point.z))
	# Mesmo assentamento do T4; a caixa de 1 m tem forma/origem centradas no corpo.
	await _seconds(3.0)
	var crate_y := crate.global_position.y
	var crate_speed := crate.linear_velocity.length()
	var crate_offset := Vector2(crate.global_position.x - point.x, crate.global_position.z - point.z).length()
	var crate_support: bool = crate_y > top_y and crate_speed < 0.3
	crate.queue_free()
	await _frames(2)
	player.teleport_to(Vector3(point.x, top_y + 2.0, point.z))
	await _seconds(1.5)
	var player_support: bool = player.is_on_floor() and player.global_position.y > top_y - 0.5
	_p4c_rmb(false)
	await _frames(2)
	var once: bool = edits.size() == 1 and svc.get_revision() == revision + 1
	queue.brush_applied.disconnect(cb)
	get_tree().process_frame.disconnect(sample_frame)
	if not frame_ms.is_empty(): frame_ms.remove_at(0)
	var timings := _stats(frame_ms)
	timings["p99"] = _percentile(frame_ms, 0.99)
	_metrics["p4c_pillar_frame_ms"] = timings
	var perf_ok: bool = _mode.begins_with("headless") or (timings.get("p95", 999.0) <= 20.0 \
		and timings.p99 <= 33.0 and timings.get("max", 999.0) <= 50.0)
	var samples := PackedVector3Array([point + Vector3.UP, point + Vector3.UP * (height * 0.5),
		point + Vector3.UP * (height - 0.7)])
	var snapshot := func():
		var sdf := []
		var material := []
		for p: Vector3 in samples:
			sdf.append(svc.sample_sdf(p))
			material.append(svc.sample_material_index(p))
		return {"sdf": sdf, "material": material}
	var saved: Dictionary = snapshot.call()
	var save_ok: bool = await main.request_world_save(SLOT)
	var after_save: Dictionary = snapshot.call()
	var reset_ok: bool = await main.request_world_reset()
	await _prepare_area(base, AABB(point - Vector3(3, 4, 3), Vector3(6, height + 8, 6)))
	var reset_top := await _wait_ray(point + Vector3.UP * (height + 5.0), point + Vector3.DOWN * 3.0,
		func(h): return not h.is_empty() and h.position.y < point.y + 0.5, 5.0)
	var load_ok: bool = await main.request_world_load(SLOT)
	await _prepare_area(base, AABB(point - Vector3(3, 4, 3), Vector3(6, height + 8, 6)))
	var loaded_top := await _wait_ray(point + Vector3.UP * (height + 5.0), point + Vector3.DOWN * 3.0,
		func(h): return not h.is_empty() and absf(h.position.y - top_y) < PROBE_TOLERANCE, 5.0)
	var loaded: Dictionary = snapshot.call()
	var persistence: bool = save_ok and reset_ok and reset_top.ok and load_ok and loaded_top.ok \
		and saved == after_save and saved.material == loaded.material
	for i in samples.size():
		persistence = persistence and float(saved.sdf[i]) < 0.0 \
			and absf(float(saved.sdf[i]) - float(loaded.sdf[i])) < SDF_TOLERANCE
	player.input_enabled = false
	_record("T63", "RMB confirma um PATH+ vertical sólido; caixa/jogador apoiam e save/reset/load preservam o pilar",
		preview and edits[0].ok and once and crate_support and player_support and persistence and perf_ok,
		{"preview_without_edit": preview, "single_path": once, "geometry": geometry, "collider_ms": top.ms,
		"top_y": top_y, "crate_supported": crate_support, "player_supported": player_support,
		"crate_y_after_3s": crate_y, "crate_speed_m_s": crate_speed, "crate_horizontal_offset_m": crate_offset,
		"saved": saved, "loaded": loaded, "persistence": persistence, "frame_ms": timings})
	await main.request_world_reset()


func _t64_earth_pillar_guards() -> void:
	const SLOT := "p4c_cancel"
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var original := earth.tuning
	var point := _ground_at(base + Vector3(0.17, 0, -5.0))
	var cases := {}
	var reject := func(name: String):
		var check := earth.validate_pillar_target()
		var rev := svc.get_revision()
		var n := _brush_log.size()
		_p4c_rmb(true)
		await _frames(2)
		_p4c_rmb(false)
		await _frames(3)
		cases[name] = {"reason": check.reason, "ok": not check.ok and svc.get_revision() == rev \
			and _brush_log.size() == n and queue.pending_count() == 0 and not earth.pillar_aiming and earth.rock == null}
	player.camera_rig.set_view(0.0, deg_to_rad(45.0))
	await _frames(2)
	await reject.call("no_ground")
	await _aim_settle(_ground_at(base + Vector3(0, 0, -earth.tuning.pillar_range - 3.0)))
	await reject.call("out_of_range")
	await _aim_settle(_ground_at(base + Vector3(0, 0, -1.0)))
	await reject.call("minimum_range")
	var wall := _p36_thin_wall(base + Vector3(0, 2, -2), Vector3(6, 5, 0.2))
	await _frames(2)
	await _aim_settle(point)
	await reject.call("wall_occlusion")
	wall.queue_free()
	await _frames(2)
	var crate := DebugProps.spawn_crate(props, point + Vector3.UP * 0.6)
	crate.freeze = true
	await _frames(2)
	await _aim_settle(MaterialResponseSystem.body_center(crate))
	await reject.call("prop_not_ground")
	crate.queue_free()
	await _frames(2)
	var roof := _p36_thin_wall(point + Vector3.UP * 3.0, Vector3(3, 0.3, 3))
	await _frames(2)
	await _aim_settle(point)
	await reject.call("future_volume_blocked")
	roof.queue_free()
	await _frames(2)
	# O espaço pode ficar ocupado depois da confirmação, antes de a fila aplicar o PATH.
	await _aim_settle(point)
	queue.set_physics_process(false)
	var revision := svc.get_revision()
	var log0 := _brush_log.size()
	var rejected0: int = earth.get_stats().pillars_rejected
	_p4c_rmb(true)
	_p4c_rmb(false)
	var queued: bool = earth.phase == "pillar_pending" and queue.pending_count() == 1
	crate = DebugProps.spawn_crate(props, point + Vector3.UP * 2.0)
	crate.freeze = true
	await _frames(2)
	queue.set_physics_process(true)
	var discarded: bool = await _wait_until(func(): return queue.pending_count() == 0, 2.0)
	cases["body_entered_pending_volume"] = {"queued": queued, "result": earth.get_stats().get("last_result", ""),
		"ok": queued and discarded and _brush_log.size() == log0 \
		and svc.get_revision() == revision and earth.get_stats().pillars_rejected == rejected0 + 1}
	crate.queue_free()
	ab.cancel_all()
	await _frames(2)
	earth.tuning = original.duplicate()
	earth.tuning.pillar_radius = 3.0
	await _aim_settle(_ground_at(base + Vector3(0, 0, -3.0)))
	await reject.call("protected_player")
	earth.tuning = original
	# RMB deixa os outros elementos e o LMB atuais funcionarem pelo mesmo dispatcher.
	for index in [1, 2, 3]:
		ab.select(index)
		var rev := svc.get_revision()
		_p4c_rmb(true)
		_p4c_rmb(false)
		await _frames(2)
		cases["other_element_%d" % index] = {"ok": svc.get_revision() == rev and not earth.pillar_aiming \
			and not ab.holding and queue.pending_count() == 0}
	ab.select(0)
	await _aim_settle(point)
	_p4b_lmb(true)
	var rock_ready: bool = await _wait_until(func(): return earth.phase == "hold", 2.0)
	var rock: RigidBody3D = earth.rock
	_p4c_rmb(true)
	_p4c_rmb(false)
	var exclusive: bool = rock_ready and earth.rock == rock and earth.phase == "hold" and not earth.pillar_aiming
	var throws: int = earth.get_stats().thrown
	_p4b_lmb(false)
	var launched: bool = await _wait_until(func(): return earth.get_stats().thrown == throws + 1, 1.0)
	cases["lmb_still_throws"] = {"ok": exclusive and launched}
	ab.cancel_all()
	base = await _p3_lab(0)
	var slot_ready: bool = await main.request_world_save(SLOT)
	var old_capture := ab.require_captured_mouse
	var old_mouse := Input.mouse_mode
	for pending: bool in [false, true]:
		for kind: String in ["select", "input_disabled", "mouse_lost", "reset", "save", "load"]:
			base = await _p3_lab(0)
			point = _ground_at(base + Vector3(0.17, 0, -5.0))
			await _aim_settle(point)
			queue.set_physics_process(false)
			var rev := svc.get_revision()
			var n := _brush_log.size()
			_p4c_rmb(true)
			var started: bool = earth.pillar_aiming
			if pending:
				_p4c_rmb(false)
				started = started and earth.phase == "pillar_pending" and queue.pending_count() == 1
			var unrelated: TerrainBrushRequest
			if pending and kind == "select":
				unrelated = TerrainBrushRequest.sphere(TerrainBrushRequest.Op.ADD, point + Vector3.RIGHT * 5.0, 0.5)
				unrelated.source = "selftest:P4C-unrelated"
				queue.enqueue(unrelated)
			var command_ok := true
			if kind == "select": ab.select(1)
			elif kind == "input_disabled": player.input_enabled = false
			elif kind == "mouse_lost":
				ab.require_captured_mouse = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif kind == "reset": command_ok = await main.request_world_reset()
			elif kind == "save": command_ok = await main.request_world_save(SLOT)
			else: command_ok = await main.request_world_load(SLOT)
			await _frames(2)
			var only_own: bool = queue.pending_count() == (1 if unrelated != null else 0)
			if unrelated != null: queue.cancel_request(unrelated)
			_p4c_rmb(false)
			queue.set_physics_process(true)
			await _frames(4)
			cases["%s_%s" % ["pending" if pending else "preview", kind]] = {"started": started,
				"only_own_request_cancelled": only_own,
				"ok": started and command_ok and only_own and not earth.pillar_aiming and earth.phase == "" \
				and not ab.holding and queue.pending_count() == 0 and _brush_log.size() == n \
				and (kind in ["reset", "load"] or svc.get_revision() == rev)}
			ab.require_captured_mouse = old_capture
			Input.mouse_mode = old_mouse
			player.input_enabled = true
			ab.cancel_all()
	earth.tuning = original
	ab.require_captured_mouse = old_capture
	Input.mouse_mode = old_mouse
	player.input_enabled = false
	_record("T64", "Pilar recusa alvos inseguros, mantém LMB/outros elementos e cancela preview/fila sem edição residual",
		slot_ready and cases.values().all(func(c): return c.ok), cases)
	await main.request_world_reset()


# --- P4D: fissura altera matéria, collider, apoio e o slot existentes ---------------------------

func _p4d_f(pressed: bool) -> void:
	_p4a_key(KEY_F, pressed)
	Input.flush_buffered_events()


func _t65_earth_fissure() -> void:
	const SLOT := "p4d_fissure"
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var point := _ground_at(base + Vector3(0.17, 0, -5.0))
	await _aim_settle(point)
	var check := earth.validate_fissure_target()
	if not check.ok:
		player.input_enabled = false
		_record("T65", "Fissura de Terra por F", false, {"reason": check.reason, "target": check})
		return
	var planned: TerrainBrushRequest = check.request
	var centers := PackedVector3Array([planned.points[0], planned.points[planned.points.size() >> 1], planned.points[-1]])
	# sample_sdf lê a célula voxel: o centro raso do PATH pode arredondar para SDF == 0.
	# Estas testemunhas ficam no interior real antes da edição e dentro da vala depois.
	var sdf_probes := PackedVector3Array()
	var original_sdf := []
	for p: Vector3 in centers:
		sdf_probes.append(p - Vector3.UP * 0.5)
		original_sdf.append(svc.sample_sdf(sdf_probes[-1]))
	var before_y := []
	for p: Vector3 in centers:
		before_y.append(_hit_y(svc.raycast_terrain(p + Vector3.UP * 4.0, p + Vector3.DOWN * 5.0)))
	# A caixa repousa de verdade no meio do futuro trecho; não é movida para simular queda.
	var middle := centers[1]
	var crate := DebugProps.spawn_crate(props, Vector3(middle.x, before_y[1] + 1.0, middle.z))
	await _seconds(2.0)
	var crate_before := crate.global_position
	var supported: bool = crate.linear_velocity.length() < 0.3 and absf(crate_before.y - before_y[1] - 0.5) < 0.25
	await _aim_settle(point)
	var edits: Array[Dictionary] = []
	var cb := func(req: TerrainBrushRequest, result: TerrainEditResult):
		if req.source == "ability:earth_fissure":
			edits.append({"request": req, "ok": result.ok, "reason": result.reason})
	queue.brush_applied.connect(cb)
	var revision := svc.get_revision()
	var extracted: int = earth.get_stats().extracted
	# Capturar a prévia fora da medição; a gravação PNG não pertence ao custo do poder.
	_p4d_f(true)
	await _frames(12)
	await _snap("p4d_fissure_preview")
	ab.cancel_all()
	_p4d_f(false)
	var frame_ms := PackedFloat32Array()
	var clock := {"last": Time.get_ticks_usec()}
	var sample_frame := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - int(clock.last)) / 1000.0)
		clock.last = now
	get_tree().process_frame.connect(sample_frame)
	_p4d_f(true)
	await _frames(12)
	_p4b_lmb(true)
	_p4b_lmb(false)
	_p4c_rmb(true)
	_p4c_rmb(false)
	var preview: bool = earth.fissure_aiming and not earth.pillar_aiming and svc.get_revision() == revision \
		and edits.is_empty() and queue.pending_count() == 0 and earth.get_stats().extracted == extracted
	_p4d_f(false)
	var applied: bool = await _wait_until(func(): return edits.size() == 1, 5.0)
	var lower := []
	var collider_ok := true
	for i in centers.size():
		var p := centers[i]
		var ray := await _wait_ray(p + Vector3.UP * 4.0, p + Vector3.DOWN * 5.0,
			func(h): return not h.is_empty() and h.position.y < float(before_y[i]) - 0.45, 5.0)
		collider_ok = collider_ok and ray.ok
		lower.append(_hit_y(ray.hit))
	await _seconds(2.0)
	var crate_drop := crate_before.y - crate.global_position.y
	var fell: bool = supported and crate_drop > 0.45
	_p4d_f(false)
	await _frames(2)
	var single_path: bool = applied and edits.size() == 1 and svc.get_revision() == revision + 1 \
		and (edits[0].request as TerrainBrushRequest).is_path() and not edits[0].request.additive
	queue.brush_applied.disconnect(cb)
	get_tree().process_frame.disconnect(sample_frame)
	await _snap("p4d_fissure")
	if not frame_ms.is_empty(): frame_ms.remove_at(0)
	var timings := _stats(frame_ms)
	timings["p99"] = _percentile(frame_ms, 0.99)
	_metrics["p4d_fissure_frame_ms"] = timings
	var perf_ok: bool = _mode.begins_with("headless") or (timings.get("p95", 999.0) <= 20.0 \
		and timings.p99 <= 33.0 and timings.get("max", 999.0) <= 50.0)
	var sdf := []
	for p: Vector3 in sdf_probes: sdf.append(svc.sample_sdf(p))
	var save_ok: bool = await main.request_world_save(SLOT)
	var save_unchanged := true
	var after_save_sdf := []
	for i in sdf_probes.size():
		var value := svc.sample_sdf(sdf_probes[i])
		after_save_sdf.append(value)
		save_unchanged = save_unchanged and is_equal_approx(float(sdf[i]), value)
	var reset_ok: bool = await main.request_world_reset()
	await _prepare_area(base, AABB(base + Vector3(-5, -4, -15), Vector3(10, 10, 15)))
	var reset_floor := true
	var reset_sdf := []
	var reset_rays := []
	for i in centers.size():
		var p := centers[i]
		var ray := await _wait_ray(p + Vector3.UP * 4.0, p + Vector3.DOWN * 5.0,
			func(h): return not h.is_empty() and absf(h.position.y - float(before_y[i])) < PROBE_TOLERANCE, 5.0)
		var value := svc.sample_sdf(sdf_probes[i])
		reset_sdf.append(value)
		reset_rays.append({"ok": ray.ok, "y": _hit_y(ray.hit), "ms": ray.ms})
		reset_floor = reset_floor and ray.ok and float(original_sdf[i]) < 0.0 and value < 0.0 \
			and absf(value - float(original_sdf[i])) < SDF_TOLERANCE
	var load_ok: bool = await main.request_world_load(SLOT)
	await _prepare_area(base, AABB(base + Vector3(-5, -4, -15), Vector3(10, 10, 15)))
	var loaded_floor := true
	var loaded_sdf := []
	var loaded_rays := []
	for i in centers.size():
		var p := centers[i]
		var ray := await _wait_ray(p + Vector3.UP * 4.0, p + Vector3.DOWN * 5.0,
			func(h): return not h.is_empty() and absf(h.position.y - float(lower[i])) < PROBE_TOLERANCE, 5.0)
		var value := svc.sample_sdf(sdf_probes[i])
		loaded_sdf.append(value)
		loaded_rays.append({"ok": ray.ok, "y": _hit_y(ray.hit), "ms": ray.ms})
		loaded_floor = loaded_floor and ray.ok and value > 0.0 and absf(value - float(sdf[i])) < SDF_TOLERANCE
	var persistence: bool = save_ok and save_unchanged and reset_ok and reset_floor and load_ok and loaded_floor
	player.input_enabled = false
	_record("T65", "F confirma uma fissura física única; caixa perde apoio e save/reset/load conservam SDF/colisão",
		preview and single_path and edits[0].ok and collider_ok and fell and persistence and perf_ok,
		{"preview_without_edit": preview, "single_subtractive_path": single_path, "collider_lowered": collider_ok,
		"floor_y_before": before_y, "floor_y_after": lower, "crate_supported_before": supported,
		"crate_drop_m": crate_drop, "original_sdf": original_sdf, "saved_sdf": sdf, "after_save_sdf": after_save_sdf,
		"reset_sdf": reset_sdf, "loaded_sdf": loaded_sdf, "reset_rays": reset_rays, "loaded_rays": loaded_rays,
		"persistence": persistence, "persistence_checks": {"save": save_ok, "save_unchanged": save_unchanged,
			"reset": reset_ok, "reset_floor_and_sdf": reset_floor, "load": load_ok, "loaded_floor_and_sdf": loaded_floor},
		"frame_ms": timings, "raycasts": {"attempts": check.ray_attempts, "hits": check.ray_hits,
			"misses": check.ray_attempts - check.ray_hits}})
	await main.request_world_reset()


func _t66_earth_fissure_guards() -> void:
	const SLOT := "p4d_cancel"
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var original := earth.tuning
	var point := _ground_at(base + Vector3(0.17, 0, -5.0))
	var cases := {}
	var reject := func(name: String):
		var check := earth.validate_fissure_target()
		var rev := svc.get_revision()
		var n := _brush_log.size()
		_p4d_f(true)
		await _frames(2)
		_p4d_f(false)
		await _frames(3)
		cases[name] = {"reason": check.reason, "raycasts": {"attempts": check.ray_attempts, "hits": check.ray_hits,
			"misses": check.ray_attempts - check.ray_hits},
			"ok": not check.ok and svc.get_revision() == rev and _brush_log.size() == n \
			and queue.pending_count() == 0 and not earth.fissure_aiming and earth.rock == null}
	player.camera_rig.set_view(0.0, deg_to_rad(45.0))
	await _frames(2)
	await reject.call("no_ground")
	await _aim_settle(_ground_at(base + Vector3(0, 0, -earth.tuning.fissure_range - 3.0)))
	await reject.call("out_of_range")
	await _aim_settle(_ground_at(base + Vector3(0, 0, -1.0)))
	await reject.call("minimum_range")
	var wall := _p36_thin_wall(base + Vector3(0, 2, -2), Vector3(6, 5, 0.2))
	await _frames(2)
	await _aim_settle(point)
	await reject.call("wall_occlusion")
	wall.queue_free()
	await _frames(2)
	var crate := DebugProps.spawn_crate(props, point + Vector3.UP * 0.6)
	crate.freeze = true
	await _frames(2)
	await _aim_settle(MaterialResponseSystem.body_center(crate))
	await reject.call("prop_not_ground")
	crate.queue_free()
	await _frames(2)
	await _aim_settle(point)
	var material: TerrainMaterial = svc.get_material_at(point - Vector3.UP * 0.5)
	if material != null:
		var was_bendable := material.bendable
		material.bendable = false
		await reject.call("non_bendable_ground")
		material.bendable = was_bendable
	else:
		cases["non_bendable_ground"] = {"ok": false, "reason": "fixture_material_missing"}
	earth.tuning = original.duplicate()
	earth.tuning.fissure_length = 30.0
	await reject.call("oversized_path")
	earth.tuning.fissure_length = original.fissure_length
	earth.tuning.fissure_radius = 0.0
	await reject.call("invalid_radius")
	earth.tuning = original
	# Na diagonal a AABB cabe, mas o comprimento ainda exigiria dividir o pedido.
	# A habilidade precisa recusar, pois cancelamento deve tratar um único PATH inteiro.
	await _aim_settle(_ground_at(base + Vector3(4, 0, -4)))
	var diagonal := earth.validate_fissure_target()
	var queue_extent := queue.max_aabb_extent
	queue.max_aabb_extent = 7.5
	await reject.call("path_would_split")
	var nominal_extent := 999.0
	var nominal_length := 0.0
	if diagonal.ok:
		var diagonal_request: TerrainBrushRequest = diagonal.request
		var size := diagonal_request.world_aabb().size
		nominal_extent = size[size.max_axis_index()]
		nominal_length = diagonal_request.length()
	cases.path_would_split["aabb_extent_m"] = nominal_extent
	cases.path_would_split["path_length_m"] = nominal_length
	cases.path_would_split["queue_extent_m"] = queue.max_aabb_extent
	cases.path_would_split.ok = cases.path_would_split.ok and diagonal.ok and nominal_extent <= queue.max_aabb_extent
	queue.max_aabb_extent = queue_extent
	await _aim_settle(point)
	# Escavar de verdade no fim do trecho cria um degrau; a fissura não salta o vazio.
	var continuous := earth.validate_fissure_target()
	if continuous.ok:
		var planned: TerrainBrushRequest = continuous.request
		var tail := planned.points[-1] + Vector3.UP * earth.tuning.fissure_depth
		var dug := svc.dig_sphere(tail - Vector3.UP * 0.5, 2.5)
		var hole := await _wait_ray(tail + Vector3.UP * 3.0, tail + Vector3.DOWN * 6.0,
			func(h): return not h.is_empty() and h.position.y < tail.y - 1.5, 5.0)
		await _aim_settle(point)
		await reject.call("discontinuous_floor")
		cases.discontinuous_floor["fixture_hole_confirmed"] = dug.ok and hole.ok
		cases.discontinuous_floor.ok = cases.discontinuous_floor.ok and dug.ok and hole.ok \
			and cases.discontinuous_floor.reason in ["desnível no caminho", "caminho sem chão contínuo"]
	else:
		cases["discontinuous_floor"] = {"ok": false, "reason": "fixture_path_not_valid"}
	base = await _p3_lab(0)
	point = _ground_at(base + Vector3(0.17, 0, -5.0))
	await _aim_settle(point)
	# Os outros elementos ignoram F. O ciclo da rocha e a prévia do pilar continuam exclusivos.
	for index in [1, 2, 3]:
		ab.select(index)
		var rev := svc.get_revision()
		_p4d_f(true)
		_p4d_f(false)
		await _frames(2)
		cases["other_element_%d" % index] = {"ok": svc.get_revision() == rev and not earth.fissure_aiming \
			and not ab.holding and queue.pending_count() == 0}
	ab.select(0)
	await _aim_settle(point)
	_p4c_rmb(true)
	_p4d_f(true)
	_p4d_f(false)
	cases["pillar_exclusive"] = {"ok": earth.pillar_aiming and not earth.fissure_aiming and queue.pending_count() == 0}
	ab.cancel_all()
	_p4c_rmb(false)
	_p4b_lmb(true)
	var rock_ready: bool = await _wait_until(func(): return earth.phase == "hold", 2.0)
	var rock: RigidBody3D = earth.rock
	_p4d_f(true)
	_p4d_f(false)
	var exclusive: bool = rock_ready and earth.rock == rock and earth.phase == "hold" and not earth.fissure_aiming
	var throws: int = earth.get_stats().thrown
	_p4b_lmb(false)
	var launched: bool = await _wait_until(func(): return earth.get_stats().thrown == throws + 1, 1.0)
	cases["lmb_still_throws"] = {"ok": exclusive and launched}
	ab.cancel_all()
	base = await _p3_lab(0)
	point = _ground_at(base + Vector3(0.17, 0, -5.0))
	await _aim_settle(point)
	var fixed := earth.validate_fissure_target()
	if fixed.ok:
		var fixed_request: TerrainBrushRequest = fixed.request
		queue.set_physics_process(false)
		var rev := svc.get_revision()
		var n := _brush_log.size()
		var rejected: int = earth.get_stats().fissures_rejected
		_p4d_f(true)
		_p4d_f(false)
		var pending: bool = earth.phase == "fissure_pending" and queue.pending_count() == 1
		player.teleport_to(fixed_request.points[fixed_request.points.size() >> 1] + Vector3.UP)
		await _frames(3)
		cases["player_entered_pending_path"] = {"queued": pending, "reason": earth.last_result,
			"ok": pending and svc.get_revision() == rev and _brush_log.size() == n and queue.pending_count() == 0 \
			and earth.get_stats().fissures_rejected == rejected + 1}
		_p4d_f(false)
		queue.set_physics_process(true)
	else:
		cases["player_entered_pending_path"] = {"ok": false, "reason": "fixture_path_not_valid"}
	ab.cancel_all()
	base = await _p3_lab(0)
	var slot_ready: bool = await main.request_world_save(SLOT)
	var old_capture := ab.require_captured_mouse
	var old_mouse := Input.mouse_mode
	for pending: bool in [false, true]:
		for kind: String in ["select", "input_disabled", "mouse_lost", "reset", "save", "load"]:
			base = await _p3_lab(0)
			point = _ground_at(base + Vector3(0.17, 0, -5.0))
			await _aim_settle(point)
			queue.set_physics_process(false)
			var rev := svc.get_revision()
			var n := _brush_log.size()
			_p4d_f(true)
			var started: bool = earth.fissure_aiming
			if pending:
				_p4d_f(false)
				started = started and earth.phase == "fissure_pending" and queue.pending_count() == 1
			var unrelated: TerrainBrushRequest
			if pending and kind == "select":
				unrelated = TerrainBrushRequest.sphere(TerrainBrushRequest.Op.ADD, point + Vector3.RIGHT * 5.0, 0.5)
				unrelated.source = "selftest:P4D-unrelated"
				queue.enqueue(unrelated)
			var command_ok := true
			if kind == "select": ab.select(1)
			elif kind == "input_disabled": player.input_enabled = false
			elif kind == "mouse_lost":
				ab.require_captured_mouse = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif kind == "reset": command_ok = await main.request_world_reset()
			elif kind == "save": command_ok = await main.request_world_save(SLOT)
			else: command_ok = await main.request_world_load(SLOT)
			await _frames(2)
			var only_own: bool = queue.pending_count() == (1 if unrelated != null else 0)
			if unrelated != null: queue.cancel_request(unrelated)
			_p4d_f(false)
			queue.set_physics_process(true)
			await _frames(4)
			cases["%s_%s" % ["pending" if pending else "preview", kind]] = {"started": started,
				"only_own_request_cancelled": only_own,
				"ok": started and command_ok and only_own and not earth.fissure_aiming and earth.phase == "" \
				and not ab.holding and queue.pending_count() == 0 and _brush_log.size() == n \
				and (kind in ["reset", "load"] or svc.get_revision() == rev)}
			ab.require_captured_mouse = old_capture
			Input.mouse_mode = old_mouse
			player.input_enabled = true
			ab.cancel_all()
	earth.tuning = original
	ab.require_captured_mouse = old_capture
	Input.mouse_mode = old_mouse
	player.input_enabled = false
	_record("T66", "Fissura respeita chão/alcance/material, mantém LMB/RMB e cancela prévia/pedido sem edição residual",
		slot_ready and cases.values().all(func(c): return c.ok), cases)
	await main.request_world_reset()


# --- P4E: estado contínuo da água, consultas físicas e reações materiais existentes -----------

func _t67_water_orb_control() -> void:
	var ab: AbilityController = main.abilities
	await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var revision := svc.get_revision()
	var bodies := props.get_child_count()
	var radius0 := controller.radius
	_p4c_rmb(true)
	var formed := orb.phase == "hold" and ab.can_manipulate_water()
	if not formed:
		_p4c_rmb(false)
		ab.cancel_all()
		player.input_enabled = false
		_record("T67", "Controle contínuo do orbe de Água", false, {"reason": "orb_not_formed", "status": orb.status()})
		return
	var start := orb.position
	var probe := {"previous": start, "max_step_m": 0.0}
	var sample_motion := func():
		probe.max_step_m = maxf(probe.max_step_m, orb.position.distance_to(probe.previous))
		probe.previous = orb.position
	var frame_ms := PackedFloat32Array()
	var clock := {"last": Time.get_ticks_usec()}
	var sample_frame := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - int(clock.last)) / 1000.0)
		clock.last = now
	get_tree().physics_frame.connect(sample_motion)
	get_tree().process_frame.connect(sample_frame)
	var height0 := orb.hold_height
	_p4a_key(KEY_E, true)
	await _frames(36)
	_p4a_key(KEY_E, false)
	var high := orb.hold_height
	var raised_m := orb.position.y - start.y
	_p4a_key(KEY_Q, true)
	await _frames(90)
	_p4a_key(KEY_Q, false)
	var low := orb.hold_height
	_p4a_key(KEY_Q, true)
	_p4a_key(KEY_E, true)
	await _frames(4)
	var opposite_neutral := is_equal_approx(orb.hold_height, low)
	_p4a_key(KEY_Q, false)
	await _frames(45)
	_p4a_key(KEY_E, false)
	var distance0 := orb.hold_distance
	_p4a_wheel(true)
	await _frames(2)
	var wheel_step := distance0 - orb.hold_distance
	for i in 20: _p4a_wheel(true)
	await _frames(4)
	var near := orb.hold_distance
	for i in 20: _p4a_wheel(false)
	await _frames(4)
	var far := orb.hold_distance
	player.camera_rig.set_view(PI * 0.5, deg_to_rad(-20.0))
	await _frames(45)
	var horizontal_m := Vector2(orb.position.x - start.x, orb.position.z - start.z).length()
	var player_start := player.global_position
	player.set_scripted_move(Vector3.RIGHT)
	await _frames(12)
	player.clear_scripted_move()
	var player_moved := player.global_position.distance_to(player_start)
	# A parede entra depois de aproximar: o teste mede um deslocamento comum até ela.
	player.camera_rig.set_view(0.0, deg_to_rad(-20.0))
	for i in 20: _p4a_wheel(true)
	await _frames(60)
	var wall_distance := 4.5
	var wall := _p36_thin_wall(player.global_position + Vector3(0, 2.0, -wall_distance), Vector3(16, 8, 0.04))
	await _frames(2)
	var blocked0: int = orb.get_stats().blocked_motion
	for i in 20: _p4a_wheel(false)
	var farthest := 0.0
	for i in 60:
		await get_tree().physics_frame
		farthest = maxf(farthest, player.global_position.z - orb.position.z)
	var wall_blocked: bool = farthest + orb.radius() <= wall_distance + 0.01 and orb.get_stats().blocked_motion > blocked0
	get_tree().physics_frame.disconnect(sample_motion)
	await _aim_settle(wall.global_position)
	var before_release := orb.position
	var launched0: int = orb.get_stats().launched
	_p4c_rmb(false)
	var launch_speed := orb.velocity.length()
	var launched: bool = orb.phase == "flight" and orb.get_stats().launched == launched0 + 1 \
		and before_release.distance_to(orb.position) < 0.0001 and launch_speed > orb.tuning.launch_speed * 0.5 \
		and launch_speed <= orb.tuning.launch_speed + orb.tuning.inherited_speed_limit + 0.001
	var finished := await _wait_until(func(): return orb.phase == "", 2.0)
	await _frames(8)
	get_tree().process_frame.disconnect(sample_frame)
	if not frame_ms.is_empty(): frame_ms.remove_at(0)
	var timings := _stats(frame_ms)
	timings["p99"] = _percentile(frame_ms, 0.99)
	_metrics["p4e_orb_frame_ms"] = timings
	var windowed := not _mode.begins_with("headless")
	var perf_ok: bool = not windowed or (timings.get("p95", 999.0) <= 20.0 and timings.p99 <= 33.0 and timings.get("max", 999.0) <= 50.0)
	var continuous: bool = float(probe.max_step_m) <= orb.tuning.max_control_speed / float(Engine.physics_ticks_per_second) + 0.01
	var ok: bool = formed and high > height0 + 0.7 and raised_m > 0.4 and is_equal_approx(low, orb.tuning.min_height) \
		and opposite_neutral and is_equal_approx(wheel_step, orb.tuning.distance_step) \
		and is_equal_approx(near, orb.tuning.min_distance) and is_equal_approx(far, orb.tuning.max_distance) \
		and horizontal_m > 2.0 and player_moved > 0.2 and continuous and wall_blocked and launched and finished \
		and svc.get_revision() == revision and props.get_child_count() == bodies + 1 and is_equal_approx(controller.radius, radius0) and perf_ok
	ab.cancel_all()
	player.input_enabled = false
	_record("T67", "Orbe: RMB, Q/E, roda, câmera e movimento contínuo; parede bloqueia e soltar lança, com benchmark curto", ok,
		{"formed": formed, "nominal_liters": orb.tuning.nominal_liters, "height_min_max_m": [low, high], "raised_m": raised_m,
		"opposite_keys_neutral": opposite_neutral, "distance_min_max_m": [near, far], "wheel_step_m": wheel_step,
		"horizontal_m": horizontal_m, "player_moved_m": player_moved, "max_control_step_m": probe.max_step_m, "continuous": continuous,
		"wall_blocked": wall_blocked, "farthest_m": farthest, "wall_distance_m": wall_distance, "radius_m": orb.radius(),
		"launched_without_teleport": launched, "launch_speed_m_s": launch_speed, "finished": finished,
		"no_terrain_edit": svc.get_revision() == revision, "brush_unchanged": is_equal_approx(controller.radius, radius0),
		"frame_ms": timings, "frame_gate_applied": windowed})
	# Captura opcional depois de fechar a amostragem: readback não entra no benchmark.
	if _screens:
		player.input_enabled = true
		player.camera_rig.set_view(0.0, deg_to_rad(-12.0))
		if ab.begin_water_orb():
			await _frames(60)
			await _snap("p4e_water_orb_hold")
		ab.cancel_all()
		player.input_enabled = false
	await main.request_world_reset()


func _p4e_orb_body_case(mass: float, ignite: bool) -> Dictionary:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var original := orb.tuning
	orb.tuning = original.duplicate(true)
	orb.tuning.visual_enabled = false
	var body := _air_crate(base + Vector3(0, 1.6, -8), mass)
	var state := materials.state_of(body)
	if ignite: _apply_direct(ElementalEvent.Kind.HEAT, body, 450.0)
	var burning_before := state.burning
	var temp_before := state.temperature
	var watch := {"contacts": 0, "wet_at_fx": 0.0, "temperature_at_fx": temp_before, "burning_at_fx": burning_before, "event_id": 0}
	var on_contact := func(kind: StringName, data: Dictionary):
		if kind == &"water_orb_impact":
			watch.contacts += 1
			watch.wet_at_fx = state.wetness
			watch.temperature_at_fx = state.temperature
			watch.burning_at_fx = state.burning
			watch.event_id = data.get("event_id", 0)
	orb.fx_event.connect(on_contact)
	var formed := ab.begin_water_orb()
	await _frames(20)
	await _aim_settle(MaterialResponseSystem.body_center(body))
	var start := body.global_position
	var impacts0: int = orb.get_stats().impacts
	var impulse0: float = orb.get_stats().impulse_ns
	ab.release_water_orb()
	var finished := await _wait_until(func(): return orb.phase == "", 2.0)
	await _frames(12)
	var impulse: float = orb.get_stats().impulse_ns - impulse0
	var speed := body.linear_velocity.length()
	var expected := impulse / mass
	var result := {"formed": formed, "finished": finished, "mass_kg": mass, "impulse_ns": impulse, "speed_m_s": speed,
		"expected_delta_v": expected, "moved_m": body.global_position.distance_to(start), "burning_before": burning_before,
		"temperature_before": temp_before, "wetness": state.wetness, "visual_disabled": not orb.tuning.visual_enabled,
		"impacts": orb.get_stats().impacts - impacts0, "fx": watch.duplicate(),
		"ok": formed and finished and orb.get_stats().impacts - impacts0 == 1 and watch.contacts == 1 and watch.event_id > 0 \
			and impulse > 0.0 and expected > 0.0 and absf(speed - expected) <= expected * 0.05 \
			and state.wetness > 0.5 and watch.wet_at_fx > 0.5 and (not ignite or (burning_before and not watch.burning_at_fx \
			and watch.temperature_at_fx < temp_before - 20.0))}
	orb.fx_event.disconnect(on_contact)
	orb.tuning = original
	ab.cancel_all()
	return result


func _t68_water_orb_contact() -> void:
	var light := await _p4e_orb_body_case(20.0, true)
	var heavy := await _p4e_orb_body_case(2000.0, false)
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var wall_original := orb.tuning
	orb.tuning = wall_original.duplicate(true)
	orb.tuning.launch_speed = 60.0
	var wall := _p36_thin_wall(base + Vector3(0, 1.6, -6), Vector3(4, 4, 0.001))
	var exposed := _air_crate(base + Vector3(0.95, 1.6, -5.3))
	var behind := _air_crate(base + Vector3(0, 1.6, -6.7))
	exposed.freeze = true
	behind.freeze = true
	var exposed_state := materials.state_of(exposed)
	var behind_state := materials.state_of(behind)
	_apply_direct(ElementalEvent.Kind.HEAT, exposed, 80.0)
	_apply_direct(ElementalEvent.Kind.HEAT, behind, 80.0)
	await _aim_settle(wall.global_position)
	var revision := svc.get_revision()
	var hits0: int = orb.get_stats().impacts
	var terrain0: int = orb.get_stats().terrain_impacts
	var formed := ab.begin_water_orb()
	await _frames(20)
	await _aim_settle(wall.global_position)
	ab.release_water_orb()
	var finished := await _wait_until(func(): return orb.phase == "", 2.0)
	await _frames(4)
	var occlusion := {"formed": formed, "finished": finished, "wall_thickness_m": 0.001,
		"launch_speed_m_s": orb.tuning.launch_speed, "step_m": orb.tuning.launch_speed / float(Engine.physics_ticks_per_second),
		"orb_diameter_m": orb.radius() * 2.0,
		"impacts": orb.get_stats().impacts - hits0, "terrain_contacts": orb.get_stats().terrain_impacts - terrain0,
		"exposed_wetness": exposed_state.wetness, "behind_wetness": behind_state.wetness,
		"exposed_temperature": exposed_state.temperature, "behind_temperature": behind_state.temperature,
		"ok": formed and finished and orb.get_stats().impacts - hits0 == 1 and orb.get_stats().terrain_impacts - terrain0 == 1 \
			and orb.tuning.launch_speed / float(Engine.physics_ticks_per_second) > orb.radius() * 2.0 \
			and exposed_state.wetness > 0.01 and behind_state.wetness < 0.001 \
			and exposed_state.temperature < behind_state.temperature - 1.0 and svc.get_revision() == revision}
	orb.tuning = wall_original
	base = await _p3_lab(1)
	var original := orb.tuning
	orb.tuning = original.duplicate(true)
	orb.tuning.max_range = 3.0
	var remote := _air_crate(base + Vector3(0, 1.6, -10))
	var remote_state := materials.state_of(remote)
	await _aim_settle(MaterialResponseSystem.body_center(remote))
	var dissipated0: int = orb.get_stats().dissipated
	hits0 = orb.get_stats().impacts
	formed = ab.begin_water_orb()
	await _frames(12)
	ab.release_water_orb()
	finished = await _wait_until(func(): return orb.phase == "", 2.0)
	var range_case := {"range_m": orb.tuning.max_range, "formed": formed, "finished": finished,
		"remote_wetness": remote_state.wetness, "remote_speed_m_s": remote.linear_velocity.length(),
		"ok": formed and finished and orb.get_stats().dissipated == dissipated0 + 1 and orb.get_stats().impacts == hits0 \
			and remote_state.wetness < 0.001 and remote.linear_velocity.length() < 0.001}
	orb.tuning = original
	base = await _p3_lab(1)
	var ground := _ground_at(base + Vector3(0, 0, -8))
	await _aim_settle(ground)
	formed = ab.begin_water_orb()
	await _frames(20)
	await _aim_settle(ground)
	hits0 = orb.get_stats().impacts
	terrain0 = orb.get_stats().terrain_impacts
	revision = svc.get_revision()
	ab.release_water_orb()
	finished = await _wait_until(func(): return orb.phase == "", 2.0)
	var ground_case := {"finished": finished, "center_y": orb.position.y, "ground_y": ground.y,
		"ok": formed and finished and orb.get_stats().impacts == hits0 + 1 \
			and orb.get_stats().terrain_impacts == terrain0 + 1 and svc.get_revision() == revision \
			and orb.position.y >= ground.y + orb.radius() - 0.05}
	base = await _p3_lab(1)
	orb.tuning = original.duplicate(true)
	orb.tuning.nominal_liters = 10.0
	_p36_thin_wall(player.global_position + Vector3(0, 1.6, -0.45), Vector3(4, 4, 0.001))
	await _frames(2)
	var formed0: int = orb.get_stats().formed
	var blocked_formation: bool = not ab.begin_water_orb() and orb.phase == "" and orb.get_stats().formed == formed0
	orb.tuning = original
	ab.cancel_all()
	player.input_enabled = false
	_record("T68", "Orbe varre contato único, transfere impulso/WET antes do FX, apaga chama e respeita parede e alcance",
		light.ok and heavy.ok and light.speed_m_s > heavy.speed_m_s * 4.0 and occlusion.ok and range_case.ok and ground_case.ok and blocked_formation,
		{"light_burning_body": light, "heavy_body": heavy, "thin_wall_occlusion": occlusion,
		"range_without_remote_contact": range_case, "voxel_ground": ground_case, "formation_blocked_by_thin_wall": blocked_formation})
	await main.request_world_reset()


func _t69_water_orb_lifecycle() -> void:
	const SLOT := "p4e_orb_cancel"
	var ab: AbilityController = main.abilities
	await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var radius0 := controller.radius
	var old_capture := ab.require_captured_mouse
	var old_mouse := Input.mouse_mode
	var cases := {}
	_p4b_lmb(true)
	var jet_first: bool = jet.active and ab.holding and not ab.begin_water_orb() and orb.phase == ""
	_p4b_lmb(false)
	_p4c_rmb(true)
	var orb_first := orb.phase == "hold"
	_p4b_lmb(true)
	orb_first = orb_first and not jet.active and not ab.holding
	_p4c_rmb(false)
	_p4b_lmb(false)
	orb_first = orb_first and orb.phase == "flight" and not jet.active
	ab.cancel_all()
	cases["first_button_wins"] = {"jet_first": jet_first, "orb_first": orb_first, "ok": jet_first and orb_first}
	var outside := []
	for index in 4:
		ab.select(index)
		var before := controller.radius
		_p4a_wheel(true)
		await _frames(1)
		outside.append(is_equal_approx(controller.radius, before + controller.radius_step))
		_p4a_wheel(false)
		await _frames(1)
	controller.radius = radius0
	ab.select(1)
	var slot_ready: bool = await main.request_world_save(SLOT)
	for flight: bool in [false, true]:
		for kind: String in ["select", "input_disabled", "mouse_lost", "escape", "reset", "save", "load"]:
			await _p3_lab(1)
			player.camera_rig.set_view(0.0, deg_to_rad(15.0))
			_p4c_rmb(true)
			var started := orb.phase == "hold"
			if flight:
				_p4c_rmb(false)
				started = started and orb.phase == "flight"
			_p4a_key(KEY_E, true)
			var impacts0: int = orb.get_stats().impacts
			var at_signal := {}
			var probe := func(_slot := ""):
				at_signal["clean"] = orb.phase == "" and orb.velocity.is_zero_approx() and not ab.holding
			var sig: Signal = svc.world_reset_started
			if kind == "save": sig = svc.world_save_started
			elif kind == "load": sig = svc.world_load_started
			if kind in ["reset", "save", "load"]: sig.connect(probe)
			var command_ok := true
			if kind == "select": ab.select(0)
			elif kind == "input_disabled": player.input_enabled = false
			elif kind == "mouse_lost":
				ab.require_captured_mouse = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif kind == "escape":
				ab.require_captured_mouse = false
				_p4a_key(KEY_ESCAPE, true)
				Input.flush_buffered_events()
				_p4a_key(KEY_ESCAPE, false)
				Input.flush_buffered_events()
			elif kind == "reset": command_ok = await main.request_world_reset()
			elif kind == "save": command_ok = await main.request_world_save(SLOT)
			else: command_ok = await main.request_world_load(SLOT)
			if sig.is_connected(probe): sig.disconnect(probe)
			await _frames(2)
			var height := orb.hold_height
			var distance := orb.hold_distance
			_p4c_rmb(false)
			await _frames(4)
			var fx_stats: Dictionary = main.fx.get_stats()
			var clean: bool = orb.phase == "" and orb.velocity.is_zero_approx() and not ab.holding \
				and orb.get_stats().impacts == impacts0 and is_equal_approx(height, orb.hold_height) \
				and is_equal_approx(distance, orb.hold_distance) and not fx_stats.get("orb_visible", false) \
				and not fx_stats.get("orb_trail_emitting", false)
			cases["%s_%s" % ["flight" if flight else "hold", kind]] = {"started": started, "command_ok": command_ok,
				"clean_at_signal": at_signal.get("clean", true), "clean_after": clean,
				"ok": started and command_ok and clean and bool(at_signal.get("clean", true))}
			_p4a_key(KEY_E, false)
			ab.require_captured_mouse = old_capture
			Input.mouse_mode = old_mouse
			player.input_enabled = true
			ab.cancel_all()
	await _p3_lab(1)
	var restarted := ab.begin_water_orb()
	var defaults: bool = restarted and is_equal_approx(orb.hold_height, orb.tuning.initial_height) \
		and is_equal_approx(orb.hold_distance, orb.tuning.initial_distance)
	ab.cancel_all()
	_p4a_key(KEY_Q, false)
	_p4a_key(KEY_E, false)
	_p4c_rmb(false)
	ab.require_captured_mouse = old_capture
	Input.mouse_mode = old_mouse
	controller.radius = radius0
	player.input_enabled = false
	_record("T69", "Orbe mantém exclusão jato/RMB e pincel; seleção/input/mouse/Esc/reset/save/load cancelam hold e voo sem resíduos",
		slot_ready and defaults and outside.all(func(passed): return passed) and cases.values().all(func(c): return c.ok),
		{"slot_ready": slot_ready, "wheel_outside_hold_by_element": outside, "restart_defaults": defaults, "cases": cases})
	await main.request_world_reset()


# --- P4F: o mesmo orbe em dois estados ------------------------------------------------------

func _p4f_c() -> void:
	_p4a_key(KEY_C, true)
	Input.flush_buffered_events()
	_p4a_key(KEY_C, false)
	Input.flush_buffered_events()


func _t70_ice_control() -> void:
	var ab: AbilityController = main.abilities
	await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var freezes0: int = orb.get_stats().freezes
	var ignored := true
	for index in 4:
		ab.select(index)
		_p4f_c()
		ignored = ignored and orb.get_stats().freezes == freezes0 and not orb.is_frozen()
	ab.select(1)
	ab.use_pressed()
	_p4f_c()
	ignored = ignored and jet.active and not orb.is_frozen()
	ab.use_released()
	_p4c_rmb(true)
	await _frames(20)
	var formed: bool = orb.phase == "hold" and not orb.is_frozen()
	var revision := svc.get_revision()
	var brush := controller.radius
	var clock := {"last": Time.get_ticks_usec()}
	var frame_ms := PackedFloat32Array()
	var sample := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - int(clock.last)) / 1000.0)
		clock.last = now
	get_tree().process_frame.connect(sample)
	_p4a_key(KEY_E, true)
	await _frames(8)
	var at := orb.position
	var velocity := orb.velocity
	var target := orb.target_position
	var radius := orb.radius()
	_p4f_c()
	var preserved: bool = orb.is_frozen() and orb.get_stats().freezes == freezes0 + 1 \
		and at.distance_to(orb.position) < 0.00001 and velocity.distance_to(orb.velocity) < 0.00001 \
		and target.distance_to(orb.target_position) < 0.00001 and is_equal_approx(radius, orb.radius())
	_p4f_c()
	var once: bool = orb.is_frozen() and orb.get_stats().freezes == freezes0 + 1
	var height0 := orb.hold_height
	await _frames(18)
	_p4a_key(KEY_E, false)
	var raised: bool = orb.hold_height > height0 + 0.4
	var distance0 := orb.hold_distance
	_p4a_wheel(true)
	Input.flush_buffered_events()
	var wheel: bool = is_equal_approx(orb.hold_distance, distance0 - orb.tuning.distance_step) and is_equal_approx(brush, controller.radius)
	player.camera_rig.set_view(0.5, deg_to_rad(-12.0))
	await _frames(20)
	var moved: bool = orb.position.distance_to(at) > 0.3
	player.camera_rig.set_view(0.0, deg_to_rad(-12.0))
	await _frames(30)
	var wall_distance := 4.8
	var wall := _p36_thin_wall(player.global_position + Vector3(0, 2, -wall_distance), Vector3(12, 6, 0.02))
	await _frames(2)
	var blocked0: int = orb.get_stats().blocked_motion
	for i in 20: _p4a_wheel(false)
	await _frames(50)
	var blocked: bool = orb.phase == "hold" and orb.is_frozen() and orb.get_stats().blocked_motion > blocked0 \
		and player.global_position.z - orb.position.z + orb.radius() <= wall_distance + 0.01
	wall.queue_free()
	await _frames(2)
	# Mira elevada: há espaço livre para observar a gravidade antes de qualquer contato.
	player.camera_rig.set_view(0.0, deg_to_rad(20.0))
	ab.release_water_orb()
	var launched: bool = orb.phase == "flight" and orb.is_frozen()
	var p0 := orb.position
	var v0 := orb.velocity
	_p4f_c()
	var flight_ignored: bool = orb.get_stats().freezes == freezes0 + 1 and orb.is_frozen()
	await _frames(6)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var dv := v0.y - orb.velocity.y
	var gravity: bool = orb.phase == "flight" and dv >= orb.tuning.ice_gravity * dt * 4.0 \
		and dv <= orb.tuning.ice_gravity * dt * 7.1 and orb.position.distance_to(p0) > 1.0
	var finished := await _wait_until(func(): return orb.phase == "", 2.0)
	get_tree().process_frame.disconnect(sample)
	if not frame_ms.is_empty(): frame_ms.remove_at(0)
	var timings := _stats(frame_ms)
	timings["p99"] = _percentile(frame_ms, 0.99)
	_metrics["p4f_ice_frame_ms"] = timings
	var windowed := not _mode.begins_with("headless")
	var perf: bool = not windowed or (timings.get("p95", 999.0) <= 20.0 and timings.p99 <= 33.0 and timings.get("max", 999.0) <= 50.0)
	_record("T70", "C contextual congela uma vez sem deslocar o orbe; controle e paredes mantidos, voo tem gravidade",
		ignored and formed and preserved and once and raised and wheel and moved and blocked and launched and flight_ignored \
		and gravity and finished and not orb.is_frozen() and svc.get_revision() == revision and perf,
		{"ignored_outside_context": ignored, "formed_liquid": formed, "preserved_position_velocity_target_radius": preserved,
		"one_freeze": once, "height_control": raised, "wheel_context": wheel, "camera_control": moved, "wall_blocked": blocked,
		"ice_launched": launched, "freeze_ignored_in_flight": flight_ignored, "gravity": gravity, "vertical_dv_6_frames": dv,
		"launch_speed": v0.length(), "finished_liquid": finished and not orb.is_frozen(), "frame_ms": timings, "frame_gate_applied": windowed})
	if _screens:
		ab.begin_water_orb()
		await _frames(20)
		_p4f_c()
		player.camera_rig.set_view(0.0, deg_to_rad(-12.0))
		await _frames(20)
		await _snap("p4f_ice_orb_hold")
	ab.cancel_all()
	player.input_enabled = false
	await main.request_world_reset()


func _p4f_body_case(structural: bool) -> Dictionary:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var body: RigidBody3D
	if structural:
		# A peça isolada atravessa o consumidor KINETIC real; ele já aplica metade do impulso.
		var piece := StructurePiece.new()
		piece.material_id = BodyMaterialLibrary.WOOD
		piece.mass = 20.0
		piece.freeze = true
		piece.gravity_scale = 0.0
		piece.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		piece.linear_damp = 0.0
		piece.collision_layer = Layers.PROPS
		piece.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		piece.add_child(shape)
		props.add_child(piece)
		piece.global_position = base + Vector3(0, 1.6, -8)
		body = piece
	else:
		body = _air_crate(base + Vector3(0, 1.6, -8), 20.0)
	var state := materials.state_of(body)
	if not structural: _apply_direct(ElementalEvent.Kind.HEAT, body, 450.0)
	var watch := {"count": 0, "frozen": false, "wet": -1.0, "burning": false, "velocity": Vector3.ZERO}
	var cb := func(kind: StringName, data: Dictionary):
		if kind == &"water_orb_impact":
			watch.count += 1
			watch.frozen = data.get("frozen", false)
			watch.wet = state.wetness
			watch.burning = state.burning
			watch.velocity = body.linear_velocity
	orb.fx_event.connect(cb)
	var formed := ab.begin_water_orb()
	await _frames(20)
	var frozen := ab.freeze_water_orb()
	await _aim_settle(MaterialResponseSystem.body_center(body))
	var hits0: int = orb.get_stats().ice_impacts
	var impulses0: float = orb.get_stats().impulse_ns
	ab.release_water_orb()
	var finished := await _wait_until(func(): return orb.phase == "", 2.0)
	await _frames(4)
	var impulse: float = orb.get_stats().impulse_ns - impulses0
	var expected := minf(orb.tuning.ice_impulse_ns, body.mass * orb.tuning.ice_max_target_delta_v) * (0.5 if structural else 1.0)
	var released: bool = not structural or (body as StructurePiece).released
	var result := {"formed": formed, "frozen": frozen, "finished": finished, "impacts": orb.get_stats().ice_impacts - hits0,
		"structural": structural, "released": released, "impulse_ns": impulse, "expected_impulse_ns": expected,
		"speed": body.linear_velocity.length(), "expected_speed": expected / body.mass, "wetness": state.wetness,
		"fx_frozen": watch.frozen, "fx_contacts": watch.count, "burning_at_impact": watch.burning,
		"ok": formed and frozen and finished and released and orb.get_stats().ice_impacts - hits0 == 1 \
			and watch.count == 1 and watch.frozen and watch.wet == 0.0 and state.wetness == 0.0 \
			and absf(impulse - expected) < 0.001 and absf(body.linear_velocity.length() - expected / body.mass) < 0.02 \
			and (structural or watch.burning) and not orb.is_frozen()}
	orb.fx_event.disconnect(cb)
	ab.cancel_all()
	return result


func _t71_ice_contact_lifecycle() -> void:
	var body := await _p4f_body_case(false)
	var structural := await _p4f_body_case(true)
	var ab: AbilityController = main.abilities
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var original := orb.tuning
	var contacts := {}
	for kind: String in ["thin_wall", "voxel_ground", "range"]:
		var base: Vector3 = await _p3_lab(1)
		orb.tuning = original.duplicate(true)
		var target := _ground_at(base + Vector3(0, 0, -8))
		var behind: RigidBody3D
		if kind == "thin_wall":
			_p36_thin_wall(base + Vector3(0, 1.6, -6), Vector3(4, 4, 0.001))
			behind = _air_crate(base + Vector3(0, 1.6, -7))
			target = base + Vector3(0, 1.6, -6)
			orb.tuning.ice_launch_speed = 60.0
		elif kind == "range":
			orb.tuning.max_range = 3.0
			target = base + Vector3(0, 5, -20)
		await _aim_settle(target)
		var formed := ab.begin_water_orb()
		await _frames(20)
		var frozen := ab.freeze_water_orb()
		await _aim_settle(target)
		var hits0: int = orb.get_stats().impacts
		var diss0: int = orb.get_stats().dissipated
		var revision := svc.get_revision()
		ab.release_water_orb()
		var finished := await _wait_until(func(): return orb.phase == "", 2.0)
		var expected_hits := 0 if kind == "range" else 1
		contacts[kind] = {"ok": formed and frozen and finished and not orb.is_frozen() and svc.get_revision() == revision \
			and orb.get_stats().impacts == hits0 + expected_hits \
			and (kind != "range" or orb.get_stats().dissipated == diss0 + 1) \
			and (behind == null or behind.linear_velocity.length() < 0.001), "impacts": orb.get_stats().impacts - hits0}
	orb.tuning = original
	const SLOT := "p4f_ice_cancel"
	await _p3_lab(1)
	var slot_ready: bool = await main.request_world_save(SLOT)
	var old_capture := ab.require_captured_mouse
	var old_mouse := Input.mouse_mode
	var cases := {}
	for flight: bool in [false, true]:
		for kind: String in ["select", "input", "mouse", "escape", "reset", "save", "load"]:
			await _p3_lab(1)
			player.camera_rig.set_view(0.0, deg_to_rad(20.0))
			var started: bool = ab.begin_water_orb() and ab.freeze_water_orb()
			if flight: ab.release_water_orb()
			var at_signal := {"clean": true}
			var probe := func(_slot := ""):
				at_signal.clean = orb.phase == "" and not orb.is_frozen() and orb.freeze_age == 0.0
			var sig: Signal = svc.world_reset_started
			if kind == "save": sig = svc.world_save_started
			elif kind == "load": sig = svc.world_load_started
			if kind in ["reset", "save", "load"]: sig.connect(probe)
			var command_ok := true
			if kind == "select": ab.select(0)
			elif kind == "input": player.input_enabled = false
			elif kind == "mouse":
				ab.require_captured_mouse = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif kind == "escape":
				_p4a_key(KEY_ESCAPE, true)
				Input.flush_buffered_events()
				_p4a_key(KEY_ESCAPE, false)
				Input.flush_buffered_events()
			elif kind == "reset": command_ok = await main.request_world_reset()
			elif kind == "save": command_ok = await main.request_world_save(SLOT)
			else: command_ok = await main.request_world_load(SLOT)
			if sig.is_connected(probe): sig.disconnect(probe)
			await _frames(2)
			var fx: Dictionary = main.fx.get_stats()
			var clean: bool = orb.phase == "" and not orb.is_frozen() and orb.velocity.is_zero_approx() \
				and orb.freeze_age == 0.0 and not fx.ice_visible and not fx.ice_fragments_emitting and not fx.orb_trail_emitting
			cases["%s_%s" % ["flight" if flight else "hold", kind]] = {"ok": started and command_ok and clean and at_signal.clean}
			ab.require_captured_mouse = old_capture
			Input.mouse_mode = old_mouse
			player.input_enabled = true
	await _p3_lab(1)
	var restart: bool = ab.begin_water_orb() and not orb.is_frozen() and orb.freeze_age == 0.0
	ab.cancel_all()
	player.input_enabled = false
	_record("T71", "Gelo aplica KINETIC único sem WET/impulso duplicado, respeita paredes/voxel/alcance e limpa estado ao cancelar",
		body.ok and structural.ok and slot_ready and restart and contacts.values().all(func(c): return c.ok) and cases.values().all(func(c): return c.ok),
		{"body": body, "structural_consumer": structural, "contacts": contacts, "cancellations": cases, "restart_liquid": restart})
	await main.request_world_reset()


## Fixture da mesma factory do impacto: só preenche orçamento/negativos, não prova o lançamento.
func _p4g_fixture(orb: WaterOrb, center: Vector3) -> IceBody:
	orb.position = center
	return orb._spawn_persistent_ice({"position": center - Vector3.UP * (orb.radius() + 0.02), "normal": Vector3.UP})


func _p4g_props_ray(center: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 1.0, center + Vector3.DOWN * 1.0, Layers.PROPS)
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func _t72_persistent_ice_physics() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var crate := _air_crate(base + Vector3(0, 1.6, -8), 20.0)
	var before := orb.get_stats()
	var watch := {"contacts": 0, "target_speed": -1.0, "ice_speed": -1.0, "frozen": false}
	var contact := func(kind: StringName, data: Dictionary):
		if kind == &"water_orb_impact":
			watch.contacts += 1
			watch.frozen = data.get("frozen", false)
			watch.target_speed = crate.linear_velocity.length()
			var ice := orb.get_persistent_ice()
			if ice.size() == 1: watch.ice_speed = ice[0].linear_velocity.length()
	orb.fx_event.connect(contact)
	_p4c_rmb(true)
	await _frames(20)
	var formed: bool = orb.phase == "hold" and not orb.is_frozen()
	_p4f_c()
	var frozen := orb.is_frozen()
	await _aim_settle(MaterialResponseSystem.body_center(crate))
	_p4c_rmb(false)
	var finished: bool = await _wait_until(func(): return orb.phase == "", 2.0)
	orb.fx_event.disconnect(contact)
	# Medir a velocidade após a integração física; manter também o snapshot observado no callback.
	await _frames(4)
	var target_speed := crate.linear_velocity.length()
	var impulse: float = orb.get_stats().impulse_ns - before.impulse_ns
	var expected_impulse := crate.mass * orb.tuning.ice_max_target_delta_v
	var created := orb.get_persistent_ice()
	if created.size() != 1:
		_record("T72", "Gelo lançado materializa corpo físico, repousa, recebe Ar e respeita orçamento", false,
			{"formed": formed, "frozen": frozen, "finished": finished, "bodies": created.size(), "stats": orb.get_stats(), "impact": watch})
		await main.request_world_reset()
		return
	var body: IceBody = created[0]
	var born := body.global_position
	var shape := body.get_node("IceCollision") as CollisionShape3D
	var expected_mass := orb.volume_liters * 0.001 * orb.tuning.ice_density
	var physical: bool = shape.shape is SphereShape3D and is_equal_approx((shape.shape as SphereShape3D).radius, orb.radius()) \
		and is_equal_approx(body.mass, expected_mass) and body.continuous_cd and not body.freeze \
		and body.collision_layer == Layers.PROPS and body.collision_mask == (Layers.TERRAIN | Layers.PLAYER | Layers.PROPS) \
		and body.is_in_group(DebrisBudget.GROUP) and body.get_node("Crystal") is MeshInstance3D \
		and BodyMaterialLibrary.of_body(body).id == BodyMaterialLibrary.ICE and not body.has_meta("volume_m3")
	var single: bool = formed and frozen and finished and watch.contacts == 1 and watch.frozen \
		and orb.get_stats().impacts == before.impacts + 1 and orb.get_stats().ice_spawned == before.ice_spawned + 1 \
		and orb.get_stats().body_impacts == before.body_impacts + 1 and absf(impulse - expected_impulse) < 0.001 \
		and absf(target_speed - orb.tuning.ice_max_target_delta_v) < 0.02 \
		and float(watch.ice_speed) < 0.0001
	var rested: bool = await _wait_until(func(): return body.sleeping, 5.0)
	var ground := _ground_at(body.global_position)
	var height := body.global_position.y - ground.y
	var ray := _p4g_props_ray(body.global_position)
	# O CharacterBody real consulta seu próprio volume contra o gelo, sem mover nenhum corpo.
	var from := Transform3D(Basis.IDENTITY, Vector3(body.global_position.x, ground.y + 0.1, body.global_position.z + 2.0))
	var player_blocked: bool = player.test_move(from, Vector3(0, 0, -3.0))
	var solid: bool = rested and body.global_position.y < born.y - 0.2 and absf(height - body.ice_radius) < 0.08 \
		and ray.get("collider") == body and player_blocked
	ab.select(0)
	await _aim_settle(body.global_position)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var not_rock: bool = not earth.validate_target().ok
	ab.select(3)
	var gust: AirGust = ab.get_ability(&"air_gust")
	var start := body.global_position
	var pushed0: int = gust.get_stats().bodies_pushed
	await _aim_settle(body.global_position)
	var wave := _air_press(ab, gust)
	var peak_speed := 0.0
	for i in 45:
		await _frames(1)
		peak_speed = maxf(peak_speed, body.linear_velocity.length())
	var air: bool = wave >= 0 and gust.get_stats().bodies_pushed == pushed0 + 1 and peak_speed > 0.2 \
		and body.global_position.distance_to(start) > 0.1
	# O primeiro caso acima usa RMB/C e o contato real. A grade abaixo só economiza lançamentos no teste de teto.
	base = await _p3_lab(1)
	var filled := true
	for z: float in [-6.0, -10.0]:
		for x: float in [-3.0, -1.0, 1.0, 3.0]:
			var p := _ground_at(base + Vector3(x, 0, z)) + Vector3.UP * (orb.radius() + 0.06)
			filled = (_p4g_fixture(orb, p) != null) and filled
	await _frames(45)
	var cap := clampi(orb.tuning.ice_max_bodies, 1, 16)
	filled = filled and orb.get_persistent_ice().size() == cap and cap == 8
	# 185 ticks (~3 s a 60 Hz), oito corpos da sessão e um novo gelo controlado/lançado.
	player.camera_rig.set_view(0.0, deg_to_rad(20.0))
	ab.begin_water_orb()
	ab.freeze_water_orb()
	await _frames(20)
	var clock := {"last": Time.get_ticks_usec()}
	var frame_ms := PackedFloat32Array()
	var sample := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - int(clock.last)) / 1000.0)
		clock.last = now
	get_tree().process_frame.connect(sample)
	for i in 185:
		if i == 60: ab.release_water_orb()
		await _frames(1)
	get_tree().process_frame.disconnect(sample)
	if not frame_ms.is_empty(): frame_ms.remove_at(0)
	var timings := _stats(frame_ms)
	timings["p99"] = _percentile(frame_ms, 0.99)
	timings["physics_ticks"] = 185
	_metrics["p4g_persistent_ice_frame_ms"] = timings
	var windowed := not _mode.begins_with("headless")
	var perf: bool = not windowed or (frame_ms.size() >= 120 and timings.get("p95", 999.0) <= 20.0 \
		and timings.p99 <= 33.0 and timings.get("max", 999.0) <= 50.0)
	ab.cancel_all()
	var oldest: IceBody = orb.get_persistent_ice()[0] if not orb.get_persistent_ice().is_empty() else null
	var eviction0: int = orb.get_stats().ice_evicted
	var extra := _p4g_fixture(orb, _ground_at(base + Vector3(5, 0, -6)) + Vector3.UP * (orb.radius() + 0.06))
	var evicted: bool = extra != null and is_instance_valid(oldest) and oldest.is_queued_for_deletion() \
		and orb.get_stats().ice_evicted == eviction0 + 1 and orb.get_persistent_ice().size() == cap
	await _frames(2)
	var survivors := orb.get_persistent_ice()
	var protected: IceBody = survivors[0] if not survivors.is_empty() else null
	if protected != null: protected.set_meta(DebrisBudget.EARTH_HELD_META, true)
	extra = _p4g_fixture(orb, _ground_at(base + Vector3(-5, 0, -6)) + Vector3.UP * (orb.radius() + 0.06))
	var skipped: bool = extra != null and protected != null and not protected.is_queued_for_deletion() and not protected.can_retire()
	for ice: IceBody in orb.get_persistent_ice(): ice.set_meta(DebrisBudget.EARTH_HELD_META, true)
	var rejected0: int = orb.get_stats().ice_spawn_rejected
	var denied := _p4g_fixture(orb, _ground_at(base + Vector3(5, 0, -10)) + Vector3.UP * (orb.radius() + 0.06))
	var guarded: bool = denied == null and orb.get_persistent_ice().size() == cap \
		and orb.get_stats().ice_spawn_rejected == rejected0 + 1 and orb.get_stats().last_ice_spawn_reason == "capacity_in_use"
	for ice: IceBody in orb.get_persistent_ice(): ice.remove_meta(DebrisBudget.EARTH_HELD_META)
	if _screens:
		player.camera_rig.set_view(0.0, deg_to_rad(-12.0))
		await _frames(2)
		await _snap("p4g_persistent_ice")
	_record("T72", "Gelo lançado materializa corpo físico, repousa, recebe Ar e respeita orçamento",
		single and physical and solid and not_rock and air and filled and evicted and skipped and guarded and perf,
		{"actual_launch": {"ok": single, "impact": watch, "target_speed_after_4_ticks": target_speed,
			"impulse_ns": impulse, "expected_impulse_ns": expected_impulse}, "physical_contract": physical, "mass_kg": expected_mass,
		"natural_rest": rested, "height_over_ground": height, "player_blocked": player_blocked, "solid": solid,
		"earth_rejected": not_rock, "air_pushed": air, "air_peak_speed": peak_speed,
		"capacity": {"factory_fixture": true, "filled_eight": filled, "oldest_evicted": evicted, "held_skipped": skipped, "all_held_rejected": guarded},
		"frame_ms": timings, "frame_gate_applied": windowed})
	player.input_enabled = false
	await main.request_world_reset()


func _t73_persistent_ice_heat_lifecycle() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var orb: WaterOrb = jet.orb
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var listeners0 := materials.melted.get_connections().size()
	var center := _ground_at(base + Vector3(0, 0, -7)) + Vector3.UP * (orb.radius() + 0.06)
	var body := _p4g_fixture(orb, center)
	if body == null:
		_record("T73", "Fogo funde gelo pelo estado térmico real; save preserva e reset/load limpam", false,
			{"fixture_created": false, "stats": orb.get_stats()})
		await main.request_world_reset()
		return
	var id := body.get_instance_id()
	var state := materials.state_of(body)
	var initial := state.temperature
	await _seconds(1.2)
	var ambient: bool = is_instance_valid(body) and not state.consumed and state.temperature <= initial + 0.001 \
		and initial < state.material.melt_temperature
	var melt_watch := {"count": 0, "consumed_before_fx": false, "collision_removed": false}
	var melted := func(candidate: Node3D):
		if candidate.get_instance_id() == id:
			melt_watch.count += 1
			melt_watch.consumed_before_fx = state.consumed
			var rigid := candidate as RigidBody3D
			melt_watch.collision_removed = rigid != null and rigid.collision_layer == 0 and rigid.collision_mask == 0
	materials.melted.connect(melted)
	ab.select(2)
	var before_hits: int = fire.get_stats().body_hits
	await _aim_settle(body.global_position)
	var first := _fire_press(ab, fire)
	var warmed: bool = await _wait_until(func(): return fire.get_stats().body_hits > before_hits, 1.5)
	var after_first := state.temperature
	var first_solid: bool = warmed and is_instance_valid(body) and not state.consumed \
		and after_first > initial and after_first < state.material.melt_temperature
	await _wait_until(func(): return fire.get_stats().cooldown_left <= 0.0, 1.0)
	var last_center := body.global_position if is_instance_valid(body) else center
	await _aim_settle(last_center)
	var second := _fire_press(ab, fire)
	var removed: bool = await _wait_until(func(): return instance_from_id(id) == null, 1.5)
	await _frames(2)
	var no_collision: bool = _p4g_props_ray(last_center).is_empty()
	var no_state: bool = not materials._states.has(id)
	materials.melted.disconnect(melted)
	var no_listener: bool = materials.melted.get_connections().size() == listeners0
	var fusion: bool = first >= 0 and second >= 0 and first_solid and removed and no_collision and no_state \
		and state.temperature >= state.material.melt_temperature and state.consumed and not state.burning \
		and melt_watch.count == 1 and melt_watch.consumed_before_fx and melt_watch.collision_removed and no_listener
	# Salvar terreno não deve alterar o corpo vivo. Repouso vem do solver, sem freeze/sleep artificial.
	ab.select(1)
	body = _p4g_fixture(orb, center)
	var lifecycle := {"save": false, "select_escape": false, "load": false, "reset": false}
	if body != null:
		var rested: bool = await _wait_until(func(): return body.sleeping, 5.0)
		var transform := body.global_transform
		var speed := body.linear_velocity
		var frozen := body.freeze
		var sleeping := body.sleeping
		var saved: bool = await main.request_world_save("p4g_ice_session")
		lifecycle.save = saved and rested and is_instance_valid(body) and body.global_transform.is_equal_approx(transform) \
			and body.linear_velocity.is_equal_approx(speed) and body.freeze == frozen and body.sleeping == sleeping
		ab.select(0)
		_p4a_key(KEY_ESCAPE, true)
		Input.flush_buffered_events()
		_p4a_key(KEY_ESCAPE, false)
		Input.flush_buffered_events()
		await _frames(2)
		lifecycle.select_escape = is_instance_valid(body) and orb.get_persistent_ice().size() == 1
		var old_id := body.get_instance_id()
		var loaded: bool = await main.request_world_load("p4g_ice_session")
		await _frames(2)
		lifecycle.load = loaded and not is_instance_valid(body) and orb.get_persistent_ice().is_empty() and not materials._states.has(old_id)
	base = await _p3_lab(1)
	body = _p4g_fixture(orb, _ground_at(base + Vector3(0, 0, -7)) + Vector3.UP * (orb.radius() + 0.06))
	var spawned: bool = body != null
	var reset_ok: bool = await main.request_world_reset()
	await _frames(2)
	lifecycle.reset = spawned and reset_ok and not is_instance_valid(body) and orb.get_persistent_ice().is_empty()
	# Espaço impossível: recusa da mesma factory, mantendo a parede e sem inventar outro impacto.
	base = await _p3_lab(1)
	center = base + Vector3(0, 2, -6)
	var wall := _p36_thin_wall(center, Vector3(3, 3, 3))
	await _frames(2)
	var wall_transform := wall.global_transform
	var before := orb.get_stats()
	var denied := _p4g_fixture(orb, center)
	var no_space: bool = denied == null and orb.get_stats().ice_spawn_rejected == before.ice_spawn_rejected + 1 \
		and orb.get_stats().last_ice_spawn_reason == "no_space" and orb.get_stats().impacts == before.impacts \
		and orb.get_persistent_ice().is_empty() and wall.global_transform.is_equal_approx(wall_transform)
	_record("T73", "Fogo funde gelo pelo estado térmico real; save preserva e reset/load limpam",
		ambient and fusion and lifecycle.save and lifecycle.select_escape and lifecycle.load and lifecycle.reset and no_space,
		{"ambient_does_not_melt": ambient, "initial_temperature": initial, "temperature_after_first_fire": after_first,
		"temperature_at_melt": state.temperature, "two_actual_fire_bolts": fusion, "melt": melt_watch,
		"collision_removed": no_collision, "material_reference_removed": no_state, "signal_listener_removed": no_listener, "session": lifecycle,
		"no_space_factory_fixture": no_space})
	ab.cancel_all()
	player.input_enabled = false
	await main.request_world_reset()
