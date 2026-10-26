extends "res://scripts/dev/p2_selftest.gd"
## Roteiro automatizado do P3: roda P0 + P1 + P2 (regressão) e depois os testes dos quatro
## elementos, na mesma cena real.
##
##   godot --headless --path . res://scenes/main.tscn -- --p3-selftest
##   godot --path . res://scenes/main.tscn -- --p3-selftest --p3-screenshots
##   opcional: --report=<caminho.json>, --only=T38,T29 (T1 e baseline sempre rodam)
##
## Código de saída: 0 = todos PASS, 1 = algum FAIL, 2 = watchdog.

const P3_WATCHDOG_S := 2100.0
const LAB_P3 := Vector3(-34, 0.6, 60)

var materials: MaterialResponseSystem


func _ready() -> void:
	materials = get_parent().materials
	super._ready()
	if OS.get_cmdline_user_args().has("--p3-screenshots") and DisplayServer.get_name() != "headless":
		_screens = true


func _report_prefix() -> String:
	return super._report_prefix() if _persist_phase != "" else "p3_selftest"


func _watchdog_seconds() -> float:
	return P3_WATCHDOG_S


func _evidence_dir() -> String:
	return "res://docs/evidence/p3/" if OS.has_feature("editor") else "user://"


func _screens_dir() -> String:
	return "res://docs/evidence/p3/screens/" if OS.has_feature("editor") else "user://screens_p3/"


func _log(msg: String) -> void:
	print("[P3TEST] ", msg)


func _run_tests() -> bool:
	var ok: bool = await super._run_tests()
	if not ok or _persist_phase != "":
		return ok
	_log("--- testes P3 ---")
	if _should_run("T38"): await _t38_material_states()
	if _should_run("T28"): await _t28_controller()
	if _should_run("T29"): await _t29_earth_lift_throw()
	if _should_run("T30"): await _t30_earth_breaks_tower()
	if _should_run("T31"): await _t31_water_jet()
	if _should_run("T32"): await _t32_fire_burst()
	if _should_run("T33"): await _t33_water_puts_out_fire()
	if _should_run("T34"): await _t34_air_gust()
	if _should_run("T35"): await _t35_fire_burns_tower()
	if _should_run("T36"): await _t36_cross_sequence()
	if _should_run("T37"): await _t37_powers_benchmark()
	return true


# --- T28: seleção de elemento e roteamento do LMB ----------------------------------------

func _t28_controller() -> void:
	var ab: AbilityController = main.abilities
	await main.request_world_reset()
	player.input_enabled = true
	var details := {"poderes": ab.abilities.map(func(a): return "%s/%s/%s" % [a.element, a.id, a.input_mode])}
	# 1–4 pelo evento de input real (InputEventAction), como o teclado gera.
	var selected := []
	for i in ab.abilities.size():
		_send_action(ElementalKeys.ACTIONS[i], true)
		_send_action(ElementalKeys.ACTIONS[i], false)
		await get_tree().physics_frame
		selected.append(ab.current)
	var sel_ok := true
	for i in selected.size():
		sel_ok = sel_ok and selected[i] == i
	_send_action(ElementalKeys.ACTIONS[0], true)
	_send_action(ElementalKeys.ACTIONS[0], false)
	await get_tree().physics_frame
	# Clique com o mouse livre (o selftest não captura o mouse) e exigência de captura: ignorado.
	var uses := []
	var cb := func(id, phase): uses.append("%s:%s" % [id, phase])
	ab.ability_used.connect(cb)
	# Em janela o mouse pode ter sido preso no meio do roteiro (qualquer clique na janela o prende,
	# third_person_camera): na bateria em janela o clique "sem captura" agiu porque estava preso.
	var captured_before := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ab.require_captured_mouse = true
	_send_action(&"ability_use", true)
	_send_action(&"ability_use", false)
	await get_tree().physics_frame
	var ignored_uncaptured := uses.is_empty()
	# Sem exigência de captura: o LMB chega ao poder atual.
	ab.require_captured_mouse = false
	player.camera_rig.set_view(0.0, deg_to_rad(-35.0))
	await _seconds(0.3)
	_send_action(&"ability_use", true)
	await get_tree().physics_frame
	_send_action(&"ability_use", false)
	await get_tree().physics_frame
	var routed := uses.size() >= 2
	# Durante o reset nada age.
	main.request_world_reset.call_deferred()
	await _wait_until(func(): return svc.is_resetting(), 2.0)
	var during_reset := ab.use_pressed()
	await _wait_until(func(): return not svc.is_resetting() and not player.is_frozen(), 10.0)
	ab.ability_used.disconnect(cb)
	player.input_enabled = false
	var ok: bool = sel_ok and ignored_uncaptured and routed and not during_reset
	details.merge({"selecionados_por_1_4": selected, "mouse_estava_preso": captured_before, "clique_sem_mouse_capturado_ignorado": ignored_uncaptured,
		"lmb_roteado": uses, "agiu_durante_reset": during_reset})
	_record("T28", "1–4 escolhem o elemento; LMB chega ao poder; clique de recaptura não age; nada age no reset", ok, details)
	for ch in props.get_children():
		ch.queue_free()


# --- T29: Terra — erguer e arremessar ---------------------------------------------------

func _t29_earth_lift_throw() -> void:
	var ab: AbilityController = main.abilities
	await main.request_world_reset()
	var base := LAB_P3 + Vector3(0, 0, 8)
	await _prepare_area(base, AABB(LAB_P3 - Vector3(8, 4, 16), Vector3(16, 10, 30)))
	ab.select(0)
	ab.require_captured_mouse = false
	player.input_enabled = true
	player.camera_rig.set_view(0.0, deg_to_rad(-35.0))
	await _seconds(0.4)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var pressed := ab.use_pressed()
	var rock := earth.rock
	var max_step := 0.0
	var prev := EarthLiftThrow.center_of(rock) if rock != null else Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	var held_ms := -1
	while rock != null and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
		if not is_instance_valid(rock):
			break
		max_step = maxf(max_step, EarthLiftThrow.center_of(rock).distance_to(prev))
		prev = EarthLiftThrow.center_of(rock)
		if held_ms < 0 and earth.phase == "held" and EarthLiftThrow.center_of(rock).distance_to(earth.hold_target()) < 1.0:
			held_ms = Time.get_ticks_msec() - t0
	var hold_err := EarthLiftThrow.center_of(rock).distance_to(earth.hold_target()) if rock != null else INF
	# Alvo: caixa 10 m à frente, sobre o chão.
	var crate := DebugProps.spawn_crate(props, base + Vector3(0, 0.0, -14))
	await _seconds(1.0)
	var c0 := crate.global_position
	_aim_at(crate.global_position)
	await get_tree().physics_frame
	var aim_hit: Dictionary = ab.aim_any(60.0, [rock.get_rid()] as Array[RID])
	ab.use_released()
	await get_tree().physics_frame
	var launch_speed := rock.linear_velocity.length() if rock != null and is_instance_valid(rock) else 0.0
	var trace := []
	for i in 6:
		await _seconds(0.25)
		if is_instance_valid(rock):
			trace.append("%s v=%.1f" % [EarthLiftThrow.center_of(rock).snappedf(0.1), rock.linear_velocity.length()])
	await _seconds(1.5)
	var moved := crate.global_position.distance_to(c0)
	player.input_enabled = false
	var st := earth.get_stats()
	var ok: bool = pressed and rock != null and held_ms >= 0 and hold_err < 1.0 and max_step < 0.5 \
		and launch_speed >= 18.0 and st.hits >= 1 and moved > 2.0
	_record("T29", "Terra: rocha real extraída, suspensa só por forças e arremessada; acerta a caixa e a desloca", ok, {
		"rocha_t": rock.mass / 1000.0 if rock != null and is_instance_valid(rock) else 0.0,
		"ms_ate_suspensa_a_1m": held_ms, "erro_suspensao_m": hold_err, "maior_passo_por_quadro_m": max_step,
		"vel_no_lancamento": launch_speed, "contatos": st.hits, "maior_impulso_Ns": st.max_impulse,
		"caixa_deslocada_m": moved, "mira_acertou": str(aim_hit.get("collider", "nada")), "mira_ponto": str(aim_hit.get("position", "")),
		"caixa_pos": str(c0), "trajetoria": trace})
	await _shot("t29_rocha_arremessada", player.global_position, 0.0, -15.0, false)
	for ch in props.get_children():
		ch.queue_free()


# --- T30: Terra × torre (dano cinético) ----------------------------------------------------

func _t30_earth_breaks_tower() -> void:
	var ab: AbilityController = main.abilities
	await main.request_world_reset()
	await _go_to_tower()
	ab.select(0)
	ab.require_captured_mouse = false
	player.input_enabled = true
	player.camera_rig.set_view(0.0, deg_to_rad(-32.0))
	await _seconds(0.4)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	# Mira no PÉ do pilar da frente à esquerda: a rocha (centro 1 meia altura acima do ponto
	# mirado) acerta o pé e/ou o bloco do meio; o bloco de cima só pode cair pelo grafo.
	var target: StructurePiece = null
	var above: StructurePiece = null
	for p in structures.get_pieces():
		var d := p.home.origin - structures.tower_origin
		if p.kind == "pilar0" and d.x < 0 and d.z > 0:
			if absf(p.home.origin.y - 0.8) < 0.1:
				target = p
			elif absf(p.home.origin.y - 3.8) < 0.1:
				above = p
	var s0 := structures.get_stats()
	var m0: Dictionary = main.materials.get_stats()
	ab.use_pressed()
	var rock := earth.rock
	var held := await _wait_until(func(): return earth.phase == "held", 4.0)
	await _seconds(0.5)
	_aim_at(target.global_position)
	await get_tree().physics_frame
	var aim_hit: Dictionary = ab.aim_any(60.0, [rock.get_rid()] as Array[RID]) if is_instance_valid(rock) else {}
	ab.use_released()
	var trace := []
	for i in 6:
		await _seconds(0.15)
		if is_instance_valid(rock):
			trace.append("%s v=%.1f" % [EarthLiftThrow.center_of(rock).snappedf(0.1), rock.linear_velocity.length()])
	await _wait_until(func(): return above.released, 2.0)
	await _wait_structures_idle(3.0)
	await _seconds(1.5)
	player.input_enabled = false
	var s1 := structures.get_stats()
	var m1: Dictionary = main.materials.get_stats()
	var by_impact: int = m1.kinetic_breaks - m0.kinetic_breaks
	var released_now := structures.released_count()
	var ok: bool = target != null and above != null and above.released and by_impact >= 1 \
		and released_now > by_impact and s1.broken > s0.broken
	_record("T30", "Terra × torre: rocha arremessada solta bloco(s) de pilar por impacto e o grafo derruba o bloco de cima", ok, {
		"pe_mirado": target.name if target else "", "pe_solto": target.released if target else false,
		"bloco_de_cima": above.name if above else "", "bloco_de_cima_solto": above.released if above else false,
		"soltas_por_impacto": by_impact, "soltas_no_total": released_now,
		"ultima_quebra": s1.last_break, "quebras_por_impacto": by_impact,
		"maior_impulso_Ns": earth.get_stats().max_impulse, "soltas_total": structures.released_count(),
		"suspensa": held, "mira_acertou": str(aim_hit.get("collider", "nada")), "alvo_pos": str(target.global_position),
		"trajetoria": trace})
	await _shot("t30_rocha_derruba_pilar", structures.tower_origin + Vector3(0, 0.5, 16), 0.0, -10.0)
	await main.request_world_reset()


# --- T31: Água — jato ----------------------------------------------------------------------

func _t31_water_jet() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(1)
	var jet: WaterJet = ab.get_ability(&"water_jet")
	# Caixa escondida atrás de um morro de terreno (esfera aditiva entre o jogador e ela).
	var hidden := DebugProps.spawn_crate(props, base + Vector3(-5, 0, -7))
	var wall := svc.add_sphere(base + Vector3(-2.5, 0.8, -3.6), 1.4)
	var wall_up := await _wait_until(func(): return not svc.raycast_terrain(ab.hand_position(),
		MaterialResponseSystem.body_center(hidden)).is_empty(), 3.0)
	await _seconds(1.0)
	var h0 := hidden.global_position
	var s0 := jet.get_stats()
	await _hold_on(hidden, 1.0)
	var s1 := jet.get_stats()
	var hidden_moved := hidden.global_position.distance_to(h0)
	var hidden_wet := materials.state_of(hidden).wetness
	# Caixa à vista, 6 m à frente: 1,5 s de jato (a mira acompanha a caixa, como o jogador faria).
	var crate := DebugProps.spawn_crate(props, base + Vector3(0, 0, -6))
	await _seconds(1.0)
	var c0 := crate.global_position
	var pressed := await _hold_on(crate, 1.5)
	await _seconds(1.0)
	var moved := crate.global_position.distance_to(c0)
	var cs := materials.state_of(crate)
	var s2 := jet.get_stats()
	player.input_enabled = false
	var ok: bool = wall.ok and wall_up and hidden_moved < 0.05 and hidden_wet < 0.001 \
		and s1.terrain_ticks > s0.terrain_ticks and s1.body_ticks == s0.body_ticks \
		and pressed and moved > 1.0 and cs.wetness >= 0.3
	_record("T31", "Água: jato empurra a caixa por força contínua e a molha; caixa atrás de terreno não é atingida", ok, {
		"morro_criado": wall.ok, "morro_bloqueia_visada": wall_up, "escondida_deslocada_m": hidden_moved,
		"escondida_umidade": hidden_wet, "quadros_no_terreno": s1.terrain_ticks - s0.terrain_ticks,
		"quadros_na_escondida": s1.body_ticks - s0.body_ticks, "caixa_deslocada_m": moved,
		"caixa_estado": cs.describe(), "quadros_na_caixa": s2.body_ticks - s1.body_ticks})
	await _shot("t31_jato_dagua", player.global_position, 0.0, -15.0, false)
	for ch in props.get_children():
		ch.queue_free()


# --- T32: Fogo — rajada --------------------------------------------------------------------

func _t32_fire_burst() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(2)
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var cases := {}
	# a) Rocha real extraída do terreno: só aquece.
	var ground := svc.raycast_terrain(base + Vector3(6, 5, -12), base + Vector3(6, -10, -12))
	var out: Dictionary = svc.extract_rock(ground.position, Vector3.UP, 1.2, props, Vector3.BACK) if not ground.is_empty() else {"bodies": []}
	var rock: RigidBody3D = out.bodies[0] if not out.bodies.is_empty() else null
	if rock != null:
		await _seconds(1.5)
		await _tap_at(MaterialResponseSystem.body_center(rock))
		await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
		var rs := materials.state_of(rock)
		cases["a_rocha_so_aquece"] = {"estado": rs.describe() if rs else "sem material", "massa_kg": rock.mass,
			"ok": rs != null and not rs.burning and rs.temperature > 60.0}
	else:
		cases["a_rocha_so_aquece"] = {"extracao": str(out.get("result")), "ok": false}
	# b) Madeira molhada (60%): a 1ª rajada gasta o calor secando; a 2ª acende.
	var wet := DebugProps.spawn_crate(props, base + Vector3(-5, 0, -7))
	await _seconds(0.8)
	_apply_direct(ElementalEvent.Kind.WET, wet, 0.6)
	var ws := materials.state_of(wet)
	await _tap_at(MaterialResponseSystem.body_center(wet))
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	var after_1 := ws.describe()
	var burn_1 := ws.burning
	await _tap_at(MaterialResponseSystem.body_center(wet))
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	cases["b_molhada_resiste_1a_rajada"] = {"apos_1a": after_1, "apos_2a": ws.describe(), "ok": not burn_1 and ws.burning}
	_apply_direct(ElementalEvent.Kind.WET, wet, 1.0)
	# c) Caixa seca acende, queima, consome combustível e carboniza; a vizinha (0,5 m de vão) pega fogo.
	var a := DebugProps.spawn_crate(props, base + Vector3(0, 0, -7))
	var b := DebugProps.spawn_crate(props, base + Vector3(1.5, 0, -7))
	await _seconds(0.8)
	var fired := await _tap_at(MaterialResponseSystem.body_center(a))
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	var as_ := materials.state_of(a)
	var bs := materials.state_of(b)
	var a_lit := as_.burning
	var t0 := Time.get_ticks_msec()
	var b_lit := await _wait_until(func(): return bs.burning, 15.0)
	var spread_s := (Time.get_ticks_msec() - t0) / 1000.0
	var charred := await _wait_until(func(): return as_.charred or as_.consumed, 12.0)
	cases["c_acende_espalha_carboniza"] = {"tocou": fired, "acesa": a_lit, "vizinha_acesa": b_lit,
		"s_ate_vizinha": spread_s, "estado": as_.describe(), "combustivel": as_.fuel,
		"chamas_fx": (main.fx as ElementalFx).get_stats().flames_created,
		"ok": fired and a_lit and b_lit and charred and as_.fuel < as_.material.fuel_seconds}
	player.input_enabled = false
	var ok: bool = cases.values().all(func(v): return v.ok)
	_record("T32", "Fogo: rajada acende madeira, queima, carboniza e espalha; molhada resiste à 1ª; rocha só aquece", ok, cases)
	await _shot("t32_fogo", player.global_position, 0.0, -15.0, false)
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


# --- T33: Água × Fogo ----------------------------------------------------------------------

func _t33_water_puts_out_fire() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(2)
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var crate := DebugProps.spawn_crate(props, base + Vector3(0, 0, -6))
	await _seconds(0.8)
	await _tap_at(MaterialResponseSystem.body_center(crate))
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	var cs := materials.state_of(crate)
	var lit := cs.burning
	await _seconds(2.5)
	var intensity := cs.intensity
	var causes := []
	var cb := func(body, cause):
		if body == crate:
			causes.append(cause)
	materials.extinguished.connect(cb)
	var fx: ElementalFx = main.fx
	var steam0: int = fx.get_stats().steam
	ab.select(1)
	var t0 := Time.get_ticks_msec()
	await _hold_on(crate, 4.0, func(): return not cs.burning)
	var out_s := (Time.get_ticks_msec() - t0) / 1000.0
	materials.extinguished.disconnect(cb)
	player.input_enabled = false
	var steam: int = fx.get_stats().steam - steam0
	var ok: bool = lit and intensity > 0.8 and not cs.burning and out_s <= 3.0 and causes == ["água"] and steam >= 1
	_record("T33", "Água × Fogo: o jato apaga a caixa em chamas em ≤ 3 s (causa: água) e solta vapor", ok, {
		"acesa": lit, "intensidade_antes": intensity, "s_ate_apagar": out_s, "causas": causes,
		"estado": cs.describe(), "vapor": steam})
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


# --- T34: Ar — rajada ----------------------------------------------------------------------

func _t34_air_gust() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(3)
	var gust: AirGust = ab.get_ability(&"air_gust")
	# Leque à frente: caixa a ~5 m, fogo pequeno e grande, e uma caixa atrás de um morro.
	var hidden := DebugProps.spawn_crate(props, base + Vector3(-3, 0, -7))
	var wall := svc.add_sphere(base + Vector3(-1.6, 0.6, -3.8), 1.2)
	var crate := DebugProps.spawn_crate(props, base + Vector3(1.5, 0, -5))
	var small := DebugProps.spawn_crate(props, base + Vector3(0.3, 0, -2.2))
	var big := DebugProps.spawn_crate(props, base + Vector3(1.2, 0, -3.0))
	var wall_up := await _wait_until(func(): return not svc.raycast_terrain(ab.hand_position(),
		MaterialResponseSystem.body_center(hidden)).is_empty(), 3.0)
	await _seconds(1.0)
	_apply_direct(ElementalEvent.Kind.HEAT, small, 400.0)
	_apply_direct(ElementalEvent.Kind.HEAT, big, 400.0)
	var ss := materials.state_of(small)
	var bs := materials.state_of(big)
	ss.intensity = 0.2
	bs.intensity = 0.6
	var c0 := crate.global_position
	var h0 := hidden.global_position
	await _tap_at(base + Vector3(0, 0.5, -6))
	await get_tree().physics_frame
	var crate_v := crate.linear_velocity.length()
	var hidden_v := hidden.linear_velocity.length()
	var small_out := not ss.burning
	var big_i := bs.intensity
	var g := gust.last_gust
	await _seconds(1.5)
	var crate_moved := crate.global_position.distance_to(c0)
	var hidden_moved := hidden.global_position.distance_to(h0)
	# Rocha real (extraída), à mesma faixa de distância: quase não se mexe.
	var ground := svc.raycast_terrain(base + Vector3(5, 5, -12), base + Vector3(5, -10, -12))
	var out: Dictionary = svc.extract_rock(ground.position, Vector3.UP, 1.2, props, Vector3.RIGHT) if not ground.is_empty() else {"bodies": []}
	var rock: RigidBody3D = out.bodies[0] if not out.bodies.is_empty() else null
	var rock_v := INF
	var rock_mass := 0.0
	var rock_in_gust := false
	if rock != null:
		await _seconds(1.5)
		var rc := MaterialResponseSystem.body_center(rock)
		var away := Vector3(rc.x - ground.position.x, 0.0, rc.z - ground.position.z)
		away = away.normalized() if away.length() > 0.1 else Vector3.BACK
		player.teleport_to(Vector3(rc.x, rc.y, rc.z) + away * 4.5)
		await _seconds(0.8)
		await _tap_at(rc)
		await get_tree().physics_frame
		rock_v = rock.linear_velocity.length()
		rock_mass = rock.mass
		rock_in_gust = (gust.last_gust.get("hit", []) as Array).has(rock)
	player.input_enabled = false
	var ok: bool = wall.ok and wall_up and crate_v >= 4.0 and crate_moved > 2.0 and hidden_v < 0.05 \
		and hidden_moved < 0.05 and small_out and bs.burning and big_i > 0.75 \
		and rock != null and rock_in_gust and rock_v < crate_v / 10.0
	_record("T34", "Ar: rajada lança a caixa, mal mexe a rocha, não passa terreno; apaga fogo fraco e aviva o forte", ok, {
		"morro_bloqueia_visada": wall_up, "caixa_vel": crate_v, "caixa_deslocada_m": crate_moved,
		"escondida_vel": hidden_v, "escondida_deslocada_m": hidden_moved,
		"corpos_na_rajada": (g.get("hit", []) as Array).size(), "bloqueados_por_terreno": g.get("blocked", -1),
		"fogo_fraco_apagou": small_out, "fogo_forte_intensidade": big_i, "rocha_kg": rock_mass, "rocha_vel": rock_v, "rocha_na_rajada": rock_in_gust})
	await _shot("t34_rajada_de_ar", player.global_position, 0.0, -15.0, false)
	for ch in props.get_children():
		ch.queue_free()
	materials.clear()


# --- T35: Fogo × torre (2º andar de madeira) ------------------------------------------------

func _t35_fire_burns_tower() -> void:
	var ab: AbilityController = main.abilities
	var fx: ElementalFx = main.fx
	await main.request_world_reset()
	await _go_to_tower()
	ab.select(2)
	ab.require_captured_mouse = false
	player.input_enabled = true
	await _seconds(0.4)
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var o := structures.tower_origin
	var low: Array[StructurePiece] = []  # bloco de baixo de cada pilar de madeira da frente
	var front_slabs: Array[StructurePiece] = []
	var back: Array[StructurePiece] = []  # madeira e placas de trás: devem ficar
	var wood := 0
	for p in structures.get_pieces():
		var d := p.home.origin - o
		wood += int(p.material_id == BodyMaterialLibrary.WOOD)
		if p.kind == "pilar1" and d.z > 0 and d.y < 6.5:
			low.append(p)
		elif p.kind == "laje2" and d.z > 0:
			front_slabs.append(p)
		elif (p.kind == "pilar1" or p.kind == "laje2") and d.z < 0:
			back.append(p)
	var s0 := structures.get_stats()
	var fx0: Dictionary = fx.get_stats()
	for p in low:
		await _tap_at(MaterialResponseSystem.body_center(p))
		await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	var lit := low.all(func(p): return materials.state_of(p).burning)
	var t0 := Time.get_ticks_msec()
	var fell := await _wait_until(func(): return front_slabs.all(func(p): return p.released), 45.0)
	var fell_s := (Time.get_ticks_msec() - t0) / 1000.0
	await _wait_structures_idle(3.0)
	await _seconds(1.0)
	player.input_enabled = false
	var s1 := structures.get_stats()
	var fx1: Dictionary = fx.get_stats()
	var back_held := back.all(func(p): return not p.released)
	var consumed: int = s1.consumed - s0.consumed
	await _shot("t35_fogo_derruba_metade_de_cima", o + Vector3(0, 0.5, 16), 0.0, -10.0)
	# Reset: torre de volta intacta, sem fogo nem estados.
	await main.request_world_reset()
	await get_tree().physics_frame
	var rebuilt := structures.get_pieces()
	var reset_ok: bool = rebuilt.size() == 36 and rebuilt.all(func(p): return not p.released and p.visible) \
		and materials.burning_count() == 0 and materials.get_stats().tracked == 0
	var ok: bool = wood == 8 and low.size() == 2 and front_slabs.size() == 2 and lit and fell and back_held \
		and consumed >= 2 and fx1.flames_created - fx0.flames_created >= 2 and reset_ok
	_record("T35", "Fogo × torre: queimar os 2 pilares de madeira da frente derruba as placas de cima pelo grafo; reset remonta", ok, {
		"blocos_de_madeira": wood, "acesos": lit, "placas_da_frente_caidas": fell, "s_ate_cair": fell_s,
		"tras_intactas": back_held, "consumidas": consumed, "soltas": s1.released - s0.released,
		"ultima_quebra": s1.last_break, "chamas_fx": fx1.flames_created - fx0.flames_created,
		"carbonizadas_fx": fx1.charred - fx0.charred, "reset_torre_intacta_sem_estados": reset_ok})


# --- T36: sequência transversal (~20 s) e reset ---------------------------------------------

## Os 4 elementos em sequência, pelo mesmo caminho do jogador (1–4 + LMB), diante da torre:
## Terra arremessa rocha no pilar de pedra → Fogo acende um pilar de madeira e uma caixa →
## Água apaga a caixa → Ar sopra outra caixa → o jogador anda até a torre e apaga o pilar →
## Ar sopra os destroços de pedra. Depois, reset: tudo como antes.
func _t36_cross_sequence() -> void:
	var ab: AbilityController = main.abilities
	var fx: ElementalFx = main.fx
	await main.request_world_reset()
	await _go_to_tower()
	ab.require_captured_mouse = false
	player.input_enabled = true
	var o := structures.tower_origin
	var crate_fire := DebugProps.spawn_crate(props, o + Vector3(1.5, 0.6, 8))
	var crate_air := DebugProps.spawn_crate(props, o + Vector3(3.5, 0.6, 11))
	await _seconds(1.0)
	var steps := {}
	var m0: Dictionary = materials.get_stats()
	var t0 := Time.get_ticks_msec()
	# 1) Terra: rocha arremessada no pé do pilar de pedra da frente à esquerda.
	_send_key(0)
	await get_tree().physics_frame
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var foot := _foot_at(Vector2(-1, 1))
	player.camera_rig.set_view(0.0, deg_to_rad(-32.0))
	await _seconds(0.3)
	_send_action(&"ability_use", true)
	var held := await _wait_until(func(): return earth.phase == "held", 4.0)
	await _seconds(0.4)
	await _aim_settle(foot.global_position)
	_send_action(&"ability_use", false)
	await _wait_until(func(): return materials.get_stats().kinetic_breaks > m0.kinetic_breaks, 2.5)
	await _seconds(1.0)
	steps["1_terra"] = {"suspensa": held, "quebras_por_impacto": materials.get_stats().kinetic_breaks - m0.kinetic_breaks,
		"soltas": structures.released_count(), "ok": held and materials.get_stats().kinetic_breaks > m0.kinetic_breaks}
	# 2) Fogo: pilar de madeira da frente à direita (bloco de baixo) e a caixa.
	_send_key(2)
	await get_tree().physics_frame
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var wood: StructurePiece = null
	for p in structures.get_pieces():
		var d := p.home.origin - o
		if p.kind == "pilar1" and d.x > 0 and d.z > 0 and d.y < 6.5:
			wood = p
	await _tap_at(MaterialResponseSystem.body_center(wood))
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	await _tap_at(MaterialResponseSystem.body_center(crate_fire))
	await _wait_until(func(): return fire.projectiles.is_empty(), 2.0)
	steps["2_fogo"] = {"madeira_acesa": materials.state_of(wood).burning, "caixa_acesa": materials.state_of(crate_fire).burning,
		"ok": materials.state_of(wood).burning and materials.state_of(crate_fire).burning}
	await _seconds(1.5)
	# 3) Água: apaga a caixa.
	_send_key(1)
	await get_tree().physics_frame
	var cs := materials.state_of(crate_fire)
	await _hold_on(crate_fire, 3.0, func(): return not cs.burning)
	steps["3_agua"] = {"caixa": cs.describe(), "madeira_segue_acesa": materials.state_of(wood).burning, "ok": not cs.burning}
	# 4) Ar: sopra a outra caixa e os destroços de pedra caídos.
	_send_key(3)
	await get_tree().physics_frame
	var gust: AirGust = ab.get_ability(&"air_gust")
	var debris := structures.get_pieces().filter(func(p): return p.released and not p.freeze)
	var a0 := crate_air.global_position
	await _tap_at(MaterialResponseSystem.body_center(crate_air))
	await get_tree().physics_frame
	var blown: Array = gust.last_gust.get("hit", [])
	var debris_hit := debris.filter(func(p): return blown.has(p)).size()
	await _seconds(1.5)
	var air_moved := crate_air.global_position.distance_to(a0)
	steps["4_ar"] = {"caixa_deslocada_m": air_moved, "corpos_na_rajada": blown.size(), "destrocos_na_rajada": debris_hit,
		"ok": air_moved > 1.0}
	# 5) O pilar de madeira segue queimando; o jogador ANDA até ~10 m da torre (contornando pela
	#    direita o buraco de onde a rocha saiu: indo na diagonal, caía nele) e o apaga com o jato.
	await _seconds(2.0)
	var walk_from := player.global_position
	player.set_scripted_move(Vector3.RIGHT)
	var walked := await _wait_until(func(): return player.global_position.x > o.x + 4.5, 3.0)
	player.set_scripted_move(Vector3.FORWARD)
	walked = walked and await _wait_until(func(): return player.global_position.z < o.z + 10.0, 4.0)
	player.clear_scripted_move()
	await _seconds(0.3)
	_send_key(1)
	await get_tree().physics_frame
	var ws := materials.state_of(wood)
	var wood_lit := ws.burning
	await _hold_on(wood, 5.0, func(): return not ws.burning)
	steps["5_agua_no_pilar"] = {"andou": walked, "de": str(walk_from - o), "ate": str(player.global_position - o),
		"acesa_antes": wood_lit, "pilar": ws.describe(),
		"ok": walked and wood_lit and not ws.burning}
	# 6) Ar nos destroços de pedra caídos do pilar atingido pela rocha.
	_send_key(3)
	await get_tree().physics_frame
	# O bloco cai num lugar diferente a cada rodada e pode ficar além dos 10 m do Ar (o jogador
	# parou a ~10,4 m dele numa rodada da bateria): anda até o mais próximo se estiver a > 7 m.
	var fallen := structures.get_pieces().filter(func(p): return p.released and not p.freeze and p.visible)
	fallen.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) \
		< b.global_position.distance_to(player.global_position))
	var fallen_hit := 0
	var debris_dist := -1.0
	if not fallen.is_empty():
		var target: StructurePiece = fallen[0]
		var flat := func(): return Vector2(target.global_position.x - player.global_position.x,
			target.global_position.z - player.global_position.z)
		if (flat.call() as Vector2).length() > 7.0:
			var d2: Vector2 = (flat.call() as Vector2).normalized()
			player.set_scripted_move(Vector3(d2.x, 0, d2.y))
			await _wait_until(func(): return (flat.call() as Vector2).length() < 6.0, 3.0)
			player.clear_scripted_move()
			await _seconds(0.3)
		debris_dist = (flat.call() as Vector2).length()
		await _tap_at(MaterialResponseSystem.body_center(target))
		await get_tree().physics_frame
		var blown2: Array = gust.last_gust.get("hit", [])
		fallen_hit = fallen.filter(func(p): return blown2.has(p)).size()
	await _seconds(1.0)
	steps["6_ar_nos_destrocos"] = {"destrocos": fallen.size(), "distancia_m": debris_dist, "destrocos_na_rajada": fallen_hit,
		"ok": fallen_hit >= 1}
	var seq_s := (Time.get_ticks_msec() - t0) / 1000.0
	player.input_enabled = false
	await _shot("t36_sequencia_transversal", o + Vector3(0, 0.5, 16), 0.0, -10.0)
	var before_reset := {"soltas": structures.released_count(), "em_chamas": materials.burning_count(),
		"chamas_fx": fx.get_stats().flames_active, "destrocos": get_tree().get_nodes_in_group(DebrisBudget.GROUP).size()}
	# Reset: torre idêntica, sem estados, sem fogo, poderes parados, nós = baseline.
	var ok_reset: bool = await main.request_world_reset()
	await _seconds(0.5)
	var pieces := structures.get_pieces()
	var off_home := pieces.filter(func(p): return p.global_position.distance_to(p.home.origin) > 0.001 or not p.freeze or p.released or not p.visible)
	var st: Dictionary = materials.get_stats()
	var nodes := get_tree().get_node_count()
	var idle: bool = earth.phase == "" and earth.rock == null and fire.projectiles.is_empty() \
		and not (ab.get_ability(&"water_jet") as WaterJet).active and not ab.holding
	var after := {"reset": ok_reset, "pecas": pieces.size(), "fora_do_lugar": off_home.size(), "estados": st.tracked,
		"em_chamas": st.burning, "chamas_fx": fx.get_stats().flames_active,
		"destrocos": get_tree().get_nodes_in_group(DebrisBudget.GROUP).size(), "nos": nodes, "nos_baseline": _baseline_nodes,
		"poderes_parados": idle}
	var reset_good: bool = ok_reset and pieces.size() == 36 and off_home.is_empty() and st.tracked == 0 and st.burning == 0 \
		and fx.get_stats().flames_active == 0 and after.destrocos == 0 and nodes == _baseline_nodes and idle
	var ok: bool = steps.values().all(func(v): return v.ok) and seq_s <= 30.0 and before_reset.soltas > 0 and reset_good
	_record("T36", "Sequência transversal (Terra → Fogo → Água → Ar diante da torre, ~20 s) e reset devolve tudo ao início", ok, {
		"passos": steps, "duracao_s": seq_s, "antes_do_reset": before_reset, "depois_do_reset": after})


# --- T37: benchmark com os 4 poderes -------------------------------------------------------

## Pior caso do P3: colapso total da torre (4 pés no mesmo quadro, como o T27) + 12 caixas em
## chamas espalhando fogo + Fogo, Água, Ar e Terra usados em sequência, por ~9 s.
## Critério do P2, só em janela: p95 ≤ 20 ms, p99 ≤ 33 ms, máx ≤ 50 ms.
func _t37_powers_benchmark() -> void:
	var ab: AbilityController = main.abilities
	var fx: ElementalFx = main.fx
	await main.request_world_reset()
	await _go_to_tower()
	ab.require_captured_mouse = false
	player.input_enabled = true
	var o := structures.tower_origin
	var crates: Array[RigidBody3D] = []
	for i in 4:
		for j in 3:
			crates.append(DebugProps.spawn_crate(props, o + Vector3(-2.4 + i * 1.6, 0.6, 5.5 + j * 1.5)))
	await _seconds(1.0)
	for c in crates:
		_apply_direct(ElementalEvent.Kind.HEAT, c, 400.0)
	var fire: FireBurst = ab.get_ability(&"fire_burst")
	var jet: WaterJet = ab.get_ability(&"water_jet")
	var gust: AirGust = ab.get_ability(&"air_gust")
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var f0 := fire.get_stats()
	var j0 := jet.get_stats()
	var g0 := gust.get_stats()
	var e0 := earth.get_stats()
	var frame_ms := PackedFloat32Array()
	var phys_ms := PackedFloat32Array()
	var last := [Time.get_ticks_usec()]
	var peak := {"burning": 0, "dynamic": 0}
	var on_frame := func():
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last[0]) / 1000.0)
		last[0] = now
	var on_physics := func():
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak.burning = maxi(peak.burning, materials.burning_count())
		var dyn := 0
		for p in structures.get_pieces():
			dyn += int(p.released and not p.freeze)
		peak.dynamic = maxi(peak.dynamic, dyn)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var c := _foot_at(corner).home.origin
		queue.enqueue(TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE, Vector3(c.x, 0, c.z), 2.0))
	get_tree().process_frame.connect(on_frame)
	get_tree().physics_frame.connect(on_physics)
	var t0 := Time.get_ticks_msec()
	# Fogo: 5 bolas nas caixas e na torre.
	_send_key(2)
	for k in 5:
		await _tap_at(MaterialResponseSystem.body_center(crates[(k * 5) % crates.size()]) if k < 4 else o + Vector3(0, 6, 2.5))
		await _seconds(0.3)
	# Água: 2 s de jato numa caixa em chamas.
	_send_key(1)
	await get_tree().physics_frame
	await _hold_on(crates[5], 2.0)
	# Ar: 4 rajadas nas caixas e nos destroços.
	_send_key(3)
	for k in 4:
		await _tap_at(o + Vector3(-1.5 + k, 0.5, 6.0))
		await _seconds(0.35)
	# Terra: ergue uma rocha do chão à frente do jogador e arremessa na torre caída.
	_send_key(0)
	await get_tree().physics_frame
	await _aim_settle(player.global_position + Vector3(0, 0, -4.5))
	ab.use_pressed()
	await _wait_until(func(): return earth.phase == "held", 3.0)
	await _aim_settle(o + Vector3(0, 1.0, 1.0))
	ab.use_released()
	await _seconds(1.5)
	var dur_s := (Time.get_ticks_msec() - t0) / 1000.0
	get_tree().process_frame.disconnect(on_frame)
	get_tree().physics_frame.disconnect(on_physics)
	player.input_enabled = false
	if not frame_ms.is_empty():
		frame_ms.remove_at(0)
	var fs := _stats(frame_ms)
	fs["p50"] = _percentile(frame_ms, 0.5)
	fs["p99"] = _percentile(frame_ms, 0.99)
	var ps := _stats(phys_ms)
	ps["p99"] = _percentile(phys_ms, 0.99)
	_metrics["p3_poderes_quadro_ms"] = fs
	_metrics["p3_poderes_fisica_ms"] = ps
	var used := {"fogo_bolas": fire.get_stats().exploded - f0.exploded, "agua_quadros_em_corpo": jet.get_stats().body_ticks - j0.body_ticks,
		"ar_rajadas": gust.get_stats().gusts - g0.gusts, "terra_arremessos": earth.get_stats().thrown - e0.thrown}
	var all_used: bool = used.fogo_bolas >= 4 and used.agua_quadros_em_corpo > 0 and used.ar_rajadas >= 4 and used.terra_arremessos >= 1
	var windowed := not _mode.begins_with("headless")
	var fps_ok: bool = (not windowed) or (fs.get("p95", 999.0) <= 20.0 and fs.get("p99", 999.0) <= 33.0 and fs.get("max", 999.0) <= 50.0)
	var ok: bool = all_used and structures.released_count() == 36 and peak.burning >= 6 and fps_ok
	_record("T37", "Benchmark: colapso total + 12 caixas em chamas + os 4 poderes; critério de FPS em janela", ok, {
		"modo": _mode, "criterio_fps_aplicado": windowed, "criterio": "p95 ≤ 20 ms, p99 ≤ 33 ms, máx ≤ 50 ms",
		"duracao_s": dur_s, "intervalo_entre_quadros_ms": fs, "time_physics_process_ms": ps, "poderes_usados": used,
		"pico_em_chamas": peak.burning, "pico_pecas_dinamicas": peak.dynamic, "soltas": structures.released_count(),
		"fx": fx.get_stats(), "materiais": materials.get_stats()})
	await _shot("t37_benchmark_poderes", o + Vector3(0, 0.5, 16), 0.0, -12.0)
	await main.request_world_reset()


# --- Utilidades P3 -------------------------------------------------------------------------

## Tecla 1–4 (índice 0–3) pelo mesmo evento de input do teclado.
func _send_key(index: int) -> void:
	_send_action(ElementalKeys.ACTIONS[index], true)
	_send_action(ElementalKeys.ACTIONS[index], false)


## Laboratório P3 limpo (reset), jogador 8 m ao sul de LAB_P3 olhando para -Z, elemento `index`.
func _p3_lab(index: int) -> Vector3:
	var ab: AbilityController = main.abilities
	await main.request_world_reset()
	var base := LAB_P3 + Vector3(0, 0, 8)
	await _prepare_area(base, AABB(LAB_P3 - Vector3(8, 4, 16), Vector3(16, 10, 30)))
	ab.select(index)
	ab.require_captured_mouse = false
	player.input_enabled = true
	player.camera_rig.set_view(0.0, deg_to_rad(-20.0))
	await _seconds(0.4)
	return base


## Evento aplicado direto a um corpo (prepara estados; não passa por poder).
func _apply_direct(kind: ElementalEvent.Kind, body: Node3D, magnitude: float) -> void:
	var e := ElementalEvent.make(kind, MaterialResponseSystem.body_center(body), magnitude, 0.0, &"selftest")
	e.target = body
	materials.apply(e)


## Mira no ponto e dá um toque no LMB (poder atual).
func _tap_at(point: Vector3) -> bool:
	var ab: AbilityController = main.abilities
	await _aim_settle(point)
	var ok := ab.use_pressed()
	ab.use_released()
	return ok


## Mira e espera o braço de mola da câmera assentar: depois de girar muito, a câmera muda de
## posição no quadro de física seguinte e o raio da mira passava ao lado da caixa (medido no T32).
func _aim_settle(point: Vector3) -> void:
	for i in 4:
		_aim_at(point)
		await get_tree().physics_frame
	_aim_at(point)


## Segura o LMB por `seconds` de física, com a mira acompanhando o centro do corpo; para antes
## se `stop` devolver true.
func _hold_on(body: Node3D, seconds: float, stop := Callable()) -> bool:
	var ab: AbilityController = main.abilities
	await _aim_settle(MaterialResponseSystem.body_center(body))
	var ok := ab.use_pressed()
	var frames := int(seconds * Engine.physics_ticks_per_second)
	for i in frames:
		if not ok or (stop.is_valid() and stop.call()):
			break
		if is_instance_valid(body):
			_aim_at(MaterialResponseSystem.body_center(body))
		await get_tree().physics_frame
	ab.use_released()
	return ok


## Envia um InputEventAction (o mesmo caminho do teclado/mouse até _unhandled_input).
func _send_action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Aponta a câmera (yaw/pitch do rig) para um ponto do mundo; duas passadas porque a posição
## da câmera depende da própria orientação (braço de mola atrás do jogador).
func _aim_at(point: Vector3) -> void:
	for i in 2:
		var cam: Camera3D = player.camera_rig.camera
		var dir := (point - cam.global_position).normalized()
		player.camera_rig.set_view(atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0)))
		player.camera_rig.force_update_transform()
		cam.force_update_transform()


# --- T38: máquina de estados de material (eventos aplicados direto) ----------------------

func _t38_material_states() -> void:
	await main.request_world_reset()
	await _prepare_area(LAB_P3 + Vector3(0, 0, 10), AABB(LAB_P3 - Vector3(6, 3, 6), Vector3(12, 6, 12)))
	var cases := {}
	var heat := func(body: Node3D, units: float):
		var e := ElementalEvent.make(ElementalEvent.Kind.HEAT, body.global_position, units, 0.0, &"selftest")
		e.target = body
		materials.apply(e)
	var wet := func(body: Node3D, amount: float):
		var e := ElementalEvent.make(ElementalEvent.Kind.WET, body.global_position, amount, 0.0, &"selftest")
		e.target = body
		materials.apply(e)
	var wind := func(body: Node3D, strength: float):
		var e := ElementalEvent.make(ElementalEvent.Kind.AIRFLOW, body.global_position, strength, 0.0, &"selftest")
		e.target = body
		materials.apply(e)

	# a) Madeira seca: 200 não acende; +150 (370 °C ≥ 300) acende.
	var a := DebugProps.spawn_crate(props, LAB_P3)
	heat.call(a, 200.0)
	var a_temp1: float = materials.state_of(a).temperature
	var a_burn1: bool = materials.state_of(a).burning
	heat.call(a, 150.0)
	var a_ok: bool = not a_burn1 and absf(a_temp1 - 220.0) < 0.01 and materials.state_of(a).burning
	cases["a_madeira_acende_no_limiar"] = {"temp_apos_200": a_temp1, "acesa_apos_200": a_burn1,
		"acesa_apos_350": materials.state_of(a).burning, "ok": a_ok}

	# b) Pedra: 1000 unidades só aquecem (÷3), nunca acende.
	var b := DebugProps.spawn_crate(props, LAB_P3 + Vector3(4, 0, 0))
	b.set_meta("body_material", BodyMaterialLibrary.STONE)
	heat.call(b, 1000.0)
	var b_s: MaterialState = materials.state_of(b)
	var b_ok := not b_s.burning and absf(b_s.temperature - (20.0 + 1000.0 / 3.0)) < 0.01
	cases["b_pedra_so_aquece"] = {"estado": b_s.describe(), "ok": b_ok}

	# c) Madeira molhada (60%): a 1ª rajada (320) gasta 60 secando e não acende; a 2ª acende.
	var c := DebugProps.spawn_crate(props, LAB_P3 + Vector3(-4, 0, 0))
	wet.call(c, 0.6)
	heat.call(c, 320.0)
	var c_s: MaterialState = materials.state_of(c)
	var c_first: String = c_s.describe()
	var c_burn1 := c_s.burning
	heat.call(c, 320.0)
	var c_ok := not c_burn1 and c_s.burning
	cases["c_molhada_resiste_1a_rajada"] = {"apos_1a": c_first, "apos_2a": c_s.describe(), "ok": c_ok}

	# d) Água apaga (umidade > 30%).
	wet.call(a, 0.4)
	var d_ok: bool = not materials.state_of(a).burning
	cases["d_agua_apaga"] = {"estado": materials.state_of(a).describe(), "ok": d_ok}

	# e) Vento: fogo fraco (0,2) sob vento 0,8 apaga; fogo forte (0,6) aviva para 0,84.
	var c2 := DebugProps.spawn_crate(props, LAB_P3 + Vector3(0, 0, 4))
	heat.call(c2, 400.0)
	materials.state_of(c2).intensity = 0.2
	wind.call(c2, 0.8)
	var e_weak_out: bool = not materials.state_of(c2).burning
	heat.call(c, 0.0)
	materials.state_of(c).intensity = 0.6
	wind.call(c, 0.8)
	var e_strong: float = materials.state_of(c).intensity
	var e_ok := e_weak_out and materials.state_of(c).burning and absf(e_strong - 0.84) < 0.001
	cases["e_vento_apaga_fraco_aviva_forte"] = {"fraco_apagou": e_weak_out, "forte_intensidade": e_strong, "ok": e_ok}

	# f) Queima até o fim: combustível curto → consumida e removida.
	var f := DebugProps.spawn_crate(props, LAB_P3 + Vector3(0, 0, -4))
	heat.call(f, 400.0)
	materials.state_of(f).fuel = 0.5
	var f_ref: WeakRef = weakref(f)
	var burned := await _wait_until(func(): return f_ref.get_ref() == null, 5.0)
	cases["f_queima_ate_consumir"] = {"removida": burned, "ok": burned}

	# g) Impacto numa peça de pedra presa: Δv 3 m/s não solta, 7 m/s solta (limiar 6).
	await _go_to_tower()
	var crown: StructurePiece = structures.get_pieces().filter(func(p): return p.kind == "coroa")[0]
	var kin := func(piece: StructurePiece, dv: float):
		var e := ElementalEvent.make(ElementalEvent.Kind.KINETIC, piece.global_position, piece.mass * dv, 0.0, &"selftest", Vector3(1, 0, 0))
		e.target = piece
		materials.apply(e)
	kin.call(crown, 3.0)
	var g_weak: bool = crown.released
	kin.call(crown, 7.0)
	var g_ok: bool = not g_weak and crown.released
	cases["g_impacto_solta_peca_acima_do_limiar"] = {"solta_com_3": g_weak, "solta_com_7": crown.released,
		"stats": structures.get_stats().last_break, "ok": g_ok}

	var ok: bool = cases.values().all(func(v): return v.ok)
	_record("T38", "Estados de material: ignição, pedra só aquece, molhada resiste, água e vento apagam, queima consome, impacto solta", ok, cases)
	for ch in props.get_children():
		ch.queue_free()
	await main.request_world_reset()
