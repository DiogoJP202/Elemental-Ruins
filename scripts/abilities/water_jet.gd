class_name WaterJet
extends Ability
## Transporte limitado por pacotes: origem/direção são capturadas na emissão.
## Cada segmento é varrido antes de transferir impulso e WET. VFX apenas lê pacotes.
const RANGE := 14.0
const FORCE := 300.0
const WET_PER_S := 0.5
const SPLASH_RADIUS := 1.2
const TUNING_PATH := "res://data/abilities/water_tuning.tres"

var tuning: WaterTuning
var active := false
var pressure := 0.0
var packets: Array[Dictionary] = []
var beam_from := Vector3.ZERO
var beam_to := Vector3.ZERO
var hit_body: Node3D
var contact_normal := Vector3.UP
var contact_point := Vector3.ZERO
var contact_age := INF
var _elapsed := 0.0
var _emit_clock := 0.0
var _stats := {"ticks": 0, "body_ticks": 0, "terrain_ticks": 0, "packets_emitted": 0,
	"packets_dropped": 0, "max_live": 0, "impulse_ns": 0.0, "queries": 0}

func _init() -> void:
	id = &"water_jet"
	element = &"water"
	display_name = "Jato d'água"
	input_mode = "hold"
	tuning = load(TUNING_PATH)

func get_stats() -> Dictionary:
	var data := _stats.duplicate()
	data["live_packets"] = packets.size()
	data["pressure"] = pressure
	return data

func on_press() -> void:
	active = true
	pressure = 0.0
	_elapsed = 0.0
	_emit_clock = maxf(tuning.emission_interval_s, 1.0 / 120.0)
	contact_age = INF
	hit_body = null
	last_result = "fluxo iniciando"

func on_hold(delta: float) -> void:
	if not active:
		return
	_stats.ticks += 1
	_elapsed += delta
	pressure = smoothstep(0.0, 1.0, clampf(_elapsed / maxf(tuning.pressure_rise_s, 0.001), 0.0, 1.0))
	var interval := maxf(tuning.emission_interval_s, 1.0 / 120.0)
	_emit_clock += delta
	var emitted := 0
	while _emit_clock >= interval and emitted < 4:
		_emit_clock -= interval
		emitted += 1
		if packets.size() >= clampi(tuning.max_packets, 1, 64):
			_stats.packets_dropped += 1
			continue
		_emit_packet(interval)

func _emit_packet(duration: float) -> void:
	beam_from = controller.hand_position()
	var toward: Vector3 = controller.aim_point(tuning.max_range + 10.0)
	var direction := (toward - beam_from).normalized()
	if direction.is_zero_approx():
		return
	var modulation := 1.0 - tuning.pressure_turbulence * (0.5 + 0.5 * sin(_elapsed * 17.0))
	packets.append({"pos": beam_from, "dir": direction, "traveled": 0.0,
		"pressure": clampf(pressure * modulation, 0.0, 1.0), "volume_dt": duration})
	_stats.packets_emitted += 1
	_stats.max_live = maxi(_stats.max_live, packets.size())

func physics_tick(delta: float) -> void:
	if not active:
		return
	contact_age += delta
	var keep: Array[Dictionary] = []
	for p in packets:
		var step := minf(maxf(tuning.stream_speed, 0.1) * delta, maxf(tuning.max_range - float(p.traveled), 0.0))
		if step <= 0.0:
			continue
		var from: Vector3 = p.pos
		var to: Vector3 = from + (p.dir as Vector3) * step
		var hit: Dictionary = controller.cast_segment(from, to)
		_stats.queries += 1
		if not hit.is_empty():
			_contact(p, hit)
			continue
		p.pos = to
		p.traveled += step
		if p.traveled < tuning.max_range:
			keep.append(p)
	packets = keep
	if contact_age > tuning.emission_interval_s * 3.0:
		hit_body = null
		if not packets.is_empty():
			beam_to = packets[0].pos

func _contact(p: Dictionary, hit: Dictionary) -> void:
	contact_point = hit.position
	contact_normal = hit.normal
	if contact_normal.is_zero_approx():
		contact_normal = -(p.dir as Vector3)
	contact_age = 0.0
	beam_to = hit.position
	var amount := float(p.volume_dt) * float(p.pressure)
	var event := ElementalEvent.make(ElementalEvent.Kind.WET, hit.position + contact_normal * 0.02,
		maxf(tuning.wet_per_s, 0.0) * amount, maxf(tuning.splash_radius, 0.0), id, p.dir)
	var body := hit.collider as RigidBody3D
	if body != null:
		hit_body = body
		event.target = body
		_stats.body_ticks += 1
		if not body.freeze:
			body.sleeping = false
			var impulse: Vector3 = (p.dir as Vector3) * maxf(tuning.force, 0.0) * amount
			body.apply_central_impulse(impulse)
			_stats.impulse_ns += impulse.length()
	else:
		_stats.terrain_ticks += 1
	emit_event(event)
	emit_fx(&"water_contact", {"position": contact_point, "normal": contact_normal, "pressure": p.pressure})

func on_release() -> void:
	cancel()

func cancel() -> void:
	active = false
	pressure = 0.0
	packets.clear()
	hit_body = null
	contact_age = INF

func clear() -> void:
	cancel()

func status() -> String:
	return "pressão %d%% · %d pacotes" % [roundi(pressure * 100), packets.size()] if active else last_result
