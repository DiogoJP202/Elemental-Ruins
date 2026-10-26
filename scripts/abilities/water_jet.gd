class_name WaterJet
extends Ability
## Água — jato (atlas ag-003; roadmap P3). Segurar: um jato sai da mão na direção da mira até
## RANGE; o primeiro obstáculo o para (terreno bloqueia: o que está atrás não é atingido).
## No corpo atingido: força contínua com teto ABSOLUTO (caixa leve desliza, rocha maciça não se
## mexe) e evento WET com respingo (molha, resfria e apaga). Não é simulação de fluido: é um
## raio por quadro de física.

const RANGE := 14.0
## Força no corpo atingido (N), por quadro de física; ~ mangueira de incêndio.
const FORCE := 300.0
## Umidade por segundo no corpo atingido; os vizinhos no raio do respingo recebem menos.
const WET_PER_S := 0.5
const SPLASH_RADIUS := 1.2

var active := false
## Segmento do jato no último quadro (para o VFX): da mão até o ponto atingido ou o alcance.
var beam_from := Vector3.ZERO
var beam_to := Vector3.ZERO
var hit_body: Node3D
var _stats := {"ticks": 0, "body_ticks": 0, "terrain_ticks": 0}


func _init() -> void:
	id = &"water_jet"
	element = &"water"
	display_name = "Jato d'água"
	input_mode = "hold"


func get_stats() -> Dictionary:
	return _stats.duplicate()


func on_press() -> void:
	active = true
	last_result = "jato"


func on_hold(delta: float) -> void:
	if not active:
		return
	_stats.ticks += 1
	beam_from = controller.hand_position()
	var toward: Vector3 = controller.aim_point(RANGE + 10.0)
	var dir := (toward - beam_from).normalized()
	var hit: Dictionary = controller.cast_segment(beam_from, beam_from + dir * RANGE)
	hit_body = null
	if hit.is_empty():
		beam_to = beam_from + dir * RANGE
		return
	beam_to = hit.position
	var e := ElementalEvent.make(ElementalEvent.Kind.WET, beam_to, WET_PER_S * delta, SPLASH_RADIUS, id, dir)
	var body := hit.collider as RigidBody3D
	if body != null:
		hit_body = body
		e.target = body
		_stats.body_ticks += 1
		if not body.freeze:
			body.sleeping = false
			body.apply_central_force(dir * FORCE)
	else:
		_stats.terrain_ticks += 1
	emit_event(e)


func on_release() -> void:
	active = false
	hit_body = null


func cancel() -> void:
	active = false
	hit_body = null


func status() -> String:
	if active:
		return "jato: %s" % (hit_body.name if hit_body != null and is_instance_valid(hit_body) else "sem alvo")
	return last_result
