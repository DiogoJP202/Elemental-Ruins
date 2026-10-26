class_name EarthLiftThrow
extends Ability
## Terra — erguer e arremessar rocha (atlas te-001; P3, polida no P3.5).
## Máquina de fases; tempos e forças em EarthTuning (data/abilities/earth_tuning.tres):
##   clique        valida o alvo (2,5–7 m do jogador, chão, área editável, material, sem prender
##                 o jogador). Inválido → fx "invalid" e nada acontece
##   anticipation  terreno intacto; só telegraph (FX: rachadura, poeira, pedrinhas)
##   detach        extract_rock com o Timer do Voxel Tools parado: a rocha fica congelada no buraco
##                 até o fim da fase E o collider da cavidade confirmado (spike P3.5 E1/E2);
##                 o tremor e a subida da malha são só visuais (EarthFx)
##   rise          trajetória vertical planejada (smoothstep) seguida por PD + aceleração de
##                 alimentação direta, com teto (spike E3); gravidade desligada; giro leve
##   hold          pronta: mola "pesada" atrás do ponto à frente do jogador, com balanço
##   windup        recua um pouco e lança (impulso + topspin). Soltar o LMB antes de pronta
##                 guarda o lançamento (ou cancela, conforme o tuning)
##   recovery      intervalo curto antes de aceitar um novo clique
## Impacto: 1º contato com CORPOS → KINETIC dividido entre os tocados no mesmo passo; 1º contato
## com o TERRENO acima de crater_min_speed → cratera real pela TerrainBrushQueue. A rocha fica
## como destroço. Toda a física é por forças e impulsos; o resto sai por fx_event.

const TUNING_PATH := "res://data/abilities/earth_tuning.tres"
## Mola do P3 (ainda usada por spring_force sem parâmetros).
const OMEGA := 6.0
const MAX_ACCEL := 40.0
const PHASE_LOG_MAX := 32
const PHASE_NAMES := {"anticipation": "antecipação", "detach": "desprendendo", "rise": "erguendo",
	"hold": "pronta: solte para arremessar", "windup": "lançando", "recovery": "recuperando"}

var tuning: EarthTuning
var rock: RigidBody3D
var phase := ""
## Fases percorridas: [{phase, ms, frame}] (testes e diagnóstico).
var phase_log: Array[Dictionary] = []
var _phase_t := 0.0
var _point := Vector3.ZERO
var _hold_dist := 4.0
var _color := Color.GRAY
var _button := false
var _release_buffered := false
var _time_scale := 1.0
var _rise_from := Vector3.ZERO
var _rise_to := Vector3.ZERO
var _hold_t := 0.0
var _prev_target := Vector3.ZERO
var _cycle_start_ms := 0
var _rng := RandomNumberGenerator.new()
var _thrown := []
var _stats := {"extracted": 0, "thrown": 0, "hits": 0, "max_impulse": 0.0, "invalid": 0, "failed": 0,
	"ground_impacts": 0, "craters": 0, "craters_rejected": 0, "buffered_throws": 0, "cancelled": 0,
	"last_ready_ms": -1, "last_cavity_wait_frames": -1}


func _init() -> void:
	id = &"earth_lift_throw"
	element = &"earth"
	display_name = "Erguer e arremessar rocha"
	input_mode = "hold"
	tuning = load(TUNING_PATH) as EarthTuning
	if tuning == null:
		tuning = EarthTuning.new()
	_rng.seed = 7


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["phase"] = phase
	return d


func is_ready() -> bool:
	return phase == "hold"


## Em ação (fases ou rocha em voo): o HUD/FX esconde o marcador do pincel para não cobrir o poder.
func is_busy() -> bool:
	return phase != "" or not _thrown.is_empty()


## 0 → 1 do clique até a rocha pronta (anel do HUD).
func ready_progress() -> float:
	var a := tuning.anticipation_s
	var d := tuning.detach_s * _time_scale
	var r := tuning.rise_s * _time_scale
	var total := a + d + r
	match phase:
		"anticipation":
			return clampf(_phase_t / total, 0.0, 1.0)
		"detach":
			return clampf((a + minf(_phase_t, d)) / total, 0.0, 1.0)
		"rise":
			return clampf((a + d + _phase_t) / total, 0.0, 1.0)
		"hold", "windup":
			return 1.0
	return 0.0


func move_speed_scale() -> float:
	return tuning.hold_move_speed_scale if phase in ["detach", "rise", "hold", "windup"] else 1.0


func status() -> String:
	if PHASE_NAMES.has(phase):
		var mass := rock.mass / 1000.0 if rock != null and is_instance_valid(rock) else 0.0
		return "%s%s" % [PHASE_NAMES[phase], (" (%.1f t)" % mass) if mass > 0.0 else ""]
	return last_result


# --- Entrada ----------------------------------------------------------------------------------

func on_press() -> void:
	_button = true
	if phase != "":
		return  # já em curso ou em recuperação
	var check := validate_target()
	if not check.ok:
		_stats.invalid += 1
		last_result = "alvo inválido: %s" % check.reason
		emit_fx(&"invalid", {"point": check.get("point", Vector3.ZERO), "reason": check.reason})
		return
	_point = check.point
	_hold_dist = clampf(check.dist, tuning.min_range, tuning.max_range)
	_color = check.color
	_release_buffered = false
	_time_scale = 1.0
	_cycle_start_ms = Time.get_ticks_msec()
	_set_phase("anticipation", {"point": _point, "color": _color, "radius": tuning.rock_radius,
		"duration": tuning.anticipation_s})
	last_result = "erguendo rocha"


func on_release() -> void:
	_button = false
	match phase:
		"anticipation", "detach", "rise":
			if tuning.buffer_release:
				_release_buffered = true
			else:
				_abort("soltou antes de a rocha ficar pronta")
		"hold":
			_begin_windup()


## O ponto sob a mira serve de origem para uma rocha? {ok, reason, point, normal, dist, color}.
## Também usado pelo HUD para o preview (verde/vermelho).
func validate_target() -> Dictionary:
	var aim: Dictionary = controller.aim_terrain(tuning.max_range + 15.0)
	if aim.is_empty():
		return {"ok": false, "reason": "sem chão na mira"}
	var p: Vector3 = aim.position
	var n: Vector3 = aim.normal
	var pl: Vector3 = controller.player.global_position
	var dist := Vector2(p.x - pl.x, p.z - pl.z).length()
	var r := {"ok": false, "reason": "", "point": p, "normal": n, "dist": dist, "color": Color.GRAY}
	if n.y < tuning.min_floor_normal_y:
		r.reason = "não é chão"
	elif dist > tuning.max_range:
		r.reason = "longe demais (%.1f m > %.1f)" % [dist, tuning.max_range]
	elif dist < tuning.min_range:
		r.reason = "perto demais (%.1f m < %.1f)" % [dist, tuning.min_range]
	else:
		r.reason = controller.terrain_service.can_extract_rock(p, Vector3.UP, tuning.rock_radius)
	if r.reason == "":
		r.ok = true
		var mat: TerrainMaterial = controller.terrain_service.get_material_at(p)
		if mat != null:
			r.color = mat.surface_color
	return r


func cancel() -> void:
	_button = false
	if phase in ["anticipation", "detach", "rise", "hold", "windup"]:
		_abort("cancelado")


func clear() -> void:
	_thrown.clear()
	rock = null
	phase = ""
	_release_buffered = false


# --- Fases ------------------------------------------------------------------------------------

func physics_tick(delta: float) -> void:
	_tick_thrown()
	if phase in ["detach", "rise", "hold", "windup"] and (rock == null or not is_instance_valid(rock)):
		rock = null
		_end_quietly()
		return
	match phase:
		"anticipation":
			_phase_t += delta
			if _done(tuning.anticipation_s):
				_begin_detach()
		"detach":
			_phase_t += delta
			var length := tuning.detach_s * _time_scale
			if _done(length):
				var confirmed: bool = controller.terrain_service.cavity_confirmed(_point)
				if confirmed or _phase_t >= length + tuning.cavity_confirm_timeout_s:
					_begin_rise(confirmed)
		"rise":
			_tick_rise(delta)
		"hold":
			_hold_t += delta
			_push_to(hold_point(), tuning.hold_omega, tuning.hold_feedforward, tuning.hold_max_accel)
		"windup":
			_tick_windup(delta)
		"recovery":
			_phase_t += delta
			if _done(tuning.recovery_s):
				_end_quietly()


func _begin_detach() -> void:
	var out: Dictionary = controller.terrain_service.extract_rock(_point, Vector3.UP, tuning.rock_radius,
		controller.props_root, Vector3.ZERO, true)
	var result: TerrainEditResult = out.result
	if result == null or not result.ok or out.bodies.is_empty():
		_stats.failed += 1
		last_result = "não extraiu: %s" % (result.reason if result != null else "?")
		emit_fx(&"invalid", {"point": _point, "reason": last_result})
		_end_quietly()
		return
	rock = out.bodies[0]
	rock.continuous_cd = true
	_stats.extracted += 1
	_time_scale = tuning.time_scale_for(rock.mass)
	_set_phase("detach", {"rock": rock, "point": _point, "color": _color, "duration": tuning.detach_s * _time_scale,
		"visual_rise": tuning.detach_visual_rise, "shake": tuning.detach_shake, "mass": rock.mass})


func _begin_rise(cavity_confirmed: bool) -> void:
	_stats.last_cavity_wait_frames = roundi((_phase_t - tuning.detach_s * _time_scale) * Engine.physics_ticks_per_second)
	rock.freeze = false
	rock.gravity_scale = 0.0
	rock.sleeping = false
	_rise_from = center_of(rock)
	_rise_to = Vector3(_rise_from.x, _point.y + tuning.hold_height, _rise_from.z)
	var axis := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
	rock.apply_torque_impulse(axis * tuning.rise_spin * _inertia(rock))
	_set_phase("rise", {"rock": rock, "point": _point, "color": _color, "duration": tuning.rise_s * _time_scale,
		"cavity_confirmed": cavity_confirmed})


## Smoothstep da posição atual (no buraco) até a altura de hold, seguido por PD com aceleração
## de alimentação direta e teto (spike P3.5 E3: sem sobressinal até 23 t a 160 ms).
func _tick_rise(delta: float) -> void:
	_phase_t += delta
	var T := tuning.rise_s * _time_scale
	var u := clampf(_phase_t / T, 0.0, 1.0)
	var span := _rise_to - _rise_from
	var x_d := _rise_from + span * (u * u * (3.0 - 2.0 * u))
	var v_d := span * (6.0 * u * (1.0 - u) / T) if u < 1.0 else Vector3.ZERO
	var a_d := span * ((6.0 - 12.0 * u) / (T * T)) if u < 1.0 else Vector3.ZERO
	var w := tuning.rise_track_omega
	var acc := a_d + (x_d - center_of(rock)) * w * w + (v_d - rock.linear_velocity) * 2.0 * w
	rock.apply_central_force(acc.limit_length(tuning.rise_max_accel) * rock.mass)
	if _done(T):
		_hold_t = 0.0
		_prev_target = _rise_to
		rock.angular_damp = tuning.hold_angular_damp
		_stats.last_ready_ms = Time.get_ticks_msec() - _cycle_start_ms
		_set_phase("hold", {"rock": rock, "ready_ms": _stats.last_ready_ms})
		last_result = "pronta"
		if _release_buffered or not _button:
			_stats.buffered_throws += 1
			_begin_windup()


func _begin_windup() -> void:
	_set_phase("windup", {"rock": rock, "duration": tuning.windup_s})
	if tuning.windup_s <= 0.0:
		_launch()


func _tick_windup(delta: float) -> void:
	_phase_t += delta
	_hold_t += delta
	var base := hold_point()
	var back: Vector3 = controller.player.global_position + Vector3.UP * tuning.hold_height - base
	back.y = 0.0
	var k := clampf(_phase_t / maxf(tuning.windup_s, 0.001), 0.0, 1.0)
	var target: Vector3 = base + back.normalized() * tuning.windup_pullback * k * k * (3.0 - 2.0 * k)
	_push_to(target, tuning.hold_omega * 1.5, tuning.hold_feedforward, tuning.hold_max_accel * 2.0)
	if _done(tuning.windup_s):
		_launch()


## Ponto do hold com transição desde o topo da subida e balanço vertical.
func hold_point() -> Vector3:
	var k := clampf(_hold_t / maxf(tuning.hold_settle_s, 0.001), 0.0, 1.0)
	var p := _rise_to.lerp(hold_target(), k * k * (3.0 - 2.0 * k))
	p.y += sin(TAU * tuning.hold_bob_hz * _hold_t) * tuning.hold_bob_amplitude
	return p


## Ponto de suspensão relativo ao jogador: à frente (direção horizontal da câmera), na distância
## em que a rocha foi arrancada, a hold_height acima dos pés.
func hold_target() -> Vector3:
	var fwd: Vector3 = controller.aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return controller.player.global_position + fwd * _hold_dist + Vector3.UP * tuning.hold_height


func _push_to(target: Vector3, omega: float, feedforward: float, max_accel: float) -> void:
	var tv := (target - _prev_target) * Engine.physics_ticks_per_second * feedforward
	_prev_target = target
	rock.apply_central_force(spring_force(rock, target, tv, center_of(rock), omega, max_accel))


# --- Lançamento e impacto ---------------------------------------------------------------------

func _launch() -> void:
	if rock == null or not is_instance_valid(rock):
		_end_quietly()
		return
	if rock.freeze:
		rock.freeze = false
	var dir: Vector3 = controller.aim_direction()
	var launch := dir * tuning.throw_speed
	# A própria rocha costuma estar entre a câmera e o alvo: fica fora do raio de mira.
	var exclude: Array[RID] = [rock.get_rid()]
	var hit: Dictionary = controller.aim_any(tuning.aim_range, exclude)
	if not hit.is_empty():
		# O centro da rocha chega no ponto mirado, mas nunca abaixo de uma meia altura acima do
		# chão sob ele: mirado no pé de uma caixa, o centro de uma rocha de ~2 m baixo demais
		# raspava o chão antes e quicava por cima (medido no T29).
		var aim_point: Vector3 = hit.position
		var ground: Dictionary = controller.terrain_service.raycast_terrain(aim_point + Vector3.UP * 0.5, aim_point + Vector3.DOWN * 20.0)
		if not ground.is_empty():
			aim_point.y = maxf(aim_point.y, ground.position.y + half_height(rock))
		var to: Vector3 = aim_point - center_of(rock)
		var flight := to.length() / tuning.throw_speed
		launch = to.normalized() * tuning.throw_speed + Vector3.UP * (9.8 * flight * 0.5)
	rock.gravity_scale = 1.0
	rock.angular_damp = 0.0
	rock.contact_monitor = true
	rock.max_contacts_reported = 8
	rock.apply_central_impulse((launch - rock.linear_velocity) * rock.mass)
	var spin_axis := Vector3.UP.cross(launch.normalized())
	if spin_axis.length() > 0.01:
		rock.apply_torque_impulse(spin_axis.normalized() * tuning.throw_spin * _inertia(rock))
	var entry := {"body": rock, "prev_vel": launch, "until_ms": Time.get_ticks_msec() + int(tuning.impact_monitor_s * 1000.0),
		"hit": false, "hit_frame": -1, "impulse": 0.0, "dir": Vector3.ZERO, "targets": [], "sent": false, "origin": Vector3.ZERO,
		"ground": false, "ground_sent": false, "ground_speed": 0.0, "ground_point": Vector3.ZERO,
		"launch_point": center_of(rock)}
	_thrown.append(entry)
	rock.body_entered.connect(_on_rock_contact.bind(entry))
	_stats.thrown += 1
	emit_fx(&"launch", {"rock": rock, "velocity": launch, "point": center_of(rock)})
	last_result = "arremessada a %.0f m/s" % tuning.throw_speed
	rock = null
	_set_phase("recovery", {})


func _tick_thrown() -> void:
	var now := Time.get_ticks_msec()
	var keep := []
	for e in _thrown:
		# Checar antes de atribuir a uma variável tipada: a rocha pode ter sido liberada (reset).
		if not is_instance_valid(e.body):
			continue
		var b: RigidBody3D = e.body
		if e.ground and not e.ground_sent:
			_dispatch_ground(e)
		if e.hit and not e.sent:
			_dispatch_impact(e)
		if now > e.until_ms or e.hit:
			b.contact_monitor = false
			continue
		e.prev_vel = b.linear_velocity
		keep.append(e)
	_thrown = keep


## 1º passo de física com contato em CORPOS: impulso estimado = massa × velocidade perdida nesse
## passo (spike P3, H2), dividido igualmente entre todos os corpos tocados no mesmo passo:
## atribuir tudo ao 1º relatado quebrava a peça errada quando a rocha tocava duas ao mesmo tempo
## (medido no T30). O 1º contato com o TERRENO é guardado à parte (FX e cratera) e não encerra o
## voo: a rocha pode raspar o chão e seguir.
func _on_rock_contact(other: Node, entry: Dictionary) -> void:
	if not is_instance_valid(entry.body):
		return
	var b: RigidBody3D = entry.body
	if other is VoxelLodTerrain:
		if center_of(b).distance_to(entry.launch_point) < tuning.ground_grace_m:
			return  # carência: raspar a borda do próprio buraco ao sair não é impacto
		if not entry.ground:
			entry.ground = true
			entry.ground_speed = (entry.prev_vel as Vector3).length()
			entry.ground_point = _ground_contact_point(b, entry.prev_vel)
		return
	var target := other as Node3D
	if target == null:
		return
	var frame := Engine.get_physics_frames()
	if entry.hit:
		if frame == entry.hit_frame and not entry.sent and not entry.targets.has(target):
			entry.targets.append(target)
		return
	entry.hit = true
	entry.hit_frame = frame
	entry.impulse = b.mass * (entry.prev_vel - b.linear_velocity).length()
	entry.dir = entry.prev_vel
	entry.targets = [target]
	entry.origin = center_of(b)
	_stats.hits += 1
	_stats.max_impulse = maxf(_stats.max_impulse, entry.impulse)


func _dispatch_impact(entry: Dictionary) -> void:
	entry.sent = true
	var n: int = entry.targets.size()
	for t in entry.targets:
		if not is_instance_valid(t):
			continue
		var e := ElementalEvent.make(ElementalEvent.Kind.KINETIC, entry.origin, entry.impulse / n, 0.0, id, entry.dir)
		e.target = t
		emit_event(e)
	emit_fx(&"impact_body", {"point": entry.origin, "impulse": entry.impulse, "targets": n, "velocity": entry.dir})


## Impacto no chão: FX acima de impact_fx_min_speed; cratera real (pela fila, D17) acima de
## crater_min_speed, uma por arremesso.
func _dispatch_ground(entry: Dictionary) -> void:
	entry.ground_sent = true
	var speed: float = entry.ground_speed
	if speed < tuning.impact_fx_min_speed:
		return
	_stats.ground_impacts += 1
	var crater := false
	if tuning.crater_enabled and speed >= tuning.crater_min_speed and controller.brush_queue != null:
		crater = controller.brush_queue.enqueue(TerrainBrushRequest.sphere(TerrainBrushRequest.Op.REMOVE,
			entry.ground_point, tuning.crater_radius))
		if crater:
			_stats.craters += 1
		else:
			_stats.craters_rejected += 1
	emit_fx(&"impact_ground", {"point": entry.ground_point, "speed": speed, "crater": crater,
		"radius": tuning.crater_radius})


## Ponto de contato aproximado com o chão: raio do centro na direção do voo (e para baixo).
func _ground_contact_point(b: RigidBody3D, vel: Vector3) -> Vector3:
	var c := center_of(b)
	var reach := half_height(b) * 2.0 + 1.0
	for dir in [vel.normalized(), Vector3.DOWN]:
		if (dir as Vector3).length() < 0.5:
			continue
		var hit: Dictionary = controller.terrain_service.raycast_terrain(c, c + (dir as Vector3) * reach)
		if not hit.is_empty():
			return hit.position
	return c + Vector3.DOWN * half_height(b)


# --- Encerramentos ----------------------------------------------------------------------------

## Interrompe e solta a rocha (se houver) com a gravidade de volta.
func _abort(reason: String) -> void:
	if rock != null and is_instance_valid(rock):
		if rock.freeze:
			rock.freeze = false
		rock.gravity_scale = 1.0
		rock.angular_damp = 0.0
	rock = null
	_stats.cancelled += 1
	last_result = reason
	emit_fx(&"cancel", {"reason": reason})
	_end_quietly()


func _end_quietly() -> void:
	phase = ""
	_phase_t = 0.0
	_release_buffered = false
	_log_phase("")


func _set_phase(p: String, data: Dictionary) -> void:
	phase = p
	_phase_t = 0.0
	_log_phase(p)
	emit_fx(StringName(p), data)


func _log_phase(p: String) -> void:
	phase_log.append({"phase": p, "ms": Time.get_ticks_msec(), "frame": Engine.get_physics_frames()})
	if phase_log.size() > PHASE_LOG_MAX:
		phase_log.pop_front()


## Fase com `length` segundos terminou? (folga contra o acúmulo de 1/60 em ponto flutuante)
func _done(length: float) -> bool:
	return _phase_t + 0.0001 >= length


# --- Utilidades -------------------------------------------------------------------------------

## Mola-amortecedor criticamente amortecida (k = mω², c = 2mω), com teto de aceleração.
## `at` é o ponto controlado (o centro da rocha, não a origem do corpo).
static func spring_force(body: RigidBody3D, target: Vector3, target_vel: Vector3, at: Vector3,
		omega := OMEGA, max_accel := MAX_ACCEL) -> Vector3:
	var k := body.mass * omega * omega
	var c := 2.0 * body.mass * omega
	var f := (target - at) * k + (target_vel - body.linear_velocity) * c
	return f.limit_length(body.mass * max_accel)


## Momento de inércia aproximado (esfera sólida do tamanho da malha), para converter rad/s em
## impulso angular.
static func _inertia(body: RigidBody3D) -> float:
	var r := half_height(body)
	return 0.4 * body.mass * r * r


static func half_height(body: RigidBody3D) -> float:
	for ch in body.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			return (ch as MeshInstance3D).mesh.get_aabb().size.y * 0.5
	return 0.5


## Centro da malha no mundo. O corpo criado por separate_floating_chunks tem a origem no canto
## da caixa do pedaço (~3 m do centro): mirar ou segurar pela origem erra o alvo (medido no T29).
static func center_of(body: RigidBody3D) -> Vector3:
	return MaterialResponseSystem.body_center(body)
