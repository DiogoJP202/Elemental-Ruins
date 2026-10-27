class_name EarthLiftThrow
extends Ability
## Terra — erguer e arremessar rocha (atlas te-001; P3, polida no P3.5).
## Máquina de fases; tempos e forças em EarthTuning (data/abilities/earth_tuning.tres):
##   clique        primeiro alvo visível: rocha extraída existente → hold (P4B);
##                 chão válido a 2,5–7 m → extração em fases. Inválido → fx "invalid"
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
	"hold": "pronta: solte para arremessar", "windup": "lançando", "recovery": "recuperando",
	"pillar_pending": "pilar na fila de terreno"}

var tuning: EarthTuning
var rock: RigidBody3D
var phase := ""
var pillar_aiming := false
var _pillar_request: TerrainBrushRequest
var _pillar_shape := CapsuleShape3D.new()
## Fases percorridas: [{phase, ms, frame}] (testes e diagnóstico).
var phase_log: Array[Dictionary] = []
var _phase_t := 0.0
var _point := Vector3.ZERO
var _hold_dist := 4.0
var _hold_height := 2.0
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
	"last_ready_ms": -1, "last_cavity_wait_frames": -1, "reused": 0, "pillars": 0, "pillars_rejected": 0}


func _init() -> void:
	id = &"earth_lift_throw"
	element = &"earth"
	display_name = "Extrair ou reutilizar rocha"
	input_mode = "hold"
	tuning = load(TUNING_PATH) as EarthTuning
	if tuning == null:
		tuning = EarthTuning.new()
	_rng.seed = 7


func setup(p_controller) -> void:
	super.setup(p_controller)
	if controller.brush_queue != null:
		controller.brush_queue.brush_applied.connect(_on_pillar_applied)


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["phase"] = phase
	return d


func is_ready() -> bool:
	return phase == "hold"


## Em ação (fases ou rocha em voo): o HUD/FX esconde o marcador do pincel para não cobrir o poder.
func is_busy() -> bool:
	return pillar_aiming or phase != "" or not _thrown.is_empty()


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
	if pillar_aiming:
		var check := validate_pillar_target()
		return "RMB: solte para criar pilar %.1f m × Ø %.1f m · %s" % [tuning.pillar_height,
			tuning.pillar_radius * 2.0, "alvo válido" if check.ok else check.reason]
	if PHASE_NAMES.has(phase):
		var mass := rock.mass / 1000.0 if rock != null and is_instance_valid(rock) else 0.0
		var text := "%s%s" % [PHASE_NAMES[phase], (" (%.1f t)" % mass) if mass > 0.0 else ""]
		if phase == "hold":
			text += " · Q/E altura %.1f m%s · roda distância %.1f m%s" % [
				_hold_height, " (limite)" if _hold_height <= tuning.hold_min_height or _hold_height >= tuning.hold_max_height else "",
				_hold_dist, " (limite)" if _hold_dist <= tuning.min_range or _hold_dist >= tuning.max_range else ""]
		return text
	return last_result


# --- Entrada ----------------------------------------------------------------------------------

func begin_pillar() -> bool:
	if phase != "" or _button or controller.brush_queue == null:
		return false
	pillar_aiming = true
	return true


func finish_pillar() -> bool:
	if not pillar_aiming:
		return false
	pillar_aiming = false
	var check := validate_pillar_target()
	if not check.ok:
		_stats.invalid += 1
		last_result = "pilar recusado: %s" % check.reason
		emit_fx(&"invalid", {"point": check.get("point", Vector3.ZERO), "reason": check.reason})
		return false
	_pillar_request = check.request
	if not controller.brush_queue.enqueue(_pillar_request):
		_pillar_request = null
		last_result = "pilar recusado: fila indisponível"
		return false
	_set_phase("pillar_pending", {})
	return true


func make_pillar_request(point: Vector3, material_id: StringName) -> TerrainBrushRequest:
	var r := tuning.pillar_radius
	var req := TerrainBrushRequest.path(PackedVector3Array([point - Vector3.UP * r,
		point + Vector3.UP * (tuning.pillar_height - r)]), PackedFloat32Array([r, r]), true, material_id)
	req.source = "ability:earth_pillar"
	return req


## O primeiro obstáculo bloqueia a mira; o volume novo também precisa estar livre de corpos.
func validate_pillar_target() -> Dictionary:
	var ray: Array = controller.aim_ray()
	var hit: Dictionary = controller.cast_segment(ray[0], ray[0] + ray[1] * (tuning.pillar_range + 15.0), true)
	if hit.is_empty():
		return {"ok": false, "reason": "sem chão na mira"}
	var p: Vector3 = hit.position
	var out := {"ok": false, "reason": "", "point": p}
	var relative: Vector3 = p - controller.player.global_position
	if not hit.collider is VoxelLodTerrain or hit.normal.y < tuning.min_floor_normal_y:
		out.reason = "mire em chão livre"
	elif relative.length() > tuning.pillar_range:
		out.reason = "fora do alcance (máx. %.1f m)" % tuning.pillar_range
	elif Vector2(relative.x, relative.z).length() < tuning.min_range:
		out.reason = "perto demais (mín. %.1f m)" % tuning.min_range
	if out.reason != "":
		return out
	var mat: TerrainMaterial = controller.terrain_service.get_material_at(p - hit.normal * 0.5)
	var req := make_pillar_request(p, mat.id if mat != null else &"")
	out.request = req
	out.reason = TerrainBrushQueue.material_policy(req.op, mat)
	if out.reason == "":
		out.reason = controller.terrain_service.can_add_path(req.points, req.radii, req.material_id)
	# Um pilar é um pedido atômico; nunca entra no fracionamento de PATHs grandes da fila.
	var size := req.world_aabb().size
	if out.reason == "" and size[size.max_axis_index()] > controller.brush_queue.max_aabb_extent:
		out.reason = "dimensões excedem o limite da fila"
	if out.reason == "" and _pillar_space_blocked(req):
		out.reason = "há um corpo no espaço do pilar"
	out.ok = out.reason == ""
	return out


func _pillar_space_blocked(req: TerrainBrushRequest) -> bool:
	_pillar_shape.radius = req.radii[0]
	_pillar_shape.height = req.length() + 2.0 * req.radii[0]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _pillar_shape
	query.transform.origin = (req.points[0] + req.points[1]) * 0.5
	query.collision_mask = Layers.PROPS
	return not controller.player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _on_pillar_applied(request: TerrainBrushRequest, result: TerrainEditResult) -> void:
	if request != _pillar_request:
		return
	_pillar_request = null
	if result.ok:
		_stats.pillars += 1
		last_result = "pilar criado · colisão atualiza em seguida"
	else:
		_stats.pillars_rejected += 1
		last_result = "pilar recusado: %s" % result.reason
	_set_phase("recovery", {})

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
	_hold_height = clampf(tuning.hold_height, tuning.hold_min_height, tuning.hold_max_height)
	_color = check.color
	_release_buffered = false
	_time_scale = 1.0
	_cycle_start_ms = Time.get_ticks_msec()
	if check.has("rock"):
		rock = check.rock
		# Cada captura encerra o voo anterior, incluindo contatos ainda não despachados.
		for i in range(_thrown.size() - 1, -1, -1):
			if is_instance_valid(_thrown[i].body) and _thrown[i].body == rock:
				_untrack_throw(_thrown[i])
				_thrown.remove_at(i)
		if rock.has_meta(DebrisBudget.PARKED_META):
			DebrisBudget.unpark(rock)
		rock.freeze = false
		rock.sleeping = false
		rock.continuous_cd = true
		rock.gravity_scale = 0.0
		rock.angular_damp = tuning.hold_angular_damp
		rock.set_meta(DebrisBudget.EARTH_HELD_META, true)
		# A mesma transição de hold parte do centro atual, sem zerar a velocidade.
		_rise_to = center_of(rock)
		_prev_target = _rise_to
		_hold_t = 0.0
		_stats.reused += 1
		_stats.last_ready_ms = 0
		_set_phase("hold", {"rock": rock, "ready_ms": 0, "reused": true})
		last_result = "rocha reutilizada"
		return
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


func can_manipulate() -> bool:
	return phase == "hold" and _button and is_instance_valid(rock)


func on_hold(delta: float) -> void:
	if controller.can_manipulate_earth():
		_hold_height = clampf(_hold_height + Input.get_axis(&"earth_lower", &"earth_raise")
			* tuning.hold_height_speed * delta, tuning.hold_min_height, tuning.hold_max_height)


func adjust_hold_distance(delta: float) -> void:
	if can_manipulate():
		_hold_dist = clampf(_hold_dist + delta, tuning.min_range, tuning.max_range)


## Primeiro alvo visível: {ok, reason, point, normal, dist, color, rock?}.
## `rock` só existe no resultado de uma captura válida; caixas e paredes bloqueiam a mira.
## Também usado pelo HUD para o preview (verde/vermelho).
func validate_target() -> Dictionary:
	var ray: Array = controller.aim_ray()
	var aim: Dictionary = controller.cast_segment(ray[0], ray[0] + ray[1] * (tuning.max_range + 15.0), true)
	if aim.is_empty():
		return {"ok": false, "reason": "sem chão na mira"}
	var p: Vector3 = aim.position
	var n: Vector3 = aim.normal
	var pl: Vector3 = controller.player.global_position
	var dist := Vector2(p.x - pl.x, p.z - pl.z).length()
	var r := {"ok": false, "reason": "", "point": p, "normal": n, "dist": dist, "color": Color.GRAY}
	if not aim.collider is VoxelLodTerrain:
		var body := aim.collider as RigidBody3D
		if body == null or not body.has_meta("volume_m3"):
			r.reason = "mire no chão ou em uma rocha extraída"
			return r
		var center := center_of(body)
		r.point = center
		r.normal = Vector3.UP
		r.dist = Vector2(center.x - pl.x, center.z - pl.z).length()
		if center.distance_to(pl) > tuning.max_range:
			r.reason = "rocha longe demais (máx. %.1f m)" % tuning.max_range
			return r
		r.ok = true
		r.rock = body
		var material := TerrainMaterialLibrary.get_by_id(body.get_meta("material_id", &""))
		if material != null:
			r.color = material.surface_color
		return r
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
	pillar_aiming = false
	if _pillar_request != null:
		controller.brush_queue.cancel_request(_pillar_request)
		_pillar_request = null
		_end_quietly()
	_button = false
	if phase in ["anticipation", "detach", "rise", "hold", "windup"]:
		_abort("cancelado")


func clear() -> void:
	cancel()
	for entry in _thrown:
		_untrack_throw(entry)
	_thrown.clear()
	rock = null
	phase = ""
	_button = false
	_release_buffered = false
	_hold_dist = 4.0
	_hold_height = tuning.hold_height


# --- Fases ------------------------------------------------------------------------------------

func physics_tick(delta: float) -> void:
	_tick_thrown()
	# Controladores rodam antes da fila (priority 100): revalidar o volume fixo enquanto
	# espera, inclusive se um corpo entrou depois de soltar RMB. Nunca seguir a mira nova.
	if _pillar_request != null and _pillar_space_blocked(_pillar_request):
		var request := _pillar_request
		controller.brush_queue.cancel_request(request)
		_on_pillar_applied(request, TerrainEditResult.failure("add_path", "corpo no espaço do pilar"))
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
	rock.set_meta(DebrisBudget.EARTH_HELD_META, true)
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


## Alvo relativo aos pés: yaw da câmera, distância pela roda e altura por Q/E.
## Somente o alvo muda; a rocha segue por forças, inclusive contra obstáculos.
func hold_target() -> Vector3:
	var fwd: Vector3 = controller.aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return controller.player.global_position + fwd * _hold_dist + Vector3.UP * _hold_height


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
	rock.remove_meta(DebrisBudget.EARTH_HELD_META)
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
			_untrack_throw(e)
			continue
		e.prev_vel = b.linear_velocity
		keep.append(e)
	_thrown = keep


## O mesmo corpo pode ser relançado: nenhum callback do voo anterior deve sobreviver.
func _untrack_throw(entry: Dictionary) -> void:
	if not is_instance_valid(entry.body):
		return
	var body: RigidBody3D = entry.body
	var callback := _on_rock_contact.bind(entry)
	if body.body_entered.is_connected(callback):
		body.body_entered.disconnect(callback)
	body.contact_monitor = false


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
		rock.remove_meta(DebrisBudget.EARTH_HELD_META)
	rock = null
	_stats.cancelled += 1
	last_result = reason
	emit_fx(&"cancel", {"reason": reason})
	_end_quietly()


func _end_quietly() -> void:
	phase = ""
	_phase_t = 0.0
	_release_buffered = false
	_button = false
	_hold_dist = 4.0
	_hold_height = tuning.hold_height
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
