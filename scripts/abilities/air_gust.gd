class_name AirGust
extends Ability
## Ar — rajada (atlas ar-001). Toque: uma frente de pressão (casca esférica recortada por um cone)
## sai da mão, na direção da mira capturada no clique, e avança a `front_speed` até `max_range`.
## Cada corpo é decidido uma única vez por onda, no tick em que a casca alcança o seu centro:
##   - exposição = fração de raios livres (TERRAIN|PROPS, alvo excluído) até o centro e a silhueta;
##     zero = nenhum efeito; exposição parcial reduz impulso e AIRFLOW;
##   - impulso = min(massa × max_delta_v, impulse_cap) × força × exposição: a caixa leve voa
##     (Δv no teto) e a rocha maciça mal se mexe (Δv = impulse_cap / massa);
##   - evento AIRFLOW com força × exposição (apaga fogo fraco, aviva o forte).
## Força = 1 − (distância / alcance)^expoente. Corpos que entram na esteira depois da casca não
## são atingidos retroativamente. Sem antecipação: a própria frente é o telegraph.

## Resíduo de ponto flutuante: um cooldown múltiplo exato do tick não custa um tick a mais.
const COOLDOWN_EPSILON_S := 0.000001
const TUNING_PATH := "res://data/abilities/air_tuning.tres"
## Teto absoluto (pool visual de frentes); o limite editável nunca o excede.
const MAX_WAVES := 4

var tuning: AirTuning
var vortex := AirVortex.new()
var waves: Array[Dictionary] = []
## Última rajada (VFX legado e testes): {origin, dir, hit, blocked, partial, at_ms, wave_id}.
## `hit` cresce conforme a frente alcança os corpos.
var last_gust := {}
var _cooldown_left := 0.0
var _next_wave_id := 1
var _epoch := 0
var _stats := {"gusts": 0, "rejected": 0, "contacts": 0, "bodies_pushed": 0, "blocked": 0, "partial": 0,
	"outside_cone": 0, "behind_front": 0, "exposure_rays": 0, "ray_fallback_hits": 0, "waves_finished": 0,
	"stale_dropped": 0, "max_live": 0, "update_ticks": 0, "update_usec": 0, "update_usec_max": 0}


func _init() -> void:
	id = &"air_gust"
	element = &"air"
	display_name = "Rajada de ar"
	input_mode = "tap"
	tuning = load(TUNING_PATH)


func setup(p_controller) -> void:
	super.setup(p_controller)
	vortex.configure(p_controller, tuning, _exposure)


func get_stats() -> Dictionary:
	var data := _stats.duplicate()
	data["live_waves"] = waves.size()
	data["cooldown_left"] = _cooldown_left
	return data


func on_press() -> void:
	if vortex.active:
		return
	if _cooldown_left > COOLDOWN_EPSILON_S or waves.size() >= clampi(tuning.max_waves, 1, MAX_WAVES):
		_stats.rejected += 1
		last_result = "recuperando" if _cooldown_left > COOLDOWN_EPSILON_S else "muitas rajadas"
		return
	if controller == null or not controller.terrain_service.is_ready():
		return
	var origin: Vector3 = controller.hand_position()
	var dir: Vector3 = (controller.aim_point(tuning.max_range + 10.0) - origin).normalized()
	if dir.is_zero_approx():
		return
	var w := {"id": _next_wave_id, "origin": origin, "dir": dir,
		"push_dir": (dir + Vector3.UP * maxf(tuning.lift, 0.0)).normalized(),
		"radius": 0.0, "prev_radius": -1.0, "age": 0.0, "treated": {}, "hit": [], "blocked": 0, "partial": 0,
		"session": controller.session_id, "generation": controller.terrain_service.get_world_generation()}
	_next_wave_id += 1
	waves.append(w)
	_cooldown_left = maxf(tuning.cooldown_s, 0.0)
	_stats.gusts += 1
	_stats.max_live = maxi(_stats.max_live, waves.size())
	last_gust = {"origin": origin, "dir": dir, "hit": w.hit, "blocked": 0, "partial": 0,
		"at_ms": Time.get_ticks_msec(), "wave_id": w.id}
	last_result = "rajada"
	emit_fx(&"air_launch", {"wave_id": w.id, "position": origin, "direction": dir})


func physics_tick(delta: float) -> void:
	vortex.physics_tick(delta)
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if waves.is_empty():
		return
	# Custo de CPU do avanço (inclui consultas, exposição, impulsos e callbacks de FX).
	var t0 := Time.get_ticks_usec()
	_advance(delta)
	var spent := Time.get_ticks_usec() - t0
	_stats.update_ticks += 1
	_stats.update_usec += spent
	_stats.update_usec_max = maxi(_stats.update_usec_max, spent)


func _advance(delta: float) -> void:
	var epoch := _epoch
	var keep: Array[Dictionary] = []
	for w: Dictionary in waves.duplicate():
		if not _context_valid(w):
			_stats.stale_dropped += 1
			continue
		w.prev_radius = w.radius
		w.radius = minf(float(w.radius) + maxf(tuning.front_speed, 0.1) * delta, maxf(tuning.max_range, 0.0))
		w.age += delta
		_sweep(w)
		if epoch != _epoch:
			return
		if float(w.radius) >= maxf(tuning.max_range, 0.0) - 0.000001:
			_stats.waves_finished += 1
			emit_fx(&"air_end", {"wave_id": w.id, "position": (w.origin as Vector3) + (w.dir as Vector3) * float(w.radius),
				"contacts": (w.hit as Array).size(), "blocked": w.blocked, "partial": w.partial})
			if epoch != _epoch:
				return
			continue
		keep.append(w)
	if epoch == _epoch:
		waves = keep


## Reset/save/load descartam frentes e recuperação. A troca de elemento não cancela: a frente
## já emitida segue, como um projétil de fogo lançado.
func cancel() -> void:
	vortex.cancel()


func clear() -> void:
	vortex.clear()
	_epoch += 1
	waves.clear()
	_cooldown_left = 0.0


func status() -> String:
	return vortex.status() if vortex.active else last_result


func _context_valid(w: Dictionary) -> bool:
	return controller != null and int(w.session) == controller.session_id \
		and int(w.generation) == controller.terrain_service.get_world_generation() \
		and controller.terrain_service.is_ready()


## Corpos cujo centro a casca alcançou neste tick (prev_radius < d ≤ radius), uma vez por onda.
func _sweep(w: Dictionary) -> void:
	var epoch := _epoch
	var origin: Vector3 = w.origin
	var dir: Vector3 = w.dir
	var radius := float(w.radius)
	var treated: Dictionary = w.treated
	for body in controller.materials.bodies_in_sphere(origin, radius, 128):
		var key: int = body.get_instance_id()
		if treated.has(key):
			continue
		var c := MaterialResponseSystem.body_center(body)
		var to := c - origin
		var d := to.length()
		if d > radius:
			continue
		treated[key] = true
		if d <= float(w.prev_radius):
			_stats.behind_front += 1
			continue
		# Obstáculos estáticos (paredes de teste) bloqueiam visadas, mas não reagem ao ar.
		var rb := body as RigidBody3D
		if rb == null:
			continue
		if d > tuning.near_radius and rad_to_deg(to.angle_to(dir)) > tuning.half_angle_deg:
			_stats.outside_cone += 1
			continue
		var strength := 1.0 - pow(clampf(d / maxf(tuning.max_range, 0.01), 0.0, 1.0), maxf(tuning.falloff_exponent, 0.1))
		if strength <= 0.0:
			continue
		var exposure := _exposure(origin, body, c)
		if exposure <= 0.0:
			w.blocked += 1
			_stats.blocked += 1
			_sync_last(w)
			continue
		if exposure < 1.0:
			w.partial += 1
			_stats.partial += 1
		var effective := strength * exposure
		var impulse := 0.0
		if not rb.freeze:
			impulse = minf(rb.mass * maxf(tuning.max_delta_v, 0.0), maxf(tuning.impulse_cap, 0.0)) * effective
			rb.sleeping = false
			rb.apply_central_impulse((w.push_dir as Vector3) * impulse)
			_stats.bodies_pushed += 1
		_stats.contacts += 1
		(w.hit as Array).append(body)
		_sync_last(w)
		var e := ElementalEvent.make(ElementalEvent.Kind.AIRFLOW, c, effective, 0.0, id, dir)
		e.target = body
		emit_event(e)
		if epoch != _epoch:
			return
		emit_fx(&"air_contact", {"wave_id": w.id, "body_id": key, "position": c, "direction": w.push_dir, "distance": d,
			"strength": strength, "exposure": exposure, "impulse": impulse, "mass": rb.mass})
		if epoch != _epoch:
			return


func _sync_last(w: Dictionary) -> void:
	if int(last_gust.get("wave_id", -1)) == int(w.id):
		last_gust.blocked = w.blocked
		last_gust.partial = w.partial


## Fração de raios livres da origem até o centro e, com 5 amostras, até quatro pontos da silhueta
## perpendicular à frente. Máscara TERRAIN|PROPS, alvo excluído; testemunhas de ±1 mm só em falha.
func _exposure(origin: Vector3, body: Node3D, center: Vector3) -> float:
	if origin.distance_squared_to(center) < 0.000001:
		return 1.0 # Corpo no próprio eixo: não lançar raios de comprimento zero.
	var points: Array[Vector3] = [center]
	if tuning.exposure_samples >= 5:
		var axis := (center - origin).normalized()
		var side := axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
		var up := side.cross(axis).normalized()
		var reach := _half_extent(body) * clampf(tuning.silhouette_fraction, 0.1, 1.0)
		points.append_array([center + side * reach, center - side * reach, center + up * reach, center - up * reach])
	var exclude: Array[RID] = []
	if body is CollisionObject3D:
		exclude.append((body as CollisionObject3D).get_rid())
	var space: PhysicsDirectSpaceState3D = controller.player.get_world_3d().direct_space_state
	var free := 0
	for p in points:
		var q := PhysicsRayQueryParameters3D.create(origin, p, Layers.TERRAIN | Layers.PROPS, exclude)
		q.hit_from_inside = true
		q.hit_back_faces = true
		var hit := PhysicsRayHelper.intersect(space, q)
		_stats.exposure_rays += 1
		if hit.is_empty():
			free += 1
		else:
			_stats.ray_fallback_hits += int(hit.get("ray_fallback", false))
	return float(free) / float(points.size())


## Menor meia-extensão da malha (escala incluída): os pontos da silhueta ficam dentro do corpo.
static func _half_extent(body: Node3D) -> float:
	for ch in body.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			var size := mi.mesh.get_aabb().size * mi.global_basis.get_scale()
			return minf(size.x, minf(size.y, size.z)) * 0.5
	return 0.25
