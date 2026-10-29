class_name FireBurst
extends Ability
## Um ponto transportado com varredura. Origem e direção são capturadas no clique (o comando),
## a antecipação ocupa um slot desde então, o impacto aquece uma vez e o alcance esgotado só dissipa.

# Compatibilidade dos pools: o limite editável nunca excede este teto.
const SPEED := 35.0
const RANGE := 30.0
const HEAT := 450.0
const SPLASH_RADIUS := 2.0
const MAX_PROJECTILES := 8
## Resíduo de ponto flutuante: um cooldown múltiplo exato do tick não custa um tick a mais.
const COOLDOWN_EPSILON_S := 0.000001
const TUNING_PATH := "res://data/abilities/fire_tuning.tres"

var tuning: FireTuning
var stream := FireStream.new()
var projectiles: Array[Dictionary] = []
## Notificação visual legada, limitada; não contém calor nem decide contatos.
var impacts: Array[Vector3] = []
var _cooldown_left := 0.0
var _next_projectile_id := 1
var _epoch := 0
var _stats := {"fired": 0, "launched": 0, "exploded": 0, "dissipated": 0,
	"body_hits": 0, "cancelled": 0, "rejected": 0, "stale_dropped": 0, "queries": 0, "ray_fallback_hits": 0,
	"max_live": 0, "update_ticks": 0, "update_usec": 0, "update_usec_max": 0}


func _init() -> void:
	id = &"fire_burst"
	element = &"fire"
	display_name = "Rajada de fogo"
	input_mode = "tap"
	tuning = load(TUNING_PATH)


func setup(p_controller) -> void:
	super.setup(p_controller)
	stream.configure(p_controller, tuning, _can_begin_stream)


func _can_begin_stream() -> bool:
	return not projectiles.any(func(p: Dictionary): return p.phase == "anticipation")


func get_stats() -> Dictionary:
	var data := _stats.duplicate()
	data["impacts"] = _stats.exploded
	data["live_projectiles"] = projectiles.size()
	data["cooldown_left"] = _cooldown_left
	return data


func on_press() -> void:
	if stream.active:
		return
	stream.last_result = ""
	if _cooldown_left > COOLDOWN_EPSILON_S or projectiles.size() >= clampi(tuning.max_projectiles, 1, MAX_PROJECTILES):
		_stats.rejected += 1
		last_result = "recuperando" if _cooldown_left > COOLDOWN_EPSILON_S else "muitos projéteis"
		return
	if controller == null or not controller.terrain_service.is_ready():
		return
	var start: Vector3 = controller.hand_position()
	var toward: Vector3 = controller.aim_point(maxf(tuning.max_range, 0.0) + 10.0)
	var direction := (toward - start).normalized()
	if direction.is_zero_approx():
		return
	var p := {"pos": start, "start": start, "vel": direction * maxf(tuning.speed, 0.1), "direction": direction,
		"traveled": 0.0, "phase": "anticipation", "age": 0.0, "id": _next_projectile_id,
		"session": controller.session_id, "generation": controller.terrain_service.get_world_generation()}
	_next_projectile_id += 1
	projectiles.append(p)
	_cooldown_left = maxf(tuning.cooldown_s, 0.0)
	_stats.fired += 1
	_stats.max_live = maxi(_stats.max_live, projectiles.size())
	last_result = "preparando rajada"
	_emit_projectile_fx(&"fire_anticipation", p)


func physics_tick(delta: float) -> void:
	stream.physics_tick(delta)
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if projectiles.is_empty():
		return
	# Custo de CPU do avanço (inclui consultas, calor aplicado no impacto e callbacks de FX).
	var t0 := Time.get_ticks_usec()
	_advance(delta)
	var spent := Time.get_ticks_usec() - t0
	_stats.update_ticks += 1
	_stats.update_usec += spent
	_stats.update_usec_max = maxi(_stats.update_usec_max, spent)


func _advance(delta: float) -> void:
	var epoch := _epoch
	var keep: Array[Dictionary] = []
	# Snapshot permite cancelamento por callback sem invalidar a iteração.
	var current := projectiles.duplicate()
	for p: Dictionary in current:
		if not _context_valid(p):
			_stats.stale_dropped += 1
			continue
		var move_dt := delta
		if p.phase == "anticipation":
			var remaining := maxf(maxf(tuning.anticipation_s, 0.0) - float(p.age), 0.0)
			p.age += delta
			if float(p.age) + 0.000001 < maxf(tuning.anticipation_s, 0.0):
				keep.append(p)
				continue
			move_dt = maxf(0.0, delta - remaining)
			p.phase = "flight"
			p.age = 0.0
			_stats.launched += 1
			last_result = "rajada lançada"
			_emit_projectile_fx(&"fire_launch", p)
			if epoch != _epoch:
				return
		if move_dt > 0.0:
			p.age += move_dt
			var direction: Vector3 = p.direction
			var side := direction.cross(Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT).normalized()
			var up := side.cross(direction)
			var phase := float(p.age) * TAU * maxf(tuning.turbulence_hz, 0.0) + float(p.id) * 2.399963
			var speed := maxf(tuning.speed, 0.1)
			var turbulence := side * sin(phase) + up * cos(phase) * 0.6
			p.vel = (direction * speed + turbulence * maxf(tuning.turbulence_mps, 0.0)).normalized() * speed
			var remaining := maxf(maxf(tuning.max_range, 0.0) - float(p.traveled), 0.0)
			var distance := minf(speed * move_dt, remaining)
			if distance > 0.000001:
				var from: Vector3 = p.pos
				var travel_dir := (p.vel as Vector3).normalized()
				var to := from + travel_dir * distance
				var hit: Dictionary = controller.cast_segment(from, to, true)
				_stats.queries += 1
				if not hit.is_empty():
					_stats.ray_fallback_hits += int(hit.get("ray_fallback", false))
					p.pos = hit.position
					p.traveled += from.distance_to(hit.position)
					_impact(p, hit, travel_dir)
					if epoch != _epoch:
						return
					continue
				p.pos = to
				p.traveled += distance
			if float(p.traveled) >= maxf(tuning.max_range, 0.0) - 0.000001:
				p.phase = "dissipated"
				_stats.dissipated += 1
				last_result = "rajada dissipada"
				_emit_projectile_fx(&"fire_dissipate", p)
				if epoch != _epoch:
					return
				continue
		keep.append(p)
	if epoch == _epoch:
		projectiles = keep


## Troca de elemento cancela antecipações e preserva projéteis já lançados.
func cancel() -> void:
	stream.cancel()
	_epoch += 1
	var keep: Array[Dictionary] = []
	for p in projectiles:
		if p.phase == "flight":
			keep.append(p)
		elif p.phase == "anticipation":
			_stats.cancelled += 1
	projectiles = keep


## Reset/save/load descartam também voos, notificações e recuperação.
func clear() -> void:
	stream.clear()
	_epoch += 1
	projectiles.clear()
	impacts.clear()
	_cooldown_left = 0.0


func status() -> String:
	return stream.status() if stream.active else (stream.last_result if stream.last_result != "" else last_result)


func _context_valid(p: Dictionary) -> bool:
	return controller != null and int(p.session) == controller.session_id \
		and int(p.generation) == controller.terrain_service.get_world_generation() \
		and controller.terrain_service.is_ready()


func _emit_projectile_fx(kind: StringName, p: Dictionary, normal := Vector3.ZERO, extra := {}) -> void:
	var data := {"projectile_id": p.id, "position": p.pos, "start": p.start, "traveled": p.traveled,
		"direction": (p.vel as Vector3).normalized(), "normal": normal, "phase": p.phase, "age": p.age}
	data.merge(extra)
	emit_fx(kind, data)


func _impact(p: Dictionary, hit: Dictionary, direction: Vector3) -> void:
	p.phase = "impact"
	_stats.exploded += 1
	var normal: Vector3 = hit.normal
	if normal.is_zero_approx():
		normal = -direction
	var body := hit.collider as RigidBody3D
	# Só leitura para o VFX (vapor ao secar); o estado muda apenas no MaterialResponseSystem.
	var state: MaterialState = controller.materials.state_of(body) if body != null else null
	var wet_before := state.wetness if state != null else 0.0
	# A visibilidade parte do lado livre do contato, nunca de dentro da parede.
	var event := ElementalEvent.make(ElementalEvent.Kind.HEAT, (p.pos as Vector3) + normal * 0.02,
		maxf(tuning.heat, 0.0), maxf(tuning.splash_radius, 0.0), id, direction)
	if body != null:
		event.target = body
		_stats.body_hits += 1
	var affected := emit_event(event)
	if not _context_valid(p):
		return
	impacts.append(p.pos)
	if impacts.size() > MAX_PROJECTILES:
		impacts.pop_front()
	_emit_projectile_fx(&"fire_impact", p, normal, {"target_wetness_before": wet_before,
		"target_wetness_after": state.wetness if state != null else 0.0, "affected": affected.size()})
	last_result = "impacto: %d corpo(s) aquecido(s)" % affected.size()
