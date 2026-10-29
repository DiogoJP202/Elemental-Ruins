class_name AirVortex
extends Ability
## Campo fixo do RMB composto no AirGust. Só aplica forças, sem possuir/controlar os corpos.
## Candidatos/exposição são limitados; a visada central é conferida novamente em cada tick.
const MATERIAL_INTERVAL_S := 1.0
var tuning: AirTuning
var active := false
var center := Vector3.ZERO
var age := 0.0
var _exposure_query := Callable()
var _candidates: Array[Dictionary] = []
var _query_clock := 0.0
var _material_clock := 0.0
var _session := -1
var _generation := -1
var _epoch := 0
var _budget: DebrisBudget
var _stats := {"formed": 0, "cancelled": 0, "rejected": 0, "queries": 0,
	"force_ticks": 0, "bodies_forced": 0, "blocked": 0, "los_checks": 0, "unparked": 0,
	"material_events": 0, "max_force_applied": 0.0, "max_speed_seen": 0.0, "last_forced": 0}


func _init() -> void:
	id = &"air_vortex"
	element = &"air"
	display_name = "Vórtice de ar"


func configure(p_controller, p_tuning: AirTuning, exposure: Callable) -> void:
	setup(p_controller)
	tuning = p_tuning
	_exposure_query = exposure
	_budget = p_controller.props_root.get_parent().get_node_or_null(^"DebrisBudget") as DebrisBudget


func get_stats() -> Dictionary:
	var data := _stats.duplicate()
	data["active"] = active
	data["cached_bodies"] = _candidates.size()
	data["age"] = age
	return data


func validate_target() -> Dictionary:
	if controller == null or not controller._can_act():
		return {"ok": false, "reason": "terreno ou input indisponível"}
	var ray: Array = controller.aim_ray()
	var hit: Dictionary = controller.cast_segment(ray[0], ray[0] + ray[1] * (tuning.vortex_range + 15.0), true)
	if hit.is_empty():
		return {"ok": false, "reason": "sem chão na mira"}
	var point: Vector3 = hit.position
	if not hit.collider is VoxelLodTerrain or hit.normal.y < 0.8:
		return {"ok": false, "reason": "mire em chão livre"}
	if point.distance_to(controller.player.global_position) > tuning.vortex_range:
		return {"ok": false, "reason": "fora do alcance do vórtice"}
	var r := maxf(tuning.vortex_radius, 0.1)
	var area := AABB(point - Vector3(r, 0.1, r), Vector3(r * 2.0, tuning.vortex_height + 0.2, r * 2.0))
	if not controller.terrain_service.can_edit_area(area):
		return {"ok": false, "reason": "área não carregada"}
	if not controller.cast_segment(controller.hand_position(), point + Vector3.UP * 0.1, true).is_empty():
		return {"ok": false, "reason": "caminho bloqueado"}
	return {"ok": true, "reason": "", "point": point}


func begin() -> bool:
	if active or controller == null or controller.current_ability().id != &"air_gust":
		return false
	var check := validate_target()
	if not check.ok:
		_stats.rejected += 1
		last_result = check.reason
		return false
	center = check.point
	active = true
	age = 0.0
	_query_clock = 0.0
	_material_clock = 0.0
	_candidates.clear()
	_session = controller.session_id
	_generation = controller.terrain_service.get_world_generation()
	_epoch += 1
	_stats.formed += 1
	last_result = "vórtice ativo"
	emit_fx(&"vortex_started", {"position": center})
	return active


func cancel() -> void:
	if not active:
		return
	active = false
	_epoch += 1
	_candidates.clear()
	_query_clock = 0.0
	_material_clock = 0.0
	_stats.last_forced = 0
	_stats.cancelled += 1
	last_result = "vórtice dissipado"
	emit_fx(&"vortex_ended", {"position": center})


func clear() -> void:
	cancel()


func _valid_context() -> bool:
	return controller != null and controller._can_act() and controller.session_id == _session \
		and controller.terrain_service.get_world_generation() == _generation \
		and controller.current_ability().id == &"air_gust" \
		and (not controller.require_captured_mouse or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func _eligible(body: RigidBody3D) -> bool:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or body.has_meta(DebrisBudget.EARTH_HELD_META) \
			or (body is IceBody and (body as IceBody).wall_anchored):
		return false
	if not body.freeze:
		return true
	# Estacionamento por distância pertence ao orçamento, inclusive quando o jogador se afasta.
	return body.get_meta(DebrisBudget.PARKED_META, "") == "budget" and is_instance_valid(_budget) \
		and body.global_position.distance_to(controller.player.global_position) < _budget.unpark_distance


func _inside(point: Vector3) -> bool:
	var offset := point - center
	return offset.y >= 0.0 and offset.y <= tuning.vortex_height \
		and Vector2(offset.x, offset.z).length_squared() <= tuning.vortex_radius * tuning.vortex_radius


func _axis_at(point: Vector3) -> Vector3:
	return Vector3(center.x, maxf(center.y + 0.05, point.y), center.z)


func _refresh() -> void:
	_candidates.clear()
	_stats.queries += 1
	var r := maxf(tuning.vortex_radius, 0.1)
	if not controller.terrain_service.can_edit_area(AABB(center - Vector3(r, 0.1, r), Vector3(r * 2.0, tuning.vortex_height + 0.2, r * 2.0))):
		return # Sem manter forças sobre uma área que saiu do terreno carregado.
	var middle := center + Vector3.UP * tuning.vortex_height * 0.5
	var reach := Vector2(tuning.vortex_radius, tuning.vortex_height * 0.5).length()
	var found: Array[Node3D] = controller.materials.bodies_in_sphere(middle, reach, 64)
	var bodies: Array[RigidBody3D] = []
	for node: Node3D in found:
		var body := node as RigidBody3D
		if body != null and _eligible(body) and _inside(MaterialResponseSystem.body_center(body)):
			bodies.append(body)
	bodies.sort_custom(func(a: RigidBody3D, b: RigidBody3D):
		return MaterialResponseSystem.body_center(a).distance_squared_to(middle) < MaterialResponseSystem.body_center(b).distance_squared_to(middle))
	for body: RigidBody3D in bodies.slice(0, clampi(tuning.vortex_max_bodies, 1, 24)):
		var point := MaterialResponseSystem.body_center(body)
		var exposure := float(_exposure_query.call(_axis_at(point), body, point))
		if exposure <= 0.0:
			_stats.blocked += 1
		_candidates.append({"body": weakref(body), "exposure": exposure})


func _edge_weight(point: Vector3) -> float:
	var distance := Vector2(point.x - center.x, point.z - center.z).length()
	return 1.0 - smoothstep(0.85, 1.0, distance / maxf(tuning.vortex_radius, 0.1))


func _force(body: RigidBody3D, point: Vector3, exposure: float) -> Vector3:
	var r := maxf(tuning.vortex_radius, 0.1)
	var offset := Vector3(point.x - center.x, 0.0, point.z - center.z)
	var distance := offset.length()
	var edge := _edge_weight(point)
	# Lineares perto do eixo: não existe divisão por distância tendendo a zero.
	var accel := -offset / r * maxf(tuning.vortex_radial_accel, 0.0)
	accel += Vector3(-offset.z, 0, offset.x) / maxf(distance, r * 0.25) * maxf(tuning.vortex_tangential_accel, 0.0)
	var v := body.linear_velocity
	accel -= Vector3(v.x, 0.0, v.z) * 2.0
	accel.y = maxf(tuning.vortex_lift_accel, 0.0) * clampf(1.0 - (point.y - center.y) / maxf(tuning.vortex_height, 0.1), 0.0, 1.0) - v.y * 1.5
	var speed := v.length()
	if speed > maxf(tuning.vortex_max_speed, 0.1):
		var direction := v / speed
		accel -= direction * (maxf(accel.dot(direction), 0.0) + (speed - tuning.vortex_max_speed) * 2.0)
	var cap := maxf(tuning.vortex_radial_accel, maxf(tuning.vortex_tangential_accel, tuning.vortex_lift_accel))
	return (accel.limit_length(maxf(cap, 0.0)) * body.mass).limit_length(maxf(tuning.vortex_max_force, 0.0)) * edge * exposure


func physics_tick(delta: float) -> void:
	if not active:
		return
	if not _valid_context():
		cancel()
		return
	var epoch := _epoch
	age += delta
	_query_clock -= delta
	if _query_clock <= 0.0:
		_refresh()
		_query_clock = clampf(tuning.vortex_query_interval_s, 0.05, 0.25)
	_material_clock += delta
	var material_tick := _material_clock >= MATERIAL_INTERVAL_S
	if material_tick:
		_material_clock = fmod(_material_clock, MATERIAL_INTERVAL_S)
	_stats.force_ticks += 1
	_stats.last_forced = 0
	for entry: Dictionary in _candidates.duplicate():
		var body := (entry.body as WeakRef).get_ref() as RigidBody3D
		if not _eligible(body):
			continue
		var point := MaterialResponseSystem.body_center(body)
		if not _inside(point) or float(entry.exposure) <= 0.0:
			continue
		var origin := _axis_at(point)
		_stats.los_checks += 1
		if not controller.materials.line_of_sight_to(origin, point, body):
			_stats.blocked += 1
			continue
		var force := _force(body, point, float(entry.exposure))
		if force.is_zero_approx():
			continue
		if body.freeze:
			DebrisBudget.unpark(body)
			_stats.unparked += 1
		body.sleeping = false
		body.apply_central_force(force)
		_stats.bodies_forced += 1
		_stats.last_forced += 1
		_stats.max_force_applied = maxf(_stats.max_force_applied, force.length())
		_stats.max_speed_seen = maxf(_stats.max_speed_seen, body.linear_velocity.length())
		if material_tick:
			# Um pulso por segundo, no mesmo domínio de magnitude da rajada: sem multiplicar por FPS.
			var event := ElementalEvent.make(ElementalEvent.Kind.AIRFLOW, point, float(entry.exposure) * _edge_weight(point), 0.0, id, Vector3.UP)
			event.target = body
			emit_event(event)
			_stats.material_events += 1
			if epoch != _epoch or not active:
				return


func status() -> String:
	return "VÓRTICE · segure RMB · %d corpos · raio %.1f m / altura %.1f m" % [_stats.last_forced, tuning.vortex_radius, tuning.vortex_height]
