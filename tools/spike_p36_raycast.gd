extends SceneTree
## Spike do P3.6: o raio do Jolt contra o collider do terreno (Voxel Tools, Transvoxel) falha
## quando passa exatamente sobre vértices/arestas da malha? Investiga a intermitência do T8 (P1:
## raio vertical em x, z inteiros na vala não achou o fundo) e o "sem chão na mira" do P3.5.
## Uso: godot --headless --path . --script res://tools/spike_p36_raycast.gd
## Saída: stdout + res://docs/evidence/p36/00_spike_raycast.txt
##
##   R1 chão plano: raios verticais numa grade 20×20 em x, z inteiros, meio-inteiros e +0,17 m;
##      comprimentos 60 m e 22 m; hit_back_faces falso (como o TerrainService) e verdadeiro
##   R2 valas cavadas como no T8 (dig_path, r 1,2): raios verticais a cada 0,5 m ao longo do eixo,
##      em x inteiro e em x + 0,17
##   R3 raios inclinados como a mira (câmera 9 m atrás e 3 m acima) para pontos de x, z inteiros
##      e deslocados, com a componente x da direção exatamente 0 / −0
##   R4 o mesmo raio repetido 10× no mesmo quadro: a falha é determinística?
##   R5 réplica do T8 (fila de brushes) com o fechamento do traço desligado e ligado

const OUT_PATH := "res://docs/evidence/p36/00_spike_raycast.txt"
const LAB := Vector3(-34, 0.6, 60)

var main: Node
var svc: TerrainService
var _lines: PackedStringArray = []
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_out("# Spike P3.6 — raycast em vértices/arestas — %s" % Time.get_datetime_string_from_system())
	_out("# Godot %s | física %s" % [Engine.get_version_info().string, ProjectSettings.get_setting("physics/3d/physics_engine")])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	svc = main.terrain_service
	await _until(func(): return svc.is_ready(), 30.0)
	main.player.input_enabled = false
	main.player.teleport_to(LAB + Vector3(0, 0, 14))
	await _until(func(): return svc.can_edit_area(AABB(LAB - Vector3(14, 4, 14), Vector3(28, 10, 28))), 15.0)
	await _seconds(1.0)
	_space = main.get_world_3d().direct_space_state
	_r1_flat()
	await _r2_trench()
	_r3_slanted()
	_r4_repeat()
	await _r5_t8_replica()
	_finish()


func _ray(from: Vector3, to: Vector3, back_faces := false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.TERRAIN)
	q.collide_with_areas = false
	q.hit_back_faces = back_faces
	return _space.intersect_ray(q)


func _r1_flat() -> void:
	_out("")
	_out("## R1 chão plano (y ≈ 0,02), grade 20×20 a partir de x=%d, z=%d" % [int(LAB.x) - 10, int(LAB.z) - 10])
	for offset in [Vector2(0, 0), Vector2(0.5, 0.5), Vector2(0.17, 0.17), Vector2(0.0, 0.5), Vector2(0.5, 0.0)]:
		for len in [60.0, 22.0]:
			for back in [false, true]:
				var miss := 0
				var examples := []
				for i in 20:
					for j in 20:
						var x: float = LAB.x - 10.0 + i + offset.x
						var z: float = LAB.z - 10.0 + j + offset.y
						var hit := _ray(Vector3(x, len * 0.5, z), Vector3(x, -len * 0.5, z), back)
						if hit.is_empty():
							miss += 1
							if examples.size() < 4:
								examples.append("(%.2f, %.2f)" % [x, z])
				_out("R1 deslocamento %s, raio %2.0f m, hit_back_faces=%s: %3d/400 sem acerto %s" % [offset, len, back, miss, examples])


func _r2_trench() -> void:
	_out("")
	_out("## R2 valas como a do T8 (dig_path de z=+8 a z=−8, raio 1,2) em 5 posições de x")
	var total := {"inteiro": [0, 0], "deslocado": [0, 0]}
	for k in 5:
		var X := LAB.x - 10.0 + k * 5.0
		var z0 := LAB.z + 8.0
		var z1 := LAB.z - 8.0
		var res := svc.dig_path(PackedVector3Array([Vector3(X, 0, z0), Vector3(X, 0, z1)]), PackedFloat32Array([1.2, 1.2]))
		if not res.ok:
			_out("R2 x=%.0f: dig_path recusado (%s)" % [X, res.reason])
			continue
		# Espera o collider da vala: raio deslocado no meio já vê o fundo.
		await _until(func(): var h := _ray(Vector3(X + 0.31, 30, (z0 + z1) * 0.5 + 0.23), Vector3(X + 0.31, -30, (z0 + z1) * 0.5 + 0.23)); return not h.is_empty() and h.position.y < -0.4, 3.0)
		await _seconds(0.3)
		for kind in ["inteiro", "deslocado"]:
			var dx := 0.0 if kind == "inteiro" else 0.17
			var miss := []
			var shallow := []
			var n := int(absf(z1 - z0) / 0.5)
			for i in n + 1:
				var z := lerpf(z0, z1, float(i) / n)
				var hit := _ray(Vector3(X + dx, 30, z), Vector3(X + dx, -30, z))
				if hit.is_empty():
					miss.append(snappedf(z - LAB.z, 0.1))
				elif hit.position.y > -0.4:
					shallow.append(snappedf(z - LAB.z, 0.1))
			total[kind][0] += miss.size()
			total[kind][1] += n + 1
			_out("R2 x=%.2f (%s): %d/%d sem acerto em z-%.0f=%s; %d rasos (> −0,4) em %s" % [X + dx, kind, miss.size(), n + 1, LAB.z, miss, shallow.size(), shallow])
	_out("R2 total: x inteiro %d/%d sem acerto; x + 0,17: %d/%d" % [total.inteiro[0], total.inteiro[1], total.deslocado[0], total.deslocado[1]])


func _r3_slanted() -> void:
	_out("")
	_out("## R3 raios inclinados como a mira (origem 9 m atrás e 2,9 m acima), comprimento 22 m")
	for kind in ["x,z inteiros", "x inteiro, z+0,5", "x+0,17"]:
		var miss := 0
		var n := 0
		for i in 15:
			for j in 6:
				var target := Vector3(LAB.x - 7.0 + i, 0.02, LAB.z - 6.0 + j)
				if kind == "x inteiro, z+0,5":
					target.z += 0.5
				elif kind == "x+0,17":
					target.x += 0.17
				var origin := Vector3(target.x, 2.94, target.z + 8.77)
				var dir := (target - origin).normalized()
				var hit := _ray(origin, origin + dir * 22.0)
				n += 1
				if hit.is_empty():
					miss += 1
		_out("R3 alvo %s: %d/%d sem acerto" % [kind, miss, n])
	# Os mesmos raios pelo TerrainService.raycast_terrain (repete deslocado 1 mm se errar).
	var miss_svc := 0
	for i in 15:
		for j in 6:
			var target := Vector3(LAB.x - 7.0 + i, 0.02, LAB.z - 6.0 + j)
			var origin := Vector3(target.x, 2.94, target.z + 8.77)
			if svc.raycast_terrain(origin, origin + (target - origin).normalized() * 22.0).is_empty():
				miss_svc += 1
	_out("R3 alvo x,z inteiros pelo TerrainService.raycast_terrain: %d/90 sem acerto" % miss_svc)
	# O caso exato do T39 no P3.5: origem (-34, 2.943481, 72.26899), direção com x = −0,0.
	var o := Vector3(-34.0, 2.943481, 72.26899)
	for dx in [0.0, -0.0, 0.000001]:
		var d := Vector3(dx, -0.316285, -0.948664)
		var h22 := _ray(o, o + d * 22.0)
		var h200 := _ray(o, o + d * 200.0)
		_out("R3 caso do T39, dir.x=%s: 22 m → %s; 200 m → %s" % [str(dx) if dx != 0.0 or not signbit(dx) else "-0.0",
			h22.get("position", "nada"), h200.get("position", "nada")])


func _r4_repeat() -> void:
	_out("")
	_out("## R4 repetição: o mesmo raio 10× no mesmo quadro")
	var x := LAB.x - 10.0
	var z := LAB.z - 10.0
	var results := []
	for i in 10:
		results.append(not _ray(Vector3(x, 11, z), Vector3(x, -11, z)).is_empty())
	_out("R4 (%.1f, %.1f) raio 22 m: acertos %s" % [x, z, results])


## Réplica do T8: traço contínuo pela TerrainBrushQueue (120 amostras em 2 s, raio 1,2, de z+10 a
## z−10) e a mesma verificação (raio vertical a cada 0,5 m; falha se sem acerto ou acima de −0,4),
## repetida em 6 posições de x. Distingue "sem acerto" de "raso" e mede onde ficou o fim da vala.
func _r5_t8_replica() -> void:
	var queue: TerrainBrushQueue = main.brush_queue
	for close in [false, true]:
		queue.close_stroke_on_end = close
		await main.request_world_reset()
		await _r5_series(queue, close)
	queue.close_stroke_on_end = true


func _r5_series(queue: TerrainBrushQueue, close: bool) -> void:
	_out("")
	_out("## R5 réplica do T8 (fila de brushes, 120 amostras, raio 1,2), 8 posições de x inteiro, close_stroke_on_end=%s" % close)
	var fails := 0
	for k in 8:
		var X := LAB.x - 16.0 + k * 4.5
		var z0 := LAB.z + 10.0
		var z1 := LAB.z - 10.0
		main.player.teleport_to(Vector3(X - 6, 0.5, LAB.z + 16))
		await _until(func(): return svc.can_edit_area(AABB(Vector3(X - 3, -4, z1 - 3), Vector3(6, 8, z0 - z1 + 6))), 10.0)
		var id := queue.begin_stroke(TerrainBrushRequest.Op.REMOVE, 1.2, &"", "spike:T8")
		for i in 120:
			await physics_frame
			queue.update_stroke(id, Vector3(X, 0, lerpf(z0, z1, float(i) / 119.0)), Vector3.UP)
		queue.end_stroke(id)
		await _until(func(): return queue.get_stats().pending == 0, 5.0)
		var t0 := Time.get_ticks_msec()
		var bad := []
		while true:
			await physics_frame
			bad = []
			for i in 41:
				var z := lerpf(z0, z1, float(i) / 40.0)
				var hit := _ray(Vector3(X, 30, z), Vector3(X, -30, z))
				if hit.is_empty():
					bad.append("%.1f:sem acerto" % (z - LAB.z))
				elif hit.position.y > -0.4:
					bad.append("%.1f:raso y=%.2f" % [z - LAB.z, hit.position.y])
			if bad.is_empty() or Time.get_ticks_msec() - t0 > 5000:
				break
		# Fundo da vala no fim do traço, com raio deslocado (não alinhado a vértice).
		var end_hit := _ray(Vector3(X + 0.23, 30, z1 + 0.11), Vector3(X + 0.23, -30, z1 + 0.11))
		_out("R5 x=%.0f: %s; fundo em z−10 (raio deslocado) y=%s; %d ms" % [X, "OK" if bad.is_empty() else str(bad),
			("%.2f" % end_hit.position.y) if not end_hit.is_empty() else "nada", Time.get_ticks_msec() - t0])
		if not bad.is_empty():
			fails += 1
	_out("R5 total (close_stroke_on_end=%s): %d/8 réplicas com ponto faltando" % [close, fails])


static func signbit(v: float) -> bool:
	return str(v).begins_with("-")


func _until(cond: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await physics_frame
	return false


func _seconds(s: float) -> void:
	await create_timer(s, true, true).timeout


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/p36"))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(0)


func _out(s: String) -> void:
	print(s)
	_lines.append(s)
