extends SceneTree
## Spike do P2: confere EMPIRICAMENTE, no binário em uso, o que o P2 vai usar.
## Uso: godot --headless --path . --script res://tools/spike_p2_api.gd
## Saída: stdout + res://docs/evidence/p2/00_spike_p2.txt. Exit 0 = checagens F* OK
## (os I* são informativos e decidem o desenho, não reprovam).
##
##   F1 matéria flutuante (ADD no ar) → separate_floating_chunks: corpos criados, removidos do terreno
##      I1 classe, forma, camada/máscara, massa, malha, cinemático → rígido (estado logo após e depois)
##   F2 o corpo cai e repousa sobre o terreno
##   I2 custo de separate_floating_chunks com caixas de 8, 16 e 30 voxels
##   F3 cenário da extração: núcleo recriado dentro de cavidade no chão vira 1 corpo; impulso o desloca
##   I3 caixa dormindo sobre o chão: escavar embaixo a acorda sozinha? (e acordar manualmente funciona?)

const OUT_PATH := "res://docs/evidence/p2/00_spike_p2.txt"
const READY_TIMEOUT_MS := 20000

var _lines: PackedStringArray = []
var _fails := 0
var _viewer: VoxelViewer
var _terrain: VoxelLodTerrain
var _tool: VoxelToolLodTerrain
var _bodies_root: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_out("# Spike P2 — %s" % Time.get_datetime_string_from_system())
	_out("# Godot %s | física %s" % [Engine.get_version_info().string, ProjectSettings.get_setting("physics/3d/physics_engine")])
	_viewer = VoxelViewer.new()
	_viewer.view_distance = 128
	root.add_child(_viewer)
	_bodies_root = Node3D.new()
	_bodies_root.name = "Bodies"
	root.add_child(_bodies_root)
	_terrain = _make_terrain()
	var ready_ms := await _wait_ready()
	_out("terreno pronto em %d ms" % ready_ms)
	if ready_ms < 0:
		_check("F0 terreno pronto", false, "timeout")
		_finish()
		return
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_SDF

	await _f1_f2_floating()
	await _i2_cost()
	await _f3_extraction()
	await _i3_sleeping()
	_finish()


# --- F1/F2/I1 --------------------------------------------------------------------

func _f1_f2_floating() -> void:
	_out("")
	_out("## F1/F2 matéria flutuante → separate_floating_chunks")
	var c := Vector3(0, 5, 0)
	_tool.mode = VoxelTool.MODE_ADD
	_tool.do_sphere(c, 1.5)
	await _frames(5)
	var sdf_before := _sdf(c)
	var t0 := Time.get_ticks_usec()
	var bodies: Array = _tool.separate_floating_chunks(AABB(c - Vector3(4, 4, 4), Vector3(8, 8, 8)), _bodies_root)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var sdf_after := _sdf(c)
	_check("F1 1 corpo criado e a matéria saiu do terreno", bodies.size() == 1 and sdf_before < 0.0 and sdf_after > 0.0,
		"corpos=%d sdf centro %.3f → %.3f; chamada %.2f ms" % [bodies.size(), sdf_before, sdf_after, ms])
	if bodies.is_empty():
		return
	var b := bodies[0] as RigidBody3D
	_out("I1 logo após (como o Voxel Tools cria): %s" % _describe(b))
	var bottom0 := _mesh_bottom(b)
	# O que o jogo fará: tirar o corpo da camada do terreno (senão raycasts do terreno batem nele).
	b.collision_layer = 4
	b.collision_mask = 1 | 4
	await _seconds(0.5)
	_out("I1 após 0,5 s: %s" % _describe(b))
	await _seconds(2.5)
	_out("I1 após 3 s: %s" % _describe(b))
	var bottom1 := _mesh_bottom(b)
	var hit := _ray_down(Vector3(c.x, 20, c.z))
	var ground_y: float = hit.position.y if not hit.is_empty() else NAN
	_check("F2 o corpo cai e repousa sobre o terreno (fundo da malha no chão)",
		absf(bottom1 - ground_y) < 0.3 and b.linear_velocity.length() < 0.1,
		"fundo da malha y %.2f → %.2f; chão (raycast só terreno) y=%.2f; vel %.2f" % [bottom0, bottom1, ground_y, b.linear_velocity.length()])


# --- I2: custo por tamanho de caixa ------------------------------------------------

func _i2_cost() -> void:
	_out("")
	_out("## I2 custo de separate_floating_chunks por tamanho de caixa")
	var x := 20.0
	for size: int in [8, 16, 30]:
		var c := Vector3(x, 6, 0)
		_tool.mode = VoxelTool.MODE_ADD
		_tool.do_sphere(c, 1.2)
		await _frames(3)
		var half := Vector3.ONE * size * 0.5
		var t0 := Time.get_ticks_usec()
		var bodies: Array = _tool.separate_floating_chunks(AABB(c - half, half * 2.0), _bodies_root)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		# Mesma caixa sem nada flutuante: custo só da detecção.
		var t1 := Time.get_ticks_usec()
		var none: Array = _tool.separate_floating_chunks(AABB(c - half, half * 2.0), _bodies_root)
		var ms_empty := (Time.get_ticks_usec() - t1) / 1000.0
		_out("I2 caixa %d³: com 1 pedaço %.2f ms (%d corpo[s]); sem pedaço %.2f ms (%d)" % [size, ms, bodies.size(), ms_empty, none.size()])
		x += 12.0
		await _frames(2)


# --- F3: extração (cavidade + núcleo recriado) -----------------------------------------

func _f3_extraction() -> void:
	_out("")
	_out("## F3 extração: cavidade em volta de um núcleo no chão")
	var c := Vector3(-10, -1.7, 10)
	_tool.mode = VoxelTool.MODE_REMOVE
	_tool.do_sphere(c, 2.4)
	_tool.mode = VoxelTool.MODE_ADD
	_tool.do_sphere(c, 1.5)
	await _frames(3)
	var t0 := Time.get_ticks_usec()
	var bodies: Array = _tool.separate_floating_chunks(AABB(c - Vector3(3.5, 3.5, 3.5), Vector3(7, 7, 7)), _bodies_root)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var sdf_core := _sdf(c)
	_out("F3 corpos=%d em %.2f ms; sdf no centro do núcleo depois: %.3f" % [bodies.size(), ms, sdf_core])
	if bodies.size() != 1:
		_check("F3 núcleo vira 1 corpo e o impulso o desloca", false, "corpos=%d" % bodies.size())
		return
	var rb := bodies[0] as RigidBody3D
	_out("F3 logo após: %s" % _describe(rb))
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	await _seconds(1.0)
	var p0 := rb.global_position
	_out("F3 após 1 s (antes do impulso): %s" % _describe(rb))
	var impulse := Vector3(0, 1, 0.4).normalized() * rb.mass * 6.0
	if rb.freeze:
		rb.freeze = false
	rb.apply_central_impulse(impulse)
	var max_y := p0.y
	for i in 30:
		await physics_frame
		max_y = maxf(max_y, rb.global_position.y)
	await _seconds(2.5)
	var p1 := rb.global_position
	_check("F3 núcleo vira 1 corpo e o impulso o desloca", sdf_core > 0.0 and max_y > p0.y + 0.5 and p1.distance_to(p0) > 0.5,
		"pos antes %s; altura máx %.2f; pos 3,5 s depois %s; massa %.2f; impulso %s" % [p0, max_y, p1, rb.mass, impulse])


# --- I3: corpo dormindo e escavação embaixo -------------------------------------------

func _i3_sleeping() -> void:
	_out("")
	_out("## I3 caixa dormindo sobre o chão e escavação embaixo")
	for manual_wake in [false, true]:
		var p := Vector3(-20 if not manual_wake else -28, 0.6, -10)
		var crate := RigidBody3D.new()
		crate.mass = 20.0
		crate.collision_layer = 4
		crate.collision_mask = 1 | 4
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE
		cs.shape = box
		crate.add_child(cs)
		_bodies_root.add_child(crate)
		crate.global_position = p
		var slept := false
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 8000:
			await physics_frame
			if crate.sleeping:
				slept = true
				break
		var sleep_ms := Time.get_ticks_msec() - t0
		var y0 := crate.global_position.y
		_tool.mode = VoxelTool.MODE_REMOVE
		_tool.do_sphere(Vector3(p.x, 0, p.z), 2.5)
		var t1 := Time.get_ticks_msec()
		var col_ms := -1
		while Time.get_ticks_msec() - t1 < 3000:
			await physics_frame
			var hit := _ray_down(Vector3(p.x, 10, p.z))
			if hit.is_empty() or hit.position.y < -1.5:
				col_ms = Time.get_ticks_msec() - t1
				break
		if manual_wake:
			crate.sleeping = false
		await _seconds(2.0)
		var y1 := crate.global_position.y
		_out("I3 %s: dormiu=%s em %d ms (y=%.2f); collider do buraco em %d ms; y 2 s depois=%.2f; sleeping=%s → %s" % [
			"com acordar manual" if manual_wake else "sem intervenção", slept, sleep_ms, y0, col_ms, y1, crate.sleeping,
			"CAIU" if y1 < y0 - 1.0 else "FICOU FLUTUANDO"])


# --- Construção e utilidades -------------------------------------------------------------

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
	t.collision_update_delay = 0
	root.add_child(t)
	return t


func _wait_ready() -> int:
	var t0 := Time.get_ticks_msec()
	var tool := _terrain.get_voxel_tool()
	var area := AABB(Vector3(-32, -8, -24), Vector3(64, 16, 48))
	while Time.get_ticks_msec() - t0 < READY_TIMEOUT_MS:
		await physics_frame
		if _terrain.is_area_meshed(area, 0) and tool.is_area_editable(area) and not _ray_down(Vector3(0, 10, 0)).is_empty():
			return Time.get_ticks_msec() - t0
	return -1


func _describe(n: Node) -> String:
	var parts := PackedStringArray(["%s" % n.get_class()])
	if n is RigidBody3D:
		var rb := n as RigidBody3D
		parts.append("massa=%.3f layer=%d mask=%d freeze=%s freeze_mode=%d sleeping=%s pos=%s vel=%.2f" % [
			rb.mass, rb.collision_layer, rb.collision_mask, rb.freeze, rb.freeze_mode, rb.sleeping,
			rb.global_position, rb.linear_velocity.length()])
	elif n is PhysicsBody3D:
		parts.append("layer=%d mask=%d" % [(n as PhysicsBody3D).collision_layer, (n as PhysicsBody3D).collision_mask])
	if n.get_parent() != null:
		parts.append("pai=%s" % n.get_parent().name)
	for ch in n.get_children():
		if ch is CollisionShape3D:
			var sh: Shape3D = (ch as CollisionShape3D).shape
			var extra := ""
			if sh is ConvexPolygonShape3D:
				extra = " pontos=%d" % (sh as ConvexPolygonShape3D).points.size()
			parts.append("filho CollisionShape3D(%s%s)" % [sh.get_class() if sh else "null", extra])
		elif ch is MeshInstance3D:
			var m: Mesh = (ch as MeshInstance3D).mesh
			var mat: Material = (ch as MeshInstance3D).material_override
			parts.append("filho MeshInstance3D(aabb=%s superfícies=%d material=%s)" % [
				m.get_aabb() if m else "null", m.get_surface_count() if m else 0,
				mat.get_class() if mat else ("surface:" + (m.surface_get_material(0).get_class() if m and m.get_surface_count() > 0 and m.surface_get_material(0) else "nenhum"))])
		else:
			parts.append("filho %s" % ch.get_class())
	return " | ".join(parts)


## Menor y da malha do corpo em coordenadas do mundo.
func _mesh_bottom(rb: RigidBody3D) -> float:
	for ch in rb.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			return (mi.global_transform * mi.mesh.get_aabb()).position.y
	return NAN


func _ray_down(from: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0, 1)
	return _viewer.get_world_3d().direct_space_state.intersect_ray(q)


func _sdf(p: Vector3) -> float:
	_tool.channel = VoxelBuffer.CHANNEL_SDF
	return _tool.get_voxel_f(Vector3i(p.round()))


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(s: float) -> void:
	await create_timer(s, true, true).timeout


func _check(id: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	_out("%s %s | %s" % ["OK  " if ok else "FAIL", id, detail])


func _finish() -> void:
	_out("")
	_out("RESULTADO: %s (%d falha(s))" % ["OK" if _fails == 0 else "FALHOU", _fails])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/p2"))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(0 if _fails == 0 else 1)


func _out(s: String) -> void:
	print(s)
	_lines.append(s)
