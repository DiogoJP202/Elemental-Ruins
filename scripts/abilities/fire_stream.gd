class_name FireStream
extends Ability
## Componente do RMB no FireBurst. A mira/colisão decide o contato atual;
## só MaterialResponseSystem transforma a dose HEAT em temperatura/umidade/fusão.
const CLOCK_EPSILON := 0.000001
const HAND_SIDE_OFFSET := 0.8
var tuning: FireTuning
var active := false
var beam_from := Vector3.ZERO
var beam_to := Vector3.ZERO
var direction := Vector3.ZERO
var contact_normal := Vector3.ZERO
var has_contact := false
var age := 0.0
var reach := 0.0
var _can_begin := Callable()
var _pulse_clock := 0.0
var _pending_seconds := 0.0
var _contact_id := 0
var _contact_point := Vector3.ZERO
var _session := -1
var _generation := -1
var _epoch := 0
var _stats := {"formed": 0, "cancelled": 0, "rejected": 0, "pulses": 0,
	"heat_units": 0.0, "contact_seconds": 0.0, "queries": 0, "body_ticks": 0,
	"update_ticks": 0, "update_usec": 0, "update_usec_max": 0}


func _init() -> void:
	id = &"fire_stream"
	element = &"fire"
	display_name = "Fluxo de fogo"


func configure(p_controller, p_tuning: FireTuning, can_begin := Callable()) -> void:
	setup(p_controller)
	tuning = p_tuning
	_can_begin = can_begin


func get_stats() -> Dictionary:
	var data := _stats.duplicate()
	data["active"] = active
	data["reach"] = reach
	data["has_contact"] = has_contact
	data["pending_contact_seconds"] = _pending_seconds
	return data


## Emissão ao lado da cápsula: a corrente precisa ser visível na câmera de terceira pessoa.
func _hand_position() -> Vector3:
	var forward: Vector3 = controller.aim_direction()
	forward.y = 0.0
	var right := forward.normalized().cross(Vector3.UP) if forward.length_squared() > 0.0001 else Vector3.RIGHT
	return controller.hand_position() + right * HAND_SIDE_OFFSET


func _hand_clear() -> bool:
	var chest: Vector3 = controller.player.global_position + Vector3.UP * 1.3
	var hand := _hand_position()
	_stats.queries += 1
	return controller.cast_segment(chest, hand, true).is_empty()


func begin() -> bool:
	if active or controller == null or not controller._can_act() or controller.current_ability().id != &"fire_burst" \
			or (controller.require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		return false
	if _can_begin.is_valid() and not bool(_can_begin.call()):
		_stats.rejected += 1
		last_result = "bola de fogo em preparação"
		return false
	if not _hand_clear():
		_stats.rejected += 1
		last_result = "mão obstruída"
		return false
	active = true
	age = 0.0
	reach = 0.0
	beam_from = _hand_position()
	beam_to = beam_from
	direction = controller.aim_direction()
	_pulse_clock = 0.0
	_clear_contact()
	_session = controller.session_id
	_generation = controller.terrain_service.get_world_generation()
	_epoch += 1
	_stats.formed += 1
	last_result = "fluxo de fogo ativo"
	emit_fx(&"stream_started", {"position": beam_from})
	return active


func _clear_contact() -> void:
	has_contact = false
	contact_normal = Vector3.ZERO
	_contact_id = 0
	_contact_point = Vector3.ZERO
	_pending_seconds = 0.0


func cancel() -> void:
	_stop("fluxo de fogo encerrado")


func _stop(reason: String) -> void:
	if not active:
		return
	var end := beam_to
	active = false
	_epoch += 1
	_clear_contact()
	_pulse_clock = 0.0
	age = 0.0
	reach = 0.0
	beam_from = Vector3.ZERO
	beam_to = Vector3.ZERO
	direction = Vector3.ZERO
	_stats.cancelled += 1
	last_result = reason
	emit_fx(&"stream_ended", {"position": end})


func clear() -> void:
	cancel()


func _valid_context() -> bool:
	return controller != null and controller._can_act() and controller.session_id == _session \
		and controller.terrain_service.get_world_generation() == _generation \
		and controller.current_ability().id == &"fire_burst" \
		and (not controller.require_captured_mouse or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func physics_tick(delta: float) -> void:
	if not active:
		return
	var t0 := Time.get_ticks_usec()
	_advance(maxf(delta, 0.0))
	var spent := Time.get_ticks_usec() - t0
	_stats.update_ticks += 1
	_stats.update_usec += spent
	_stats.update_usec_max = maxi(_stats.update_usec_max, spent)


func _advance(delta: float) -> void:
	if not _valid_context():
		cancel()
		return
	if not _hand_clear():
		_stop("mão obstruída")
		return
	age += delta
	var speed := maxf(tuning.stream_front_speed, 0.1)
	reach = minf(age * speed, maxf(tuning.stream_range, 0.0))
	beam_from = _hand_position()
	var toward: Vector3 = controller.aim_point(maxf(tuning.stream_range, 0.0) + 10.0)
	direction = (toward - beam_from).normalized()
	if direction.is_zero_approx():
		direction = controller.aim_direction()
	beam_to = beam_from + direction * reach
	if reach <= CLOCK_EPSILON:
		_clear_contact()
		return
	_stats.queries += 1
	var hit: Dictionary = controller.cast_segment(beam_from, beam_to, true)
	var collider := hit.get("collider") as Node3D
	if collider == null or collider.is_queued_for_deletion():
		_clear_contact()
	else:
		beam_to = hit.position
		var key := collider.get_instance_id()
		# Uma superfície sem alvo térmico direto não transporta crédito para outra região ao varrer.
		var moved_surface: bool = not collider is RigidBody3D and beam_to.distance_squared_to(_contact_point) > 0.0004
		if key != _contact_id or moved_surface:
			_pending_seconds = 0.0
		_contact_id = key
		_contact_point = beam_to
		has_contact = true
		contact_normal = hit.normal
		if contact_normal.is_zero_approx():
			contact_normal = -direction
		# A frente pode chegar no meio do tick; só o tempo posterior transfere calor.
		var exposed_dt := clampf(age - beam_from.distance_to(beam_to) / speed, 0.0, delta)
		_pending_seconds += exposed_dt
		_stats.contact_seconds += exposed_dt
	_pulse_clock += delta
	var interval := clampf(tuning.stream_interval_s, 0.05, 0.5)
	if _pulse_clock + CLOCK_EPSILON < interval:
		return
	# Colapsar intervalos de um frame longo em um pulso com dose real, sem rajada de callbacks.
	var periods := floorf((_pulse_clock + CLOCK_EPSILON) / interval)
	_pulse_clock = maxf(0.0, _pulse_clock - periods * interval)
	if has_contact and _pending_seconds > 0.0:
		_apply_heat(collider)


func _apply_heat(collider: Node3D) -> void:
	var seconds := _pending_seconds
	_pending_seconds = 0.0
	var heat := maxf(tuning.stream_heat_per_s, 0.0) * seconds
	if heat <= 0.0:
		return
	var epoch := _epoch
	var event := ElementalEvent.make(ElementalEvent.Kind.HEAT, beam_to + contact_normal * 0.02,
		heat, maxf(tuning.stream_contact_radius, 0.0), id, direction)
	event.duration = seconds
	var body := collider as RigidBody3D
	if body != null:
		event.target = body
		_stats.body_ticks += 1
	_stats.pulses += 1
	_stats.heat_units += heat
	var affected := emit_event(event)
	if epoch != _epoch or not active or not _valid_context():
		return
	emit_fx(&"stream_contact", {"position": beam_to, "normal": contact_normal,
		"heat_units": heat, "contact_seconds": seconds, "affected": affected.size()})


func status() -> String:
	return "FLUXO DE FOGO · segure RMB · %.1f m · %.0f HEAT/s" % [beam_from.distance_to(beam_to), tuning.stream_heat_per_s]
