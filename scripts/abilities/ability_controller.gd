class_name AbilityController
extends Node
## Poderes elementais (P3): 1–4 escolhem Terra / Água / Fogo / Ar e o LMB usa o poder do
## elemento (segurar ou tocar, conforme o poder). Um poder por elemento (roadmap: no máximo 4).
## Modo Criativo: recurso infinito e sem recarga. Nada age enquanto o terreno é recriado
## (reset/salvar/carregar) nem com o input do jogador desligado.

signal element_changed(element: StringName)
signal ability_used(ability_id: StringName, phase: String)

const ELEMENT_NAMES := {&"earth": "TERRA", &"water": "ÁGUA", &"fire": "FOGO", &"air": "AR"}

## Só age com o mouse capturado: o clique que recaptura o mouse não lança poder.
## Os testes desligam isto (o selftest deixa o mouse livre de propósito).
var require_captured_mouse := true

var terrain_service: TerrainService
## Edições de terreno feitas por poderes passam pela fila (D17): cratera da Terra (P3.5).
var brush_queue: TerrainBrushQueue
var materials: MaterialResponseSystem
var structures: StructureService
var player: PlayerController
var props_root: Node3D
var dust: DustFx

var abilities: Array[Ability] = []
var current := 0
var holding := false


func setup(p_terrain: TerrainService, p_materials: MaterialResponseSystem, p_structures: StructureService,
		p_player: PlayerController, p_props: Node3D, p_dust: DustFx, p_queue: TerrainBrushQueue = null) -> void:
	terrain_service = p_terrain
	brush_queue = p_queue
	materials = p_materials
	structures = p_structures
	player = p_player
	props_root = p_props
	dust = p_dust
	abilities = [EarthLiftThrow.new(), WaterJet.new(), FireBurst.new(), AirGust.new()]
	for a in abilities:
		a.setup(self)
	require_captured_mouse = DisplayServer.get_name() != "headless"
	terrain_service.world_reset_started.connect(cancel_all)
	terrain_service.world_save_started.connect(func(_s): cancel_all())
	terrain_service.world_load_started.connect(func(_s): cancel_all())


func current_ability() -> Ability:
	return abilities[current] if current < abilities.size() else null


func get_ability(ability_id: StringName) -> Ability:
	for a in abilities:
		if a.id == ability_id:
			return a
	return null


func select(index: int) -> bool:
	if index < 0 or index >= abilities.size() or index == current:
		return false
	if holding:
		use_released()
	current_ability().cancel()
	current = index
	element_changed.emit(current_ability().element)
	return true


## LMB pressionado (também chamado pelos testes).
func use_pressed() -> bool:
	if not _can_act():
		return false
	var a := current_ability()
	holding = a.input_mode == "hold"
	a.on_press()
	ability_used.emit(a.id, "press")
	return true


func use_released() -> void:
	var a := current_ability()
	if a == null:
		return
	if holding:
		holding = false
		a.on_release()
		ability_used.emit(a.id, "release")


func cancel_all() -> void:
	holding = false
	for a in abilities:
		a.cancel()
		a.clear()


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.input_enabled:
		return
	for i in ElementalKeys.ACTIONS.size():
		if event.is_action_pressed(ElementalKeys.ACTIONS[i]):
			select(i)
			return
	if event.is_action_pressed(&"ability_use"):
		if require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		use_pressed()
	elif event.is_action_released(&"ability_use"):
		use_released()


func _physics_process(delta: float) -> void:
	if abilities.is_empty():
		return
	if holding and (not _can_act() or not player.input_enabled):
		cancel_all()
	elif holding:
		current_ability().on_hold(delta)
	var speed := 1.0
	for a in abilities:
		a.physics_tick(delta)
		speed = minf(speed, a.move_speed_scale())
	if player != null:
		player.speed_scale = speed


func _can_act() -> bool:
	return terrain_service != null and terrain_service.is_ready() and player != null and player.input_enabled


# --- Mira (centro da tela) ---------------------------------------------------------------

func aim_ray() -> Array:
	return player.camera_rig.get_aim_ray()


func aim_direction() -> Vector3:
	return (aim_ray()[1] as Vector3).normalized()


## Ponto de terreno sob a mira até `max_distance` ({} se nada).
func aim_terrain(max_distance: float) -> Dictionary:
	var r := aim_ray()
	return terrain_service.raycast_terrain(r[0], r[0] + r[1] * max_distance)


## Primeiro terreno ou corpo (PROPS) sob a mira.
func aim_any(max_distance: float, exclude: Array[RID] = []) -> Dictionary:
	var r := aim_ray()
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * max_distance, Layers.TERRAIN | Layers.PROPS, exclude)
	return player.get_world_3d().direct_space_state.intersect_ray(q)


## Ponto que a mira atinge (terreno ou corpo), ou o fim do raio se não atinge nada.
func aim_point(max_distance: float) -> Vector3:
	var hit := aim_any(max_distance)
	if not hit.is_empty():
		return hit.position
	var r := aim_ray()
	return r[0] + (r[1] as Vector3).normalized() * max_distance


## De onde saem jato, bola de fogo e rajada: à frente do peito, na direção horizontal da mira
## (fora da cápsula do jogador, raio 0,35 m).
func hand_position() -> Vector3:
	var fwd := aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return player.global_position + Vector3.UP * 1.3 + fwd * 0.6


## Primeiro terreno ou corpo (PROPS) no segmento `from` → `to` ({} se nada).
func cast_segment(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.TERRAIN | Layers.PROPS)
	return player.get_world_3d().direct_space_state.intersect_ray(q)


## Corpo físico sob a mira (para o HUD mostrar o estado do material).
func aimed_body(max_distance := 40.0) -> Node3D:
	var hit := aim_any(max_distance)
	return hit.get("collider") as RigidBody3D if not hit.is_empty() else null


func element_label() -> String:
	var a := current_ability()
	if a == null:
		return "—"
	return "%d %s — %s [%s LMB]" % [current + 1, ELEMENT_NAMES.get(a.element, a.element), a.display_name,
		"segure" if a.input_mode == "hold" else "toque"]
