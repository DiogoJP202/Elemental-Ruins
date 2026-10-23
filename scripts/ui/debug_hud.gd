class_name DebugHud
extends CanvasLayer
## Overlay de engenharia (P0/P1): retícula, desempenho, terreno, fila de brushes,
## material sob a mira, motor voxel, reset/salvar/carregar e legenda.
## Só lê estado; não executa comandos.

const LEGEND := "WASD mover · Shift correr · Space pular · Mouse câmera · Esc solta o mouse\n" \
	+ "G escavar · H adicionar · N suavizar (segure) · J túnel · K rampa · M material do H · roda / [ ] raio\n" \
	+ "Z RESET DO MUNDO · F5 salvar slot · F9 carregar slot · B caixa de teste"
const MATERIAL_NAMES := {&"soil": "solo", &"sand": "areia", &"stone": "pedra"}
## Janela das métricas de tempo de quadro.
const FRAME_WINDOW_S := 1.0

var terrain_service: TerrainService
var brush_queue: TerrainBrushQueue
var player: PlayerController
var edit_controller: TerrainEditController

var _status: Label
var _last_edit: Label
var _accum := 0.0
var _frame_dts := PackedFloat32Array()
var _frame_stamps := PackedFloat64Array()
var _reset_count := 0
var _last_reset := ""
var _last_save := ""
var _last_load := ""


func setup(p_service: TerrainService, p_queue: TerrainBrushQueue, p_player: PlayerController,
		p_controller: TerrainEditController) -> void:
	terrain_service = p_service
	brush_queue = p_queue
	player = p_player
	edit_controller = p_controller
	edit_controller.edit_performed.connect(_on_edit_performed)
	terrain_service.world_reset_started.connect(func(): _set_last("RESET DO MUNDO em andamento...", Color.YELLOW))
	terrain_service.world_reset_finished.connect(_on_reset_finished)
	terrain_service.world_save_started.connect(func(slot): _set_last("Salvando '%s'..." % slot, Color.YELLOW))
	terrain_service.world_saved.connect(_on_saved)
	terrain_service.world_load_started.connect(func(slot): _set_last("Carregando '%s'..." % slot, Color.YELLOW))
	terrain_service.world_loaded.connect(_on_loaded)


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_status = _make_label(root, Vector2(16, 12), 14)
	_last_edit = _make_label(root, Vector2(16, 262), 16)

	var legend := _make_label(root, Vector2.ZERO, 14)
	legend.text = LEGEND
	legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend.position = Vector2(16, -80)
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var reticle := Label.new()
	reticle.text = "+"
	reticle.add_theme_font_size_override("font_size", 26)
	reticle.add_theme_color_override("font_outline_color", Color.BLACK)
	reticle.add_theme_constant_override("outline_size", 4)
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)
	reticle.position -= reticle.size * 0.5


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_frame_dts.append(delta)
	_frame_stamps.append(now)
	while not _frame_stamps.is_empty() and now - _frame_stamps[0] > FRAME_WINDOW_S:
		_frame_stamps.remove_at(0)
		_frame_dts.remove_at(0)
	_accum += delta
	if _accum < 0.2 or terrain_service == null:
		return
	_accum = 0.0
	_status.text = "\n".join(_status_lines())


## Métricas de tempo de quadro do último segundo (ms): média e pico.
func get_frame_stats() -> Dictionary:
	var total := 0.0
	var peak := 0.0
	for dt in _frame_dts:
		total += dt
		peak = maxf(peak, dt)
	var n := _frame_dts.size()
	return {"n": n, "avg_ms": total / n * 1000.0 if n > 0 else 0.0, "max_ms": peak * 1000.0}


## As linhas do overlay (também usadas pelo selftest para conferir o conteúdo).
func _status_lines() -> PackedStringArray:
	var stats := terrain_service.get_debug_stats()
	var q := brush_queue.get_stats()
	var fs := get_frame_stats()
	var aim := edit_controller.get_aim()
	var state := "PRONTO" if stats.ready else (("OCUPADO: %s" % stats.busy_op) if stats.resetting else "CARREGANDO")
	var p := player.global_position
	var lines := PackedStringArray([
		"ELEMENTAL // RUINS — laboratório P1 (terreno volumétrico)",
		"FPS %d  |  quadro %.1f ms (pico 1 s: %.1f ms)  |  monitores TIME_PROCESS %.2f ms, TIME_PHYSICS_PROCESS %.2f ms" % [
			Engine.get_frames_per_second(), fs.avg_ms, fs.max_ms,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
		"Terreno: %s  geração %d  revisão %d  edições %d  recusas %d  |  sessão %s (%d arquivo[s])" % [
			state, stats.world_generation, stats.revision, stats.edits, stats.rejects,
			stats.session_file if stats.persistence else "sem stream", stats.session_files],
		"Fila: pendentes %d  traços %d  |  aplicadas %d  recusadas %d  descartadas %d  |  fundidos %d  divisões %d  |  ops/quadro %d (pico %d)" % [
			q.pending, q.active_strokes, q.applied, q.rejected, q.dropped + q.cleared, q.merged, q.splits,
			q.ops_last_frame, q.max_ops_in_frame],
		"Último brush: %s" % _last_brush_text(),
		"Motor voxel: %s  |  memória estática %.0f MB  |  corpos ativos %d" % [
			_voxel_engine_text(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)],
		"Jogador: (%.1f, %.1f, %.1f)  no chão: %s" % [p.x, p.y, p.z, "sim" if player.is_on_floor() else "não"],
		"Pincel: raio %.2f m  |  material do H: %s" % [edit_controller.get_radius(),
			MATERIAL_NAMES.get(edit_controller.get_add_material(), edit_controller.get_add_material())],
		"Mira: %s" % _aim_text(aim),
		"Reset: %d%s  |  Salvar: %s  |  Carregar: %s" % [_reset_count,
			("  último " + _last_reset) if _last_reset != "" else "", _last_save if _last_save != "" else "—",
			_last_load if _last_load != "" else "—"],
	])
	return lines


func _last_brush_text() -> String:
	var req := brush_queue.get_last_request()
	var res := brush_queue.get_last_result()
	if req == null or res == null:
		return "—"
	var s := res.world_aabb.size
	var text := "%s r=%.2f  AABB %.1f×%.1f×%.1f m" % [req.op_name(), req.max_radius(), s.x, s.y, s.z]
	if req.merged_count > 1:
		text += "  (%d carimbos fundidos)" % req.merged_count
	if res.ok:
		text += "  %s ~%.0f kg (estimativa)  chamada %.2f ms  espera na fila %.1f ms" % [
			MATERIAL_NAMES.get(res.material_id, res.material_id), res.est_mass_kg, res.duration_usec / 1000.0,
			(req.applied_usec - req.enqueued_usec) / 1000.0]
	else:
		text += "  RECUSADO (%s)" % res.reason
	return text


func _aim_text(aim: Dictionary) -> String:
	if not aim.hit:
		return "sem alvo"
	var pt: Vector3 = aim.point
	var text := "(%.1f, %.1f, %.1f) %s" % [pt.x, pt.y, pt.z, "editável" if aim.editable else "NÃO editável"]
	var m: TerrainMaterial = aim.material
	if m != null:
		text += "  |  material: %s (dureza %.1f, %d kg/m³, %s)" % [
			MATERIAL_NAMES.get(m.id, m.id), m.hardness, m.density, "dobrável" if m.bendable else "NÃO dobrável"]
	return text


func _voxel_engine_text() -> String:
	if not Engine.has_singleton("VoxelEngine"):
		return "indisponível"
	var st: Dictionary = Engine.get_singleton("VoxelEngine").call("get_stats")
	var tasks: Dictionary = st.get("tasks", {})
	var mem: Dictionary = st.get("memory_pools", {})
	return "tarefas stream %d / geração %d / malha %d  |  voxels %.1f MB" % [
		tasks.get("streaming", 0), tasks.get("generation", 0), tasks.get("meshing", 0),
		mem.get("voxel_used", 0) / 1048576.0]


func _on_edit_performed(result: TerrainEditResult) -> void:
	_set_last("Última edição: %s" % result, Color(0.6, 1.0, 0.6) if result.ok else Color(1.0, 0.55, 0.5))


func _on_reset_finished(generation: int, duration_ms: float) -> void:
	_reset_count += 1
	var ok := terrain_service.is_ready()
	_last_reset = "%d ms %s" % [duration_ms, "ok" if ok else "FALHOU"]
	_set_last("Mundo restaurado do gerador (geração %d) em %d ms" % [generation, duration_ms],
		Color(0.6, 0.85, 1.0) if ok else Color(1.0, 0.55, 0.5))


func _on_saved(slot: String, ok: bool, duration_ms: float) -> void:
	var info: Dictionary = terrain_service.get_debug_stats().last_save
	_last_save = "%s %s %d ms %d KB" % [slot, "ok" if ok else "FALHOU", duration_ms, maxi(info.get("bytes", 0), 0) / 1024]
	_set_last("Salvo em '%s' (%s)" % [slot, _last_save] if ok else "Falha ao salvar '%s': %s" % [slot, info],
		Color(0.6, 0.85, 1.0) if ok else Color(1.0, 0.55, 0.5))


func _on_loaded(slot: String, ok: bool, duration_ms: float) -> void:
	var info: Dictionary = terrain_service.get_debug_stats().last_load
	_last_load = "%s %s %d ms" % [slot, "ok" if ok else "FALHOU (%s)" % info.get("reason", "?"), duration_ms]
	_set_last("Carregado '%s' em %d ms" % [slot, duration_ms] if ok else "Falha ao carregar '%s': %s" % [slot, info.get("reason", info)],
		Color(0.6, 0.85, 1.0) if ok else Color(1.0, 0.55, 0.5))


func _set_last(text: String, color: Color) -> void:
	_last_edit.text = text
	_last_edit.add_theme_color_override("font_color", color)


func _make_label(parent: Control, pos: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
