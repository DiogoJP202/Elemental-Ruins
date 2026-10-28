class_name WaterOrb
extends Ability
## Uma massa abstrata com estado contínuo; não é RigidBody3D nem altera o terreno.
## Esfera varrida antes de cada deslocamento. Contato decide eventos antes dos VFX.
const SKIN := 0.005
enum MatterState { LIQUID, FROZEN }
var tuning: WaterOrbTuning = preload("res://data/abilities/water_orb_tuning.tres")
var phase := ""
var matter_state: MatterState = MatterState.LIQUID
var freeze_age := 0.0
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
	"terrain_impacts": 0, "cancelled": 0, "dissipated": 0, "blocked_motion": 0, "impulse_ns": 0.0,
	"freezes": 0, "ice_impacts": 0, "ice_spawned": 0, "ice_spawn_rejected": 0, "ice_evicted": 0}
var _last_ice_spawn_reason := ""


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
	data["matter_state"] = "FROZEN" if is_frozen() else "LIQUID"
	data["persistent_ice"] = get_persistent_ice().size()
	data["last_ice_spawn_reason"] = _last_ice_spawn_reason
	return data


func get_persistent_ice() -> Array[IceBody]:
	var live: Array[IceBody] = []
	if controller != null and is_instance_valid(controller.props_root):
		for node in controller.props_root.get_children():
			if node is IceBody and not node.is_queued_for_deletion():
				live.append(node)
	return live


func _ice_space_free(at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = Layers.TERRAIN | Layers.PLAYER | Layers.PROPS
	query.margin = 0.002
	return _space().intersect_shape(query, 1).is_empty()


func _spawn_persistent_ice(hit: Dictionary) -> IceBody:
	# O centro seguro da própria varredura preserva também contatos de raspão.
	var at := position
	if not _ice_space_free(at):
		var normal: Vector3 = hit.normal
		var candidate: Vector3 = hit.position + normal.normalized() * (radius() + 0.02)
		if candidate.distance_to(position) > 0.05 or not _ice_space_free(candidate):
			_stats.ice_spawn_rejected += 1
			_last_ice_spawn_reason = "no_space"
			return null
		at = candidate
	var live := get_persistent_ice()
	var limit := clampi(tuning.ice_max_bodies, 1, 16)
	var required := maxi(0, live.size() - limit + 1)
	var removable: Array[IceBody] = []
	for body in live:
		if body.can_retire():
			removable.append(body)
	if removable.size() < required:
		_stats.ice_spawn_rejected += 1
		_last_ice_spawn_reason = "capacity_in_use"
		return null
	for i in required:
		removable[i].retire("limit")
		_stats.ice_evicted += 1
	var body := IceBody.new()
	body.setup(tuning, radius(), volume_liters, controller.materials, _on_ice_body_removed)
	controller.props_root.add_child(body)
	body.global_position = at
	# Não carregar novamente a velocidade de impacto: o KINETIC já foi aplicado.
	_stats.ice_spawned += 1
	_last_ice_spawn_reason = ""
	emit_fx(&"ice_body_spawned", {"body": body, "position": at, "radius": radius()})
	return body


func _on_ice_body_removed(body: IceBody, reason: String) -> void:
	emit_fx(&"ice_body_removed", {"body": body, "position": body.global_position, "radius": body.ice_radius,
		"duration": body.melt_duration_s if reason == "melt" else 0.18, "reason": reason})


func is_frozen() -> bool:
	return matter_state == MatterState.FROZEN


func _reset_matter() -> void:
	matter_state = MatterState.LIQUID
	freeze_age = 0.0


func freeze_orb() -> bool:
	if phase != "hold" or is_frozen() or controller == null or not controller.can_manipulate_water():
		return false
	matter_state = MatterState.FROZEN
	freeze_age = 0.0
	_stats.freezes += 1
	last_result = "orbe congelado"
	emit_fx(&"water_orb_frozen", {"position": position, "radius": radius()})
	return true


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
	_reset_matter()
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
	var speed := tuning.ice_launch_speed if is_frozen() else tuning.launch_speed
	velocity = direction * maxf(speed, 0.1) + velocity.limit_length(maxf(tuning.inherited_speed_limit, 0.0))
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
	if is_frozen():
		freeze_age += delta
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
	var motion := velocity * delta
	var gravity_step := Vector3.ZERO
	if is_frozen():
		gravity_step = Vector3.DOWN * maxf(tuning.ice_gravity, 0.0) * delta
		motion += gravity_step * delta * 0.5
	var time_fraction := minf(1.0, remaining / maxf(motion.length(), 0.000001))
	motion = motion.limit_length(remaining)
	var result := _sweep(position, motion)
	position += motion * float(result.fraction)
	_traveled += motion.length() * float(result.fraction)
	if is_frozen():
		velocity += gravity_step * time_fraction * float(result.fraction)
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
	var frozen := is_frozen()
	phase = ""
	_reset_matter()
	_stats.impacts += 1
	if frozen:
		_stats.ice_impacts += 1
	var session: int = controller.session_id
	var direction := velocity.normalized()
	var body := hit.collider as RigidBody3D
	var impulse := 0.0
	if body != null:
		_stats.body_impacts += 1
		var was_frozen := body.freeze
		var strength := tuning.ice_impulse_ns if frozen else tuning.impulse_ns
		var max_delta_v := tuning.ice_max_target_delta_v if frozen else tuning.max_target_delta_v
		impulse = minf(maxf(strength, 0.0), body.mass * maxf(max_delta_v, 0.0))
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
	if not frozen:
		var wet := ElementalEvent.make(ElementalEvent.Kind.WET, hit.position + hit.normal * 0.02,
			maxf(tuning.wetness, 0.0), maxf(tuning.splash_radius, 0.0), id, direction)
		if is_instance_valid(body):
			wet.target = body
		emit_event(wet)
	var persistent: IceBody
	if frozen:
		persistent = _spawn_persistent_ice(hit)
		last_result = "gelo físico criado" if persistent != null else "gelo em fragmentos: %s" % _last_ice_spawn_reason
	else:
		last_result = "água em contato"
	if controller.session_id == session:
		emit_fx(&"water_orb_impact", {"position": hit.position, "normal": hit.normal, "radius": radius(),
			"frozen": frozen, "persistent": persistent != null})
	velocity = Vector3.ZERO


func _dissipate(reason: String) -> void:
	phase = ""
	_reset_matter()
	velocity = Vector3.ZERO
	_stats.dissipated += 1
	last_result = reason
	emit_fx(&"water_orb_dissipate", {"position": position})


func cancel() -> void:
	if phase != "":
		_stats.cancelled += 1
	phase = ""
	_reset_matter()
	velocity = Vector3.ZERO
	hold_distance = clampf(tuning.initial_distance, tuning.min_distance, tuning.max_distance)
	hold_height = clampf(tuning.initial_height, tuning.min_height, tuning.max_height)
	emit_fx(&"water_orb_cancel")


func clear() -> void:
	cancel()


func status() -> String:
	var label := "GELO" if is_frozen() else "ÁGUA · C congela"
	return "%s · %.0f L Criativo · RMB solta · Q/E altura %.1f · roda distância %.1f" % [label, volume_liters, hold_height, hold_distance] \
		if phase == "hold" else (("gelo em voo" if is_frozen() else "água em voo") if phase == "flight" else last_result)
