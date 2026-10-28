class_name WaterOrb
extends Ability
## Uma massa abstrata com estado contínuo; não é RigidBody3D nem altera o terreno.
## Esfera varrida antes de cada deslocamento. Contato decide eventos antes dos VFX.
const SKIN := 0.005
var tuning: WaterOrbTuning = preload("res://data/abilities/water_orb_tuning.tres")
var phase := ""
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var target_position := Vector3.ZERO
var hold_distance := 3.0
var hold_height := 1.6
var age := 0.0
var volume_liters := 150.0
var launch_position := Vector3.ZERO
var launch_velocity := Vector3.ZERO
var _traveled := 0.0
var _shape := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _stats := {"formed": 0, "launched": 0, "impacts": 0, "body_impacts": 0,
	"terrain_impacts": 0, "cancelled": 0, "dissipated": 0, "blocked_motion": 0, "impulse_ns": 0.0}


func _init() -> void:
	id = &"water_orb"
	element = &"water"
	display_name = "Orbe d'água"
	_query.shape = _shape
	_query.collision_mask = Layers.TERRAIN | Layers.PROPS
	_query.margin = 0.001
	_capture_volume()


func radius() -> float:
	return _shape.radius


func _capture_volume() -> void:
	# Uma formação tem tamanho fixo; editar o Resource vale para a próxima massa.
	volume_liters = clampf(tuning.nominal_liters, 10.0, 600.0)
	_shape.radius = pow(volume_liters * 0.001 * 3.0 / (4.0 * PI), 1.0 / 3.0)


func get_stats() -> Dictionary:
	var data := _stats.duplicate()
	data["phase"] = phase
	data["traveled_m"] = _traveled
	return data


func begin() -> bool:
	if phase != "" or controller == null or not controller._can_act():
		return false
	_capture_volume()
	var start: Vector3 = controller.hand_position()
	var chest: Vector3 = controller.player.global_position + Vector3.UP * 1.3
	var passage := _sweep(chest, start - chest)
	if passage.blocked or not _overlaps(start).is_empty():
		last_result = "sem espaço para formar água"
		return false
	position = start
	velocity = Vector3.ZERO
	hold_distance = clampf(tuning.initial_distance, tuning.min_distance, tuning.max_distance)
	hold_height = clampf(tuning.initial_height, tuning.min_height, tuning.max_height)
	target_position = _control_target()
	age = 0.0
	_traveled = 0.0
	phase = "hold"
	_stats.formed += 1
	last_result = "reserva Criativo · %.0f L" % volume_liters
	return true


func adjust_hold_distance(amount: float) -> void:
	if phase == "hold":
		hold_distance = clampf(hold_distance + amount, tuning.min_distance, tuning.max_distance)


func _control_target() -> Vector3:
	var direction: Vector3 = controller.aim_direction()
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	return controller.player.global_position + direction * hold_distance + Vector3.UP * hold_height


func release() -> void:
	if phase != "hold":
		return
	var toward: Vector3 = controller.aim_point(tuning.max_range + hold_distance + 10.0)
	var direction := (toward - position).normalized()
	if direction.is_zero_approx():
		direction = controller.aim_direction()
	velocity = direction * maxf(tuning.launch_speed, 0.1) + velocity.limit_length(maxf(tuning.inherited_speed_limit, 0.0))
	launch_position = position
	launch_velocity = velocity
	_traveled = 0.0
	age = 0.0
	phase = "flight"
	_stats.launched += 1
	last_result = "orbe lançado"


func physics_tick(delta: float) -> void:
	if phase == "":
		return
	if not controller._can_act():
		cancel()
		return
	age += delta
	if phase == "hold":
		_hold_tick(delta)
	else:
		_flight_tick(delta)


func _hold_tick(delta: float) -> void:
	hold_height = clampf(hold_height + Input.get_axis(&"earth_lower", &"earth_raise") * tuning.height_speed * delta,
		tuning.min_height, tuning.max_height)
	target_position = _control_target()
	var omega := maxf(tuning.follow_omega, 0.1)
	var acceleration := ((target_position - position) * omega * omega - velocity * 2.0 * omega).limit_length(tuning.max_control_accel)
	velocity = (velocity + acceleration * delta).limit_length(tuning.max_control_speed)
	var before := position
	var motion := velocity * delta
	var result := _sweep(position, motion)
	if result.overlap:
		cancel() # Geometria móvel invadiu a massa; não teleportar para sair dela.
		return
	position += motion * float(result.fraction)
	if result.blocked:
		_stats.blocked_motion += 1
		if not result.hit.is_empty():
			var slide := velocity.slide(result.hit.normal) * delta * (1.0 - float(result.fraction))
			var tangent := _sweep(position, slide)
			if not tangent.overlap:
				position += slide * float(tangent.fraction)
	velocity = (position - before) / maxf(delta, 0.000001)


func _flight_tick(delta: float) -> void:
	var remaining := maxf(tuning.max_range - _traveled, 0.0)
	var motion := (velocity * delta).limit_length(remaining)
	var result := _sweep(position, motion)
	position += motion * float(result.fraction)
	_traveled += motion.length() * float(result.fraction)
	if result.blocked:
		if not result.hit.is_empty():
			_impact(result.hit)
		else:
			_dissipate("contato sem testemunho")
	elif remaining <= motion.length() + 0.00001:
		_dissipate("alcance")


func _space() -> PhysicsDirectSpaceState3D:
	return controller.player.get_world_3d().direct_space_state


func _overlaps(at: Vector3) -> Array[Dictionary]:
	_query.transform = Transform3D(Basis.IDENTITY, at)
	_query.motion = Vector3.ZERO
	return _space().intersect_shape(_query, 1)


## cast_motion ignora sobreposições iniciais; conferi-las explicitamente evita sair por uma parede.
## get_rest_info recebe a esfera na fração de contato (não depende de sua propriedade motion).
func _sweep(from: Vector3, motion: Vector3) -> Dictionary:
	var overlap := _overlaps(from)
	if not overlap.is_empty():
		var resting := _space().get_rest_info(_query)
		return {"fraction": 0.0, "blocked": true, "overlap": true, "hit": _contact_info(resting)}
	if motion.length_squared() < 0.00000001:
		return {"fraction": 1.0, "blocked": false, "overlap": false, "hit": {}}
	_query.motion = motion
	var fractions := _space().cast_motion(_query)
	if fractions.size() == 2 and fractions[0] >= 1.0:
		return {"fraction": 1.0, "blocked": false, "overlap": false, "hit": {}}
	var safe := float(fractions[0]) if fractions.size() == 2 else 0.0
	var unsafe := float(fractions[1]) if fractions.size() == 2 else 0.0
	_query.motion = Vector3.ZERO
	_query.transform.origin = from + motion * minf(1.0, unsafe + SKIN / motion.length())
	var contact := _space().get_rest_info(_query)
	return {"fraction": maxf(0.0, safe - SKIN / motion.length()), "blocked": true,
		"overlap": false, "hit": _contact_info(contact)}


func _contact_info(rest: Dictionary) -> Dictionary:
	if rest.is_empty():
		return {}
	return {"position": rest.point, "normal": rest.normal,
		"collider": instance_from_id(int(rest.collider_id))}


func _impact(hit: Dictionary) -> void:
	# Encerrar antes de callbacks de materiais: contato e efeitos só podem ocorrer uma vez.
	phase = ""
	_stats.impacts += 1
	var session: int = controller.session_id
	var direction := velocity.normalized()
	var body := hit.collider as RigidBody3D
	var impulse := 0.0
	if body != null:
		_stats.body_impacts += 1
		var was_frozen := body.freeze
		impulse = minf(maxf(tuning.impulse_ns, 0.0), body.mass * maxf(tuning.max_target_delta_v, 0.0))
		var kinetic := ElementalEvent.make(ElementalEvent.Kind.KINETIC, hit.position, impulse, 0.0, id, direction)
		kinetic.target = body
		emit_event(kinetic)
		if controller.session_id != session:
			return
		if is_instance_valid(body) and not body.freeze and not was_frozen:
			body.sleeping = false
			body.apply_central_impulse(direction * impulse)
			_stats.impulse_ns += impulse
		elif is_instance_valid(body) and was_frozen and not body.freeze:
			# O consumidor KINETIC já solta a peça aplicando metade do impulso (contrato existente).
			_stats.impulse_ns += impulse * 0.5
	else:
		_stats.terrain_impacts += 1
	if controller.session_id != session:
		return
	var wet := ElementalEvent.make(ElementalEvent.Kind.WET, hit.position + hit.normal * 0.02,
		maxf(tuning.wetness, 0.0), maxf(tuning.splash_radius, 0.0), id, direction)
	if is_instance_valid(body):
		wet.target = body
	emit_event(wet)
	last_result = "água em contato"
	if controller.session_id == session:
		emit_fx(&"water_orb_impact", {"position": hit.position, "normal": hit.normal, "radius": radius()})
	velocity = Vector3.ZERO


func _dissipate(reason: String) -> void:
	phase = ""
	velocity = Vector3.ZERO
	_stats.dissipated += 1
	last_result = reason
	emit_fx(&"water_orb_dissipate", {"position": position})


func cancel() -> void:
	if phase != "":
		_stats.cancelled += 1
	phase = ""
	velocity = Vector3.ZERO
	hold_distance = clampf(tuning.initial_distance, tuning.min_distance, tuning.max_distance)
	hold_height = clampf(tuning.initial_height, tuning.min_height, tuning.max_height)
	emit_fx(&"water_orb_cancel")


func clear() -> void:
	cancel()


func status() -> String:
	return "%.0f L Criativo · RMB solta · Q/E altura %.1f · roda distância %.1f" % [volume_liters, hold_height, hold_distance] \
		if phase == "hold" else ("orbe em voo" if phase == "flight" else last_result)
