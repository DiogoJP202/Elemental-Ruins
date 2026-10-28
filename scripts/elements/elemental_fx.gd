class_name ElementalFx
extends Node3D
## Apresentação P3.6: só sinaliza o que o MaterialResponseSystem e os poderes JÁ
## decidiram (pesquisa §3.5: estado antes do VFX). Nada aqui muda física ou estado.
##   chamas    um emissor contínuo por corpo em chamas (filho do corpo), quantidade ∝ intensidade;
##             teto MAX_FLAMES (os excedentes queimam sem chama visível e contam em skipped)
##   vapor     disparo único ao apagar com água
##   carvão    corpo carbonizado escurece (material_override), mesmo depois de apagado
##   jato      cilindro translúcido da mão ao ponto atingido + respingo
##   orbe      núcleo legível sem partículas; deformação, trilha e respingo só leem o estado real
##   fogo      núcleo + chamas periféricas por projétil (slot estável por id), brasas na antecipação,
##             trilha térmica chama→brasa→fumaça em voo, clarão no impacto, vapor ao secar alvo molhado,
##             baforada de fumaça na dissipação por alcance
##   ar        sopro curto na mão ao emitir; anel na seção do cone acompanhando a casca real (pool por onda,
##             turbulência só visual); poeira em cada contato efetivo e no chão a cada `dust_spacing_m` da frente

const MAX_FLAMES := 24
const BURST_POOL := 4
const CHAR_CHECK_S := 0.25
const CHARRED_COLOR := Color("#2B2420")
const FIRE_TUNING_PATH := "res://data/abilities/fire_tuning.tres"
const AIR_TUNING_PATH := "res://data/abilities/air_tuning.tres"
const DUST_POOL := 6
static var _soft_texture: ImageTexture

var abilities: AbilityController
var materials: MaterialResponseSystem

var _flames := {}  # instance_id → {"body": WeakRef, "emitter": GPUParticles3D}
var _darkened := {}  # instance_id → weak body + materiais visuais de dano
var _flame_process: ParticleProcessMaterial
var _flame_quad: QuadMesh
var _steam: Array[GPUParticles3D] = []
var _blasts: Array[GPUParticles3D] = []
var _gusts: Array[GPUParticles3D] = []
var _fizzles: Array[GPUParticles3D] = []
var _next := {"steam": 0, "blast": 0, "gust": 0, "fizzle": 0, "dust": 0, "water_orb": 0}
var _dust: Array[GPUParticles3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_slots := {}  # wave id → índice do pool, estável durante a vida da onda
var _ring_dust_next := {}  # wave id → próxima distância com poeira de passagem
var _beam: MultiMeshInstance3D
var _water_snapshot: Array = []
var _water_tail := 0.0
var _water_clock := 0.0
var _spray: GPUParticles3D
var _water_orb_mesh: MeshInstance3D
var _water_orb_material: StandardMaterial3D
var _water_orb_trail: GPUParticles3D
var _water_orb_splashes: Array[GPUParticles3D] = []
var _orb_was_flying := false
var _balls: Array[MeshInstance3D] = []
var _fire_trails: Array[GPUParticles3D] = []
var _halos: Array[MeshInstance3D] = []
var _fire_slots := {}  # projectile id → índice do pool, estável durante a vida do projétil
var _slot_idle_ms: Array[int] = []
var _char_accum := 0.0
var _stats := {"flames_created": 0, "flames_skipped": 0, "steam": 0, "blasts": 0, "gusts": 0, "charred": 0,
	"fire_anticipations": 0, "fire_launches": 0, "fire_dissipations": 0, "fire_steam": 0, "fire_slots_missing": 0,
	"fire_vfx_frames": 0, "fire_vfx_usec": 0, "fire_vfx_usec_max": 0, "air_dust_contacts": 0, "air_dust_front": 0,
	"air_rings_missing": 0, "water_orb_impacts": 0, "water_orb_dissipations": 0}


func setup(p_abilities: AbilityController, p_materials: MaterialResponseSystem) -> void:
	abilities = p_abilities
	materials = p_materials
	materials.ignited.connect(_on_ignited)
	materials.extinguished.connect(_on_extinguished)
	materials.burned_out.connect(_on_burned_out)
	var fire := abilities.get_ability(&"fire_burst")
	if fire != null:
		fire.fx_event.connect(_on_fire_event)
	var air := abilities.get_ability(&"air_gust")
	if air != null:
		air.fx_event.connect(_on_air_event)
	var water := abilities.get_ability(&"water_jet") as WaterJet
	if water != null:
		water.orb.fx_event.connect(_on_water_orb_event)
	# Transições limpam também partículas de impactos anteriores, no próprio comando.
	abilities.terrain_service.world_reset_started.connect(_clear_water_orb)
	abilities.terrain_service.world_save_started.connect(func(_slot): _clear_water_orb())
	abilities.terrain_service.world_load_started.connect(func(_slot): _clear_water_orb())


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["flames_active"] = _flames.size()
	d["water_instances"] = _beam.multimesh.visible_instance_count if _beam != null else 0
	d["water_spray"] = _spray.emitting if _spray != null else false
	d["orb_visible"] = _water_orb_mesh.visible if _water_orb_mesh != null else false
	d["orb_trail_emitting"] = _water_orb_trail.emitting if _water_orb_trail != null else false
	d["orb_splash_pool"] = _water_orb_splashes.size()
	d["fire_trail_pool"] = _fire_trails.size()
	d["fire_slots_live"] = _fire_slots.size()
	d["air_rings_live"] = _ring_slots.size()
	var visible_balls := 0
	for ball in _balls:
		visible_balls += int(ball.visible)
	d["fire_balls_visible"] = visible_balls
	return d


func _ready() -> void:
	_flame_process = _process_material(Vector3.UP, 15.0, 1.0, 2.2, Vector3(0, 1.5, 0), Color("#FF8A2A"))
	_flame_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_flame_process.emission_box_extents = Vector3(0.45, 0.6, 0.45)
	var fire_tuning = load(FIRE_TUNING_PATH)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color(1.0, 0.95, 0.65, 0.9), fire_tuning.flame_color,
		fire_tuning.ember_color, fire_tuning.smoke_color, Color(0.22, 0.2, 0.19, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	_flame_process.color = Color.WHITE
	_flame_process.color_ramp = ramp
	_flame_process.angular_velocity_min = -35.0
	_flame_process.angular_velocity_max = 35.0
	_flame_quad = _quad(maxf(fire_tuning.flame_size, 0.05), Color(1, 1, 1, 0.8))
	# Fumaça da dissipação: brasa que esfria sem clarão (não houve contato nem calor).
	var smoke := Gradient.new()
	smoke.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	smoke.colors = PackedColorArray([fire_tuning.ember_color, fire_tuning.smoke_color, Color(0.22, 0.2, 0.19, 0.0)])
	var smoke_ramp := GradientTexture1D.new()
	smoke_ramp.gradient = smoke
	for i in BURST_POOL:
		_steam.append(_burst_emitter("Steam%d" % i, _process_material(Vector3.UP, 30.0, 1.0, 2.5, Vector3(0, 0.8, 0), Color("#E8EEF2")), 0.8, 1.4))
		var blast := _process_material(Vector3.UP, 180.0, 3.0, 6.0, Vector3(0, -2.0, 0), Color.WHITE)
		blast.color_ramp = ramp
		_blasts.append(_burst_emitter("Blast%d" % i, blast, 0.5, 0.6))
		var fizzle := _process_material(Vector3.UP, 70.0, 0.3, 0.9, Vector3(0, 0.6, 0), Color.WHITE)
		fizzle.color_ramp = smoke_ramp
		_fizzles.append(_burst_emitter("FireFizzle%d" % i, fizzle, 0.6, 0.35))
	for i in 2:
		_gusts.append(_burst_emitter("Gust%d" % i, _process_material(Vector3.FORWARD, 35.0, 8.0, 14.0, Vector3.ZERO, Color("#DDE6EA")), 0.35, 0.7))
	var air_tuning = load(AIR_TUNING_PATH)
	for i in DUST_POOL:
		_dust.append(_burst_emitter("AirDust%d" % i,
			_process_material(Vector3.UP, 55.0, 0.6, 2.0, Vector3(0, -1.2, 0), air_tuning.dust_color), 0.7, 0.5))
	for i in AirGust.MAX_WAVES:
		var ring := MeshInstance3D.new()
		ring.name = "AirFront%d" % i
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.0
		torus.rings = 24
		torus.ring_segments = 6
		var front: Color = air_tuning.front_color
		var front_material := _unshaded(Color(front.r, front.g, front.b, air_tuning.front_alpha))
		front_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		torus.material = front_material
		ring.mesh = torus
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		add_child(ring)
		_rings.append(ring)
	_beam = MultiMeshInstance3D.new()
	_beam.name = "WaterStream"
	var volume := SphereMesh.new()
	volume.radius = 0.1
	volume.height = 0.2
	volume.radial_segments = 6
	volume.rings = 2
	var water_material := _unshaded(Color(1, 1, 1, 0.8))
	water_material.vertex_color_use_as_albedo = true
	volume.material = water_material
	var stream := MultiMesh.new()
	stream.transform_format = MultiMesh.TRANSFORM_3D
	stream.use_colors = true
	stream.mesh = volume
	stream.instance_count = 24
	stream.visible_instance_count = 0
	_beam.multimesh = stream
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_spray = _burst_emitter("Spray", _process_material(Vector3.UP, 60.0, 1.0, 3.0, Vector3(0, -6.0, 0), Color("#C7E9EE")), 0.3, 0.16)
	_spray.one_shot = false
	_create_water_orb_visuals()
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
		# Chamas periféricas: casca aditiva maior que o núcleo, filha da bola.
		var halo := MeshInstance3D.new()
		halo.name = "Halo"
		var shell := SphereMesh.new()
		shell.radius = 0.25
		shell.height = 0.5
		shell.radial_segments = 8
		shell.rings = 4
		var flame_color: Color = fire_tuning.flame_color
		var halo_material := _unshaded(Color(flame_color.r, flame_color.g, flame_color.b, 0.35))
		halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		shell.material = halo_material
		halo.mesh = shell
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.add_child(halo)
		_halos.append(halo)
		var trail_process := _process_material(Vector3.BACK, 25.0, 0.4, 1.2, Vector3(0, 0.7, 0), Color.WHITE)
		trail_process.color_ramp = ramp
		var trail := _burst_emitter("FireTrail%d" % i, trail_process, fire_tuning.trail_lifetime_s, fire_tuning.trail_size)
		trail.amount = clampi(fire_tuning.trail_amount, 1, 24)
		trail.one_shot = false
		_fire_trails.append(trail)
		_slot_idle_ms.append(0)


func _process(delta: float) -> void:
	if abilities == null or materials == null:
		return
	_update_jet(delta)
	_update_water_orb()
	var t0 := Time.get_ticks_usec()
	_update_fireballs()
	_update_air()
	_char_accum += delta
	if _char_accum >= CHAR_CHECK_S:
		_char_accum = 0.0
		_update_flames()
	# CPU do VFX de fogo/ar por quadro (não inclui GPU).
	var spent := Time.get_ticks_usec() - t0
	_stats.fire_vfx_frames += 1
	_stats.fire_vfx_usec += spent
	_stats.fire_vfx_usec_max = maxi(_stats.fire_vfx_usec_max, spent)


# --- Chamas, vapor, carvão ------------------------------------------------------------------

func _on_ignited(body: Node3D) -> void:
	var id := body.get_instance_id()
	if _flames.has(id):
		return
	var tuning = _fire_parameters()
	if _flames.size() >= mini(MAX_FLAMES, tuning.max_flame_emitters):
		_stats.flames_skipped += 1
		return
	var e := GPUParticles3D.new()
	e.name = "Flame"
	e.amount = clampi(tuning.flame_amount, 1, 48)
	e.lifetime = maxf(tuning.flame_lifetime_s, 0.1)
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
	for id in _darkened.keys():
		if _darkened[id].body.get_ref() == null:
			_darkened.erase(id)
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
	var s := materials.state_of(body)
	if s == null or s.integrity >= 0.99:
		return
	if not _darkened.has(id):
		var meshes := []
		for ch in body.get_children():
			if ch is not MeshInstance3D or (ch as MeshInstance3D).mesh == null or (ch as MeshInstance3D).mesh.get_surface_count() == 0:
				continue
			var mi := ch as MeshInstance3D
			var original := mi.get_active_material(0) as StandardMaterial3D
			var visual: StandardMaterial3D = original.duplicate() if original != null else StandardMaterial3D.new()
			meshes.append({"material": visual, "color": visual.albedo_color})
			mi.material_override = visual
		_darkened[id] = {"body": weakref(body), "meshes": meshes, "notified": false}
	for m in _darkened[id].meshes:
		(m.material as StandardMaterial3D).albedo_color = (m.color as Color).lerp(CHARRED_COLOR, clampf(1.0 - s.integrity, 0.0, 1.0))
	if s.charred and not _darkened[id].notified:
		_darkened[id].notified = true
		_stats.charred += 1


# --- Poderes --------------------------------------------------------------------------------

func _create_water_orb_visuals() -> void:
	_water_orb_mesh = MeshInstance3D.new()
	_water_orb_mesh.name = "WaterOrb"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	_water_orb_material = _unshaded(Color(0.34, 0.76, 0.92, 0.72))
	sphere.material = _water_orb_material
	_water_orb_mesh.mesh = sphere
	_water_orb_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_orb_mesh.visible = false
	add_child(_water_orb_mesh)
	# Brilho interno original: mantém leitura de volume sem shader ou partículas.
	var glint := MeshInstance3D.new()
	glint.name = "Glint"
	var inner := SphereMesh.new()
	inner.radius = 0.6
	inner.height = 1.2
	inner.radial_segments = 12
	inner.rings = 6
	inner.material = _unshaded(Color(0.8, 0.96, 1.0, 0.32))
	glint.mesh = inner
	glint.position = Vector3(-0.16, 0.23, 0.08)
	glint.scale = Vector3(0.7, 0.85, 0.6)
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_orb_mesh.add_child(glint)
	_water_orb_trail = _burst_emitter("WaterOrbTrail",
		_process_material(Vector3.BACK, 30.0, 0.2, 0.8, Vector3(0, -1.5, 0), Color("#A5E5F2")), 0.2, 0.12)
	_water_orb_trail.amount = 8
	_water_orb_trail.one_shot = false
	_water_orb_trail.visible = false
	for i in 2:
		_water_orb_splashes.append(_burst_emitter("WaterOrbSplash%d" % i,
			_process_material(Vector3.UP, 75.0, 2.0, 4.0, Vector3(0, -4.0, 0), Color("#A5E5F2")), 0.45, 0.18))


func _update_water_orb() -> void:
	var jet := abilities.get_ability(&"water_jet") as WaterJet
	if jet == null or jet.orb.phase == "":
		_clear_water_orb(false)
		return
	var orb = jet.orb
	var t = orb.tuning
	if not t.visual_enabled:
		_clear_water_orb()
		return
	_water_orb_mesh.visible = true
	_water_orb_mesh.global_position = orb.position
	_water_orb_material.albedo_color = t.color
	var wobble := clampf(t.wobble, 0.0, 0.1)
	var ripple := sin(orb.age * 5.7) * wobble
	var formation: float = smoothstep(0.0, 0.16, orb.age) if orb.phase == "hold" else 1.0
	# A silhueta permanece dentro do raio consultado pela física, inclusive na deformação.
	_water_orb_mesh.scale = Vector3(1.0 + ripple, 1.0 - ripple * 0.55,
		1.0 + sin(orb.age * 7.3) * wobble * 0.5) * orb.radius() * 0.9 * maxf(formation, 0.05)
	var flying: bool = orb.phase == "flight" and t.trail_amount > 0
	_water_orb_trail.visible = flying
	_water_orb_trail.global_position = orb.position
	_water_orb_trail.amount = clampi(t.trail_amount, 1, 12)
	_water_orb_trail.lifetime = clampf(t.trail_lifetime_s, 0.05, 0.5)
	if flying and not _orb_was_flying:
		_water_orb_trail.restart()
	_water_orb_trail.emitting = flying
	if flying:
		var direction: Vector3 = -orb.velocity.normalized()
		(_water_orb_trail.process_material as ParticleProcessMaterial).direction = direction
	_orb_was_flying = flying


func _on_water_orb_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"water_orb_impact":
			_clear_water_orb(false)
			var jet := abilities.get_ability(&"water_jet") as WaterJet
			if jet == null or not jet.orb.tuning.visual_enabled:
				return
			var emitter := _water_orb_splashes[_next.water_orb]
			emitter.visible = true
			var splash := emitter.process_material as ParticleProcessMaterial
			var spread_scale := clampf(float(data.get("radius", 0.33)) / 0.33, 0.5, 2.0)
			splash.initial_velocity_min = 2.0 * spread_scale
			splash.initial_velocity_max = 4.0 * spread_scale
			_fire_burst(_water_orb_splashes, "water_orb", data.position, data.get("normal", Vector3.UP))
			_stats.water_orb_impacts += 1
		&"water_orb_cancel":
			_clear_water_orb()
		&"water_orb_dissipate":
			_clear_water_orb()
			_stats.water_orb_dissipations += 1


func _clear_water_orb(clear_splashes := true) -> void:
	_orb_was_flying = false
	if _water_orb_mesh != null:
		_water_orb_mesh.visible = false
	if _water_orb_trail != null:
		_water_orb_trail.emitting = false
		_water_orb_trail.visible = false
	if clear_splashes:
		for emitter in _water_orb_splashes:
			emitter.emitting = false
			emitter.visible = false


func _update_jet(delta := 0.0) -> void:
	var jet := abilities.get_ability(&"water_jet") as WaterJet
	if jet == null:
		return
	_water_clock += delta
	var records: Array
	if jet.active:
		_water_snapshot = jet.packets.duplicate(true)
		_water_tail = jet.tuning.tail_s
		records = jet.packets
	else:
		_water_tail = maxf(0.0, _water_tail - delta)
		records = _water_snapshot if _water_tail > 0.0 else []
	var count := mini(records.size(), clampi(jet.tuning.visual_segments, 4, 24))
	_beam.visible = count > 0
	_beam.multimesh.visible_instance_count = count
	var alpha := 1.0 if jet.active else _water_tail / maxf(jet.tuning.tail_s, 0.001)
	for i in count:
		# Inclui a frente e a emissão perto da mão mesmo com tuning acima do teto visual.
		var sample_index := roundi(float(i) * float(records.size() - 1) / maxf(float(count - 1), 1.0))
		var p: Dictionary = records[sample_index]
		var axis: Vector3 = p.dir
		var side := axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
		var across := side.cross(axis)
		var length := maxf(0.01, minf(float(p.traveled), jet.tuning.stream_speed * jet.tuning.emission_interval_s * 1.15))
		var radius := jet.tuning.stream_radius / 0.1 * lerpf(0.4, 1.0, float(p.pressure))
		var wobble := jet.tuning.visual_turbulence * sin(_water_clock * 17.0 + float(i) * 2.1)
		var stream_position: Vector3 = p.pos - axis * length * 0.5 + side * wobble
		var basis := Basis(side * radius, axis * length / 0.2, across * radius)
		_beam.multimesh.set_instance_transform(i, Transform3D(basis, stream_position))
		var tint := jet.tuning.stream_color.lerp(Color.WHITE, 0.35 if i % 4 == 0 else 0.0)
		tint.a = 0.75 * alpha
		_beam.multimesh.set_instance_color(i, tint)
	_spray.emitting = jet.active and jet.contact_age < jet.tuning.emission_interval_s * 2.5
	if _spray.emitting:
		_spray.global_position = jet.contact_point
		(_spray.process_material as ParticleProcessMaterial).direction = jet.contact_normal
		_spray.amount_ratio = clampf(jet.pressure, 0.1, 1.0)


## Cada projétil fica no mesmo slot do pool da antecipação ao fim: trocar de slot quando
## outro projétil some faria a trilha (coordenadas globais) saltar entre trajetórias.
func _update_fireballs() -> void:
	var fire := abilities.get_ability(&"fire_burst") as FireBurst
	if fire == null:
		return
	var live := {}
	for p: Dictionary in fire.projectiles:
		live[int(p.id)] = p
	for pid: int in _fire_slots.keys():
		if live.has(pid):
			continue
		var gone: int = _fire_slots[pid]
		_balls[gone].visible = false
		_fire_trails[gone].emitting = false
		_slot_idle_ms[gone] = Time.get_ticks_msec()
		_fire_slots.erase(pid)
	var radius_scale := maxf(fire.tuning.projectile_radius / 0.25, 0.05)
	for pid: int in live:
		var p: Dictionary = live[pid]
		if not _fire_slots.has(pid):
			var free := _free_fire_slot()
			if free < 0:
				_stats.fire_slots_missing += 1
				continue
			_fire_slots[pid] = free
			_fire_trails[free].global_position = p.pos
			_fire_trails[free].restart()
		var i: int = _fire_slots[pid]
		var pending: bool = p.phase == "anticipation"
		var age := float(p.age)
		var ratio := clampf(age / maxf(fire.tuning.anticipation_s, 0.001), 0.0, 1.0)
		var flicker := sin(age * 29.0 + float(pid) * 1.7)
		_balls[i].visible = true
		_balls[i].global_position = p.pos
		_balls[i].scale = Vector3.ONE * radius_scale * (lerpf(0.2, 0.75, ratio) if pending else 1.0 + 0.06 * flicker)
		# Turbulência visual só na casca; o núcleo segue a posição simulada.
		var wobble := 1.55 + 0.2 * sin(age * TAU * maxf(fire.tuning.turbulence_hz, 0.0) * 1.3 + float(pid))
		_halos[i].scale = Vector3.ONE * (lerpf(1.0, 1.35, ratio) if pending else wobble)
		# Antecipação: brasas fracas reunindo-se na mão (telegraph); voo: trilha completa.
		_fire_trails[i].emitting = true
		_fire_trails[i].global_position = p.pos
		(_fire_trails[i].process_material as ParticleProcessMaterial).direction = -(p.vel as Vector3).normalized()
		_fire_trails[i].amount_ratio = 0.35 if pending else 1.0


func _free_fire_slot() -> int:
	var used := {}
	for slot: int in _fire_slots.values():
		used[slot] = true
	var best := -1
	for i in _balls.size():
		if not used.has(i) and (best < 0 or _slot_idle_ms[i] < _slot_idle_ms[best]):
			best = i
	return best


func _fire_parameters():
	if abilities != null:
		var fire := abilities.get_ability(&"fire_burst") as FireBurst
		if fire != null:
			return fire.tuning
	return load(FIRE_TUNING_PATH)


func _on_fire_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"fire_anticipation":
			_stats.fire_anticipations += 1
		&"fire_launch":
			_stats.fire_launches += 1
		&"fire_dissipate":
			_fire_burst(_fizzles, "fizzle", data.position, Vector3.UP)
			_stats.fire_dissipations += 1
		&"fire_impact":
			var direction: Vector3 = data.get("normal", Vector3.UP)
			if direction.is_zero_approx():
				direction = Vector3.UP
			_fire_burst(_blasts, "blast", data.position, direction)
			_stats.blasts += 1
			# Reação à água: o impacto secou umidade real do alvo.
			if float(data.get("target_wetness_before", 0.0)) - float(data.get("target_wetness_after", 0.0)) > 0.01:
				_fire_burst(_steam, "steam", data.position, direction)
				_stats.fire_steam += 1


## Frente: anel na seção do cone à distância atual da casca; poeira no chão a cada `dust_spacing_m`
## percorrido (consulta só de leitura, sem efeito físico).
func _update_air() -> void:
	var air := abilities.get_ability(&"air_gust") as AirGust
	if air == null:
		return
	var live := {}
	for w: Dictionary in air.waves:
		live[int(w.id)] = w
	for wid: int in _ring_slots.keys():
		if live.has(wid):
			continue
		_rings[_ring_slots[wid]].visible = false
		_ring_slots.erase(wid)
		_ring_dust_next.erase(wid)
	var t := air.tuning
	var spacing := maxf(t.dust_spacing_m, 0.5)
	for wid: int in live:
		var w: Dictionary = live[wid]
		if not _ring_slots.has(wid):
			var used := {}
			for s: int in _ring_slots.values():
				used[s] = true
			var free := -1
			for i in _rings.size():
				if not used.has(i):
					free = i
					break
			if free < 0:
				_stats.air_rings_missing += 1
				continue
			_ring_slots[wid] = free
			_ring_dust_next[wid] = spacing
		var dir: Vector3 = w.dir
		var origin: Vector3 = w.origin
		var radius := float(w.radius)
		var section := maxf(radius * tan(deg_to_rad(t.half_angle_deg)), 0.15)
		section *= 1.0 + t.visual_turbulence * sin(float(w.age) * 37.0 + float(wid) * 1.3)
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
		var across := side.cross(dir).normalized()
		var ring := _rings[_ring_slots[wid]]
		ring.visible = radius > 0.05
		ring.global_transform = Transform3D(Basis(side * section, dir * 0.6, across * section), origin + dir * radius)
		var fade := clampf(1.0 - radius / maxf(t.max_range, 0.01), 0.0, 1.0)
		var ring_material := (ring.mesh as TorusMesh).material as StandardMaterial3D
		ring_material.albedo_color.a = t.front_alpha * sqrt(fade)
		while radius >= float(_ring_dust_next[wid]) and float(_ring_dust_next[wid]) <= t.max_range + 0.001:
			var at := origin + dir * float(_ring_dust_next[wid])
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, Layers.TERRAIN)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				_fire_burst(_dust, "dust", hit.position, Vector3.UP)
				_stats.air_dust_front += 1
			_ring_dust_next[wid] = float(_ring_dust_next[wid]) + spacing


func _on_air_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"air_launch":
			_fire_burst(_gusts, "gust", data.position, data.direction)
			_stats.gusts += 1
		&"air_contact":
			_fire_burst(_dust, "dust", data.position, data.direction)
			_stats.air_dust_contacts += 1


# --- Emissores ------------------------------------------------------------------------------

func _fire_burst(pool: Array[GPUParticles3D], key: String, at: Vector3, dir: Vector3) -> void:
	var e := pool[_next[key]]
	_next[key] = (_next[key] + 1) % pool.size()
	var direction := dir.normalized() if not dir.is_zero_approx() else Vector3.UP
	var up := Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP
	var basis: Basis
	if key == "gust":
		basis = Basis.looking_at(direction, up)
	else:
		var side := direction.cross(up).normalized()
		basis = Basis(side, direction, side.cross(direction))
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
	mat.albedo_texture = _particle_texture()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	return quad


## Textura procedural compartilhada: remove os quadrados opacos dos respingos,
## brasas e fumaça sem adicionar emissores ou física decorativa.
static func _particle_texture() -> ImageTexture:
	if _soft_texture != null:
		return _soft_texture
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var uv := (Vector2(x, y) + Vector2.ONE * 0.5) / 8.0 - Vector2.ONE
			var alpha := 1.0 - smoothstep(0.35, 1.0, uv.length())
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	_soft_texture = ImageTexture.create_from_image(img)
	return _soft_texture


static func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
