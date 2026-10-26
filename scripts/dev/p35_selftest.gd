extends "res://scripts/dev/p3_selftest.gd"
## Roteiro automatizado do P3.5 (polish da Terra): roda P0 + P1 + P2 + P3 (regressão) e depois
## os testes das fases da Terra, na mesma cena real.
##
##   godot --headless --path . res://scenes/main.tscn -- --p35-selftest
##   godot --path . res://scenes/main.tscn -- --p35-selftest --p35-screenshots
##   opcional: --report=<caminho.json>, --only=T39,T41 (T1 e baseline sempre rodam)
##
## Código de saída: 0 = todos PASS, 1 = algum FAIL, 2 = watchdog.

const P35_WATCHDOG_S := 2400.0


func _ready() -> void:
	super._ready()
	if OS.get_cmdline_user_args().has("--p35-screenshots") and DisplayServer.get_name() != "headless":
		_screens = true


func _report_prefix() -> String:
	return super._report_prefix() if _persist_phase != "" else "p35_selftest"


func _watchdog_seconds() -> float:
	return P35_WATCHDOG_S


func _evidence_dir() -> String:
	return "res://docs/evidence/p35/" if OS.has_feature("editor") else "user://"


func _screens_dir() -> String:
	return "res://docs/evidence/p35/screens/" if OS.has_feature("editor") else "user://screens_p35/"


func _log(msg: String) -> void:
	print("[P35TEST] ", msg)


func _run_tests() -> bool:
	var ok: bool = await super._run_tests()
	if not ok or _persist_phase != "":
		return ok
	_log("--- testes P3.5 (Terra) ---")
	if _should_run("T39"): await _t39_earth_phases()
	if _should_run("T40"): await _t40_quick_throw()
	if _should_run("T41"): await _t41_invalid_targets()
	if _should_run("T42"): await _t42_hold_weight()
	if _should_run("T43"): await _t43_ground_crater()
	if _should_run("T44"): await _t44_tuning_is_used()
	if _should_run("T45"): await _t45_phase_captures()
	return true


# --- T39: fases na ordem e nos tempos do tuning ----------------------------------------------

func _t39_earth_phases() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var tu := earth.tuning
	var aim_target := _ground_at(base + Vector3(0.17, 0, -4.5))
	await _aim_settle(aim_target)
	var check := earth.validate_target()
	var point: Vector3 = check.get("point", Vector3.ZERO)
	var core := point + Vector3.DOWN * tu.rock_radius
	var kinds := []
	var cb := func(kind, _data): kinds.append(String(kind))
	earth.fx_event.connect(cb)
	# Contadores do EarthFx ANTES do clique (a rachadura e o telegraph saem no próprio clique).
	var efx: EarthFx = main.earth_fx
	var fx_prev := efx.get_stats()
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_msec()
	ab.use_pressed()
	var fx_at_press := efx.get_stats()
	# Quadro a quadro até a rocha ficar pronta: terreno intacto na antecipação, cavidade aberta e
	# rocha congelada no desprendimento, rocha solta (dinâmica) no levantamento.
	var frames := {"anticipation": 0, "detach": 0, "rise": 0}
	var intact_in_anticipation := true
	var frozen_in_detach := true
	var cavity_open_in_detach := true
	var dynamic_in_rise := true
	var rock_before_detach := false
	# Em que fase cada contador do EarthFx subiu pela 1ª vez (o clique conta como antecipação).
	var fx_phase := {}
	for k in ["cracks", "telegraphs"]:
		if int(fx_at_press[k]) > int(fx_prev[k]):
			fx_phase[k] = "anticipation"
	var watch_fx := func():
		var now := efx.get_stats()
		for k in ["cracks", "telegraphs", "mesh_shakes", "rock_pebbles", "trails", "impacts"]:
			if not fx_phase.has(k) and int(now[k]) > int(fx_prev[k]):
				fx_phase[k] = earth.phase
	while earth.phase != "hold" and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().physics_frame
		watch_fx.call()
		match earth.phase:
			"anticipation":
				frames.anticipation += 1
				intact_in_anticipation = intact_in_anticipation and svc.sample_sdf(core) < 0.0
				rock_before_detach = rock_before_detach or earth.rock != null
			"detach":
				frames.detach += 1
				frozen_in_detach = frozen_in_detach and earth.rock != null and earth.rock.freeze
				cavity_open_in_detach = cavity_open_in_detach and svc.sample_sdf(core) > 0.0
			"rise":
				frames.rise += 1
				dynamic_in_rise = dynamic_in_rise and earth.rock != null and not earth.rock.freeze
	var ready_ms := Time.get_ticks_msec() - t0
	var st := earth.get_stats()
	# Durações pelo registro de fases (quadros de física entre as transições).
	var seq := []
	var dur := {}
	var entries := earth.phase_log.filter(func(e): return e.frame >= f0)
	for i in entries.size():
		seq.append(entries[i].phase)
		if i + 1 < entries.size():
			dur[entries[i].phase] = entries[i + 1].frame - entries[i].frame
	var hz := Engine.physics_ticks_per_second
	var expect := {"anticipation": ceili(tu.anticipation_s * hz - 0.01), "detach": ceili(tu.detach_s * hz - 0.01),
		"rise": ceili(tu.rise_s * hz - 0.01)}
	var timing_ok := true
	for k in expect:
		timing_ok = timing_ok and absi(int(dur.get(k, -99)) - int(expect[k])) <= 1
	ab.use_released()
	var t_rel := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_rel < 1500:
		await get_tree().physics_frame
		watch_fx.call()
	earth.fx_event.disconnect(cb)
	player.input_enabled = false
	var order_ok := seq.slice(0, 4) == ["anticipation", "detach", "rise", "hold"]
	var fx_order := ["anticipation", "detach", "rise", "hold", "windup", "launch"]
	var fx_ok := kinds.filter(func(k): return fx_order.has(k)) == fx_order
	# FX na fase certa: rachadura e telegraph na antecipação, tremor da malha no desprendimento,
	# pedrinhas da rocha no levantamento; rastro e impacto depois do lançamento.
	var fx_phase_ok: bool = fx_phase.get("cracks") == "anticipation" and fx_phase.get("telegraphs") == "anticipation" \
		and fx_phase.get("mesh_shakes") == "detach" and fx_phase.get("rock_pebbles") == "rise" \
		and fx_phase.get("trails") in ["recovery", ""] and fx_phase.has("impacts")
	var ok: bool = check.get("ok", false) and order_ok and timing_ok and intact_in_anticipation and not rock_before_detach \
		and frozen_in_detach and cavity_open_in_detach and dynamic_in_rise and st.last_ready_ms <= 400 \
		and st.last_cavity_wait_frames == 0 and fx_ok and fx_phase_ok
	_record("T39", "Terra em fases: antecipação (chão intacto) → desprendimento (rocha congelada, cavidade aberta) → levantamento → pronta em ≤ 400 ms", ok, {
		"alvo": {"ok": check.get("ok"), "motivo": check.get("reason"), "dist": check.get("dist"), "ponto": str(point),
			"jogador": str(player.global_position), "ultimo": earth.last_result},
		"sequencia": seq, "quadros_por_fase": dur, "esperado": expect, "quadros_observados": frames,
		"chao_intacto_na_antecipacao": intact_in_anticipation, "rocha_antes_do_desprendimento": rock_before_detach,
		"congelada_no_desprendimento": frozen_in_detach, "cavidade_aberta_no_desprendimento": cavity_open_in_detach,
		"dinamica_no_levantamento": dynamic_in_rise, "pronta_ms": st.last_ready_ms, "pronta_ms_relogio_teste": ready_ms,
		"espera_extra_pela_cavidade_quadros": st.last_cavity_wait_frames, "fx_eventos": kinds, "fx_na_fase": fx_phase})
	for ch in props.get_children():
		ch.queue_free()


# --- T40: toque curto = arremesso guardado; recuperação ------------------------------------

func _t40_quick_throw() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var tu := earth.tuning
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -4.5)))
	var launches := []
	var cb := func(kind, data):
		if kind == &"launch":
			launches.append({"ms": Time.get_ticks_msec(), "v": data.velocity, "from": data.point})
	earth.fx_event.connect(cb)
	var t0 := Time.get_ticks_msec()
	ab.use_pressed()
	await get_tree().physics_frame
	ab.use_released()
	var released_in := earth.phase
	# A mira muda depois de soltar: o lançamento usa a mira do instante em que sai.
	var far := base + Vector3(0, 1.0, -22)
	await _aim_settle(far)
	await _wait_until(func(): return not launches.is_empty(), 1.5)
	var launch_ms: int = launches[0].ms - t0 if not launches.is_empty() else -1
	var angle := 180.0
	if not launches.is_empty():
		var v: Vector3 = launches[0].v
		var to: Vector3 = far - (launches[0].from as Vector3)
		angle = rad_to_deg(Vector2(v.x, v.z).angle_to(Vector2(to.x, to.z)))
	# Recuperação: um clique logo depois do lançamento não começa outro ciclo.
	var extracted0: int = earth.get_stats().extracted
	var phase_after := earth.phase
	ab.use_pressed()
	ab.use_released()
	await get_tree().physics_frame
	var blocked: bool = earth.phase == "recovery" and earth.get_stats().extracted == extracted0
	await _seconds(tu.recovery_s + 0.1)
	var free_again := earth.phase == ""
	earth.fx_event.disconnect(cb)
	player.input_enabled = false
	var limit_ms := 400 + int(tu.windup_s * 1000.0) + 50
	var ok: bool = released_in == "anticipation" and launch_ms > 0 and launch_ms <= limit_ms and absf(angle) < 15.0 \
		and phase_after == "recovery" and blocked and free_again
	_record("T40", "Toque curto: soltar na antecipação guarda o arremesso, que sai ao ficar pronta na direção da mira do instante; recuperação bloqueia novo clique", ok, {
		"soltou_na_fase": released_in, "lancamento_ms": launch_ms, "limite_ms": limit_ms, "angulo_com_a_mira_graus": angle,
		"fase_apos_lancar": phase_after, "clique_na_recuperacao_ignorado": blocked, "livre_apos_recuperacao": free_again})
	await _seconds(1.0)
	for ch in props.get_children():
		ch.queue_free()


# --- T41: alvo inválido ---------------------------------------------------------------------

func _t41_invalid_targets() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var tu := earth.tuning
	var invalids := []
	var cb := func(kind, data):
		if kind == &"invalid":
			invalids.append(String(data.get("reason", "")))
	earth.fx_event.connect(cb)
	var cases := {}
	var run_case := func(name: String) -> void:
		var rev := svc.get_revision()
		var ext: int = earth.get_stats().extracted
		var n := invalids.size()
		ab.use_pressed()
		ab.use_released()
		await get_tree().physics_frame
		await get_tree().physics_frame
		cases[name] = {"motivo": invalids[n] if invalids.size() > n else "", "fase": earth.phase,
			"edicoes": svc.get_revision() - rev, "extraidas": earth.get_stats().extracted - ext,
			"ok": invalids.size() > n and earth.phase == "" and svc.get_revision() == rev and earth.get_stats().extracted == ext}
	# a) céu
	player.camera_rig.set_view(0.0, deg_to_rad(30.0))
	await _seconds(0.2)
	await run_case.call("a_ceu")
	# b) longe demais (9 m)
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -9.0)))
	await run_case.call("b_longe_9m")
	# c) perto demais (1,5 m)
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -1.5)))
	await run_case.call("c_perto_1_5m")
	# d) cavidade sobre o jogador: sem a distância mínima, o TerrainService recusa (overlaps_player)
	var min0 := tu.min_range
	tu.min_range = 0.0
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -1.2)))
	await run_case.call("d_sobre_o_jogador")
	tu.min_range = min0
	earth.fx_event.disconnect(cb)
	player.input_enabled = false
	var ok: bool = cases.values().all(func(c): return c.ok) and String(cases.d_sobre_o_jogador.motivo).contains("overlaps_player")
	_record("T41", "Alvo inválido (céu, longe, perto, sobre o jogador): nenhuma extração, nenhuma edição, evento 'invalid' com motivo", ok, cases)


# --- T42: peso no hold -------------------------------------------------------------------

func _t42_hold_weight() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var tu := earth.tuning
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -4.5)))
	ab.use_pressed()
	await _wait_until(func(): return earth.phase == "hold", 2.0)
	var rock := earth.rock
	if rock == null:
		_record("T42", "Peso no hold", false, {"erro": "a rocha não ficou pronta", "fase": earth.phase, "ultimo": earth.last_result})
		player.input_enabled = false
		return
	var speed_in_hold := player.speed_scale
	await _seconds(0.8)
	# Balanço: amplitude vertical do centro parado, por 2,5 s.
	var ys := PackedFloat32Array()
	for i in 150:
		await get_tree().physics_frame
		ys.append(EarthLiftThrow.center_of(rock).y)
	var bob: float = (Array(ys).max() - Array(ys).min()) * 0.5
	# Giro rápido de 90° da câmera: a rocha atrasa (peso) e assenta sem oscilar.
	var pitch := deg_to_rad(-20.0)
	player.camera_rig.set_view(PI * 0.5, pitch)
	var target0 := earth.hold_target()
	var lag_100ms := 0.0
	var settle_ms := -1
	var t0 := Time.get_ticks_msec()
	var reached := false
	var overshoot := 0.0
	var from_dir := (target0 - EarthLiftThrow.center_of(rock)).normalized()
	while Time.get_ticks_msec() - t0 < 2500:
		await get_tree().physics_frame
		var err := EarthLiftThrow.center_of(rock).distance_to(earth.hold_target())
		if lag_100ms == 0.0 and Time.get_ticks_msec() - t0 >= 100:
			lag_100ms = err
		if not reached and err < 0.3:
			reached = true
			settle_ms = Time.get_ticks_msec() - t0
		if reached:
			overshoot = maxf(overshoot, (EarthLiftThrow.center_of(rock) - earth.hold_target()).dot(from_dir))
	ab.use_released()
	await _wait_until(func(): return earth.phase != "hold" and earth.phase != "windup", 1.0)
	await _seconds(tu.recovery_s + 0.1)
	var speed_after := player.speed_scale
	player.input_enabled = false
	var ok: bool = absf(speed_in_hold - tu.hold_move_speed_scale) < 0.001 and speed_after == 1.0 \
		and bob > tu.hold_bob_amplitude * 0.4 and bob < tu.hold_bob_amplitude * 2.0 \
		and lag_100ms > 1.0 and settle_ms > 0 and settle_ms < 2000 and overshoot < 0.3
	_record("T42", "Peso no hold: giro de 90° faz a rocha atrasar e assentar sem oscilar; balanço vertical; jogador mais lento só enquanto carrega", ok, {
		"velocidade_jogador_no_hold": speed_in_hold, "velocidade_depois": speed_after, "balanco_amplitude_m": bob,
		"atraso_100ms_m": lag_100ms, "ms_ate_0_3m": settle_ms, "sobressinal_m": overshoot})
	await _seconds(1.0)
	for ch in props.get_children():
		ch.queue_free()


# --- T43: impacto no chão abre cratera real ------------------------------------------------

func _t43_ground_crater() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var tu := earth.tuning
	var ground_fx := []
	var cb := func(kind, data):
		if kind == &"impact_ground":
			ground_fx.append({"speed": data.speed, "crater": data.crater, "point": data.point})
	earth.fx_event.connect(cb)
	# A) arremesso rápido no chão a 12 m → cratera (uma só por arremesso).
	var c0: int = earth.get_stats().craters
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -4.5)))
	ab.use_pressed()
	await _wait_until(func(): return earth.phase == "hold", 2.0)
	await _seconds(0.4)
	await _aim_settle(_ground_at(base + Vector3(2, 0, -13)))
	ab.use_released()
	await _wait_until(func(): return not ground_fx.is_empty(), 3.0)
	await _seconds(2.0)
	var a_fx: Dictionary = ground_fx[0] if not ground_fx.is_empty() else {}
	var a_point: Vector3 = a_fx.get("point", Vector3.ZERO)
	var a_sdf := svc.sample_sdf(a_point + Vector3.DOWN * 0.3) if not a_fx.is_empty() else -1.0
	var a_craters: int = earth.get_stats().craters - c0
	# B) arremesso lento (8 m/s) no chão perto → sem cratera. Arranca longe da 1ª cavidade
	# (r ≈ 2,15 m): mirar ao lado dela caía dentro do buraco, o alvo ficava inválido e o caso
	# passava sem lançar nada.
	await _seconds(tu.recovery_s + 0.2)
	var speed0 := tu.throw_speed
	tu.throw_speed = 8.0
	var n_fx := ground_fx.size()
	var c1: int = earth.get_stats().craters
	var thrown1: int = earth.get_stats().thrown
	await _aim_settle(_ground_at(base + Vector3(4, 0, -4.5)))
	ab.use_pressed()
	var b_ready := await _wait_until(func(): return earth.phase == "hold", 2.0)
	await _seconds(0.4)
	await _aim_settle(_ground_at(base + Vector3(5, 0, -7.5)))
	ab.use_released()
	await _seconds(2.5)
	tu.throw_speed = speed0
	var b_thrown: int = earth.get_stats().thrown - thrown1
	var b_craters: int = earth.get_stats().craters - c1
	var b_fx: Array = ground_fx.slice(n_fx)
	earth.fx_event.disconnect(cb)
	player.input_enabled = false
	var ok: bool = not a_fx.is_empty() and a_fx.speed >= tu.crater_min_speed and a_fx.crater and a_craters == 1 \
		and b_ready and b_thrown == 1 \
		and a_sdf > 0.0 and b_craters == 0
	_record("T43", "Impacto no chão a ≥ 12 m/s abre cratera real pela fila (uma por arremesso); arremesso lento não abre", ok, {
		"A_velocidade_no_chao": a_fx.get("speed", 0.0), "A_crateras": a_craters, "A_ponto": str(a_point), "A_sdf_no_ponto": a_sdf,
		"B_pronta": b_ready, "B_arremessos": b_thrown, "B_crateras": b_craters,
		"B_impactos_no_chao": b_fx.map(func(f): return "%.1f m/s" % f.speed)})
	await _shot("t43_cratera_do_impacto", player.global_position, 0.0, -25.0, false)
	for ch in props.get_children():
		ch.queue_free()


# --- T44: o tuning é de fato usado ------------------------------------------------------

func _t44_tuning_is_used() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var tu := earth.tuning
	var ant0 := tu.anticipation_s
	var spd0 := tu.hold_move_speed_scale
	tu.anticipation_s = 0.14
	tu.hold_move_speed_scale = 0.5
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -4.5)))
	var idle_before := await _wait_until(func(): return earth.phase == "", 1.0)
	var f0 := Engine.get_physics_frames()
	var pressed := ab.use_pressed()
	var phase_after_press := earth.phase
	var result_after_press := earth.last_result
	await _wait_until(func(): return earth.phase == "hold", 2.0)
	var speed_in_hold := player.speed_scale
	var entries := earth.phase_log.filter(func(e): return e.frame >= f0)
	var ant_frames := -1
	for i in entries.size() - 1:
		if entries[i].phase == "anticipation":
			ant_frames = entries[i + 1].frame - entries[i].frame
	ab.use_released()
	await _wait_until(func(): return earth.phase == "" or earth.phase == "recovery", 1.0)
	tu.anticipation_s = ant0
	tu.hold_move_speed_scale = spd0
	await _seconds(0.6)
	player.input_enabled = false
	var expect := ceili(0.14 * Engine.physics_ticks_per_second - 0.01)
	var ok: bool = absi(ant_frames - expect) <= 1 and absf(speed_in_hold - 0.5) < 0.001
	_record("T44", "Tuning em uso: antecipação de 140 ms e velocidade 0,5 no hold mudam o que é medido", ok, {
		"quadros_de_antecipacao": ant_frames, "esperado": expect, "velocidade_jogador_no_hold": speed_in_hold,
		"livre_antes": idle_before, "clique_aceito": pressed, "fase_apos_clique": phase_after_press, "resultado": result_after_press})
	for ch in props.get_children():
		ch.queue_free()


# --- T45: capturas de cada fase (em janela) -------------------------------------------------

## Fotografa a Terra DURANTE cada fase (antecipação, desprendimento, levantamento, pronta, voo,
## impacto). Em headless não há imagem: o teste só confere que todas as fases aconteceram.
func _t45_phase_captures() -> void:
	var ab: AbilityController = main.abilities
	var base: Vector3 = await _p3_lab(0)
	var earth: EarthLiftThrow = ab.get_ability(&"earth_lift_throw")
	var seen := []
	var cb := func(kind, _data): seen.append(String(kind))
	earth.fx_event.connect(cb)
	var shots := 0
	await _aim_settle(_ground_at(base + Vector3(0.17, 0, -5.0)))
	ab.use_pressed()
	await _frames(3)
	shots += int(await _snap("p35_1_antecipacao"))
	await _wait_until(func(): return earth.phase == "detach", 1.0)
	await _frames(4)
	shots += int(await _snap("p35_2_desprendimento"))
	await _wait_until(func(): return earth.phase == "rise", 1.0)
	await _frames(5)
	shots += int(await _snap("p35_3_levantamento"))
	await _wait_until(func(): return earth.phase == "hold", 1.0)
	await _seconds(0.35)
	shots += int(await _snap("p35_4_pronta"))
	await _aim_settle(_ground_at(base + Vector3(1.5, 0, -14.0)))
	ab.use_released()
	await _wait_until(func(): return earth.phase == "recovery", 1.0)
	await _frames(8)
	shots += int(await _snap("p35_5_voo"))
	await _wait_until(func(): return seen.has("impact_ground") or seen.has("impact_body"), 3.0)
	await _frames(6)
	shots += int(await _snap("p35_6_impacto"))
	await _seconds(1.2)
	shots += int(await _snap("p35_7_cratera_e_rachaduras"))
	earth.fx_event.disconnect(cb)
	player.input_enabled = false
	var need := ["anticipation", "detach", "rise", "hold", "windup", "launch"]
	var ok: bool = need.all(func(k): return seen.has(k)) and (seen.has("impact_ground") or seen.has("impact_body")) \
		and (shots == 7 or not _screens)
	_record("T45", "Capturas da Terra durante cada fase (janela); em headless só confere que as fases aconteceram", ok, {
		"fases_vistas": seen, "capturas": shots, "capturas_ativas": _screens})
	for ch in props.get_children():
		ch.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Captura imediata do quadro atual (sem mudar câmera nem esperar), para fases de ~100 ms.
func _snap(name: String) -> bool:
	if not _screens:
		return false
	await RenderingServer.frame_post_draw
	_shot_index += 1
	var dir := _screens_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s%02d_%s.png" % [dir, _shot_index, name]
	var err := get_viewport().get_texture().get_image().save_png(path)
	_log("captura %s -> %s" % [name, "OK" if err == OK else error_string(err)])
	return err == OK
