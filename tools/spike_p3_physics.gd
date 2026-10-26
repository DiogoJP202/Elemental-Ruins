extends SceneTree
## Spike do P3: confere EMPIRICAMENTE a física que os poderes vão usar, antes de escrevê-los.
## Uso: godot --headless --path . --script res://tools/spike_p3_physics.gd
## Saída: stdout + res://docs/evidence/p3/00_spike_p3.txt. Exit 0 = checagens H* OK.
##
##   H1 rocha de 14,7 t segurada por mola-amortecedor (gravity_scale 0, força com teto):
##      chega ao ponto, não oscila, segue um alvo em movimento, sem saltos de posição
##   H2 arremesso por impulso + contact_monitor: o impacto numa peça CONGELADA é detectado e o
##      impulso é estimado pela velocidade antes/depois
##   H3 consulta em cone (esfera + ângulo + oclusão por raycast no terreno) com 150 corpos: custo

const OUT_PATH := "res://docs/evidence/p3/00_spike_p3.txt"
const ROCK_MASS := 14670.0
const OMEGA := 6.0           # frequência natural da mola (rad/s)
const MAX_ACCEL := 40.0      # teto de aceleração da mola (m/s²)

var _lines: PackedStringArray = []
var _fails := 0
var _viewer: VoxelViewer
var _terrain: VoxelLodTerrain
var _root3d: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_out("# Spike P3 — %s" % Time.get_datetime_string_from_system())
	_out("# Godot %s | física %s | ticks/s %d" % [Engine.get_version_info().string,
		ProjectSettings.get_setting("physics/3d/physics_engine"), Engine.physics_ticks_per_second])
	_root3d = Node3D.new()
	root.add_child(_root3d)
	_viewer = VoxelViewer.new()
	_root3d.add_child(_viewer)
	_terrain = _make_terrain()
	if await _wait_ready() < 0:
		_check("H0 terreno pronto", false, "timeout")
		_finish()
		return
	await _h1_spring_hold()
	await _h2_throw_contact()
	await _h3_cone_query()
	_finish()


# --- H1 ---------------------------------------------------------------------------------

func _h1_spring_hold() -> void:
	_out("")
	_out("## H1 mola-amortecedor numa rocha de %.0f kg" % ROCK_MASS)
	var rock := _make_rock(Vector3(0, 1.2, 0), ROCK_MASS)
	await _seconds(1.0)
	rock.gravity_scale = 0.0
	var target := Vector3(0, 4.0, -3.0)
	var max_step := 0.0
	var max_force_ratio := 0.0
	var prev := rock.global_position
	var reach_ms := -1
	var t0 := Time.get_ticks_msec()
	var overshoot := 0.0
	# Fase 1: subir até o ponto e estabilizar (2 s).
	for i in 120:
		await physics_frame
		var f := _spring_force(rock, target)
		max_force_ratio = maxf(max_force_ratio, f.length() / (rock.mass * MAX_ACCEL))
		rock.apply_central_force(f)
		var p := rock.global_position
		max_step = maxf(max_step, p.distance_to(prev))
		prev = p
		var err := p.distance_to(target)
		if reach_ms < 0 and err < 0.3:
			reach_ms = Time.get_ticks_msec() - t0
		if reach_ms >= 0:
			overshoot = maxf(overshoot, err)
	var settle_err := rock.global_position.distance_to(target)
	# Fase 2: o alvo gira em volta (câmera virando) a 1,5 rad/s, raio 3 m (4,5 m/s). O amortecimento
	# é relativo à velocidade do alvo (alimentação direta); amortecer contra zero dava atraso
	# ≈ 2v/ω = 1,5 m (medido na 1ª rodada: 1,42 m).
	var track_max := 0.0
	var prev_target := target
	for i in 120:
		var a := i / 60.0 * 1.5
		target = Vector3(sin(a) * 3.0, 4.0, -cos(a) * 3.0)
		var target_vel := (target - prev_target) * Engine.physics_ticks_per_second
		prev_target = target
		await physics_frame
		rock.apply_central_force(_spring_force(rock, target, target_vel))
		var p := rock.global_position
		max_step = maxf(max_step, p.distance_to(prev))
		prev = p
		if i > 20:
			track_max = maxf(track_max, p.distance_to(target))
	var v_cap := MAX_ACCEL * (1.0 / 60.0)
	_check("H1 rocha segura por forças: chega, estabiliza, acompanha, sem saltos", reach_ms >= 0 and reach_ms < 1500 \
			and settle_err < 0.1 and overshoot < 0.5 and track_max < 1.0 and max_step < 0.5,
		"chegou (<0,3 m) em %d ms; erro após 2 s %.3f m; sobressinal %.3f m; erro máx. seguindo alvo %.3f m; maior passo por quadro %.3f m; força máx./teto %.2f (Δv máx. por quadro pelo teto %.2f m/s)" % [
			reach_ms, settle_err, overshoot, track_max, max_step, max_force_ratio, v_cap])
	rock.queue_free()
	await physics_frame


## Mola-amortecedor criticamente amortecida (k = mω², c = 2mω) com teto de aceleração.
func _spring_force(rock: RigidBody3D, target: Vector3, target_vel := Vector3.ZERO) -> Vector3:
	var k := rock.mass * OMEGA * OMEGA
	var c := 2.0 * rock.mass * OMEGA
	var f := (target - rock.global_position) * k + (target_vel - rock.linear_velocity) * c
	return f.limit_length(rock.mass * MAX_ACCEL)


# --- H2 ---------------------------------------------------------------------------------

func _h2_throw_contact() -> void:
	_out("")
	_out("## H2 arremesso + contact_monitor contra peça congelada")
	var piece := RigidBody3D.new()
	piece.mass = 3900.0
	piece.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	piece.freeze = true
	piece.collision_layer = 4
	piece.collision_mask = 1 | 4
	_add_box(piece, Vector3(1, 1.5, 1))
	_root3d.add_child(piece)
	piece.global_position = Vector3(0, 0.8, -14)
	# Como no jogo: a rocha fica suspensa pela mola (gravidade desligada) e só então é lançada.
	var rock := _make_rock(Vector3(0, 2.6, 0), ROCK_MASS)
	rock.gravity_scale = 0.0
	rock.contact_monitor = true
	rock.max_contacts_reported = 4
	rock.continuous_cd = true
	var hold := Vector3(0, 2.6, 0)
	for i in 30:
		await physics_frame
		rock.apply_central_force(_spring_force(rock, hold))
	var hits := []
	var state := {"prev_vel": Vector3.ZERO}
	rock.body_entered.connect(func(body: Node):
		hits.append({"corpo": body.name, "v_antes": state.prev_vel, "v_depois": rock.linear_velocity,
			"impulso_est_Ns": rock.mass * (state.prev_vel - rock.linear_velocity).length()}))
	# Lançamento: gravidade de volta e velocidade com a componente vertical que compensa a queda
	# até o alvo (tempo de voo ≈ distância / velocidade).
	var aim := piece.global_position - rock.global_position
	var speed := 22.0
	var flight := aim.length() / speed
	var launch := aim.normalized() * speed + Vector3.UP * (9.8 * flight * 0.5)
	rock.gravity_scale = 1.0
	rock.apply_central_impulse((launch - rock.linear_velocity) * rock.mass)
	var t0 := Time.get_ticks_msec()
	var first_hit_ms := -1
	var track := []
	var frame := 0
	while Time.get_ticks_msec() - t0 < 2000:
		state.prev_vel = rock.linear_velocity
		await physics_frame
		frame += 1
		if frame % 10 == 0:
			track.append("%s|%s" % [rock.global_position.snappedf(0.1), rock.get_colliding_bodies().map(func(b): return b.name)])
		if first_hit_ms < 0 and not hits.is_empty():
			first_hit_ms = Time.get_ticks_msec() - t0
	_out("H2 trajetória (a cada 10 quadros: posição | corpos em contato): %s" % [track])
	var piece_hit := hits.filter(func(h): return h.corpo == piece.name)
	var ok: bool = not piece_hit.is_empty() and piece_hit[0].impulso_est_Ns > 1000.0
	_check("H2 impacto numa peça congelada é detectado com impulso estimado", ok,
		"contatos=%s; 1º contato em %d ms; posição da peça %s (congelada continua no lugar)" % [
			str(hits.slice(0, 3)), first_hit_ms, piece.global_position])
	rock.queue_free()
	piece.queue_free()
	await physics_frame


# --- H3 ---------------------------------------------------------------------------------

func _h3_cone_query() -> void:
	_out("")
	_out("## H3 consulta em cone com 150 corpos")
	var bodies: Array[RigidBody3D] = []
	for i in 150:
		var b := RigidBody3D.new()
		b.mass = 20.0
		b.collision_layer = 4
		b.collision_mask = 1 | 4
		_add_box(b, Vector3.ONE)
		_root3d.add_child(b)
		b.global_position = Vector3(-15 + (i % 15) * 2.0, 0.6, -2.0 - floorf(i / 15.0) * 2.0)
		bodies.append(b)
	await _seconds(1.5)
	var origin := Vector3(0, 1.0, 2.0)
	var forward := Vector3(0, 0, -1)
	var t0 := Time.get_ticks_usec()
	var sphere := SphereShape3D.new()
	sphere.radius = 15.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, origin)
	q.collision_mask = 4
	var space := _viewer.get_world_3d().direct_space_state
	var found := space.intersect_shape(q, 256)
	var in_cone := 0
	var visible := 0
	for h in found:
		var b := h.collider as RigidBody3D
		var to := b.global_position - origin
		if to.length() < 0.01 or forward.dot(to.normalized()) < cos(deg_to_rad(30.0)):
			continue
		in_cone += 1
		var ray := PhysicsRayQueryParameters3D.create(origin, b.global_position, 1)
		if space.intersect_ray(ray).is_empty():
			visible += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check("H3 consulta em cone custa pouco", ms < 5.0 and in_cone > 0,
		"%d corpos na esfera, %d no cone de 30°, %d sem terreno no caminho; %.2f ms" % [found.size(), in_cone, visible, ms])
	for b in bodies:
		b.queue_free()


# --- Utilidades -----------------------------------------------------------------------------

func _make_rock(at: Vector3, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = mass
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	var sm := SphereMesh.new()
	sm.radius = 1.3
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	for v: Vector3 in sm.get_mesh_arrays()[Mesh.ARRAY_VERTEX]:
		pts.append(v)
	shape.points = pts
	cs.shape = shape
	rb.add_child(cs)
	_root3d.add_child(rb)
	rb.global_position = at
	return rb


func _add_box(b: RigidBody3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)


func _make_terrain() -> VoxelLodTerrain:
	var t := VoxelLodTerrain.new()
	var gen := VoxelGeneratorGraph.new()
	var fn: VoxelGraphFunction = gen.get_main_function()
	var in_y := fn.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 0))
	var plane := fn.create_node(VoxelGraphFunction.NODE_SDF_PLANE, Vector2(160, 0))
	fn.add_connection(in_y, 0, plane, fn.get_node_input_index(plane, "y"))
	fn.set_node_default_input_by_name(plane, "height", 0.0)
	var out := fn.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(320, 0))
	fn.add_connection(plane, 0, out, fn.get_node_input_index(out, "sdf"))
	gen.compile()
	t.generator = gen
	t.mesher = VoxelMesherTransvoxel.new()
	t.voxel_bounds = AABB(Vector3(-64, -32, -64), Vector3(128, 64, 128))
	t.lod_count = 2
	t.lod_distance = 48.0
	t.view_distance = 96
	t.mesh_block_size = 16
	t.generate_collisions = true
	t.collision_layer = 1
	t.collision_mask = 0
	_root3d.add_child(t)
	return t


func _wait_ready() -> int:
	var t0 := Time.get_ticks_msec()
	var tool := _terrain.get_voxel_tool()
	var area := AABB(Vector3(-24, -8, -24), Vector3(48, 16, 48))
	while Time.get_ticks_msec() - t0 < 20000:
		await physics_frame
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, 10, 0), Vector3(0, -10, 0), 1)
		if _terrain.is_area_meshed(area, 0) and tool.is_area_editable(area) \
				and not _viewer.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return Time.get_ticks_msec() - t0
	return -1


func _seconds(s: float) -> void:
	await create_timer(s, true, true).timeout


func _check(id: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	_out("%s %s | %s" % ["OK  " if ok else "FAIL", id, detail])


func _finish() -> void:
	_out("")
	_out("RESULTADO: %s (%d falha(s))" % ["OK" if _fails == 0 else "FALHOU", _fails])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/p3"))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(0 if _fails == 0 else 1)


func _out(s: String) -> void:
	print(s)
	_lines.append(s)
