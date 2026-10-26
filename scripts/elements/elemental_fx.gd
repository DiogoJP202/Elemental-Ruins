class_name ElementalFx
extends Node3D
## VFX mínimos do P3 (sem arte): só sinalizam o que o MaterialResponseSystem e os poderes JÁ
## decidiram (pesquisa §3.5: estado antes do VFX). Nada aqui muda física ou estado.
##   chamas    um emissor contínuo por corpo em chamas (filho do corpo), quantidade ∝ intensidade;
##             teto MAX_FLAMES (os excedentes queimam sem chama visível e contam em skipped)
##   vapor     disparo único ao apagar com água
##   carvão    corpo carbonizado escurece (material_override), mesmo depois de apagado
##   jato      cilindro translúcido da mão ao ponto atingido + respingo
##   fogo      esfera brilhante por bola em voo + clarão na explosão
##   ar        disparo único em cone na rajada

const MAX_FLAMES := 24
const BURST_POOL := 4
const CHAR_CHECK_S := 0.25
const CHARRED_COLOR := Color("#2B2420")

var abilities: AbilityController
var materials: MaterialResponseSystem

var _flames := {}  # instance_id → {"body": WeakRef, "emitter": GPUParticles3D}
var _darkened := {}  # instance_id → true
var _flame_process: ParticleProcessMaterial
var _flame_quad: QuadMesh
var _steam: Array[GPUParticles3D] = []
var _blasts: Array[GPUParticles3D] = []
var _gusts: Array[GPUParticles3D] = []
var _next := {"steam": 0, "blast": 0, "gust": 0}
var _beam: MeshInstance3D
var _spray: GPUParticles3D
var _balls: Array[MeshInstance3D] = []
var _last_gust_ms := -1
var _char_accum := 0.0
var _charred_material: StandardMaterial3D
var _stats := {"flames_created": 0, "flames_skipped": 0, "steam": 0, "blasts": 0, "gusts": 0, "charred": 0}


func setup(p_abilities: AbilityController, p_materials: MaterialResponseSystem) -> void:
	abilities = p_abilities
	materials = p_materials
	materials.ignited.connect(_on_ignited)
	materials.extinguished.connect(_on_extinguished)
	materials.burned_out.connect(_on_burned_out)


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["flames_active"] = _flames.size()
	return d


func _ready() -> void:
	_charred_material = StandardMaterial3D.new()
	_charred_material.albedo_color = CHARRED_COLOR
	_charred_material.roughness = 1.0
	_flame_process = _process_material(Vector3.UP, 15.0, 1.0, 2.2, Vector3(0, 1.5, 0), Color("#FF8A2A"))
	_flame_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_flame_process.emission_box_extents = Vector3(0.45, 0.6, 0.45)
	_flame_quad = _quad(0.45, Color(1, 1, 1, 0.8))
	for i in BURST_POOL:
		_steam.append(_burst_emitter("Steam%d" % i, _process_material(Vector3.UP, 30.0, 1.0, 2.5, Vector3(0, 0.8, 0), Color("#E8EEF2")), 0.8, 1.4))
		_blasts.append(_burst_emitter("Blast%d" % i, _process_material(Vector3.UP, 180.0, 3.0, 6.0, Vector3(0, -2.0, 0), Color("#FFB347")), 0.5, 0.6))
	for i in 2:
		_gusts.append(_burst_emitter("Gust%d" % i, _process_material(Vector3.FORWARD, 35.0, 8.0, 14.0, Vector3.ZERO, Color("#DDE6EA")), 0.35, 0.7))
	_beam = MeshInstance3D.new()
	_beam.name = "WaterBeam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.12
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.material = _unshaded(Color(0.45, 0.7, 1.0, 0.6))
	_beam.mesh = cyl
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_spray = _burst_emitter("Spray", _process_material(Vector3.UP, 60.0, 1.0, 3.0, Vector3(0, -6.0, 0), Color("#9CC8F0")), 0.3, 0.6)
	_spray.one_shot = false
	for i in FireBurst.MAX_PROJECTILES:
		var ball := MeshInstance3D.new()
		ball.name = "FireBall%d" % i
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		sphere.radial_segments = 8
		sphere.rings = 4
		sphere.material = _unshaded(Color("#FF7A1A"))
		ball.mesh = sphere
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.visible = false
		add_child(ball)
		_balls.append(ball)


func _process(delta: float) -> void:
	if abilities == null or materials == null:
		return
	_update_jet()
	_update_fireballs()
	_update_gust()
	_char_accum += delta
	if _char_accum >= CHAR_CHECK_S:
		_char_accum = 0.0
		_update_flames()


# --- Chamas, vapor, carvão ------------------------------------------------------------------

func _on_ignited(body: Node3D) -> void:
	var id := body.get_instance_id()
	if _flames.has(id):
		return
	if _flames.size() >= MAX_FLAMES:
		_stats.flames_skipped += 1
		return
	var e := GPUParticles3D.new()
	e.name = "Flame"
	e.amount = 24
	e.lifetime = 0.7
	e.process_material = _flame_process
	e.draw_pass_1 = _flame_quad
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	body.add_child(e)
	e.global_position = MaterialResponseSystem.body_center(body)
	e.emitting = true
	_flames[id] = {"body": weakref(body), "emitter": e}
	_stats.flames_created += 1


func _on_extinguished(body: Node3D, cause: String) -> void:
	_darken_if_charred(body)
	_remove_flame(body)
	if cause == "água":
		_fire_burst(_steam, "steam", MaterialResponseSystem.body_center(body), Vector3.UP)
		_stats.steam += 1


func _on_burned_out(body: Node3D) -> void:
	_remove_flame(body)


func _remove_flame(body: Node3D) -> void:
	var id := body.get_instance_id()
	if not _flames.has(id):
		return
	var e: GPUParticles3D = _flames[id].emitter
	if is_instance_valid(e):
		e.queue_free()
	_flames.erase(id)


## Intensidade → fração de partículas; carbonizado → escurece. Corpos sumidos saem da lista.
func _update_flames() -> void:
	for id in _flames.keys():
		var entry: Dictionary = _flames[id]
		var body := entry.body.get_ref() as Node3D
		if body == null or not body.is_inside_tree():
			_flames.erase(id)
			continue
		var s := materials.state_of(body)
		if s == null:
			continue
		(entry.emitter as GPUParticles3D).amount_ratio = clampf(s.intensity, 0.2, 1.0)
		_darken_if_charred(body)


func _darken_if_charred(body: Node3D) -> void:
	var id := body.get_instance_id()
	if _darkened.has(id):
		return
	var s := materials.state_of(body)
	if s == null or not s.charred:
		return
	for ch in body.get_children():
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).material_override = _charred_material
	_darkened[id] = true
	_stats.charred += 1


# --- Poderes --------------------------------------------------------------------------------

func _update_jet() -> void:
	var jet := abilities.get_ability(&"water_jet") as WaterJet
	var on := jet != null and jet.active and jet.beam_from.distance_to(jet.beam_to) > 0.1
	_beam.visible = on
	if _spray.emitting != on:
		_spray.emitting = on
	if not on:
		return
	var axis := jet.beam_to - jet.beam_from
	var y := axis.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_beam.global_transform = Transform3D(Basis(x, y * axis.length(), z), (jet.beam_from + jet.beam_to) * 0.5)
	_spray.global_position = jet.beam_to


func _update_fireballs() -> void:
	var fire := abilities.get_ability(&"fire_burst") as FireBurst
	if fire == null:
		return
	for i in _balls.size():
		var on := i < fire.projectiles.size()
		_balls[i].visible = on
		if on:
			_balls[i].global_position = fire.projectiles[i].pos
	for at in fire.impacts:
		_fire_burst(_blasts, "blast", at, Vector3.UP)
		_stats.blasts += 1
	fire.impacts.clear()


func _update_gust() -> void:
	var air := abilities.get_ability(&"air_gust") as AirGust
	if air == null or air.last_gust.is_empty() or air.last_gust.at_ms == _last_gust_ms:
		return
	_last_gust_ms = air.last_gust.at_ms
	_fire_burst(_gusts, "gust", air.last_gust.origin, air.last_gust.dir)
	_stats.gusts += 1


# --- Emissores ------------------------------------------------------------------------------

func _fire_burst(pool: Array[GPUParticles3D], key: String, at: Vector3, dir: Vector3) -> void:
	var e := pool[_next[key]]
	_next[key] = (_next[key] + 1) % pool.size()
	var basis := Basis.IDENTITY
	if dir.normalized().abs().distance_to(Vector3.UP) > 0.01:
		basis = Basis.looking_at(dir.normalized(), Vector3.UP)  # −Z do emissor aponta para dir
	e.global_transform = Transform3D(basis, at)
	e.restart()
	e.emitting = true


func _burst_emitter(n: String, process: ParticleProcessMaterial, lifetime: float, size: float) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.name = n
	e.one_shot = true
	e.emitting = false
	e.amount = 24
	e.lifetime = lifetime
	e.explosiveness = 0.85
	e.local_coords = false
	e.process_material = process
	e.draw_pass_1 = _quad(size, Color(1, 1, 1, 0.6))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 10, 16))
	add_child(e)
	return e


static func _process_material(direction: Vector3, spread: float, v_min: float, v_max: float, gravity: Vector3,
		color: Color) -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = gravity
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.scale_min = 0.4
	p.scale_max = 0.9
	p.color = color
	return p


static func _quad(size: float, tint: Color) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := _unshaded(tint)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	return quad


static func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
