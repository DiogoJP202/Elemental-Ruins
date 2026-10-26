class_name FireBurst
extends Ability
## Fogo — rajada (atlas fo-002; roadmap P3). Toque: uma bola de fogo sai da mão na direção da
## mira e anda em linha reta (sem gravidade) até bater em terreno ou corpo, ou até o alcance.
## No ponto: evento HEAT com golpe direto no corpo atingido e respingo no raio. Madeira seca
## acende; molhada gasta o calor secando; pedra só aquece. A bola é um ponto simulado com raio
## por quadro (não é corpo físico), então anda por posição.

const SPEED := 35.0
const RANGE := 30.0
## Calor no corpo atingido; no respingo, cai linearmente até SPLASH_RADIUS.
const HEAT := 450.0
const SPLASH_RADIUS := 2.0
const MAX_PROJECTILES := 8

## Bolas em voo: [{pos, vel, traveled}] (o VFX lê).
var projectiles := []
## Últimos pontos de explosão (o VFX lê e esvazia; no máximo MAX_PROJECTILES).
var impacts := []
var _stats := {"fired": 0, "exploded": 0, "body_hits": 0}


func _init() -> void:
	id = &"fire_burst"
	element = &"fire"
	display_name = "Rajada de fogo"
	input_mode = "tap"


func get_stats() -> Dictionary:
	return _stats.duplicate()


func on_press() -> void:
	if projectiles.size() >= MAX_PROJECTILES:
		last_result = "muitas bolas em voo"
		return
	var from: Vector3 = controller.hand_position()
	var toward: Vector3 = controller.aim_point(RANGE + 10.0)
	projectiles.append({"pos": from, "vel": (toward - from).normalized() * SPEED, "traveled": 0.0})
	_stats.fired += 1
	last_result = "bola de fogo lançada"


func physics_tick(delta: float) -> void:
	if projectiles.is_empty():
		return
	var keep := []
	for p in projectiles:
		var step: Vector3 = p.vel * delta
		var hit: Dictionary = controller.cast_segment(p.pos, p.pos + step)
		if not hit.is_empty():
			_explode(hit.position, hit.collider as RigidBody3D, step.normalized())
			continue
		p.pos += step
		p.traveled += step.length()
		if p.traveled >= RANGE:
			_explode(p.pos, null, step.normalized())
			continue
		keep.append(p)
	projectiles = keep


func clear() -> void:
	projectiles.clear()
	impacts.clear()


func _explode(at: Vector3, body: RigidBody3D, dir: Vector3) -> void:
	_stats.exploded += 1
	var e := ElementalEvent.make(ElementalEvent.Kind.HEAT, at, HEAT, SPLASH_RADIUS, id, dir)
	if body != null:
		e.target = body
		_stats.body_hits += 1
	var hit := emit_event(e)
	impacts.append(at)
	if impacts.size() > MAX_PROJECTILES:
		impacts.pop_front()
	last_result = "explodiu: %d corpo(s) aquecido(s)" % hit.size()
