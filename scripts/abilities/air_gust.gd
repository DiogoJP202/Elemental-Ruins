class_name AirGust
extends Ability
## Ar — rajada (atlas ar-001; roadmap P3). Toque: um cone a partir da mão, na direção da mira.
## Cada corpo no cone, com linha de visada livre de TERRENO (atrás de um morro não pega), recebe:
##   - impulso = min(massa × MAX_DV, IMPULSE) × força: o vento empurra com a mesma pressão,
##     então a caixa leve voa (Δv no teto) e a rocha maciça mal se mexe (Δv = IMPULSE / massa);
##   - evento AIRFLOW com a força (apaga fogo fraco, aviva o forte).
## Força = 1 − (distância / RANGE)²: quase cheia perto, zero no alcance.

const RANGE := 10.0
const HALF_ANGLE_DEG := 35.0
## Corpos mais perto que isso contam mesmo fora do ângulo (colados no jogador).
const NEAR := 1.5
const IMPULSE := 1500.0
const MAX_DV := 12.0
## Componente para cima somado à direção do cone: a caixa sai do chão em vez de só deslizar.
const LIFT := 0.35

## Última rajada (para o VFX e os testes): {origin, dir, hit, blocked, at_ms}.
var last_gust := {}
var _stats := {"gusts": 0, "bodies_pushed": 0, "blocked_by_terrain": 0}


func _init() -> void:
	id = &"air_gust"
	element = &"air"
	display_name = "Rajada de ar"
	input_mode = "tap"


func get_stats() -> Dictionary:
	return _stats.duplicate()


func on_press() -> void:
	var origin: Vector3 = controller.hand_position()
	var dir: Vector3 = (controller.aim_point(RANGE + 10.0) - origin).normalized()
	var push_dir := (dir + Vector3.UP * LIFT).normalized()
	var hit: Array[Node3D] = []
	var blocked := 0
	_stats.gusts += 1
	for body in controller.materials.bodies_in_sphere(origin, RANGE, 128):
		var c := MaterialResponseSystem.body_center(body)
		var to := c - origin
		var dist := to.length()
		if dist > RANGE:
			continue
		if dist > NEAR and rad_to_deg(to.angle_to(dir)) > HALF_ANGLE_DEG:
			continue
		if not controller.terrain_service.raycast_terrain(origin, c).is_empty():
			blocked += 1
			continue
		var strength := 1.0 - pow(dist / RANGE, 2.0)
		var rb := body as RigidBody3D
		if rb != null and not rb.freeze:
			rb.sleeping = false
			rb.apply_central_impulse(push_dir * minf(rb.mass * MAX_DV, IMPULSE) * strength)
			_stats.bodies_pushed += 1
		var e := ElementalEvent.make(ElementalEvent.Kind.AIRFLOW, c, strength, 0.0, id, dir)
		e.target = body
		emit_event(e)
		hit.append(body)
	_stats.blocked_by_terrain += blocked
	last_gust = {"origin": origin, "dir": dir, "hit": hit, "blocked": blocked, "at_ms": Time.get_ticks_msec()}
	last_result = "rajada: %d corpo(s)%s" % [hit.size(), (", %d atrás de terreno" % blocked) if blocked > 0 else ""]
