class_name EarthFx
extends Node3D
## VFX e retorno local da Terra polida (P3.5). Só lê o fx_event da EarthLiftThrow e o estado;
## não muda física nem estado (mesma regra do ElementalFx; pesquisa §3.5).
##   antecipação     rachadura (decal procedural) crescendo, anel de telegraph no chão (visível a
##                   todos), poeira rasteira e pedrinhas saltando, tremor leve de câmera
##   desprendimento  rachadura cheia, estouro de poeira e pedrinhas na cor do material; uma CÓPIA
##                   da malha da rocha treme e sobe até detach_visual_rise (a malha original fica
##                   escondida e parada, e o centro usado pela física não se mexe)
##   levantamento    a cópia volta à rocha real em ~0,08 s; poeira subindo do buraco; pedrinhas
##                   caindo da rocha
##   lançamento      puff de poeira e rastro enquanto a rocha passa de 8 m/s
##   impacto         poeira, pedrinhas e rachadura no ponto; tremor ∝ força e proximidade
##   alvo inválido   anel vermelho curto no ponto mirado
##   preview         anel verde/vermelho no ponto de arranque, com a Terra escolhida e parada
## Pedrinhas são partículas (colisão por GPUParticlesCollisionHeightField3D que segue a câmera;
## custo medido no spike P3.5 E4), nunca corpos físicos.

const DECAL_POOL := 8
const BURST_POOL := 6
const DECAL_HOLD_S := 4.0
const DECAL_FADE_S := 2.0
const RING_COLOR := Color(0.95, 0.68, 0.32, 0.55)
const INVALID_COLOR := Color(0.95, 0.2, 0.15, 0.8)
const PREVIEW_OK := Color(0.35, 0.95, 0.45, 0.35)
const PREVIEW_BAD := Color(0.95, 0.3, 0.25, 0.3)
const TRAIL_MIN_SPEED := 8.0
const TRAIL_MAX_S := 2.5
const SHAKE_BLEND_OUT_S := 0.08
const PREVIEW_EVERY := 3
## Distância (m) da câmera em que o tremor some.
const TRAUMA_RANGE := 30.0

var abilities: AbilityController
var earth: EarthLiftThrow
var camera: ThirdPersonCamera
## Marcador do pincel (G/H): escondido enquanto a Terra age, para não cobrir o poder.
var edit_controller: TerrainEditController

var _rng := RandomNumberGenerator.new()
var _cracks: Array[ImageTexture] = []
var _decals: Array[Decal] = []
var _decal_state: Array[Dictionary] = []
var _next_decal := 0
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _ring_t := -1.0
var _invalid: MeshInstance3D
var _invalid_mat: StandardMaterial3D
var _invalid_t := -1.0
var _preview: MeshInstance3D
var _preview_mat: StandardMaterial3D
var _dust: Array[GPUParticles3D] = []
var _pebbles: Array[GPUParticles3D] = []
var _next := {"dust": 0, "pebbles": 0}
var _shake := {}
var _attached := []  # [{emitter, rock, t, max_t, trail}]
var _frame := 0
var _stats := {"cracks": 0, "telegraphs": 0, "dust": 0, "pebbles": 0, "mesh_shakes": 0, "rock_pebbles": 0,
	"trails": 0, "impacts": 0, "invalid": 0, "trauma_events": 0}


func setup(p_abilities: AbilityController, p_camera: ThirdPersonCamera, p_edit: TerrainEditController = null) -> void:
	abilities = p_abilities
	camera = p_camera
	edit_controller = p_edit
	earth = abilities.get_ability(&"earth_lift_throw") as EarthLiftThrow
	if earth != null:
		earth.fx_event.connect(_on_fx)


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["attached_emitters"] = _attached.size()
	d["shake_active"] = not _shake.is_empty()
	return d


func _ready() -> void:
	_rng.seed = 11
	for s in 3:
		# Linhas grossas (256 / 22 px ≈ 0,2 m num decal de 4,4 m): mais finas sumiam a ~9 m nas capturas.
		_cracks.append(CrackTexture.make(256, 101 + s * 17, 6 + s, 256.0 / 22.0))
	for i in DECAL_POOL:
		var d := Decal.new()
		d.name = "Crack%d" % i
		d.visible = false
		d.upper_fade = 0.2
		d.lower_fade = 0.6
		add_child(d)
		_decals.append(d)
		_decal_state.append({})
	_ring_mat = _unshaded(RING_COLOR)
	_ring = _torus("Telegraph", 1.62, 1.82, _ring_mat)
	_invalid_mat = _unshaded(INVALID_COLOR)
	_invalid = _torus("Invalid", 0.45, 0.6, _invalid_mat)
	_preview_mat = _unshaded(PREVIEW_OK)
	_preview = _torus("Preview", 1.7, 1.8, _preview_mat)
	for i in BURST_POOL:
		_dust.append(_make_dust("Dust%d" % i))
		_pebbles.append(_make_pebbles("Pebbles%d" % i, true))
	var hf := GPUParticlesCollisionHeightField3D.new()
	hf.name = "PebbleCollision"
	hf.size = Vector3(48, 24, 48)
	hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	hf.follow_camera_enabled = true
	add_child(hf)


# --- Eventos ---------------------------------------------------------------------------------

func _on_fx(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"invalid":
			_stats.invalid += 1
			var p: Vector3 = data.get("point", Vector3.ZERO)
			if p != Vector3.ZERO:
				_invalid.global_position = p + Vector3.UP * 0.05
				_invalid.visible = true
				_invalid_t = 0.0
		&"anticipation":
			var p: Vector3 = data.point
			var col: Color = data.get("color", Color.GRAY)
			var grow_s: float = data.get("duration", 0.1) + earth.tuning.detach_s
			# 6 m: os ramos chegam a ~2,7 m do centro, além da boca da cavidade (~1,8 m); com 4,4 m
			# ficavam quase todos dentro do buraco (capturas do T45).
			_crack(p, 1.5, 6.0, grow_s, 0.5, 1.0)
			_ring.global_position = p + Vector3.UP * 0.04
			_ring.visible = true
			_ring_t = 0.0
			_stats.telegraphs += 1
			_burst(_dust, "dust", p, col.lightened(0.35), 0.45, 0.6, 1.4)
			_burst(_pebbles, "pebbles", p, col.darkened(0.25), 0.35, 1.2, 2.4)
			_trauma(0.12, p)
		&"detach":
			var p: Vector3 = data.point
			var col: Color = data.get("color", Color.GRAY)
			_burst(_dust, "dust", p, col.lightened(0.3), 1.0, 1.5, 3.2)
			_burst(_pebbles, "pebbles", p, col.darkened(0.25), 1.0, 2.5, 5.0)
			_start_shake(data.get("rock"), data.get("duration", 0.1), data.get("visual_rise", 0.3), data.get("shake", 0.05))
			_trauma(0.3, p)
		&"rise":
			_ring.visible = false
			_ring_t = -1.0
			if not _shake.is_empty():
				_shake.blend_out = 0.0
			var p: Vector3 = data.point
			var col: Color = data.get("color", Color.GRAY)
			_burst(_dust, "dust", p, col.lightened(0.3), 0.8, 3.0, 5.0)
			var rock := data.get("rock") as RigidBody3D
			if rock != null:
				var e := _make_pebbles("RockPebbles", false)
				(e.process_material as ParticleProcessMaterial).color = col.darkened(0.2)
				_attach(rock, e, 0.5, false)
				_stats.rock_pebbles += 1
		&"launch":
			var rock := data.get("rock") as RigidBody3D
			var p: Vector3 = data.get("point", Vector3.ZERO)
			_burst(_dust, "dust", p, Color(0.85, 0.78, 0.68), 0.5, 1.0, 2.5)
			if rock != null:
				_attach(rock, _make_dust("Trail", false), TRAIL_MAX_S, true)
				_stats.trails += 1
			_trauma(0.15, p)
		&"impact_body":
			var p: Vector3 = data.point
			var imp: float = data.get("impulse", 1000.0)
			_impact(p, clampf(log(maxf(imp, 10.0)) / log(10.0) / 6.0, 0.2, 0.8), 2.4)
		&"impact_ground":
			var p: Vector3 = data.point
			var speed: float = data.get("speed", 10.0)
			_impact(p, clampf(speed / 30.0, 0.15, 0.7), 3.6 if data.get("crater", false) else 2.4)
		&"cancel":
			_ring.visible = false
			_ring_t = -1.0
			_end_shake()


func _impact(p: Vector3, strength: float, crack_size: float) -> void:
	_stats.impacts += 1
	_crack(p, crack_size * 0.6, crack_size, 0.12, 0.9, 0.9)
	_burst(_dust, "dust", p, Color(0.82, 0.74, 0.64), 1.0, 2.0, 4.0)
	_burst(_pebbles, "pebbles", p, Color(0.45, 0.38, 0.32), 1.0, 2.0, 4.5)
	_trauma(strength, p)


# --- Quadro a quadro ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_frame += 1
	_update_decals(delta)
	if _ring_t >= 0.0:
		_ring_t += delta
		_ring_mat.albedo_color.a = RING_COLOR.a * (0.6 + 0.4 * sin(_ring_t * 40.0))
	if _invalid_t >= 0.0:
		_invalid_t += delta
		_invalid_mat.albedo_color.a = INVALID_COLOR.a * clampf(1.0 - _invalid_t / 0.4, 0.0, 1.0)
		if _invalid_t > 0.4:
			_invalid.visible = false
			_invalid_t = -1.0
	_update_shake(delta)
	_update_attached(delta)
	if edit_controller != null and earth != null:
		edit_controller.marker_suppressed = earth.is_busy()
	if _frame % PREVIEW_EVERY == 0:
		_update_preview()


func _update_decals(delta: float) -> void:
	for i in _decals.size():
		var s := _decal_state[i]
		if s.is_empty():
			continue
		s.t += delta
		var d := _decals[i]
		var k := clampf(s.t / maxf(s.grow_s, 0.001), 0.0, 1.0)
		var size: float = lerpf(s.from, s.to, k * (2.0 - k))
		d.size = Vector3(size, 2.0, size)
		var a: float = lerpf(s.a0, s.a1, k)
		if s.t > s.grow_s + DECAL_HOLD_S:
			a *= clampf(1.0 - (s.t - s.grow_s - DECAL_HOLD_S) / DECAL_FADE_S, 0.0, 1.0)
		d.modulate = Color(1, 1, 1, a)
		if s.t > s.grow_s + DECAL_HOLD_S + DECAL_FADE_S:
			d.visible = false
			_decal_state[i] = {}


## Desprendimento: a cópia da malha treme e sobe; no levantamento volta à malha real.
func _update_shake(delta: float) -> void:
	if _shake.is_empty():
		return
	# Checar antes de converter: a rocha (e a malha) pode ter sido liberada pelo reset.
	if not is_instance_valid(_shake.mesh) or not is_instance_valid(_shake.copy):
		_end_shake()
		return
	var mesh := _shake.mesh as MeshInstance3D
	var copy := _shake.copy as MeshInstance3D
	_shake.t += delta
	var offset: Vector3
	if _shake.blend_out < 0.0:
		var k := clampf(_shake.t / maxf(_shake.dur, 0.001), 0.0, 1.0)
		var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1))
		offset = Vector3.UP * _shake.rise * k * k * (3.0 - 2.0 * k) + jitter * _shake.amp * (0.4 + 0.6 * k)
		_shake.last = offset
	else:
		_shake.blend_out += delta
		var b := clampf(_shake.blend_out / SHAKE_BLEND_OUT_S, 0.0, 1.0)
		offset = (_shake.last as Vector3) * (1.0 - b)
		if b >= 1.0:
			_end_shake()
			return
	copy.global_transform = Transform3D(mesh.global_transform.basis, mesh.global_transform.origin + offset)


func _update_attached(delta: float) -> void:
	var keep := []
	for a in _attached:
		# Emissores são filhos da rocha: somem com ela no reset (checar antes de converter).
		if not is_instance_valid(a.emitter):
			continue
		var e := a.emitter as GPUParticles3D
		a.t += delta
		var alive: bool = is_instance_valid(a.rock) and a.t < a.max_t
		if alive and a.trail:
			e.emitting = (a.rock as RigidBody3D).linear_velocity.length() > TRAIL_MIN_SPEED
		elif not alive and e.emitting:
			e.emitting = false
		if a.t > a.max_t + e.lifetime:
			e.queue_free()
			continue
		keep.append(a)
	_attached = keep


## Anel no ponto de arranque com a Terra escolhida e parada: verde se o clique vai funcionar.
func _update_preview() -> void:
	var show := false
	if earth != null and abilities.current_ability() == earth and earth.phase == "" \
			and abilities.player != null and abilities.player.input_enabled:
		var check := earth.validate_target()
		if check.has("point"):
			show = true
			_preview.global_position = (check.point as Vector3) + Vector3.UP * 0.03
			_preview_mat.albedo_color = PREVIEW_OK if check.ok else PREVIEW_BAD
	_preview.visible = show


# --- Peças ----------------------------------------------------------------------------------

func _crack(p: Vector3, from: float, to: float, grow_s: float, a0: float, a1: float) -> void:
	var d := _decals[_next_decal]
	_decal_state[_next_decal] = {"t": 0.0, "from": from, "to": to, "grow_s": grow_s, "a0": a0, "a1": a1}
	_next_decal = (_next_decal + 1) % _decals.size()
	d.texture_albedo = _cracks[_rng.randi() % _cracks.size()]
	d.global_position = p
	d.rotation = Vector3(0.0, _rng.randf() * TAU, 0.0)
	d.size = Vector3(from, 2.0, from)
	d.modulate = Color(1, 1, 1, a0)
	d.visible = true
	_stats.cracks += 1


func _start_shake(rock: Variant, dur: float, rise: float, amp: float) -> void:
	_end_shake()
	var rb := rock as RigidBody3D
	if rb == null:
		return
	var mesh: MeshInstance3D = null
	for ch in rb.get_children():
		if ch is MeshInstance3D:
			mesh = ch
			break
	if mesh == null:
		return
	var copy := MeshInstance3D.new()
	copy.name = "DetachCopy"
	copy.mesh = mesh.mesh
	copy.material_override = mesh.material_override
	add_child(copy)
	copy.global_transform = mesh.global_transform
	mesh.visible = false
	_shake = {"mesh": mesh, "copy": copy, "t": 0.0, "dur": dur, "rise": rise, "amp": amp, "blend_out": -1.0,
		"last": Vector3.ZERO}
	_stats.mesh_shakes += 1


func _end_shake() -> void:
	if _shake.is_empty():
		return
	if is_instance_valid(_shake.mesh):
		(_shake.mesh as MeshInstance3D).visible = true
	if is_instance_valid(_shake.copy):
		(_shake.copy as Node).queue_free()
	_shake = {}


func _burst(pool: Array[GPUParticles3D], key: String, at: Vector3, color: Color, amount: float,
		v_min: float, v_max: float) -> void:
	var e := pool[_next[key]]
	_next[key] = (_next[key] + 1) % pool.size()
	var pm := e.process_material as ParticleProcessMaterial
	pm.color = color
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	e.amount_ratio = clampf(amount, 0.05, 1.0)
	e.global_position = at + Vector3.UP * 0.1
	e.restart()
	e.emitting = true
	_stats[key] += 1


func _attach(rock: RigidBody3D, e: GPUParticles3D, max_t: float, trail: bool) -> void:
	e.one_shot = false
	e.emitting = true
	var box := AABB(rock.global_position, Vector3.ONE)
	for ch in rock.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			box = (ch as MeshInstance3D).mesh.get_aabb()
			break
	var pm := e.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box.size * 0.45
	if trail:
		pm.color = Color(0.8, 0.72, 0.62)
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.8
	rock.add_child(e)
	e.position = box.get_center()
	_attached.append({"emitter": e, "rock": rock, "t": 0.0, "max_t": max_t, "trail": trail})


func _trauma(amount: float, at: Vector3) -> void:
	if camera == null:
		return
	var prox := clampf(1.0 - camera.camera.global_position.distance_to(at) / TRAUMA_RANGE, 0.0, 1.0)
	if prox <= 0.0:
		return
	camera.add_trauma(amount * prox)
	_stats.trauma_events += 1


func _make_dust(n: String, one_shot := true) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 1.9
	pm.emission_ring_inner_radius = 1.1
	pm.emission_ring_height = 0.2
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.gravity = Vector3(0, -1.0, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.color = Color(0.85, 0.78, 0.68)
	var e := GPUParticles3D.new()
	e.name = n
	e.amount = 40
	e.lifetime = 1.2
	e.one_shot = one_shot
	e.explosiveness = 0.85 if one_shot else 0.0
	e.emitting = false
	e.process_material = pm
	e.draw_pass_1 = _quad(0.7, Color(1, 1, 1, 0.5))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 10, 12))
	if one_shot:
		add_child(e)
	return e


## Pedrinhas: malha low-poly com cor por partícula, gravidade e colisão com o heightfield.
func _make_pebbles(n: String, pooled: bool) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 1.9
	pm.emission_ring_inner_radius = 0.9
	pm.emission_ring_height = 0.2
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.25
	pm.collision_friction = 0.7
	pm.color = Color(0.45, 0.38, 0.32)
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.11
	mesh.radial_segments = 5
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.material = mat
	var e := GPUParticles3D.new()
	e.name = n
	e.amount = 24
	e.lifetime = 1.4
	e.one_shot = pooled
	e.explosiveness = 0.8 if pooled else 0.0
	e.emitting = false
	e.process_material = pm
	e.draw_pass_1 = mesh
	e.collision_base_size = 0.08
	e.visibility_aabb = AABB(Vector3(-6, -4, -6), Vector3(12, 10, 12))
	if pooled:
		add_child(e)
	else:
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 1.0
	return e


func _torus(n: String, inner: float, outer: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 48
	t.ring_segments = 4
	t.material = mat
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = t
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1.0, 0.15, 1.0)
	mi.visible = false
	add_child(mi)
	return mi


## Quad de poeira com mancha radial suave (sem textura saía um quadrado duro; capturas do T45).
static func _quad(size: float, tint: Color) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := _unshaded(tint)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	return quad


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


static func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	return mat
