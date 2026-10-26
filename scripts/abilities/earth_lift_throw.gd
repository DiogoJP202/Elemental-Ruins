class_name EarthLiftThrow
extends Ability
## Terra — erguer e arremessar rocha (atlas te-001; roadmap P3).
## Segurar: extrai uma rocha real do terreno sob a mira (TerrainService.extract_rock, P2) e a
## leva até um ponto à frente do jogador por mola-amortecedor criticamente amortecida, com
## amortecimento relativo à velocidade do alvo (spike P3, H1). Primeiro sobe na vertical,
## porque a boca da cavidade é mais estreita que ela (P2, D25). Soltar: lançamento na direção
## da mira, compensando a queda até o ponto mirado; no 1º contato, um evento KINETIC com o
## impulso perdido pela rocha vai ao alvo (pode soltar peças da torre).

const OMEGA := 6.0
const MAX_ACCEL := 40.0
const THROW_SPEED := 22.0
const RANGE := 18.0
const HOLD_DISTANCE := 4.0
const HOLD_HEIGHT := 2.6
const ROCK_RADIUS := 1.2
const MONITOR_S := 4.0

var rock: RigidBody3D
var phase := ""  # "", "rising", "held", "thrown"
var _hole := Vector3.ZERO
var _prev_target := Vector3.ZERO
var _thrown := []  # [{body, prev_vel, until_ms, hit}]
var _stats := {"extracted": 0, "thrown": 0, "hits": 0, "max_impulse": 0.0}


func _init() -> void:
	id = &"earth_lift_throw"
	element = &"earth"
	display_name = "Erguer e arremessar rocha"
	input_mode = "hold"


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["phase"] = phase
	return d


func on_press() -> void:
	if rock != null and is_instance_valid(rock):
		return
	var aim: Dictionary = controller.aim_terrain(RANGE)
	if aim.is_empty():
		last_result = "sem terreno ao alcance (%.0f m)" % RANGE
		return
	var out: Dictionary = controller.terrain_service.extract_rock(aim.position, aim.normal, ROCK_RADIUS, controller.props_root)
	var result: TerrainEditResult = out.result
	if result == null or not result.ok or out.bodies.is_empty():
		last_result = "não extraiu: %s" % (result.reason if result != null else "?")
		return
	rock = out.bodies[0]
	rock.gravity_scale = 0.0
	rock.continuous_cd = true
	_hole = aim.position
	_prev_target = rock.global_position
	phase = "rising"
	_stats.extracted += 1
	last_result = "rocha de %.1f t extraída" % (rock.mass / 1000.0)
	if controller.dust != null:
		controller.dust.burst(aim.position)


func on_hold(_delta: float) -> void:
	if rock == null or not is_instance_valid(rock):
		phase = ""
		return
	if rock.freeze:
		return  # o Voxel Tools mantém o corpo cinemático por < 0,5 s (collider do buraco atualizar)
	var target := hold_target()
	if phase == "rising":
		# Sobe na vertical até o fundo da rocha passar da superfície; depois vai ao ponto de suspensão.
		target = _hole + Vector3.UP * (ROCK_RADIUS * 2.0 + 1.0)
		if _mesh_bottom(rock) > _hole.y + 0.4:
			phase = "held"
	var tv := (target - _prev_target) * Engine.physics_ticks_per_second
	_prev_target = target
	rock.apply_central_force(spring_force(rock, target, tv if phase == "held" else Vector3.ZERO, center_of(rock)))


func on_release() -> void:
	if rock == null or not is_instance_valid(rock):
		phase = ""
		return
	if rock.freeze:
		rock.freeze = false
	var dir: Vector3 = controller.aim_direction()
	var launch := dir * THROW_SPEED
	# A própria rocha costuma estar entre a câmera e o alvo: fica fora do raio de mira.
	var exclude: Array[RID] = [rock.get_rid()]
	var hit: Dictionary = controller.aim_any(60.0, exclude)
	if not hit.is_empty():
		# O centro da rocha chega no ponto mirado, mas nunca abaixo de uma meia altura acima do
		# chão sob ele: mirado no pé de uma caixa, o centro de uma rocha de ~2 m baixo demais
		# raspava o chão antes e quicava por cima (medido no T29).
		var aim_point: Vector3 = hit.position
		var ground: Dictionary = controller.terrain_service.raycast_terrain(aim_point + Vector3.UP * 0.5, aim_point + Vector3.DOWN * 20.0)
		if not ground.is_empty():
			aim_point.y = maxf(aim_point.y, ground.position.y + half_height(rock))
		var to: Vector3 = aim_point - center_of(rock)
		var flight := to.length() / THROW_SPEED
		launch = to.normalized() * THROW_SPEED + Vector3.UP * (9.8 * flight * 0.5)
	rock.gravity_scale = 1.0
	rock.contact_monitor = true
	rock.max_contacts_reported = 8
	rock.apply_central_impulse((launch - rock.linear_velocity) * rock.mass)
	var entry := {"body": rock, "prev_vel": launch, "until_ms": Time.get_ticks_msec() + int(MONITOR_S * 1000.0),
		"hit": false, "hit_frame": -1, "impulse": 0.0, "dir": Vector3.ZERO, "targets": [], "sent": false}
	_thrown.append(entry)
	rock.body_entered.connect(_on_rock_contact.bind(entry))
	_stats.thrown += 1
	last_result = "arremessada a %.0f m/s" % THROW_SPEED
	phase = "thrown"
	rock = null


func physics_tick(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var keep := []
	for e in _thrown:
		# Checar antes de atribuir a uma variável tipada: a rocha pode ter sido liberada (reset).
		if not is_instance_valid(e.body):
			continue
		var b: RigidBody3D = e.body
		if e.hit and not e.sent:
			_dispatch_impact(e)
		if now > e.until_ms or e.hit:
			b.contact_monitor = false
			continue
		e.prev_vel = b.linear_velocity
		keep.append(e)
	_thrown = keep
	if phase == "thrown" and _thrown.is_empty():
		phase = ""


func cancel() -> void:
	if rock != null and is_instance_valid(rock):
		rock.gravity_scale = 1.0
	rock = null
	phase = ""


func status() -> String:
	if phase == "rising" or phase == "held":
		return "segurando rocha de %.1f t (%s)" % [rock.mass / 1000.0 if rock != null else 0.0, "subindo" if phase == "rising" else "pronta: solte para arremessar"]
	return last_result


## Ponto de suspensão: à frente do jogador, na direção horizontal da câmera, acima da cabeça.
func hold_target() -> Vector3:
	var fwd: Vector3 = controller.aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return controller.player.global_position + fwd * HOLD_DISTANCE + Vector3.UP * HOLD_HEIGHT


## Mola-amortecedor criticamente amortecida (k = mω², c = 2mω), com teto de aceleração.
## `at` é o ponto controlado (o centro da rocha, não a origem do corpo).
static func spring_force(body: RigidBody3D, target: Vector3, target_vel: Vector3, at: Vector3) -> Vector3:
	var k := body.mass * OMEGA * OMEGA
	var c := 2.0 * body.mass * OMEGA
	var f := (target - at) * k + (target_vel - body.linear_velocity) * c
	return f.limit_length(body.mass * MAX_ACCEL)


static func half_height(body: RigidBody3D) -> float:
	for ch in body.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			return (ch as MeshInstance3D).mesh.get_aabb().size.y * 0.5
	return 0.5


## Centro da malha no mundo. O corpo criado por separate_floating_chunks tem a origem no canto
## da caixa do pedaço (~3 m do centro): mirar ou segurar pela origem erra o alvo (medido no T29).
static func center_of(body: RigidBody3D) -> Vector3:
	for ch in body.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			return mi.global_transform * mi.mesh.get_aabb().get_center()
	return body.global_position


## 1º passo de física com contato em CORPOS (terreno não conta: a rocha pode raspar o chão e
## seguir). Impulso estimado = massa × velocidade perdida nesse passo (spike P3, H2), dividido
## igualmente entre todos os corpos tocados no mesmo passo: atribuir tudo ao 1º relatado
## quebrava a peça errada quando a rocha tocava duas ao mesmo tempo (medido no T30).
func _on_rock_contact(other: Node, entry: Dictionary) -> void:
	if not is_instance_valid(entry.body):
		return
	var target := other as Node3D
	if target == null or target is VoxelLodTerrain:
		return
	var frame := Engine.get_physics_frames()
	if entry.hit:
		if frame == entry.hit_frame and not entry.sent and not entry.targets.has(target):
			entry.targets.append(target)
		return
	var b: RigidBody3D = entry.body
	entry.hit = true
	entry.hit_frame = frame
	entry.impulse = b.mass * (entry.prev_vel - b.linear_velocity).length()
	entry.dir = entry.prev_vel
	entry.targets = [target]
	entry.origin = center_of(b)
	_stats.hits += 1
	_stats.max_impulse = maxf(_stats.max_impulse, entry.impulse)


func _dispatch_impact(entry: Dictionary) -> void:
	entry.sent = true
	var n: int = entry.targets.size()
	for t in entry.targets:
		if not is_instance_valid(t):
			continue
		var e := ElementalEvent.make(ElementalEvent.Kind.KINETIC, entry.origin, entry.impulse / n, 0.0, id, entry.dir)
		e.target = t
		emit_event(e)


static func _mesh_bottom(b: RigidBody3D) -> float:
	for ch in b.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			return (mi.global_transform * mi.mesh.get_aabb()).position.y
	return b.global_position.y
