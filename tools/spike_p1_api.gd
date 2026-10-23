extends SceneTree
## Spike do P1: confere EMPIRICAMENTE, no binário em uso, o comportamento das APIs que o P1
## vai usar (o dump do probe_voxel_api.gd só prova que os nomes existem).
## Uso: godot --headless --path . --script res://tools/spike_p1_api.gd
## Saída: stdout + res://docs/evidence/p1/00_spike_api.txt. Exit 0 = todas as checagens S* OK.
##
## Monta terrenos próprios (plano y=0, material por Select em x), sem a cena do jogo:
##   S1 grafo com OutputSingleTexture compila; VoxelFormat com índices de 8 bits
##   S2 o gerador escreve o canal INDICES (lido com get_voxel)
##   S3 MODE_SET + CHANNEL_INDICES + value + do_sphere altera só a esfera e não o SDF
##   S4 do_path em MODE_ADD cria matéria (rampa)
##   S5 smooth_sphere altera o SDF de uma saliência
##   S6 VoxelStreamSQLite: editar → save_modified_blocks → tracker completo → liberar →
##      fechar → copiar → reabrir a cópia → SDF e índices idênticos
##   S7 arquivo novo/vazio devolve o estado do gerador (sem edições)
##   I* informativos (não reprovam): autosave ao liberar sem salvar; apagar arquivo aberto/fechado

const OUT_PATH := "res://docs/evidence/p1/00_spike_api.txt"
const READY_TIMEOUT_MS := 20000
const SAVE_TIMEOUT_MS := 15000

const IDX_WEST := 1   # x < 0
const IDX_EAST := 2   # x >= 0
const IDX_PAINT := 3

var _lines: PackedStringArray = []
var _fails := 0
var _dir := ""
var _viewer: VoxelViewer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_out("# Spike P1 — %s" % Time.get_datetime_string_from_system())
	_out("# Godot %s" % Engine.get_version_info().string)
	_dir = ProjectSettings.globalize_path("user://spike_p1/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_dir)
	_out("# pasta de teste: %s" % _dir)

	_viewer = VoxelViewer.new()
	_viewer.view_distance = 128
	root.add_child(_viewer)

	await _s1_to_s5()
	await _s6_s7_sqlite()
	await _i1_autosave_on_free()

	_out("")
	_out("RESULTADO: %s (%d falha(s))" % ["OK" if _fails == 0 else "FALHOU", _fails])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/p1"))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(0 if _fails == 0 else 1)


# --- S1–S5: formato, gerador, pintura, add_path, smooth -----------------------

func _s1_to_s5() -> void:
	_out("")
	_out("## S1–S5 (sem stream)")
	var t := _make_terrain(null)
	var ready_ms := await _wait_ready(t)
	_check("S1 terreno com OutputSingleTexture e índices 8 bits fica pronto", ready_ms >= 0,
		"pronto em %d ms; format.indices_depth=%d; mesher.texturing_mode=%d; gen.texture_mode=%d" % [
			ready_ms, t.format.indices_depth, (t.mesher as VoxelMesherTransvoxel).texturing_mode,
			(t.generator as VoxelGeneratorGraph).texture_mode])
	if ready_ms < 0:
		t.queue_free()
		return
	var tool := t.get_voxel_tool()

	var w := _idx(tool, Vector3(-6, -1, 0))
	var e := _idx(tool, Vector3(6, -1, 0))
	var w_air := _idx(tool, Vector3(-6, 3, 0))
	_check("S2 gerador escreve INDICES (Select: t<limiar → a)", w == IDX_WEST and e == IDX_EAST,
		"x=-6 → %d (esperado %d); x=+6 → %d (esperado %d); ar x=-6,y=3 → %d" % [w, IDX_WEST, e, IDX_EAST, w_air])

	# Antes da 1ª edição o bloco não existe nos dados e get_voxel_f avalia o gerador (float exato);
	# a edição materializa o bloco com SDF quantizado em 16 bits. O ponto de controle fica no
	# MESMO bloco de dados, fora da esfera: se ele variar igual ao centro, a variação é da
	# quantização ao materializar, não da pintura.
	var c := Vector3(-6, -1, 6)
	var ctrl := c + Vector3(3, 0, 0)
	var sdf_before := _sdf(tool, c)
	var ctrl_before := _sdf(tool, ctrl)
	var out_before := _idx(tool, c + Vector3(4, 0, 0))
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	tool.mode = VoxelTool.MODE_SET
	tool.value = IDX_PAINT
	tool.do_sphere(c, 2.0)
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var in_after := _idx(tool, c)
	var edge_after := _idx(tool, c + Vector3(1, 1, 0))
	var out_after := _idx(tool, c + Vector3(4, 0, 0))
	var sdf_after := _sdf(tool, c)
	var ctrl_after := _sdf(tool, ctrl)
	var d_center := sdf_after - sdf_before
	var d_ctrl := ctrl_after - ctrl_before
	# Segunda pintura no bloco já materializado: aqui o SDF tem de ficar exatamente igual.
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	tool.value = IDX_WEST
	tool.do_sphere(c, 2.0)
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var sdf_after2 := _sdf(tool, c)
	var idx_after2 := _idx(tool, c)
	_check("S3 MODE_SET em INDICES pinta só a esfera e não mexe no SDF",
		in_after == IDX_PAINT and edge_after == IDX_PAINT and out_after == out_before and idx_after2 == IDX_WEST
			and absf(d_center - d_ctrl) < 1e-4 and absf(d_center) < 0.02 and sdf_after2 == sdf_after,
		"centro %d, borda %d, fora %d→%d; sdf centro %.4f→%.4f (Δ %.4f), controle fora da esfera Δ %.4f; 2ª pintura: índice %d, sdf %.4f→%.4f" % [
			in_after, edge_after, out_before, out_after, sdf_before, sdf_after, d_center, d_ctrl, idx_after2, sdf_after, sdf_after2])

	var p0 := Vector3(8, 0.0, -8)
	var p1 := Vector3(8, 3.0, -18)
	var mid := (p0 + p1) * 0.5
	var mid_before := _sdf(tool, mid + Vector3.UP * 0.5)
	tool.mode = VoxelTool.MODE_ADD
	tool.do_path(PackedVector3Array([p0, p1]), PackedFloat32Array([1.5, 1.5]))
	var mid_after := _sdf(tool, mid + Vector3.UP * 0.5)
	_check("S4 do_path em MODE_ADD cria matéria", mid_before > 0.0 and mid_after < 0.0,
		"sdf no meio da rampa (+0,5 m): %.3f → %.3f" % [mid_before, mid_after])

	var b := Vector3(-10, 1.0, -10)
	tool.mode = VoxelTool.MODE_ADD
	tool.do_sphere(b, 2.0)
	var probes := [b + Vector3(0, 2, 0), b + Vector3(0, 1, 0), b + Vector3(2, -1, 0), b + Vector3(3, -1, 0), b + Vector3(0, -1, 3)]
	var before := []
	for p: Vector3 in probes:
		before.append(_sdf(tool, p))
	var t0 := Time.get_ticks_usec()
	tool.smooth_sphere(b, 3.5, 2)
	var smooth_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var after := []
	var max_delta := 0.0
	for i in probes.size():
		var v := _sdf(tool, probes[i])
		after.append(v)
		max_delta = maxf(max_delta, absf(v - before[i]))
	_check("S5 smooth_sphere altera o SDF da saliência", max_delta > 0.05,
		"sdf antes %s depois %s; maior variação %.3f; chamada %.2f ms" % [_fmt_arr(before), _fmt_arr(after), max_delta, smooth_ms])

	root.remove_child(t)
	t.free()
	await physics_frame


# --- S6–S7: VoxelStreamSQLite --------------------------------------------------

func _s6_s7_sqlite() -> void:
	_out("")
	_out("## S6–S7 VoxelStreamSQLite")
	var path_a := _dir.path_join("session_a.sqlite")
	var stream_a := _make_stream(path_a)
	var t := _make_terrain(stream_a)
	var ready_ms := await _wait_ready(t)
	if ready_ms < 0:
		_check("S6 terreno com stream fica pronto", false, "timeout")
		return
	_out("terreno com stream pronto em %d ms" % ready_ms)
	var tool := t.get_voxel_tool()
	var pts := _sample_points()
	var gen_state := _snapshot(tool, pts)

	tool.mode = VoxelTool.MODE_REMOVE
	tool.do_sphere(Vector3(-6, 0, -6), 3.05)
	tool.mode = VoxelTool.MODE_ADD
	tool.do_sphere(Vector3(6, 1, 6), 2.0)
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	tool.mode = VoxelTool.MODE_SET
	tool.value = IDX_PAINT
	tool.do_sphere(Vector3(6, 1, 6), 2.0)
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var edited := _snapshot(tool, pts)
	var changed := _diff(gen_state, edited).size()
	_out("edições aplicadas: %d de %d amostras mudaram" % [changed, pts.size()])

	var t0 := Time.get_ticks_msec()
	var tracker: VoxelSaveCompletionTracker = t.save_modified_blocks()
	var complete := false
	while Time.get_ticks_msec() - t0 < SAVE_TIMEOUT_MS:
		await physics_frame
		if tracker.is_complete():
			complete = true
			break
	var save_ms := Time.get_ticks_msec() - t0
	_out("save_modified_blocks: completo=%s abortado=%s total=%d restantes=%d em %d ms" % [
		complete, tracker.is_aborted(), tracker.get_total_tasks(), tracker.get_remaining_tasks(), save_ms])
	_out("arquivos após salvar (aberto): %s" % _list_dir())

	root.remove_child(t)
	t.free()
	await physics_frame
	stream_a.database_path = ""
	stream_a = null
	await physics_frame
	_out("arquivos após fechar: %s" % _list_dir())

	var path_b := _dir.path_join("slot_copy.sqlite")
	var copy_err := DirAccess.copy_absolute(path_a, path_b)
	_out("cópia sessão → slot: %s (%d bytes)" % [error_string(copy_err), _file_size(path_b)])

	var stream_b := _make_stream(path_b)
	var tb := _make_terrain(stream_b)
	var ready_b := await _wait_ready(tb)
	var loaded := _snapshot(tb.get_voxel_tool(), pts) if ready_b >= 0 else {}
	var diffs := _diff(edited, loaded)
	_check("S6 SQLite: salvar, fechar, copiar e reabrir devolve SDF e índices idênticos",
		complete and not tracker.is_aborted() and copy_err == OK and ready_b >= 0 and changed > 0 and diffs.is_empty(),
		"pronto em %d ms; %d amostras; diferenças: %s" % [ready_b, pts.size(), diffs.slice(0, 6)])

	var del_open := DirAccess.remove_absolute(path_b)
	_out("I2 apagar o arquivo com o stream aberto: %s" % error_string(del_open))

	root.remove_child(tb)
	tb.free()
	await physics_frame
	stream_b.database_path = ""
	stream_b = null
	await physics_frame
	var del_closed := DirAccess.remove_absolute(path_a)
	_out("I3 apagar o arquivo depois de fechar: %s" % error_string(del_closed))

	var path_c := _dir.path_join("session_c_vazio.sqlite")
	var stream_c := _make_stream(path_c)
	var tc := _make_terrain(stream_c)
	var ready_c := await _wait_ready(tc)
	var fresh := _snapshot(tc.get_voxel_tool(), pts) if ready_c >= 0 else {}
	var fresh_diffs := _diff(gen_state, fresh)
	_check("S7 arquivo novo devolve o estado do gerador", ready_c >= 0 and fresh_diffs.is_empty(),
		"pronto em %d ms; diferenças: %s" % [ready_c, fresh_diffs.slice(0, 6)])
	root.remove_child(tc)
	tc.free()
	await physics_frame
	stream_c.database_path = ""


## Informativo: liberar o nó SEM save_modified_blocks grava as edições no stream?
## Importa para o reset (o arquivo da sessão descartada não pode ser reaproveitado).
func _i1_autosave_on_free() -> void:
	_out("")
	_out("## I1 autosave ao liberar o terreno sem salvar")
	var path_d := _dir.path_join("session_d.sqlite")
	var stream_d := _make_stream(path_d)
	var t := _make_terrain(stream_d)
	if await _wait_ready(t) < 0:
		_out("I1 inconclusivo: terreno não ficou pronto")
		return
	var tool := t.get_voxel_tool()
	var p := Vector3(-6, -1, -6)
	var before := _sdf(tool, p)
	tool.mode = VoxelTool.MODE_REMOVE
	tool.do_sphere(p, 3.05)
	var after := _sdf(tool, p)
	root.remove_child(t)
	t.free()
	for i in 60:
		await physics_frame
	stream_d.database_path = ""
	stream_d = null
	await physics_frame
	_out("arquivo após liberar sem salvar: %d bytes" % _file_size(path_d))
	var stream_e := _make_stream(path_d)
	var te := _make_terrain(stream_e)
	if await _wait_ready(te) < 0:
		_out("I1 inconclusivo: reabertura não ficou pronta")
		return
	var reopened := _sdf(te.get_voxel_tool(), p)
	_out("I1 sdf em %s: gerador %.3f, editado %.3f, reaberto %.3f → %s" % [p, before, after, reopened,
		"edição FOI salva ao liberar" if absf(reopened - after) < 0.01 else "edição NÃO foi salva ao liberar"])
	root.remove_child(te)
	te.free()
	await physics_frame
	stream_e.database_path = ""


# --- Construção ----------------------------------------------------------------

func _make_terrain(stream: VoxelStream) -> VoxelLodTerrain:
	var t := VoxelLodTerrain.new()
	var fmt := VoxelFormat.new()
	fmt.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)
	t.format = fmt
	var mesher := VoxelMesherTransvoxel.new()
	mesher.texturing_mode = VoxelMesherTransvoxel.TEXTURES_SINGLE_S4
	t.mesher = mesher
	t.generator = _make_generator()
	if stream != null:
		t.stream = stream
	t.voxel_bounds = AABB(Vector3(-64, -32, -64), Vector3(128, 64, 128))
	t.lod_count = 2
	t.lod_distance = 48.0
	t.view_distance = 96
	t.mesh_block_size = 16
	t.generate_collisions = true
	root.add_child(t)
	return t


func _make_generator() -> VoxelGeneratorGraph:
	var gen := VoxelGeneratorGraph.new()
	gen.texture_mode = VoxelGeneratorGraph.TEXTURE_MODE_SINGLE
	var fn: VoxelGraphFunction = gen.get_main_function()
	var in_x := fn.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var in_y := fn.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 80))
	var plane := fn.create_node(VoxelGraphFunction.NODE_SDF_PLANE, Vector2(160, 80))
	fn.add_connection(in_y, 0, plane, fn.get_node_input_index(plane, "y"))
	fn.set_node_default_input_by_name(plane, "height", 0.0)
	var out_sdf := fn.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(320, 80))
	fn.add_connection(plane, 0, out_sdf, fn.get_node_input_index(out_sdf, "sdf"))

	var sel := fn.create_node(VoxelGraphFunction.NODE_SELECT, Vector2(160, 0))
	fn.set_node_default_input_by_name(sel, "a", float(IDX_WEST))
	fn.set_node_default_input_by_name(sel, "b", float(IDX_EAST))
	fn.add_connection(in_x, 0, sel, fn.get_node_input_index(sel, "t"))
	fn.set_node_param_by_name(sel, "threshold", 0.0)
	var out_tex := fn.create_node(VoxelGraphFunction.NODE_OUTPUT_SINGLE_TEXTURE, Vector2(320, 0))
	fn.add_connection(sel, 0, out_tex, fn.get_node_input_index(out_tex, "index"))

	var result: Dictionary = gen.compile()
	_out("compile do grafo: %s" % result)
	return gen


func _make_stream(path: String) -> VoxelStreamSQLite:
	var s := VoxelStreamSQLite.new()
	s.database_path = path
	return s


func _wait_ready(t: VoxelLodTerrain) -> int:
	var t0 := Time.get_ticks_msec()
	var tool := t.get_voxel_tool()
	var area := AABB(Vector3(-16, -8, -24), Vector3(32, 16, 48))
	while Time.get_ticks_msec() - t0 < READY_TIMEOUT_MS:
		await physics_frame
		if t.is_area_meshed(area, 0) and tool.is_area_editable(area):
			return Time.get_ticks_msec() - t0
	return -1


# --- Amostragem ----------------------------------------------------------------

func _sample_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for x in [-9, -6, -4, 0, 4, 6, 8]:
		for y in [-3, -1, 0, 1, 2, 3]:
			for z in [-6, 0, 6]:
				pts.append(Vector3(x, y, z))
	return pts


func _snapshot(tool: VoxelTool, pts: Array[Vector3]) -> Dictionary:
	var out := {}
	for p in pts:
		out[p] = [_sdf(tool, p), _idx(tool, p)]
	return out


func _diff(a: Dictionary, b: Dictionary) -> Array:
	var d := []
	for k in a:
		if not b.has(k):
			d.append("%s ausente" % k)
		elif absf(a[k][0] - b[k][0]) > 1e-4 or a[k][1] != b[k][1]:
			d.append("%s %s→%s" % [k, a[k], b[k]])
	return d


func _sdf(tool: VoxelTool, p: Vector3) -> float:
	tool.channel = VoxelBuffer.CHANNEL_SDF
	return tool.get_voxel_f(Vector3i(p.round()))


func _idx(tool: VoxelTool, p: Vector3) -> int:
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	var v := tool.get_voxel(Vector3i(p.round()))
	tool.channel = VoxelBuffer.CHANNEL_SDF
	return v


# --- Saída ---------------------------------------------------------------------

func _check(id: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	_out("%s %s | %s" % ["OK  " if ok else "FAIL", id, detail])


func _list_dir() -> String:
	var names := PackedStringArray()
	for n in DirAccess.get_files_at(_dir):
		names.append("%s(%d)" % [n, _file_size(_dir.path_join(n))])
	return ", ".join(names)


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n


func _fmt_arr(a: Array) -> String:
	var s := PackedStringArray()
	for v in a:
		s.append("%.2f" % v)
	return "[" + ", ".join(s) + "]"


func _out(s: String) -> void:
	print(s)
	_lines.append(s)
