extends SceneTree
## Spike do P3.5 (polish da Terra): mede NA CENA REAL o que a máquina de fases nova precisa,
## antes de escrevê-la.
## Uso: godot --headless --path . --script res://tools/spike_p35_earth.gd   (E1–E3)
##      godot --path . --script res://tools/spike_p35_earth.gd              (E1–E4: custo de GPU e captura)
## Saída: stdout + res://docs/evidence/p35/00_spike_p35.txt. Exit 0 = checagens OK.
##
##   E1 Timer do Voxel Tools: quanto tempo o corpo fica cinemático; se parar o Timer e descongelar
##      só quando a forma da rocha já não sobrepõe o collider do terreno é estável (sem empurrão);
##      controle: descongelar no 1º quadro
##   E2 latência da confirmação da cavidade (consulta de forma contra TERRAIN)
##   E3 levantamento planejado (smoothstep, PD + aceleração de alimentação direta) em 120/160/200 ms
##      com rochas de núcleo 1,0/1,2/1,6 m: erro na chegada, sobressinal, maior passo, aceleração
##      de pico, contato com as paredes da cavidade
##   E4 (só em janela) custo de 8 decals de rachadura + 6 emissores de pedrinhas com colisão por
##      heightfield, sem vsync; captura para conferir que o shader do terreno recebe decal

const OUT_PATH := "res://docs/evidence/p35/00_spike_p35.txt"
const OUT_PATH_WINDOW := "res://docs/evidence/p35/00_spike_p35_window.txt"
const SHOT_PATH := "res://docs/evidence/p35/spike_decal.png"
const LAB := Vector3(-34, 0.6, 60)
const HOLD_HEIGHT := 1.4
const TRACK_OMEGA := 30.0
const RISE_MAX_ACCEL := 600.0

var main: Node
var svc: TerrainService
var props: Node3D
var player: PlayerController
var _lines: PackedStringArray = []
var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_out("# Spike P3.5 (Terra) — %s" % Time.get_datetime_string_from_system())
	_out("# Godot %s | física %s | ticks/s %d | display %s" % [Engine.get_version_info().string,
		ProjectSettings.get_setting("physics/3d/physics_engine"), Engine.physics_ticks_per_second, DisplayServer.get_name()])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	svc = main.terrain_service
	props = main.props_root
	player = main.player
	if not await _until(func(): return svc.is_ready(), 30.0):
		_check("E0 terreno pronto", false, "timeout")
		_finish()
		return
	player.input_enabled = false
	player.teleport_to(LAB + Vector3(0, 0, 14))
	var area := AABB(LAB - Vector3(12, 4, 12), Vector3(24, 10, 26))
	if not await _until(func(): return svc.can_edit_area(area), 15.0):
		_check("E0 área do laboratório editável", false, "timeout")
		_finish()
		return
	await _seconds(0.5)
	if OS.get_cmdline_user_args().has("--e5-only"):
		await _e5_subvoxel_separation()
		_finish()
		return
	await _e1_e2_timer_and_confirm()
	await _e3_rise()
	await _e5_subvoxel_separation()
	if DisplayServer.get_name() != "headless":
		await _e4_gpu_cost()
	else:
		_out("")
		_out("## E4 custo de GPU: NÃO MEDIDO (headless; rode em janela)")
	_finish()


# --- E1 + E2 -------------------------------------------------------------------------------

func _e1_e2_timer_and_confirm() -> void:
	_out("")
	_out("## E1/E2 Timer do Voxel Tools e confirmação da cavidade")
	# A) Comportamento padrão do Voxel Tools.
	var a := await _extract(LAB + Vector3(-6, 0, -6), 1.2)
	if a == null:
		_check("E1 extração", false, "extract_rock recusou")
		return
	var timer := _timer_of(a)
	var info := "sem Timer"
	if timer != null:
		var conns := timer.timeout.get_connections().map(func(c): return str(c.callable))
		info = "wait_time=%.3f one_shot=%s autostart=%s parado=%s time_left=%.3f conexões=%s" % [
			timer.wait_time, timer.one_shot, timer.autostart, timer.is_stopped(), timer.time_left, conns]
	_out("E1 Timer logo após a extração: %s" % info)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var clear_frame := -1
	while a.freeze and frames < 90:
		await physics_frame
		frames += 1
		if clear_frame < 0 and _clear_of_terrain(a):
			clear_frame = frames
	var vt_ms := Time.get_ticks_msec() - t0
	var a_kick := await _track_speed(a, 30)
	_out("E1 A (padrão do VT): descongelou após %d quadros (%d ms); forma livre do terreno no quadro %d; depois: %s" % [
		frames, vt_ms, clear_frame, a_kick])
	a.queue_free()

	# B) Timer parado; descongela quando o collider da CAVIDADE aparece: um raio no centro do
	# buraco passa a enxergar o fundo da cavidade (o collider do terreno é uma casca, então a
	# consulta de forma acima não diz nada sobre uma rocha dentro do sólido).
	var b := await _extract(LAB + Vector3(0, 0, -6), 1.2)
	var bt := _timer_of(b)
	if bt != null:
		bt.stop()
	var hole: Vector3 = b.get_meta("_hole")
	var t1 := Time.get_ticks_msec()
	var bf := 0
	while not _cavity_visible(hole) and bf < 60:
		await physics_frame
		bf += 1
	var confirm_ms := Time.get_ticks_msec() - t1
	var still_frozen_before := b.freeze
	b.freeze = false
	var b_kick := await _track_speed(b, 30)
	_out("E2 B (Timer parado): raio no buraco vê o fundo da cavidade após %d quadros (%d ms); congelado até lá: %s; depois de descongelar: %s" % [
		bf, confirm_ms, still_frozen_before, b_kick])
	b.queue_free()

	# C) Controle: Timer parado e descongela no 1º quadro, sem confirmar.
	var c := await _extract(LAB + Vector3(6, 0, -6), 1.2)
	var ct := _timer_of(c)
	if ct != null:
		ct.stop()
	var c_clear_now := _clear_of_terrain(c)
	c.freeze = false
	var c_kick := await _track_speed(c, 30)
	_out("E1 C (controle: descongela no 1º quadro, forma livre=%s): %s" % [c_clear_now, c_kick])
	c.queue_free()

	# D) Timer parado sem descongelar: continua congelado depois de 1 s (o controle é nosso)?
	var d := await _extract(LAB + Vector3(-6, 0, 0), 1.2)
	var dt := _timer_of(d)
	var d_has_timer := dt != null
	if dt != null:
		dt.stop()
	await _seconds(1.0)
	var d_frozen := d.freeze
	d.queue_free()
	_check("E1 Timer do VT parado deixa o corpo congelado (o desprendimento controla o descongelamento)",
		d_has_timer and d_frozen, "Timer encontrado=%s; congelado após 1 s com o Timer parado=%s" % [d_has_timer, d_frozen])
	# Cair na folga da cavidade (gravidade) é esperado; o risco seria um empurrão PARA CIMA.
	_check("E2 collider da cavidade confirmado dentro do desprendimento (≤ 100 ms) e descongelar não dá empurrão",
		bf < 60 and confirm_ms <= 100 and b_kick.max_up < 1.0 and c_kick.max_up < 1.0,
		"%d quadros / %d ms; subida máx. depois da confirmação %.2f m/s; no controle sem confirmação %.2f m/s" % [
			bf, confirm_ms, b_kick.max_up, c_kick.max_up])
	await _seconds(0.3)


# --- E3 -------------------------------------------------------------------------------------

func _e3_rise() -> void:
	_out("")
	_out("## E3 levantamento planejado (smoothstep; PD ω=%.0f + aceleração de alimentação direta; teto %.0f m/s²; centro a %.1f m sobre o chão)" % [
		TRACK_OMEGA, RISE_MAX_ACCEL, HOLD_HEIGHT])
	var spots := [Vector3(-6, 0, -6), Vector3(0, 0, -6), Vector3(6, 0, -6), Vector3(-6, 0, 0), Vector3(0, 0, 0),
		Vector3(6, 0, 0), Vector3(-6, 0, 6), Vector3(0, 0, 6), Vector3(6, 0, 6)]
	var i := 0
	var worst_err := 0.0
	var worst_over := 0.0
	var worst_contacts := 0
	for r in [1.0, 1.2, 1.6]:
		for T in [0.12, 0.16, 0.2]:
			var res := await _rise_once(LAB + spots[i], r, T)
			i += 1
			if res.is_empty():
				_check("E3 r=%.1f T=%.2f" % [r, T], false, "extração recusada")
				continue
			# O gate vale para os tempos padrão (160–200 ms) e o núcleo padrão (≤ 1,2 m); 120 ms e
			# núcleo 1,6 m (~23 t) ficam como informação para o tuning.
			if T < 0.15 or r > 1.3:
				_out("E3 r=%.1f T=%3d ms (informativo) | massa %.1f t | erro em T %.3f m | sobressinal %.3f m | maior passo %.3f m | v máx %.1f m/s | a pedida máx %.0f m/s² | quadros no teto %d | contatos %d" % [
					r, int(T * 1000), res.mass / 1000.0, res.err_at_t, res.overshoot, res.max_step, res.max_speed, res.max_accel,
					res.saturated, res.terrain_contacts])
				continue
			_out("E3 r=%.1f T=%3d ms | massa %.1f t | subida %.2f m | erro em T %.3f m | sobressinal %.3f m | erro após 0,4 s %.3f m | maior passo %.3f m | v máx %.1f m/s | a pedida máx %.0f m/s² | quadros no teto %d | contatos com terreno %d" % [
				r, int(T * 1000), res.mass / 1000.0, res.dist, res.err_at_t, res.overshoot, res.settle, res.max_step, res.max_speed,
				res.max_accel, res.saturated, res.terrain_contacts])
			worst_err = maxf(worst_err, res.err_at_t)
			worst_over = maxf(worst_over, res.overshoot)
			worst_contacts = maxi(worst_contacts, res.terrain_contacts)
	_check("E3 levantamento nos tempos padrão (160–200 ms, núcleo ≤ 1,2 m) chega ao ponto (erro ≤ 0,25 m), sobressinal ≤ 0,15 m, sem raspar a cavidade",
		worst_err <= 0.25 and worst_over <= 0.15 and worst_contacts == 0,
		"pior erro em T %.3f m; pior sobressinal %.3f m; maior nº de contatos %d" % [worst_err, worst_over, worst_contacts])


func _rise_once(spot: Vector3, core: float, T: float) -> Dictionary:
	var rb := await _extract(spot, core)
	if rb == null:
		return {}
	var timer := _timer_of(rb)
	if timer != null:
		timer.stop()
	await _until(func(): return _clear_of_terrain(rb), 1.0)
	var hole: Vector3 = rb.get_meta("_hole")
	rb.freeze = false
	rb.gravity_scale = 0.0
	rb.continuous_cd = true
	rb.contact_monitor = true
	rb.max_contacts_reported = 4
	var contacts := [0]
	rb.body_entered.connect(func(b): if b is VoxelLodTerrain: contacts[0] += 1)
	var start := MaterialResponseSystem.body_center(rb)
	var target := hole + Vector3.UP * HOLD_HEIGHT
	var d := target - start
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t := 0.0
	var prev := start
	var res := {"mass": rb.mass, "dist": d.length(), "max_step": 0.0, "max_speed": 0.0, "max_accel": 0.0, "saturated": 0,
		"err_at_t": 0.0, "overshoot": 0.0, "settle": 0.0, "terrain_contacts": 0}
	var hold_frames := int(0.4 * Engine.physics_ticks_per_second)
	var rise_frames := int(ceil(T / dt))
	for f in rise_frames + hold_frames:
		var u := clampf(t / T, 0.0, 1.0)
		var s := u * u * (3.0 - 2.0 * u)
		var ds := 6.0 * u * (1.0 - u) / T if u < 1.0 else 0.0
		var dds := (6.0 - 12.0 * u) / (T * T) if u < 1.0 else 0.0
		var x_d := start + d * s
		var v_d := d * ds
		var a_d := d * dds
		var x := MaterialResponseSystem.body_center(rb)
		var acc := a_d + (x_d - x) * TRACK_OMEGA * TRACK_OMEGA + (v_d - rb.linear_velocity) * 2.0 * TRACK_OMEGA
		res.max_accel = maxf(res.max_accel, acc.length())
		if acc.length() > RISE_MAX_ACCEL:
			res.saturated += 1
			acc = acc.limit_length(RISE_MAX_ACCEL)
		rb.apply_central_force(acc * rb.mass)
		await physics_frame
		t += dt
		var p := MaterialResponseSystem.body_center(rb)
		res.max_step = maxf(res.max_step, p.distance_to(prev))
		res.max_speed = maxf(res.max_speed, rb.linear_velocity.length())
		prev = p
		if f == rise_frames - 1:
			res.err_at_t = p.distance_to(target)
		if f >= rise_frames:
			res.overshoot = maxf(res.overshoot, (p - target).dot(d.normalized()))
	res.settle = MaterialResponseSystem.body_center(rb).distance_to(target)
	res.terrain_contacts = contacts[0]
	rb.queue_free()
	await physics_frame
	return res


# --- E5 -------------------------------------------------------------------------------------

## A rocha se separa do terreno em qualquer posição sub-voxel do ponto de arranque? Achado no
## selftest P3.5 (T45): extract_rock OK com 0 corpos em x = −33,83 — cavidade aberta, núcleo
## preso. Mede a taxa de separação numa grade de deslocamentos (0, 0,17, …, 0,83 m em x e z).
func _e5_subvoxel_separation() -> void:
	_out("")
	_out("## E5 separação do núcleo por deslocamento sub-voxel (núcleo 1,2 m; folga %.2f m)" % svc.extract_gap)
	await main.request_world_reset()
	player.teleport_to(LAB + Vector3(0, 0, 14))
	await _until(func(): return svc.can_edit_area(AABB(LAB - Vector3(12, 4, 12), Vector3(24, 10, 26))), 15.0)
	await _seconds(0.3)
	var offsets := [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]
	var fails := []
	var total := 0
	var i := 0
	for ox in offsets:
		for oz in offsets:
			# Pontos a 6 m uns dos outros (cavidade de ~2,2 m de raio), numa grade 6×6 em volta de LAB.
			var spot := LAB + Vector3(-15.0 + (i % 6) * 6.0 + ox, 0.0, -15.0 + floorf(i / 6.0) * 6.0 + oz)
			i += 1
			var hit := svc.raycast_terrain(spot + Vector3.UP * 5.0, spot + Vector3.DOWN * 10.0)
			if hit.is_empty():
				continue
			var out := svc.extract_rock(hit.position, Vector3.UP, 1.2, props)
			var res: TerrainEditResult = out.result
			if res == null or not res.ok:
				continue
			total += 1
			if out.bodies.is_empty():
				fails.append("(%.2f, %.2f)" % [ox, oz])
			for b in out.bodies:
				(b as Node).queue_free()
			await physics_frame
	_out("E5 %d extrações; %d sem corpo (núcleo preso) nos deslocamentos x,z: %s" % [total, fails.size(), fails])
	_check("E5 o núcleo se separa em todas as posições sub-voxel", fails.is_empty() and total > 0,
		"%d/%d separaram" % [total - fails.size(), total])


# --- E4 -------------------------------------------------------------------------------------

func _e4_gpu_cost() -> void:
	_out("")
	_out("## E4 custo de GPU (janela, vsync desligado durante a medição)")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	player.camera_rig.set_view(0.0, deg_to_rad(-30.0))
	player.teleport_to(LAB + Vector3(0, 0, 14))
	await _seconds(1.0)
	var base := await _frame_stats(2.0)
	var fx_root := Node3D.new()
	main.add_child(fx_root)
	var tex := CrackTexture.make(256, 7)
	for k in 8:
		var dec := Decal.new()
		dec.texture_albedo = tex
		dec.size = Vector3(3.0, 2.0, 3.0)
		dec.modulate = Color(1, 1, 1, 0.9)
		fx_root.add_child(dec)
		var hit := svc.raycast_terrain(LAB + Vector3(-7 + k * 2.0, 5, (k % 2) * 3.0), LAB + Vector3(-7 + k * 2.0, -10, (k % 2) * 3.0))
		dec.global_position = hit.position if not hit.is_empty() else LAB
	await _seconds(0.3)
	var decals := await _frame_stats(2.0)
	var emitters: Array[GPUParticles3D] = []
	for k in 6:
		var e := GPUParticles3D.new()
		e.amount = 32
		e.lifetime = 1.0
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 40.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 4.0
		pm.gravity = Vector3(0, -9.8, 0)
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_bounce = 0.2
		pm.collision_friction = 0.6
		e.process_material = pm
		var mesh := SphereMesh.new()
		mesh.radius = 0.06
		mesh.height = 0.1
		mesh.radial_segments = 4
		mesh.rings = 2
		e.draw_pass_1 = mesh
		e.collision_base_size = 0.08
		fx_root.add_child(e)
		e.global_position = LAB + Vector3(-5 + k * 2.0, 0.3, 1.5)
		emitters.append(e)
	await _seconds(0.3)
	var particles := await _frame_stats(2.0)
	var hf := GPUParticlesCollisionHeightField3D.new()
	hf.size = Vector3(40, 20, 40)
	hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	fx_root.add_child(hf)
	hf.global_position = LAB + Vector3(0, 0, 4)
	await _seconds(0.3)
	var with_hf := await _frame_stats(2.0)
	var shot := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/p35"))
	shot.save_png(ProjectSettings.globalize_path(SHOT_PATH))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	for s in [["base", base], ["+8 decals", decals], ["+6 emissores", particles], ["+heightfield", with_hf]]:
		_out("E4 %-13s quadro p50 %.2f / p95 %.2f / máx %.2f ms (n=%d)" % [s[0], s[1].p50, s[1].p95, s[1].max, s[1].n])
	_out("E4 captura: %s (conferir a rachadura sobre o terreno a olho)" % SHOT_PATH)
	_check("E4 decals + pedrinhas + heightfield custam < 2 ms no p95", with_hf.p95 - base.p95 < 2.0,
		"Δp95 = %.2f ms" % (with_hf.p95 - base.p95))
	fx_root.queue_free()


func _frame_stats(seconds: float) -> Dictionary:
	var v := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		v.append((now - last) / 1000.0)
		last = now
	v.sort()
	if v.is_empty():
		return {"p50": 0.0, "p95": 0.0, "max": 0.0, "n": 0}
	return {"p50": v[int(v.size() * 0.5)], "p95": v[mini(v.size() - 1, int(v.size() * 0.95))], "max": v[v.size() - 1], "n": v.size()}


# --- Utilidades -----------------------------------------------------------------------------

func _extract(spot: Vector3, core: float) -> RigidBody3D:
	var hit := svc.raycast_terrain(spot + Vector3.UP * 5.0, spot + Vector3.DOWN * 10.0)
	if hit.is_empty():
		return null
	var out := svc.extract_rock(hit.position, Vector3.UP, core, props)
	if out.bodies.is_empty():
		_out("extração recusada em %s: %s" % [spot, (out.result as TerrainEditResult).reason])
		return null
	var rb: RigidBody3D = out.bodies[0]
	rb.set_meta("_hole", hit.position)
	return rb


func _timer_of(rb: RigidBody3D) -> Timer:
	for ch in rb.get_children():
		if ch is Timer:
			return ch
	return null


## O collider já tem a cavidade? Raio vertical no centro do buraco chega mais de 1 m abaixo da boca.
func _cavity_visible(hole: Vector3) -> bool:
	var hit := svc.raycast_terrain(hole + Vector3.UP * 1.0, hole + Vector3.DOWN * 6.0)
	return not hit.is_empty() and hit.position.y < hole.y - 1.0


## A forma da rocha (no transform atual) sobrepõe o collider do terreno? O collider é uma casca:
## uma rocha inteira dentro do sólido NÃO sobrepõe nada (medido no E1).
func _clear_of_terrain(rb: RigidBody3D) -> bool:
	for ch in rb.get_children():
		if ch is CollisionShape3D:
			var cs := ch as CollisionShape3D
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs.shape
			q.transform = cs.global_transform
			q.collision_mask = Layers.TERRAIN
			q.margin = 0.02
			return rb.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
	return false


func _track_speed(rb: RigidBody3D, frames: int) -> Dictionary:
	var out := {"max_speed": 0.0, "max_up": 0.0, "moved": 0.0}
	var p0 := rb.global_position
	for f in frames:
		await physics_frame
		out.max_speed = maxf(out.max_speed, rb.linear_velocity.length())
		out.max_up = maxf(out.max_up, rb.linear_velocity.y)
	out.moved = rb.global_position.distance_to(p0)
	return out


func _until(cond: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await physics_frame
	return false


func _seconds(s: float) -> void:
	await create_timer(s, true, true).timeout


func _check(id: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	_out("%s %s | %s" % ["OK  " if ok else "FAIL", id, detail])


func _finish() -> void:
	_out("")
	_out("RESULTADO: %s (%d falha(s))" % ["OK" if _fails == 0 else "FALHOU", _fails])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/p35"))
	var f := FileAccess.open(OUT_PATH if DisplayServer.get_name() == "headless" else OUT_PATH_WINDOW, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(0 if _fails == 0 else 1)


func _out(s: String) -> void:
	print(s)
	_lines.append(s)
