class_name DebugHud
extends CanvasLayer
## HUD de engenharia do P0: retícula, estado do terreno, última edição e legenda.
## Só lê estado; não executa comandos.

const LEGEND := "WASD mover · Shift correr · Space pular · Mouse câmera · Esc solta o mouse\n" \
	+ "G escavar · H adicionar · J túnel (10 m) · Z RESET DO MUNDO · roda / [ ] raio · B caixa de teste"

var terrain_service: TerrainService
var player: PlayerController
var edit_controller: TerrainEditController

var _status: Label
var _last_edit: Label
var _accum := 0.0
var _reset_count := 0
var _last_reset_ms := -1.0


func setup(p_service: TerrainService, p_player: PlayerController, p_controller: TerrainEditController) -> void:
	terrain_service = p_service
	player = p_player
	edit_controller = p_controller
	edit_controller.edit_performed.connect(_on_edit_performed)
	terrain_service.world_reset_started.connect(func(): _set_last("RESET DO MUNDO em andamento...", Color.YELLOW))
	terrain_service.world_reset_finished.connect(_on_reset_finished)


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_status = _make_label(root, Vector2(16, 12), 15)
	_last_edit = _make_label(root, Vector2(16, 200), 17)

	var legend := _make_label(root, Vector2.ZERO, 14)
	legend.text = LEGEND
	legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend.position = Vector2(16, -60)
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
	_accum += delta
	if _accum < 0.2 or terrain_service == null:
		return
	_accum = 0.0
	var stats := terrain_service.get_debug_stats()
	var aim := edit_controller.get_aim()
	var state := "PRONTO" if stats.ready else ("RESETANDO" if stats.resetting else "CARREGANDO")
	var p := player.global_position
	var lines := PackedStringArray([
		"ELEMENTAL // RUINS — laboratório P0 (terreno volumétrico)",
		"FPS %d  |  frame %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)],
		"Terreno: %s  geração %d  revisão %d  edições %d  recusas %d" % [state, stats.world_generation, stats.revision, stats.edits, stats.rejects],
		"Jogador: (%.1f, %.1f, %.1f)  no chão: %s" % [p.x, p.y, p.z, "sim" if player.is_on_floor() else "não"],
		"Raio do pincel: %.2f m" % edit_controller.get_radius(),
		"Mira: %s" % (("(%.1f, %.1f, %.1f) %s" % [aim.point.x, aim.point.y, aim.point.z, "editável" if aim.editable else "NÃO editável"]) if aim.hit else "sem alvo"),
		"Resets: %d%s" % [_reset_count, ("  último: %d ms" % _last_reset_ms) if _last_reset_ms >= 0.0 else ""],
	])
	_status.text = "\n".join(lines)


func _on_edit_performed(result: TerrainEditResult) -> void:
	_set_last("Última edição: %s" % result, Color(0.6, 1.0, 0.6) if result.ok else Color(1.0, 0.55, 0.5))


func _on_reset_finished(generation: int, duration_ms: float) -> void:
	_reset_count += 1
	_last_reset_ms = duration_ms
	_set_last("Mundo restaurado do gerador (geração %d) em %d ms" % [generation, duration_ms], Color(0.6, 0.85, 1.0))


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
